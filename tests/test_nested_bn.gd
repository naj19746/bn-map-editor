extends "res://tests/support/test_case.gd"
## Stage 6 acceptance on core data: every place_nested entry and "nested"
## symbol mapping in core draws its chunk on its parent without errors, with
## the counts an independent Python pass over data/json found (PLAN.MD,
## Stage 6): 21691 top-level chunk placements, 284 reaching past their
## overmap tile, 2 rotated non-square chunks. A palette edit that changes
## chunks names every map placing them, as a brute force finds them.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")
const MAX_REPORTED := 20

static var _core: DataIndex


func _core_index() -> DataIndex:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	if _core == null:
		_core = DataIndex.load_bn(bn)
	return _core


func test_all_core_chunks_draw() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var t := Time.get_ticks_msec()
	var bad := PackedStringArray()
	var top := 0
	var overhang := 0
	var rotated := 0
	var inner := 0
	var nothing := 0
	for ref in index.mapgens:
		if ref.method != "json":
			continue
		var mapgen := objects.object_for(ref)
		var resolved := MapgenResolver.resolve(index, mapgen)
		var o := ChunkOverlay.build(index, mapgen, resolved, objects.object_for)
		var where := "%s #%d %s" % [ref.source.path, ref.source.index, ref.title()]
		for p in o.problems():
			bad.append("%s: %s" % [where, p])
		for s in o.stamps:
			if s.depth > 0:
				inner += 1
			else:
				top += 1
				if s.overhangs():
					overhang += 1
			if s.chunk_id.is_empty() or s.ref == null:
				nothing += 1
				continue
			# The footprint is the anchor range plus the (turned) chunk.
			var turned := s.chunk_size if s.rotation % 2 == 0 else Vector2i(s.chunk_size.y, s.chunk_size.x)
			if s.footprint != Rect2i(s.anchor.position, s.anchor.size + turned - Vector2i.ONE):
				bad.append("%s: %s footprint %s" % [where, s.path, s.footprint])
			if s.rotation % 2 == 1 and s.chunk_size.x != s.chunk_size.y:
				rotated += 1
		# Every cell a chunk wrote is inside its footprint.
		for i in o.owner.size():
			var st := o.owner[i]
			if st >= 0 and not o.stamps[st].footprint.has_point(Vector2i(i % o.size.x, i / o.size.x)):
				bad.append("%s: cell %d written outside %s's footprint" % [where, i, o.stamps[st].path])
				break
	print("     laid out %d top-level and %d inner chunk placements in %d ms (%d place nothing)" % [
		top, inner, Time.get_ticks_msec() - t, nothing])
	check_eq(bad.slice(0, MAX_REPORTED), PackedStringArray())
	check_eq(top, 21691, "top-level placements (independent count)")
	check_eq(overhang, 284, "placements reaching past their tile (independent count)")
	check_eq(rotated, 2, "rotated non-square chunks (independent count)")
	check(inner > 1000, "chunks placed by chunks: %d" % inner)


## A real parent draws its chunk's cells: house_01's place_nested entries
## each write cells, and the ASCII view shows what the chunk leaves there.
func test_real_map_draws_chunks() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var found := false
	for ref in index.mapgens:
		if ref.method != "json" or ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
			continue
		var mapgen := objects.object_for(ref)
		if not mapgen.object.get("place_nested") is Array:
			continue
		var resolved := MapgenResolver.resolve(index, mapgen)
		var o := ChunkOverlay.build(index, mapgen, resolved, objects.object_for)
		var cell := -1
		for i in o.owner.size():
			if o.owner[i] >= 0 and (o.ter[i] or (o.furn[i] and o.furn[i] != "f_null")):
				cell = i
				break
		if cell < 0:
			continue
		var a := AsciiMap.build(index, resolved, 0, true, o)
		var x := cell % o.size.x
		var y := cell / o.size.x
		var id := o.furn[cell] if o.furn[cell] and o.furn[cell] != "f_null" else o.ter[cell]
		var def: DataIndex.TileDef = index.furniture.get(id, index.terrain.get(id))
		check(def != null, "%s: %s is known" % [ref.title(), id])
		check(a.describe_cell(x, y).contains("chunk " + o.stamp_at(Vector2i(x, y)).chunk_id), a.describe_cell(x, y))
		check_eq(AsciiMap.build(index, resolved).describe_cell(x, y).contains("chunk "), false, "no overlay, no chunk")
		found = true
		break
	check(found, "a map with place_nested draws a chunk cell")


## An edit to standard_domestic_palette changes chunks (bedrooms, ...); the
## warning also names every map that places a changed chunk, directly or
## through other chunks, exactly as a brute-force pass over every core map's
## chunks (all options, all variants, followed through) finds them.
func test_palette_warning_names_parents() -> void:
	var index := _core_index()
	if index == null:
		return
	var ws := TempTree.make({})
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var pal := session.open_palette(index.palette("standard_domestic_palette"))
	var c := pal.build_set_tiles("h", null, "f_bed", "h")
	var t := Time.get_ticks_msec()
	var warning := session.impact_of(pal, c)
	print("     warning for standard_domestic_palette 'h' in %d ms" % (Time.get_ticks_msec() - t))
	session.close_palette(pal)
	var direct := {}
	var changed_chunks := {}
	var via := PackedStringArray()
	for a in warning:
		if a.via:
			via.append("%s#%d" % [a.ref.source.path, a.ref.source.index])
		else:
			direct[a.ref] = true
			if a.ref.kind == DataIndex.MapgenRef.NESTED:
				changed_chunks[a.ref.ids[0]] = true
	check(changed_chunks.size() > 10, "chunks changed: %d" % changed_chunks.size())

	# Brute force: what every map can place, followed through every chunk.
	t = Time.get_ticks_msec()
	var placed := {}
	for ref in index.mapgens:
		if ref.method == "json":
			var o := session.objects.object_for(ref)
			placed[ref] = ChunkOverlay.placed_ids(o, MapgenResolver.resolve(index, o))
	var reach := {}
	var expected := PackedStringArray()
	for ref: DataIndex.MapgenRef in placed:
		if direct.has(ref):
			continue
		for id in _reach(index, placed, reach, placed[ref], {}):
			if changed_chunks.has(id):
				expected.append("%s#%d" % [ref.source.path, ref.source.index])
				break
	print("     brute-force chunk closure of %d mapgens in %d ms" % [placed.size(), Time.get_ticks_msec() - t])
	via.sort()
	expected.sort()
	check_eq(via, expected, "parents named via a chunk = brute force")
	check(via.size() > 20, "parents via chunks: %d" % via.size())
	TempTree.remove(ws)


## Every chunk id reachable from [param ids]: those, and what any mapgen of
## theirs places, followed through (memoized in [param reach]).
func _reach(index: DataIndex, placed: Dictionary, reach: Dictionary, ids: PackedStringArray,
		visiting: Dictionary) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = true
		if visiting.has(id):
			continue
		if not reach.has(id):
			visiting[id] = true
			var inner := PackedStringArray()
			for r: DataIndex.MapgenRef in index.nested.get(id, []):
				inner.append_array(placed.get(r, PackedStringArray()))
			reach[id] = _reach(index, placed, reach, inner, visiting)
			visiting.erase(id)
		out.merge(reach[id])
	return out

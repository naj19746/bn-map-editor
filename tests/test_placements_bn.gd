extends "res://tests/support/test_case.gd"
## Stage 5 acceptance: every placement entry in core reads into the model
## and writes back unchanged, BN's odd cases are counted as an independent
## script counted them (PLAN.MD, "Checked after Stage 4"), and editing one
## entry of a real multi-tile map changes only that entry's lines.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")
const MAX_REPORTED := 20
## Range-valued fields besides x/y (jmapgen_int with a default).
const RANGE_FIELDS := ["repeat", "chance", "amount", "pack_size"]

static var _core: DataIndex


func _core_index() -> DataIndex:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	if _core == null:
		_core = DataIndex.load_bn(bn)
	return _core


static func _size(ref: DataIndex.MapgenRef) -> Vector2i:
	if ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		return ref.chunk_size if ref.chunk_size != Vector2i.ZERO else Vector2i(24, 24)
	return ref.size_omt() * 24


func test_all_core_placements() -> void:
	var index := _core_index()
	if index == null:
		return
	var t := Time.get_ticks_msec()
	var files := {}
	var bad := PackedStringArray()
	var entries := 0
	var raw_entries := 0
	var counts := {}
	var set_maps := {}
	for ref in index.mapgens:
		if ref.method != "json":
			continue
		if not files.has(ref.source.path):
			var parsed := BnJson.parse(FileAccess.get_file_as_string(index.bn_path.path_join(ref.source.path)))
			files[ref.source.path] = parsed.value if parsed.value is Array else [parsed.value]
		var mapgen: Dictionary = files[ref.source.path][ref.source.index]
		for member: String in mapgen.object:
			if Placement.KINDS.has(member) and mapgen.object[member] is Array:
				raw_entries += mapgen.object[member].size()
		for p in Placement.read_all(mapgen, _size(ref)):
			entries += 1
			var where := "%s #%d %s" % [ref.source.path, ref.source.index, p.title()]
			var key := "%s %s" % ["set" if p.is_set() else "place", Placement.Status.keys()[p.status]]
			counts[key] = counts.get(key, 0) + 1
			if p.is_set() and p.status == Placement.Status.DROPPED:
				set_maps[ref.source] = true
			# Every range comes back as written.
			for f in ["x", "y", "x2", "y2"] + RANGE_FIELDS:
				if not p.entry.has(f) or (f == "chance" and p.member == "place_loot"):
					continue
				var one_means_both: bool = f in ["x", "y", "x2", "y2"]
				var r := Placement.IntRange.parse(p.entry[f], 1, 1, one_means_both)
				if not r.valid() or BnJson.stringify(r.to_json()) != BnJson.stringify(p.entry[f]):
					bad.append("%s: %s %s" % [where, f, BnJson.stringify(p.entry[f])])
			# Placing an entry where it is changes nothing.
			if p.status == Placement.Status.OK:
				for i in p.instances().size():
					var same := p.values_for(p.instances()[i], true, i)
					if p.x2 == null:
						same.merge(p.values_for(p.instances()[i], false, i), false)
					for f: String in same:
						if BnJson.stringify(same[f]) != BnJson.stringify(p.entry[f]):
							bad.append("%s: placed where it is, %s becomes %s" % [where, f, BnJson.stringify(same[f])])
	print("     read %d placements from %d files in %d ms: %s" % [entries, files.size(), Time.get_ticks_msec() - t, counts])
	check_eq(entries, raw_entries, "every entry read")
	check(entries > 15000, "entries: %d" % entries)
	check_eq(bad.slice(0, MAX_REPORTED), PackedStringArray())
	# Counted independently (a Python pass over data/json, 2026-09-27).
	check_eq(counts.get("place DROPPED", 0), 19, "place_* anchored outside their map")
	check_eq(counts.get("place SPANS_BACK", 0), 54, "reversed ranges reaching into the previous tile")
	check_eq(counts.get("set DROPPED", 0), 209, "set entries past the tile in multi-tile maps")
	check_eq(set_maps.size(), 44, "in this many mapgens")
	check_eq(counts.get("place CROSSES", 0) + counts.get("set CROSSES", 0), 0, "BN would refuse these")
	check_eq(counts.get("place OUTSIDE_CHUNK", 0) > 0, true, "chunks with entries past their mapgensize")


## Edits one entry of [param id]'s map with [param edit] (given the
## document), saves to a temp workspace, and checks the diff against BN:
## exactly the entry's line changes, into the new entry.
func _edit_one(id: String, member: String, i: int, edit: Callable) -> void:
	var index := _core_index()
	if index == null:
		return
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built")
		return
	var ws := TempTree.make({})
	index.workspace_path = ws
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var ref: DataIndex.MapgenRef = index.mapgens_for(id)[0]
	var doc := session.open(ref)
	if not check(doc != null, session.last_error):
		return
	var before := BnJson.stringify(doc.object()[member][i])
	edit.call(doc)
	var after := BnJson.stringify(doc.object()[member][i])
	check(before != after, "the entry changed")
	check_eq(session.save(ref.source.path), "")
	var out := []
	OS.execute("diff", ["-U0", index.bn_path.path_join(ref.source.path), ws.path_join(ref.source.path)], out, true)
	var minus := PackedStringArray()
	var plus := PackedStringArray()
	for l in "".join(PackedStringArray(out)).split("\n"):
		if l.begins_with("---") or l.begins_with("+++"):
			continue
		if l.begins_with("-"):
			minus.append(l.substr(1).strip_edges().trim_suffix(","))
		elif l.begins_with("+"):
			plus.append(l.substr(1).strip_edges().trim_suffix(","))
	if check_eq([minus.size(), plus.size()], [1, 1], "one line out, one in: %s %s" % [minus, plus]):
		check_eq(BnJson.stringify(BnJson.parse(minus[0]).value), before, "the old line is the entry")
		check_eq(BnJson.stringify(BnJson.parse(plus[0]).value), after, "the new line is the edited entry")
	index.workspace_path = ""
	TempTree.remove(ws)


## 2x2: shrink the NE tile's monster range and change its chance.
func test_edit_apartments_tower_entry() -> void:
	_edit_one("apartments_mod_tower_NW", "place_monsters", 3, func(doc: MapDocument) -> void:
		check_eq(doc.placement("place_monsters", 3).anchor_omt, Vector2i(1, 0))
		check_eq(doc.place_at("place_monsters", 3, Rect2i(30, 2, 10, 12), false), "")
		check_eq(doc.set_placement_fields("place_monsters", 3, {"chance": 3}), "")
		check_eq(doc.object().place_monsters[3].x, [30, 39]))


## 9x1 mall: drag a loot entry with the Place tool into the next tile.
func test_edit_mall_entry_with_tool() -> void:
	_edit_one("mall_a_1", "place_loot", 0, func(doc: MapDocument) -> void:
		var p := doc.placement("place_loot", 0)
		var tool := PlacementTool.new()
		tool.layer_mask = 1 << Placement.Layer.ITEMS
		var from := p.span().position
		tool.select("place_loot", 0)
		tool.press(doc, from)
		check_eq(tool.member, "place_loot", "grabbed")
		var to := from + Vector2i(30, 0)
		tool.move(to)
		tool.release(to)
		var moved := doc.placement("place_loot", 0)
		check_eq(moved.status, Placement.Status.OK)
		check(moved.geometry.tile_of(moved.span().position).encloses(moved.span()), "in one tile"))

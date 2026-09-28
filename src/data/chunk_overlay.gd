class_name ChunkOverlay
extends RefCounted
## The nested chunks a map places, laid over its cells the way BN applies
## them (mapgen.cpp: jmapgen_nested, mapgen_function_json_nested::nest).
##
## - Pieces: "nested" symbol mappings (the map's own and its palettes', at
##   every cell using the symbol) and place_nested entries. BN runs them
##   after the map's terrain, furniture and other pieces, one overmap tile at
##   a time: mapping cells in row order, then place_nested in list order.
##   Later chunks draw over earlier ones.
## - Which chunk: "chunks" is a weighted list; the overlay draws the heaviest
##   id other than "null" (the first on ties), and of that id's mapgens the
##   heaviest. neighbors/joins/connections choose between "chunks" and
##   "else_chunks" and need the overmap around the map, so "chunks" is drawn.
## - Where: the chunk's top-left corner is picked in the entry's x/y range;
##   the overlay uses the range's low corner. The placing entry's "rotation"
##   turns the chunk clockwise around its mapgensize (a non-square chunk's
##   footprint swaps width and height). The chunk's own "rotation" is never
##   used by BN.
## - Cells: a chunk cell with terrain replaces the terrain (and the furniture,
##   when the new terrain is a WALL), then its furniture replaces the
##   furniture. Undefined " "/"." leave the cell as it was; a chunk's
##   fill_ter is ignored.
## - Chunks inside chunks: the inner piece's anchor turns with the outer
##   chunk, but the inner chunk turns only by its own piece's rotation (BN
##   passes just that to nest()).
## - Overhang: BN doesn't clip a chunk to its anchor's tile. The footprint is
##   drawn whole and marked when it leaves the tile; whether the overhang
##   survives in game depends on when the neighbouring tile is generated
##   (unverified).
## - Consoles: a chunk cell with a computer becomes t_console (BN overrides
##   the symbol), and each stamp lists the consoles its chunk puts down.
## - Other picks: [member forced] makes a stamp draw a given chunk, mapgen
##   and rotation instead of the heaviest, so the Validator can judge every
##   chunk an entry may pick (see Validator._check_chunk_consoles).

const MAX_DEPTH := 12
## A [member forced] value that places nothing.
const NOTHING := ["", null, 0]
const WALL := "WALL"

## What kind of problem an entry of [member Stamp.issues] is.
enum Issue { ROTATION, UNKNOWN_CHUNK, LOOP, TOO_DEEP, UNREADABLE }


## One chunk placement: a place_nested entry or a "nested" mapping at a
## cell, at any depth.
class Stamp:
	## "place_nested", or "nested" for a symbol mapping.
	var member := ""
	## The place_nested list index, or -1 for a mapping.
	var index := -1
	## The symbol, for a mapping.
	var key := ""
	## 0 when the map places it itself.
	var depth := 0
	## Position in ChunkOverlay.stamps of the stamp whose chunk placed this
	## one, -1 at depth 0.
	var parent := -1
	## Where the chunk's top-left corner can go, in map cells.
	var anchor := Rect2i()
	## "chunks" and "else_chunks" as [[id, weight], ...].
	var options: Array = []
	var else_options: Array = []
	## True when neighbors/joins/connections decide between the two lists.
	var conditional := false
	## The chunk drawn, "" when nothing is.
	var chunk_id := ""
	## The mapgen drawn for chunk_id, and how many that id has.
	var ref: DataIndex.MapgenRef
	var variants := 0
	## Quarter turns clockwise; rotation_text is set when it's a range.
	var rotation := 0
	var rotation_text := ""
	## Every rotation the entry can pick (0-3, low to high).
	var rotations: Array[int] = [0]
	## The chunk's mapgensize, and its footprint once turned.
	var chunk_size := Vector2i.ZERO
	var size := Vector2i.ZERO
	## Every cell the chunk can cover: anchor range + size.
	var footprint := Rect2i()
	## The overmap tile (or chunk) the top-level placement belongs to.
	var tile := Rect2i()
	var repeat := ""
	## Where it comes from, e.g. "place_nested #2 > chunk_a > 'X' nested".
	var path := ""
	## Names this placement across builds of the same map, whatever its
	## parents picked (the key of [member ChunkOverlay.forced]).
	var uid := ""
	## True when [member ChunkOverlay.forced] chose the chunk.
	var is_forced := false
	## The consoles the chunk puts down: [cell in map cells (may be outside
	## the map), computer JSON, the chunk's symbol ("" for place_computers)].
	var consoles: Array = []
	## The placing entry and where it sat, for replay().
	var piece := {}
	var context: RefCounted
	var problems := PackedStringArray()
	## [member problems] again, as [Issue, text].
	var issues: Array = []

	func title() -> String:
		return "place_nested #%d" % (index + 1) if member == "place_nested" else "'%s' nested" % key

	func overhangs() -> bool:
		return footprint.has_area() and not tile.encloses(footprint)

	## The other ids "chunks" can pick, besides the one drawn.
	func others() -> int:
		var n := 0
		for o: Array in options:
			if o[0] != chunk_id:
				n += 1
		return n

	## The canvas label: "chunk_a", "chunk_a +2 r1", "(nothing)".
	func label() -> String:
		var parts := PackedStringArray([chunk_id if chunk_id else "(nothing)"])
		if others():
			parts.append("+%d" % others())
		if rotation_text:
			parts.append("r" + rotation_text)
		elif rotation:
			parts.append("r%d" % rotation)
		if repeat:
			parts.append("x" + repeat)
		if overhangs() or not problems.is_empty():
			parts.append("!")
		return " ".join(parts)

	func add_problem(code: Issue, text: String) -> void:
		problems.append(text)
		issues.append([code, text])

	## One line for the status bar and the inspector.
	func describe() -> String:
		var parts := PackedStringArray()
		if chunk_id:
			var turned := " turned %s to %dx%d" % [rotation_text if rotation_text else str(rotation), size.x, size.y] \
					if rotation or rotation_text else ""
			parts.append("chunk %s (%dx%d%s)" % [chunk_id, chunk_size.x, chunk_size.y, turned])
			if variants > 1:
				parts.append("the heaviest of %d mapgens" % variants)
		else:
			parts.append("places nothing")
		var ids := options.map(func(o: Array) -> String: return "%s %d" % o)
		if ids.size() > 1:
			parts.append("picked from " + ", ".join(ids))
		if conditional:
			var alt := else_options.map(func(o: Array) -> String: return o[0])
			parts.append("if its neighbours match; else " + (", ".join(alt) if alt else "nothing"))
		if overhangs():
			parts.append("reaches past its overmap tile (BN doesn't clip it)")
		parts.append_array(problems)
		return "; ".join(parts)


var index: DataIndex
## The map's size in cells.
var size := Vector2i.ZERO
## Every placement, in the order BN applies them (inner chunks right after
## the chunk placing them).
var stamps: Array[Stamp] = []
## Per cell (y * size.x + x): the terrain and furniture the chunks leave
## there ("" = the map's own; "f_null" = furniture removed), the stamp that
## wrote it last (-1 for none) and that chunk's symbol.
var ter := PackedStringArray()
var furn := PackedStringArray()
var owner := PackedInt32Array()
var chunk_keys := PackedStringArray()
## Chunk ids drawn at any depth, and the palettes those chunks applied: an
## edit to either can change the overlay.
var drawn_ids := {}
var palette_ids := {}
## Every chunk id any stamp can pick ("chunks" and "else_chunks").
var option_ids := {}
## Stamp uid -> [chunk id, MapgenRef, rotation]: draw that instead of the
## heaviest pick (NOTHING: draw nothing there).
var forced := {}

## (MapgenRef) -> the mapgen object.
var objects: Callable
## MapgenRef -> [ResolvedMapgen, Array[Placement]], or null if unreadable.
var chunk_cache := {}


## Lays out every chunk [param mapgen] (a whole mapgen object, resolved as
## [param resolved]) places. [param p_objects] returns a MapgenRef's object.
## [param p_forced]: see [member forced]. [param cache] is shared between
## builds so each chunk is resolved once (see resolve_chunk()).
static func build(p_index: DataIndex, mapgen: Dictionary, resolved: ResolvedMapgen,
		p_objects: Callable, p_forced := {}, cache := {}) -> ChunkOverlay:
	var o := ChunkOverlay.new()
	o.index = p_index
	o.objects = p_objects
	o.forced = p_forced
	o.chunk_cache = cache
	o.size = resolved.size
	var n := o.size.x * o.size.y
	o.ter.resize(n)
	o.furn.resize(n)
	o.chunk_keys.resize(n)
	o.owner.resize(n)
	o.owner.fill(-1)
	o._run(mapgen, resolved)
	return o


func _run(mapgen: Dictionary, resolved: ResolvedMapgen) -> void:
	var placements := Placement.read_all(mapgen, resolved.size)
	var g := Placement.Geometry.of(mapgen, resolved.size)
	var tiles: Array[Rect2i] = []
	if g.chunk:
		tiles.append(Rect2i(Vector2i.ZERO, size))
	else:
		for ty in g.omts().y:
			for tx in g.omts().x:
				tiles.append(Rect2i(Vector2i(tx, ty) * Placement.OMT, Vector2i(Placement.OMT, Placement.OMT)))
	for tile in tiles:
		var ctx := _Context.new()
		ctx.tile = tile
		var cells := tile.intersection(Rect2i(Vector2i.ZERO, size))
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				for piece in _mapping_pieces(resolved, resolved.cells[y][x]):
					_place(piece, "nested", -1, resolved.cells[y][x], Rect2i(x, y, 1, 1), ctx)
		for p in placements:
			if p.member == "place_nested" and _runs(p, g) and g.tile_of(Vector2i(p.x.first, p.y.first)) == tile:
				_place(p.entry, p.member, p.index, "", p.span(), ctx)


## Where a piece sits and who placed it.
class _Context:
	var tile := Rect2i()
	var depth := 0
	var parent := -1
	var path := ""
	var uid := ""
	var chain := PackedStringArray()


## True when BN keeps entry [param p] (dropped and crossing ones don't run).
static func _runs(p: Placement, g: Placement.Geometry) -> bool:
	if p.status == Placement.Status.DROPPED or p.status == Placement.Status.CROSSES:
		return false
	return g.chunk or p.status != Placement.Status.OUTSIDE_CHUNK


## The "nested" pieces [param key] maps to in [param r] (every definition,
## palettes first), each an object.
static func _mapping_pieces(r: ResolvedMapgen, key: String) -> Array:
	var out := []
	var info: ResolvedMapgen.SymbolInfo = r.symbols.get(key)
	if info == null:
		return out
	for b: ResolvedMapgen.Binding in info.extras.get("nested", []):
		for piece: Variant in (b.value if b.value is Array else [b.value]):
			if piece is Dictionary:
				out.append(piece)
	return out


func _place(piece: Dictionary, member: String, i: int, key: String, anchor: Rect2i, ctx: _Context) -> void:
	var s := Stamp.new()
	s.member = member
	s.index = i
	s.key = key
	s.depth = ctx.depth
	s.parent = ctx.parent
	s.anchor = anchor
	s.footprint = anchor
	s.tile = ctx.tile
	s.path = (ctx.path + " > " if ctx.path else "") + s.title()
	s.uid = "%s/%s%d%s@%d,%d" % [ctx.uid, member, i, key, anchor.position.x, anchor.position.y]
	s.piece = piece
	s.context = ctx
	s.options = DataIndex.weighted_ids(piece.get("chunks"))
	s.else_options = DataIndex.weighted_ids(piece.get("else_chunks"))
	s.conditional = piece.has("neighbors") or piece.has("joins") or piece.has("connections")
	if piece.has("repeat"):
		s.repeat = Placement.IntRange.parse(piece.repeat, 1, 1, false).text()
	var rot := Placement.IntRange.parse(piece.get("rotation"))
	if not rot.valid():
		s.add_problem(Issue.ROTATION, "rotation must be an int or [min, max]")
	else:
		s.rotation = rot.lo()
		if rot.first != rot.second:
			s.rotation_text = "%d-%d" % [rot.lo(), rot.hi()]
		if rot.lo() < 0 or rot.hi() > 4:
			s.add_problem(Issue.ROTATION, "rotation %s is outside 0-4 (BN asserts)" % rot.text())
			s.rotation = posmod(s.rotation, 4)
		s.rotations.clear()
		for r in range(rot.lo(), mini(rot.hi(), rot.lo() + 3) + 1):
			if not s.rotations.has(posmod(r, 4)):
				s.rotations.append(posmod(r, 4))
	stamps.append(s)
	var si := stamps.size() - 1
	for o: Array in s.options + s.else_options:
		if o[0] and o[0] != "null":
			option_ids[o[0]] = true
	s.chunk_id = pick(s.options)
	if forced.has(s.uid):
		s.chunk_id = forced[s.uid][0]
		s.is_forced = true
	if s.chunk_id.is_empty():
		return
	var refs: Array = index.nested.get(s.chunk_id, [])
	if refs.is_empty():
		s.add_problem(Issue.UNKNOWN_CHUNK, "unknown chunk \"%s\" (BN places nothing)" % s.chunk_id)
		return
	s.variants = refs.size()
	s.ref = heaviest(refs)
	if s.is_forced:
		s.ref = forced[s.uid][1]
		s.rotation = forced[s.uid][2]
	if ctx.chain.has(s.chunk_id):
		s.add_problem(Issue.LOOP, "chunk loop: %s > %s" % [" > ".join(ctx.chain), s.chunk_id])
		return
	if ctx.depth >= MAX_DEPTH:
		s.add_problem(Issue.TOO_DEEP, "chunks nested more than %d deep" % MAX_DEPTH)
		return
	var chunk: Variant = resolve_chunk(s.ref)
	if chunk == null:
		s.add_problem(Issue.UNREADABLE, "can't read chunk %s (%s)" % [s.chunk_id, s.ref.source])
		return
	var r: ResolvedMapgen = chunk[0]
	s.chunk_size = r.size
	s.size = r.size if s.rotation % 2 == 0 else Vector2i(r.size.y, r.size.x)
	s.footprint = Rect2i(anchor.position, anchor.size + s.size - Vector2i.ONE)
	drawn_ids[s.chunk_id] = true
	for p in r.palettes:
		palette_ids[p] = true
	for options in r.choice_options:
		for p in options:
			palette_ids[p] = true

	var origin := anchor.position
	var bounds := Rect2i(Vector2i.ZERO, size)
	for cy in r.size.y:
		for cx in r.size.x:
			var info: ResolvedMapgen.SymbolInfo = r.symbols.get(r.cells[cy][cx])
			if info == null:
				continue
			var t := origin + rotate(Vector2i(cx, cy), s.rotation, r.size)
			if not bounds.has_point(t):
				continue
			var c := t.y * size.x + t.x
			var wrote := false
			if info.terrain and info.terrain.id():
				ter[c] = info.terrain.id()
				var def: DataIndex.TileDef = index.terrain.get(ter[c])
				if def and def.has_flag(WALL):
					furn[c] = "f_null"
				wrote = true
			if info.furniture and info.furniture.id():
				furn[c] = info.furniture.id()
				wrote = true
			if wrote:
				owner[c] = si
				chunk_keys[c] = r.cells[cy][cx]
	# BN puts a console under every computer, whatever the symbol says.
	var consoles := Validator.console_cells(r, chunk[1])
	var local: Array = consoles.keys()
	local.sort()
	for at: Vector2i in local:
		var t := origin + rotate(at, s.rotation, r.size)
		s.consoles.append([t, consoles[at][1], consoles[at][0]])
		if bounds.has_point(t):
			var c := t.y * size.x + t.x
			ter[c] = Computer.CONSOLE
			furn[c] = "f_null"
			owner[c] = si
			chunk_keys[c] = consoles[at][0]

	var inner := _Context.new()
	inner.tile = ctx.tile
	inner.depth = ctx.depth + 1
	inner.parent = si
	inner.path = "%s > %s" % [s.path, s.chunk_id]
	inner.uid = s.uid
	inner.chain = ctx.chain.duplicate()
	inner.chain.append(s.chunk_id)
	for cy in r.size.y:
		for cx in r.size.x:
			for p in _mapping_pieces(r, r.cells[cy][cx]):
				var at := origin + rotate(Vector2i(cx, cy), s.rotation, r.size)
				_place(p, "nested", -1, r.cells[cy][cx], Rect2i(at, Vector2i.ONE), inner)
	var g := Placement.Geometry.of({"nested_mapgen_id": s.chunk_id}, r.size)
	for p: Placement in chunk[1]:
		if p.member == "place_nested" and _runs(p, g):
			var a := rotate(Vector2i(p.x.first, p.y.first), s.rotation, r.size)
			var b := rotate(Vector2i(p.x.second, p.y.second), s.rotation, r.size)
			_place(p.entry, p.member, p.index, "", Rect2i(origin + a.min(b), (a - b).abs() + Vector2i.ONE), inner)


## [ResolvedMapgen, Array[Placement]] for [param ref], resolved once; null
## if its object can't be read.
func resolve_chunk(ref: DataIndex.MapgenRef) -> Variant:
	if not chunk_cache.has(ref):
		var mapgen: Dictionary = objects.call(ref)
		if not mapgen.get("object") is Dictionary:
			chunk_cache[ref] = null
		else:
			var r := MapgenResolver.resolve(index, mapgen)
			chunk_cache[ref] = [r, Placement.read_all(mapgen, r.size)]
	return chunk_cache[ref]


## point::rotate: [param p] turned [param turns] quarter turns clockwise
## inside an area of [param dim].
static func rotate(p: Vector2i, turns: int, dim: Vector2i) -> Vector2i:
	match posmod(turns, 4):
		1: return Vector2i(dim.y - p.y - 1, p.x)
		2: return Vector2i(dim.x - p.x - 1, dim.y - p.y - 1)
		3: return Vector2i(p.y, dim.x - p.x - 1)
	return p


## The id drawn for a weighted list: the heaviest one that places
## something, the first on ties; "" when none does.
static func pick(options: Array) -> String:
	var best := ""
	var best_weight := 0
	for o: Array in options:
		if o[0] and o[0] != "null" and o[1] > best_weight:
			best = o[0]
			best_weight = o[1]
	return best


## The heaviest of [param refs] (a nested id's mapgens), the first on ties.
static func heaviest(refs: Array) -> DataIndex.MapgenRef:
	var best: DataIndex.MapgenRef = refs[0]
	for r: DataIndex.MapgenRef in refs:
		if r.weight > best.weight:
			best = r
	return best


## Every chunk id [param mapgen] (resolved as [param resolved]) can place
## itself: any option of its place_nested entries, and of the "nested"
## mappings of the symbols its rows use (its palettes' included).
static func placed_ids(mapgen: Dictionary, resolved: ResolvedMapgen) -> PackedStringArray:
	var obj: Variant = mapgen.get("object")
	var out := DataIndex.chunk_options({"place_nested": obj.get("place_nested")}) if obj is Dictionary \
			else PackedStringArray()
	for key in resolved.used_keys():
		for piece in _mapping_pieces(resolved, key):
			for id in DataIndex.chunk_options({"place_nested": [piece]}):
				if not out.has(id):
					out.append(id)
	return out


## The stamp whose chunk wrote cell [param cell] last, or null.
func stamp_at(cell: Vector2i) -> Stamp:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return null
	var i := owner[cell.y * size.x + cell.x]
	return stamps[i] if i >= 0 else null


## Stamps whose footprint holds [param cell], outermost (depth 0) first.
func stamps_at(cell: Vector2i) -> Array[Stamp]:
	var out: Array[Stamp] = []
	for s in stamps:
		if s.footprint.has_point(cell):
			out.append(s)
	out.sort_custom(func(a: Stamp, b: Stamp) -> bool: return a.depth < b.depth)
	return out


## A copy of this overlay's cells with stamp [param s] (of this overlay or
## one it was replayed from) placed again on top, [param p_forced] deciding
## its picks. Only the replayed stamps are in the copy's [member stamps], so
## [member owner] is meaningless there. The Validator lays each chunk pick
## over an overlay without that placement this way, instead of building the
## whole map again per pick (so the pick lands last, over later chunks).
func replay(s: Stamp, p_forced: Dictionary) -> ChunkOverlay:
	var o := ChunkOverlay.new()
	o.index = index
	o.objects = objects
	o.chunk_cache = chunk_cache
	o.forced = p_forced
	o.size = size
	o.ter = ter.duplicate()
	o.furn = furn.duplicate()
	o.owner = owner.duplicate()
	o.chunk_keys = chunk_keys.duplicate()
	o._place(s.piece, s.member, s.index, s.key, s.anchor, s.context)
	o.stamps[0].parent = -1
	return o


## The stamp with [param uid], or null.
func stamp_by_uid(uid: String) -> Stamp:
	for s in stamps:
		if s.uid == uid:
			return s
	return null


## The stamps chunk [param s] (one of [member stamps]) places itself.
func children(s: Stamp) -> Array[Stamp]:
	var out: Array[Stamp] = []
	var i := stamps.find(s)
	for t in stamps:
		if t.parent == i and i >= 0 and t != s:
			out.append(t)
	return out


## The depth-0 stamp of place_nested entry #[param i], or null.
func stamp_for(i: int) -> Stamp:
	for s in stamps:
		if s.depth == 0 and s.member == "place_nested" and s.index == i:
			return s
	return null


## True when [param other] leaves every cell as this one does.
func same_cells(other: ChunkOverlay) -> bool:
	return other != null and other.size == size and other.ter == ter and other.furn == furn \
			and other.owner == owner


## "path: problem" for every stamp with problems.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for s in stamps:
		for p in s.problems:
			out.append("%s: %s" % [s.path, p])
	return out

class_name Stairs
extends RefCounted
## Where a map may have stairs, and how a building's levels pair them up
## (game::find_stairs, BN 39f4883093 game.cpp):
## - Going up from a GOES_UP cell, the player lands on the same x,y of the
##   level above if it is GOES_DOWN (not DEEP_WATER), else on the nearest
##   GOES_DOWN cell (or t_manhole_cover) anywhere in that overmap tile.
##   Going down from GOES_DOWN, the same with GOES_UP cells below.
## - Only when the tile has none does the player land on the same x,y ("You
##   may be unable to return back down these stairs").
## - Terrain and furniture flags both count (map::has_flag).
## - DEEP_WATER cells aren't stairs: find_stairs skips them going up, and
##   the lake and sea beds that "go up" are swum through.
## TODO: elevators. find_stairs also takes t_elevator when moving 2 levels
## (movez +/- 2), which isn't paired here (PLAN.MD, Stage 10 "TODO").
##
## "May have": every id a cell can get counts (distributions, parameters,
## switches), and so do place_terrain / place_furniture / "set" entries
## over their whole range and every chunk any nested piece may pick (every
## option, mapgen, rotation and anchor). A stair that may be there is
## enough to pair with, so the check has no false "no stairs" findings from
## random choices.
##
## A [Grid] holds one bit set per cell of a map: [constant UP], [constant
## DOWN], [constant LANDING] (a cell the player may land on going up: DOWN
## or a manhole cover).

const UP := 1
const DOWN := 2
const LANDING := 4
const OMT := MapgenResolver.OMT_SIZE
const MANHOLE := "t_manhole_cover"
## place_* lists that set terrain or furniture, and the field naming it.
const TILE_MEMBERS := {"place_terrain": "ter", "place_furniture": "furn"}


## A map's stair cells.
class Grid:
	var size := Vector2i.ZERO
	var bits := PackedByteArray()

	func _init(p_size := Vector2i.ZERO) -> void:
		size = p_size
		bits.resize(size.x * size.y)

	func mark(c: Vector2i, b: int) -> void:
		if b and c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y:
			bits[c.y * size.x + c.x] |= b

	func at(c: Vector2i) -> int:
		return bits[c.y * size.x + c.x]

	## The cells of overmap tile [param tile] (in tiles) with bit [param b],
	## tile-local, row order.
	func cells(tile: Vector2i, b: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var o := tile * OMT
		for y in mini(OMT, size.y - o.y):
			for x in mini(OMT, size.x - o.x):
				if bits[(o.y + y) * size.x + o.x + x] & b:
					out.append(Vector2i(x, y))
		return out


var index: DataIndex
## (MapgenRef) -> its mapgen object.
var objects: Callable
## MapgenRef -> Grid of maps looked up (not the one being checked).
var grids := {}
## Chunk id -> Array of [size, Grid] (one per mapgen), [] while being
## worked out (a loop places nothing more).
var _chunks := {}
## Terrain / furniture id -> bits.
var _flags := {}
## Shared by the chunk overlays built here.
var _chunk_cache := {}


func _init(p_index: DataIndex, p_objects: Callable) -> void:
	index = p_index
	objects = p_objects


## The stair cells of [param mapgen] (resolved as [param resolved]; its
## chunk [param overlay], or null to lay them out here).
func grid_of(mapgen: Dictionary, resolved: ResolvedMapgen, overlay: ChunkOverlay = null) -> Grid:
	var g := Grid.new(resolved.size)
	var chunk := mapgen.has("nested_mapgen_id")
	for y in resolved.size.y:
		for x in resolved.size.x:
			var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(resolved.cells[y][x])
			var b := 0
			var ter: ResolvedMapgen.Binding = info.terrain if info else null
			if ter == null and not chunk:
				ter = resolved.fill_binding()
			if ter:
				b |= _bits_of(DataIndex.TYPE_TERRAIN, ter.ids)
			if info and info.furniture:
				b |= _bits_of(DataIndex.TYPE_FURNITURE, info.furniture.ids)
			g.mark(Vector2i(x, y), b)
	for p in Placement.read_all(mapgen, resolved.size):
		if p.status == Placement.Status.DROPPED or p.status == Placement.Status.CROSSES:
			continue
		var b := _placement_bits(p)
		if b == 0:
			continue
		for r in p.instances():
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					g.mark(Vector2i(x, y), b)
	if overlay == null or overlay.size != resolved.size:
		overlay = ChunkOverlay.build(index, mapgen, resolved, objects, {}, _chunk_cache)
	for s in overlay.stamps:
		if s.depth == 0:
			_stamp_into(g, s)
	return g


## The stair cells of [param ref] (cached).
func grid_for(ref: DataIndex.MapgenRef) -> Grid:
	if not grids.has(ref):
		var mapgen: Dictionary = objects.call(ref) if ref.method == "json" else {}
		if not mapgen.get("object") is Dictionary:
			grids[ref] = null
		else:
			grids[ref] = grid_of(mapgen, MapgenResolver.resolve(index, mapgen))
	return grids[ref]


## Bits a place_terrain / place_furniture / "set" entry may put down.
func _placement_bits(p: Placement) -> int:
	if p.is_set():
		var kind: Variant = null
		for op in ["point", "line", "square"]:
			kind = p.entry.get(op, kind)
		if kind == "terrain" or kind == "furniture":
			return _bits_of(kind, _ids(p.entry.get("id")))
		return 0
	if TILE_MEMBERS.has(p.member):
		var kind: String = DataIndex.TYPE_TERRAIN if p.member == "place_terrain" else DataIndex.TYPE_FURNITURE
		return _bits_of(kind, _ids(p.entry.get(TILE_MEMBERS[p.member])))
	return 0


## The plain ids in a place_* value (a string, or a list of alternatives).
static func _ids(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is String:
		out.append(v)
	elif v is Array:
		for e: Variant in v:
			if e is String:
				out.append(e)
			elif e is Array and not e.is_empty() and e[0] is String:
				out.append(e[0])
	return out


func _bits_of(kind: String, ids: PackedStringArray) -> int:
	var b := 0
	for id in ids:
		var k := kind + " " + id
		if not _flags.has(k):
			var def: DataIndex.TileDef = (index.terrain if kind == DataIndex.TYPE_TERRAIN else index.furniture).get(id)
			var f := 0
			# Deep water that goes up or down is swum through, not stairs.
			if def and not def.has_flag("DEEP_WATER"):
				if def.has_flag("GOES_UP"):
					f |= UP
				if def.has_flag("GOES_DOWN"):
					f |= DOWN | LANDING
			if id == MANHOLE:
				f |= LANDING
			_flags[k] = f
		b |= _flags[k]
	return b


## Marks every cell any pick of stamp [param s] may give stairs.
func _stamp_into(g: Grid, s: ChunkOverlay.Stamp) -> void:
	var ids := {}
	for o: Array in s.options + s.else_options:
		if o[0] and o[0] != "null":
			ids[o[0]] = true
	for id: String in ids:
		for v: Array in _chunk(id):
			var size: Vector2i = v[0]
			var cg: Grid = v[1]
			for cy in size.y:
				for cx in size.x:
					var b := cg.at(Vector2i(cx, cy))
					if b == 0:
						continue
					for rot in s.rotations:
						var t := ChunkOverlay.rotate(Vector2i(cx, cy), rot, size)
						for ay in range(s.anchor.position.y, s.anchor.end.y):
							for ax in range(s.anchor.position.x, s.anchor.end.x):
								g.mark(Vector2i(ax, ay) + t, b)


## [size, Grid] per mapgen of chunk [param id] that may put stairs down.
func _chunk(id: String) -> Array:
	if _chunks.has(id):
		return _chunks[id]
	_chunks[id] = []
	var out := []
	for ref: DataIndex.MapgenRef in index.nested.get(id, []):
		var mapgen: Dictionary = objects.call(ref)
		if not mapgen.get("object") is Dictionary:
			continue
		var r := MapgenResolver.resolve(index, mapgen)
		var cg := grid_of(mapgen, r)
		if _any(cg):
			out.append([r.size, cg])
	_chunks[id] = out
	return out


static func _any(g: Grid) -> bool:
	for b in g.bits:
		if b:
			return true
	return false

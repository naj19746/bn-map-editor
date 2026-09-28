class_name LevelNav
extends RefCounted
## The rest of a map's building level, drawn around the map in the viewer
## (the tiles and places come from BuildingLevels). Cells are counted from
## the current map's top-left cell, so a tile west or north of it has
## negative cells.

const OMT := MapgenResolver.OMT_SIZE


## One map drawn beside the current one: a mapgen (the first a level tile
## has) at its place, covering one or more of the level's tiles; or a single
## tile no mapgen draws (ref null). A multi-tile mapgen whose tiles the
## building turns is split into one piece per tile, each turned on its own,
## as BN runs and turns each 24x24 tile of it separately.
class Neighbor:
	var ref: DataIndex.MapgenRef
	## Top-left cell, relative to the current map's top-left.
	var cell := Vector2i.ZERO
	## In cells.
	var size := Vector2i(OMT, OMT)
	## The level tiles it covers.
	var tiles: Array[BuildingLevels.Tile] = []
	## The cells of [member ref]'s map it draws: all of them, or one tile's.
	var part := Rect2i()
	## Quarter turns clockwise it is drawn with: its tile's rotation (as BN
	## turns it), less the current map's tile's under it for a ghost piece
	## (see LevelNav.ghosts).
	var turn := 0
	## How it looks, filled in by the viewer (null: drawn as an outline):
	## [member part] of the map, turned (see shape()).
	var ascii: AsciiMap
	## Cells (in [member ascii], so turned) with stairs to the current
	## level, for a ghost: filled in by the viewer.
	var stairs: Array[Vector2i] = []
	## Its elevator floor cells (Stairs.ELEVATOR), like [member stairs].
	var elevators: Array[Vector2i] = []

	func turns() -> int:
		return turn

	## True when it draws one tile of a bigger map.
	func split() -> bool:
		return ref != null and part.size != ref.size_omt() * OMT

	func rect() -> Rect2i:
		return Rect2i(cell, size)

	## [param whole] ([member ref]'s map as drawn unturned) cut to
	## [member part] and turned.
	func shape(whole: AsciiMap) -> AsciiMap:
		if whole == null:
			return null
		if part.position == Vector2i.ZERO and part.size == whole.size and turn == 0:
			return whole
		return whole.piece(part, turn)

	## Where [param ref] map's cell [param c] is drawn, relative to
	## [member cell]; (-1, -1) outside [member part].
	func to_piece(c: Vector2i) -> Vector2i:
		if not part.has_point(c):
			return -Vector2i.ONE
		return ChunkOverlay.rotate(c - part.position, turn, part.size)

	## The map cell drawn at [param c] (relative to [member cell]).
	func to_ref(c: Vector2i) -> Vector2i:
		var dim := part.size if turn % 2 == 0 else Vector2i(part.size.y, part.size.x)
		return part.position + ChunkOverlay.rotate(c, -turn, dim)

	## Shown on the canvas: the tile's terrain, and what's special about it.
	func label() -> String:
		var t := tiles[0]
		var text := ref.title() if ref else t.tile.oter
		if ref == null:
			return text + " (no mapgen)"
		if split():
			var n := ref.size_omt()
			text = "%s (a tile of a %dx%d map)" % [t.tile.oter, n.x, n.y]
		if t.refs.size() > 1:
			text += " (1 of %d)" % t.refs.size()
		if turn:
			text += " (turned %s)" % DataIndex.DIRECTIONS[turn]
		return text


## The maps to draw around [param ref] (at [param place]) on its own level:
## every other tile of the level, grouped by the mapgen that draws it (a
## multi-tile mapgen once, unless the building turns its tiles), in the
## building's order, each turned as the building places it. A tile with
## several mapgens shows the first, or one of [param open] (the maps open in
## tabs).
static func neighbors(index: DataIndex, place: BuildingLevels.Place, ref: DataIndex.MapgenRef,
		open: Array = []) -> Array[Neighbor]:
	return _pieces(index, place, place.origin.z, ref, open, {})


## The whole of level [param z] of [param place]'s building, to draw under
## (or over) [param ref]: like neighbors(), without leaving anything out. A
## piece under the map is turned by its rotation less the rotation of the
## map's tile over it, so it lines up with the map as drawn (unturned); the
## others are turned like neighbors. With [param as_placed] (the map drawn
## as placed, see placed()), every piece is turned by its own rotation.
static func ghosts(index: DataIndex, place: BuildingLevels.Place, ref: DataIndex.MapgenRef, z: int,
		open: Array = [], as_placed := false) -> Array[Neighbor]:
	var from := {}
	if not as_placed:
		for p in placed_turns(place, ref):
			from[p[0] * OMT] = p[1]
	return _pieces(index, place, z, null, open, from)


## [param ref]'s map as [param place]'s building puts it down: one piece
## per overmap tile the building places where the map's layout has it,
## turned by that tile's rotation (all [member Neighbor.ref] is
## [param ref]). A tile the building puts elsewhere (a multi-tile map turned
## as a whole: its tiles trade places) is left out; it shows among the
## neighbors. [] when every tile is there unturned (drawn as it is).
static func placed(place: BuildingLevels.Place, ref: DataIndex.MapgenRef) -> Array[Neighbor]:
	var out: Array[Neighbor] = []
	var turns := placed_turns(place, ref)
	var size := ref.size_omt()
	var plain := turns.size() == size.x * size.y
	for p: Array in turns:
		var n := Neighbor.new()
		n.ref = ref
		n.cell = p[0] * OMT
		n.part = Rect2i(n.cell, n.size)
		n.turn = p[1]
		plain = plain and n.turn == 0
		out.append(n)
	if plain:
		out.clear()
	return out


## [tile, quarter turns] for each overmap tile of [param ref] (in tiles
## from its top-left) that [param place]'s building puts there: the
## rotation it gives the tile.
static func placed_turns(place: BuildingLevels.Place, ref: DataIndex.MapgenRef) -> Array:
	var out := []
	var size := ref.size_omt()
	if size == Vector2i.ONE:
		return [[Vector2i.ZERO, _turns(place.dir)]]
	for y in size.y:
		for x in size.x:
			var bt := place.building.at(place.origin + Vector3i(x, y, 0))
			if bt and ref.position_of(bt.oter) == Vector2i(x, y):
				out.append([Vector2i(x, y), _turns(bt.dir)])
	return out


static func _turns(dir: String) -> int:
	return maxi(0, DataIndex.DIRECTIONS.find(dir))


## The pieces of level [param z], leaving out [param skip]'s own tiles;
## [param from]: tile cell -> quarter turns taken off a piece there.
static func _pieces(index: DataIndex, place: BuildingLevels.Place, z: int, skip: DataIndex.MapgenRef,
		open: Array, from: Dictionary) -> Array[Neighbor]:
	var out: Array[Neighbor] = []
	var own := Rect2i(Vector2i.ZERO, skip.size_omt() * OMT) if skip else Rect2i()
	var by_key := {}
	for tile in BuildingLevels.level(index, place, z):
		if skip and own.has_point(tile.cell):
			continue
		var n: Neighbor = null
		var key := ""
		if not tile.missing():
			var r := tile.refs[0]
			for o: DataIndex.MapgenRef in tile.refs:
				if open.has(o):
					r = o
					break
			var at := r.position_of(tile.tile.oter)
			var cell := tile.cell - at * OMT
			key = "%d %s" % [r.get_instance_id(), cell]
			if skip and r == skip and cell == Vector2i.ZERO:
				continue
			n = by_key.get(key)
			if n == null:
				n = Neighbor.new()
				n.ref = r
				n.cell = cell
				n.size = r.size_omt() * OMT
				n.part = Rect2i(Vector2i.ZERO, n.size)
		if n == null:
			n = Neighbor.new()
			n.cell = tile.cell
		n.tiles.append(tile)
		if key and not by_key.has(key):
			by_key[key] = n
			out.append(n)
		elif not key:
			out.append(n)
	var turned: Array[Neighbor] = []
	for n in out:
		var turns := n.tiles.map(func(t: BuildingLevels.Tile) -> int:
				return posmod(_turns(t.tile.dir) - from.get(t.cell, 0), 4))
		if n.ref == null or n.ref.size_omt() == Vector2i.ONE or turns.all(func(t: int) -> bool: return t == 0):
			n.turn = turns[0] if n.ref == null or n.ref.size_omt() == Vector2i.ONE else 0
			turned.append(n)
			continue
		# BN turns each tile of a multi-tile map on its own.
		for i in n.tiles.size():
			var t := n.tiles[i]
			var piece := Neighbor.new()
			piece.ref = n.ref
			piece.tiles = [t] as Array[BuildingLevels.Tile]
			piece.cell = t.cell
			piece.part = Rect2i(n.ref.position_of(t.tile.oter) * OMT, piece.size)
			piece.turn = turns[i]
			turned.append(piece)
	return turned


## The neighbor under [param cell] (relative to the current map), or -1.
static func neighbor_at(list: Array[Neighbor], cell: Vector2i) -> int:
	for i in list.size():
		if list[i].rect().has_point(cell):
			return i
	return -1

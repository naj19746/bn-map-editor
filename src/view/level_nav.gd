class_name LevelNav
extends RefCounted
## The rest of a map's building level, drawn around the map in the viewer
## (the tiles and places come from BuildingLevels). Cells are counted from
## the current map's top-left cell, so a tile west or north of it has
## negative cells.

const OMT := MapgenResolver.OMT_SIZE


## One map drawn beside the current one: a mapgen (the first a level tile
## has) at its place, covering one or more of the level's tiles; or a single
## tile no mapgen draws (ref null).
class Neighbor:
	var ref: DataIndex.MapgenRef
	## Top-left cell, relative to the current map's top-left.
	var cell := Vector2i.ZERO
	## In cells.
	var size := Vector2i(OMT, OMT)
	## The level tiles it covers.
	var tiles: Array[BuildingLevels.Tile] = []
	## How it looks, filled in by the viewer (null: drawn as an outline).
	var ascii: AsciiMap
	## Cells (in [member ascii], so turned) with stairs to the current
	## level, for a ghost: filled in by the viewer.
	var stairs: Array[Vector2i] = []
	## Quarter turns taken off turns(): the current map's own, for a ghost
	## piece under it (see LevelNav.ghosts).
	var turned_from := 0

	## Quarter turns clockwise to draw it with: its tile's rotation (as BN
	## turns it) less [member turned_from]; only a one-tile map is drawn
	## turned (a turned multi-tile map is labelled).
	## TODO: turn multi-tile pieces too, neighbours and ghosts alike (PLAN.MD,
	## Stage 10 "TODO").
	func turns() -> int:
		if ref == null or ref.size_omt() != Vector2i.ONE:
			return 0
		return posmod(maxi(0, DataIndex.DIRECTIONS.find(tiles[0].tile.dir)) - turned_from, 4)

	func rect() -> Rect2i:
		return Rect2i(cell, size)

	## Shown on the canvas: the tile's terrain, and what's special about it.
	func label() -> String:
		var t := tiles[0]
		var text := ref.title() if ref else t.tile.oter
		if ref == null:
			return text + " (no mapgen)"
		if t.refs.size() > 1:
			text += " (1 of %d)" % t.refs.size()
		if t.tile.dir and t.tile.dir != "north":
			text += " (turned %s)" % t.tile.dir if turns() else " (%s: drawn unturned)" % t.tile.dir
		return text


## The maps to draw around [param ref] (at [param place]) on its own level:
## every other tile of the level, grouped by the mapgen that draws it (a
## multi-tile mapgen once), in the building's order. A tile with several
## mapgens shows the first, or one of [param open] (the maps open in tabs).
static func neighbors(index: DataIndex, place: BuildingLevels.Place, ref: DataIndex.MapgenRef,
		open: Array = []) -> Array[Neighbor]:
	return _pieces(index, place, place.origin.z, ref, open)


## The whole of level [param z] of [param place]'s building, to draw under
## (or over) [param ref]: like neighbors(), without leaving anything out. A
## one-tile piece under the map is turned by its rotation minus the map's,
## so it lines up with the map as drawn (unturned); the others are turned
## like neighbors.
static func ghosts(index: DataIndex, place: BuildingLevels.Place, ref: DataIndex.MapgenRef, z: int,
		open: Array = []) -> Array[Neighbor]:
	var out := _pieces(index, place, z, null, open)
	var own := Rect2i(Vector2i.ZERO, ref.size_omt() * OMT)
	var own_turns := maxi(0, DataIndex.DIRECTIONS.find(place.dir)) if ref.size_omt() == Vector2i.ONE else 0
	for n in out:
		if own.intersects(n.rect()):
			n.turned_from = own_turns
	return out


## The pieces of level [param z], leaving out [param skip]'s own tiles.
static func _pieces(index: DataIndex, place: BuildingLevels.Place, z: int, skip: DataIndex.MapgenRef,
		open: Array) -> Array[Neighbor]:
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
		if n == null:
			n = Neighbor.new()
			n.cell = tile.cell
		n.tiles.append(tile)
		if key and not by_key.has(key):
			by_key[key] = n
			out.append(n)
		elif not key:
			out.append(n)
	return out


## The neighbor under [param cell] (relative to the current map), or -1.
static func neighbor_at(list: Array[Neighbor], cell: Vector2i) -> int:
	for i in list.size():
		if list[i].rect().has_point(cell):
			return i
	return -1

class_name BuildingLevels
extends RefCounted
## Where a map sits in the buildings that place it (DataIndex.Building), and
## the tiles of each level of those buildings, with the mapgens that draw
## them: what level up / level down steps to, what the stair check pairs.
##
## A map's place is a building plus the building point of the map's top-left
## overmap tile. Tile cells are counted from the current map's top-left
## cell, so a tile west or north of it has negative cells.

const OMT := MapgenResolver.OMT_SIZE


## One building that places a map, and where.
class Place:
	var building: DataIndex.Building
	## The building point of the map's top-left overmap tile.
	var origin := Vector3i.ZERO
	## The rotation the building places the map's tile with ("" or "north":
	## as drawn).
	var dir := ""

	func label() -> String:
		return "%s (%d, %d, z %d)" % [building.id, origin.x, origin.y, origin.z]

	## Says when the building turns the map (the editor shows it unturned).
	func turn_note() -> String:
		return "" if dir == "" or dir == "north" else "placed turned %s here; shown unturned" % dir


## One overmap tile of a level, with the mapgens BN may pick for it.
class Tile:
	var tile: DataIndex.BuildingTile
	## Its om_terrain mapgens: the ones BN loads first, then disabled ones.
	var refs: Array[DataIndex.MapgenRef] = []
	## The tile's top-left cell, relative to the current map's top-left.
	var cell := Vector2i.ZERO

	## True when no mapgen draws the tile (BN leaves it to its fallbacks).
	func missing() -> bool:
		return refs.is_empty()


## Every building that places one of [param ref]'s overmap terrains, with
## the point its top-left tile lands on; mutable specials are left out (they
## have no fixed points).
static func places(index: DataIndex, ref: DataIndex.MapgenRef) -> Array[Place]:
	var out: Array[Place] = []
	if ref == null or ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		return out
	var seen := {}
	for id in ref.ids:
		var at := ref.position_of(id)
		for t in index.buildings_using(id):
			if not t.placed or not index.buildings.has(t.building):
				continue
			var origin := t.point - Vector3i(at.x, at.y, 0)
			var key := "%s %s" % [t.building, origin]
			if seen.has(key):
				continue
			seen[key] = true
			var p := Place.new()
			p.building = index.buildings[t.building]
			p.origin = origin
			p.dir = t.dir
			out.append(p)
	return out


## The mutable specials that have one of [param ref]'s overmap terrains
## among their pieces (they have no fixed points, so places() leaves them
## out).
static func mutable_specials(index: DataIndex, ref: DataIndex.MapgenRef) -> Array[DataIndex.Building]:
	var out: Array[DataIndex.Building] = []
	if ref == null or ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		return out
	for id in ref.ids:
		for t in index.buildings_using(id):
			var b: DataIndex.Building = index.buildings.get(t.building)
			if b and b.mutable and not out.has(b):
				out.append(b)
	return out


## The om_terrain mapgens for [param oter]: enabled ones first.
static func mapgens(index: DataIndex, oter: String) -> Array[DataIndex.MapgenRef]:
	var out: Array[DataIndex.MapgenRef] = []
	var off: Array[DataIndex.MapgenRef] = []
	for r: DataIndex.MapgenRef in index.om_terrain.get(oter, []):
		(off if r.disabled else out).append(r)
	out.append_array(off)
	return out


## The tiles of level [param z] of [param place]'s building.
static func level(index: DataIndex, place: Place, z: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for t in place.building.level(z):
		var tile := Tile.new()
		tile.tile = t
		tile.refs = mapgens(index, t.oter)
		tile.cell = Vector2i(t.point.x - place.origin.x, t.point.y - place.origin.y) * OMT
		out.append(tile)
	return out


## The tile to go to on level [param z] from a map of [param size_omt] tiles
## at [param place]: one under the map's footprint (top-left first), else
## the nearest one; null when the building has no level [param z].
static func step(index: DataIndex, place: Place, size_omt: Vector2i, z: int) -> Tile:
	var best: Tile = null
	var best_d := 0
	for tile in level(index, place, z):
		var d := _distance(tile.cell / OMT, size_omt)
		if best == null or d < best_d:
			best = tile
			best_d = d
	return best


## 0 inside the map's footprint (ordered top-left first), else the distance
## outside it (plus a bias so any inside tile wins).
static func _distance(at: Vector2i, size_omt: Vector2i) -> int:
	if at.x >= 0 and at.y >= 0 and at.x < size_omt.x and at.y < size_omt.y:
		return at.y * size_omt.x + at.x
	var dx := maxi(0, maxi(-at.x, at.x - size_omt.x + 1))
	var dy := maxi(0, maxi(-at.y, at.y - size_omt.y + 1))
	return size_omt.x * size_omt.y + dx + dy


## Where [param ref] sits when it draws [param tile]: its place in the
## tile's building.
static func place_of(index: DataIndex, tile: DataIndex.BuildingTile, ref: DataIndex.MapgenRef) -> Place:
	var p := Place.new()
	p.building = index.buildings[tile.building]
	var at := ref.position_of(tile.oter)
	p.origin = tile.point - Vector3i(maxi(at.x, 0), maxi(at.y, 0), 0)
	p.dir = tile.dir
	return p


## An om_terrain id for a new level [param dz] away from a map of
## [param id], not used yet: "house_2" above "house_1" (else "house_2" above
## "house"), "house_roof" for a roof ([param roof]), "house_basement" below.
static func new_level_id(index: DataIndex, id: String, dz: int, roof := false) -> String:
	var base := id
	var n := -1
	var cut := id.rfind("_")
	if cut > 0 and id.substr(cut + 1).is_valid_int():
		base = id.left(cut)
		n = int(id.substr(cut + 1))
	for suffix in ["_roof", "_basement", "_ground"]:
		base = base.trim_suffix(suffix)
	var want := base + "_roof" if roof else base + "_basement" if dz < 0 \
			else "%s_%d" % [base, n + 1 if n >= 0 else 2]
	var out := want
	var k := 2
	while index.om_terrain.has(out) or index.overmap_terrain.has(out):
		out = "%s_%d" % [want, k]
		k += 1
	return out


## True when om_terrain [param id] names a roof: "roof" is one of its
## "_"-separated words ("house_roof", "house_roof_nw", "roof_2").
static func is_roof_id(id: String) -> bool:
	return id.to_lower().split("_").has("roof")


## [fill_ter, palettes] to start a new level at [param z] with (suggestions,
## from core's city buildings): a roof t_flat_roof and roof_palette; below
## ground t_thconc_floor; an upper floor [param fill_near] (the fill of the
## floor it is added to) unless that is the ground floor's, else t_floor.
## Terrain or palettes the index lacks are left out.
static func new_level_defaults(index: DataIndex, z: int, roof: bool, fill_near: String,
		near_z: int) -> Array:
	var fill := "t_floor"
	var palettes := PackedStringArray()
	if roof:
		fill = "t_flat_roof"
		if index.palette("roof_palette"):
			palettes.append("roof_palette")
	elif z < 0:
		fill = "t_thconc_floor"
	elif fill_near and near_z > 0:
		fill = fill_near
	if not index.terrain.has(fill):
		fill = fill_near if index.terrain.has(fill_near) else ""
	return [fill, palettes]

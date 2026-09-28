class_name RoofHints
extends RefCounted
## Where a roof and the level under it disagree, compared as the canvas
## draws them (the map, or its pieces as placed, over the ghost level's
## pieces, each turned as LevelNav turns it): a hint on the canvas, not a
## finding (BN builds whatever the rows say).
## - OVERHANG: the roof has something there (not open air) over a cell
##   below that isn't part of the building (its terrain has no "roof":
##   grass, pavement), so the roof runs past the outer walls.
## - UNCOVERED: the roof is open air over a building cell below (a floor,
##   wall, door or window: its terrain has a "roof"), so the interior is
##   open to the sky.
## Cells the ghost doesn't cover (no tile below there) aren't judged.

enum Kind { OVERHANG = 1, UNCOVERED = 2 }


## Canvas cell -> Kind for the cells of [param top] (pieces: [AsciiMap,
## top-left cell] pairs, the map or its placed tiles) over [param ghosts]
## (the level below).
static func find(top: Array, ghosts: Array[LevelNav.Neighbor]) -> Dictionary:
	var out := {}
	for g in ghosts:
		if g.ascii == null:
			continue
		var below := g.ascii
		var g_rect := Rect2i(g.cell, below.size)
		for t: Array in top:
			var a: AsciiMap = t[0]
			var at: Vector2i = t[1]
			var both := g_rect.intersection(Rect2i(at, a.size))
			for y in range(both.position.y, both.end.y):
				for x in range(both.position.x, both.end.x):
					var i := (y - at.y) * a.size.x + (x - at.x)
					var j := (y - g.cell.y) * below.size.x + (x - g.cell.x)
					if a.states[i] == AsciiMap.State.EMPTY:
						continue
					var open := a.see_through[i] == 1
					if not open and below.roofed[j] == 0 and below.states[j] != AsciiMap.State.EMPTY:
						out[Vector2i(x, y)] = Kind.OVERHANG
					elif open and below.roofed[j] == 1:
						out[Vector2i(x, y)] = Kind.UNCOVERED
	return out


## True when [param place] puts [param ref] above ground with nothing
## above any of its tiles: the building's roof there.
static func is_roof(place: BuildingLevels.Place, ref: DataIndex.MapgenRef) -> bool:
	if place.origin.z <= 0:
		return false
	for id in ref.ids:
		var at := ref.position_of(id)
		if place.building.at(place.origin + Vector3i(at.x, at.y, 1)):
			return false
	return true

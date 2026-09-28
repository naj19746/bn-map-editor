extends "res://tests/support/test_case.gd"
## Stage 7 acceptance on core data: BN's CI loads core with its checks on, so
## every core json mapgen and palette must validate with NO errors, and the
## warnings and notes must match independent counts over data/json (PLAN.MD,
## Stage 7): 19 dropped anchors, 209 dropped "set" in 44 maps, 0 place_items
## chances outside 1-100 (warnings); 54 reversed spans, 13 place_* past a
## chunk's mapgensize, 574 chunk rotations that do nothing, 284 overhangs,
## 259 conditional nested pieces (notes); the 10 weight-0 mapgens skipped.
## Computers (Stage 8): no console without options or a stand cell and no
## door option that reaches nothing (warnings); 17 consoles with other
## locked doors in reach and 15 console pairs sharing doors (notes), as an
## independent Python pass over the om_terrain maps counts. Chunk consoles
## (Stage 8d): every pick of every placement (417 console placements, 118
## with door options) reaches its doors, no console lands past its tile,
## and the 27 door consoles of chunks opened alone reach theirs, as an
## independent Python pass over every json mapgen counts (pick by pick).
## Stairs between levels (Stage 10c): warnings where the next level has none
## back, notes for pairs in other cells and stairs leaving the building.
## Elevators (Stage 11b): controls offering no other floor, floors off
## reach, controls with no car beside them.

const BnEnv := preload("res://tests/support/bn_env.gd")
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


func test_core_validates() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var stairs := Stairs.new(index, objects.object_for)
	var t := Time.get_ticks_msec()
	var errors := PackedStringArray()
	var counts := {}
	var set_maps := {}
	var maps := 0
	for ref in index.mapgens:
		if ref.method != "json":
			continue
		maps += 1
		var mapgen := objects.object_for(ref)
		var resolved := MapgenResolver.resolve(index, mapgen)
		var placements := Placement.read_all(mapgen, resolved.size)
		var overlay := ChunkOverlay.build(index, mapgen, resolved, objects.object_for)
		for f in Validator.validate_map(index, ref, mapgen, resolved, placements, overlay, stairs):
			var code: String = Validator.Code.keys()[f.code]
			counts[code] = counts.get(code, 0) + 1
			if f.code == Validator.Code.DROPPED_SET:
				set_maps[ref] = true
			if f.severity == Validator.Severity.ERROR:
				errors.append("%s #%d %s: %s" % [ref.source.path, ref.source.index, ref.title(), f.describe()])
	var palettes := 0
	for id: String in index.palettes:
		palettes += 1
		for f in Validator.validate_palette(index, id, index.palette(id).data):
			var code: String = "palette " + Validator.Code.keys()[f.code]
			counts[code] = counts.get(code, 0) + 1
			if f.severity == Validator.Severity.ERROR:
				errors.append(f.describe())
	print("     validated %d maps and %d palettes in %d ms: %s" % [maps, palettes, Time.get_ticks_msec() - t, counts])
	check_eq(errors.slice(0, MAX_REPORTED), PackedStringArray(), "%d errors" % errors.size())
	# Warnings.
	check_eq(counts.get("DROPPED", 0), 19, "place_* anchored outside their map")
	check_eq(counts.get("DROPPED_SET", 0), 209, "dropped set entries")
	check_eq(set_maps.size(), 44, "maps with dropped set entries")
	check_eq(counts.get("ITEMS_CHANCE", 0), 0, "place_items chances outside 1-100")
	for code in ["NO_OPTIONS", "NO_STAND", "NO_DOOR", "COMPUTER_IGNORED", "palette NO_OPTIONS", "CHUNK_CONSOLE",
			"CONSOLE_OVERHANG"]:
		check_eq(counts.get(code, 0), 0, code)
	# Notes.
	check_eq(counts.get("SPANS_BACK", 0), 54, "reversed ranges reaching into the previous tile")
	check_eq(counts.get("OUTSIDE_CHUNK", 0), 13, "place_* past a chunk's mapgensize")
	check_eq(counts.get("CHUNK_ROTATION", 0), 574, "chunk rotations that do nothing")
	check_eq(counts.get("OVERHANG", 0), 284, "chunks reaching past their tile")
	check_eq(counts.get("CONDITIONAL", 0), 259, "conditional nested pieces")
	check_eq(counts.get("DISABLED", 0), 10, "weight-0 mapgens skipped")
	check_eq(counts.get("OTHER_LOCKED", 0), 17, "consoles with other locked doors in reach")
	check_eq(counts.get("SHARED_DOOR", 0), 15, "console pairs sharing doors")
	check_eq(counts.get("DOOR_ELSEWHERE", 0), 0, "door options relying on set/place_terrain")
	check_eq(counts.get("EDGE_CONSOLE", 0), 0, "chunk consoles standable only outside the chunk")
	# Stairs (Stage 10c): the editor's own count, not an independent one;
	# spot-checked (house_31 has no stairs down to its basement, and
	# apartments_mod_tower_NW's stairs up are 3 cells off the floor above's).
	check_eq(counts.get("STAIRS", 0), 20, "stairs with none back on the next level (warnings)")
	check_eq(counts.get("STAIRS_OFFSET", 0), 249, "stairs paired with stairs elsewhere in the tile")
	check_eq(counts.get("STAIRS_NO_TILE", 0), 4, "stairs out of the building")
	# Elevators (Stage 11b): the editor's own count; spot-checked (the steel
	# mill's z 1 has open air where z 0's car would arrive, mall_b_25's second
	# control has no car beside it). The stair counts above didn't change:
	# BN never pairs ELEVATOR cells as stairs.
	check_eq(counts.get("ELEVATOR", 0), 5, "elevator controls offering no other floor (warnings)")
	check_eq(counts.get("ELEVATOR_OFFSET", 0), 18, "controls with no car beside them, or floors too far off")
	check_eq(counts.get("ELEVATOR_ON", 0), 0, "elevator_on with no powerless controls on the level")


## Stage 11d: every core building validates with no errors (overmap terrain
## ids, duplicated points) and every tile has something to draw it; the
## city_buildings no region's city list names are notes. An independent
## Python pass over data/json at BN 39f4883093 finds 400 of 406 city_building
## ids in a city list (the other 6 spawn by other routes).
func test_core_buildings() -> void:
	var index := _core_index()
	if index == null:
		return
	var counts := {}
	var errors := PackedStringArray()
	for id: String in index.buildings:
		for f in Validator.validate_building(index, index.buildings[id]):
			var code: String = Validator.Code.keys()[f.code]
			counts[code] = counts.get(code, 0) + 1
			if f.severity != Validator.Severity.NOTE and errors.size() < MAX_REPORTED:
				errors.append(f.describe())
	check_eq(errors, PackedStringArray(), "no errors or warnings")
	check_eq(counts, {"CITY_LIST": 6}, "unlisted city_buildings")

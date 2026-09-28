extends "res://tests/support/test_case.gd"
## Stage 1 acceptance: index the real BN checkout and resolve its mapgens.

const BnEnv := preload("res://tests/support/bn_env.gd")
const MAX_REPORTED := 20

## Indexing core takes a few seconds, so tests share one index.
static var _core: DataIndex


func _core_index() -> DataIndex:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	if _core == null:
		var t := Time.get_ticks_msec()
		_core = DataIndex.load_bn(bn)
		print("     indexed %d files in %d ms" % [_core.file_count, Time.get_ticks_msec() - t])
	return _core


func test_core_index() -> void:
	var index := _core_index()
	if index == null:
		return
	check_eq(index.errors, PackedStringArray())
	check_eq(index.mods, PackedStringArray(["bn"]))
	check(index.terrain.size() > 800, "terrain: %d" % index.terrain.size())
	check(index.furniture.size() > 400, "furniture: %d" % index.furniture.size())
	check(index.palettes.size() > 150, "palettes: %d" % index.palettes.size())
	check(index.item_groups.size() > 1000, "item groups: %d" % index.item_groups.size())
	check(index.monster_groups.size() > 100, "monster groups: %d" % index.monster_groups.size())
	check(index.om_terrain.size() > 2000, "om_terrain ids: %d" % index.om_terrain.size())
	check(index.nested.size() > 1000, "nested ids: %d" % index.nested.size())

	var floor: DataIndex.TileDef = index.terrain.get("t_floor")
	if check(floor != null, "t_floor"):
		check_eq(floor.source.path, "data/json/furniture_and_terrain/terrain-floors-indoor.json")
	# Terrain outside furniture_and_terrain is found by type, not folder.
	var outside := 0
	for id: String in index.terrain:
		if not index.terrain[id].source.path.begins_with("data/json/furniture_and_terrain/"):
			outside += 1
	check(outside > 0, "terrain defined outside furniture_and_terrain")

	# copy-from resolved: every tile has a symbol and color for all seasons.
	var bad := PackedStringArray()
	for table: Dictionary in [index.terrain, index.furniture]:
		for id: String in table:
			var t: DataIndex.TileDef = table[id]
			for s in 4:
				if t.ascii(s).length() != 1 or t.color[s].is_empty():
					bad.append("%s (%s)" % [id, t.source])
					break
	check_eq(bad.slice(0, MAX_REPORTED), PackedStringArray(), "tiles without symbol/color")
	check_eq(index.terrain["t_wall"].symbol[0], "LINE_OXOX")
	check_eq(index.terrain["t_wall"].ascii(), "─")
	check_eq(index.furniture["f_null"].source.path, "", "built-in")



## Stage 10a: city_building / overmap_special z-stacks in core.
func test_core_buildings() -> void:
	var index := _core_index()
	if index == null:
		return
	var b: DataIndex.Building = index.buildings.get("2Story02")
	if check(b != null, "2Story02"):
		check_eq(b.levels(), PackedInt32Array([-1, 0, 1, 2]))
		var ids := PackedStringArray()
		for z in b.levels():
			ids.append(b.at(Vector3i(0, 0, z)).oter)
		check_eq(ids, PackedStringArray(["2Story02_basement", "2Story02_1", "2Story02_2", "2Story02_roof"]))
		for id in ids:
			check(not index.mapgens_for(id).is_empty(), "a mapgen for " + id)
	var roof := index.buildings_using("2Story02_roof")
	check_eq(roof.size(), 1)
	check_eq(roof[0].building, "2Story02")
	check_eq(roof[0].point, Vector3i(0, 0, 2))
	# house_04_roof tops several houses.
	var users := PackedStringArray()
	for t in index.buildings_using("house_04_roof"):
		users.append(t.building)
	check(users.has("house_04") and users.has("house_05"), str(users))
	# Counts (2026-09-28): 406 city_building + 237 overmap_special, 10 mutable.
	var mutable := 0
	var multi_z := 0
	for id: String in index.buildings:
		var bld: DataIndex.Building = index.buildings[id]
		mutable += int(bld.mutable)
		multi_z += int(bld.levels().size() > 1)
	check(index.buildings.size() >= 600, "buildings: %d" % index.buildings.size())
	check(mutable >= 8, "mutable: %d" % mutable)
	check(multi_z >= 500, "multi-level: %d" % multi_z)
	# Every placed tile's terrain is a known overmap_terrain once its suffix is gone
	# (linear ones like subway_ns keep their line suffix: BN's om_lines).
	var unknown := PackedStringArray()
	for oter: String in index.building_tiles:
		var linear := oter.substr(0, oter.rfind("_"))
		if not index.has_overmap_terrain(oter) and not index.has_overmap_terrain(linear):
			unknown.append(oter)
	check_eq(unknown.slice(0, MAX_REPORTED), PackedStringArray(), "unknown overmap terrains")

func test_apartments_mod_tower() -> void:
	var index := _core_index()
	if index == null:
		return
	var refs: Array = index.om_terrain.get("apartments_mod_tower_NW", [])
	if not check_eq(refs.size(), 1, "mapgens for apartments_mod_tower_NW"):
		return
	var ref: DataIndex.MapgenRef = refs[0]
	check_eq(ref.source.path, "data/json/mapgen/apartment_mod.json")
	check_eq(ref.size_omt(), Vector2i(2, 2))
	check_eq(ref.position_of("apartments_mod_tower_SE"), Vector2i(1, 1))
	check_eq(ref.weight, 250)
	check(index.om_terrain["apartments_mod_tower_SE"][0] == ref, "each id of the grid maps to the entry")

	var r := MapgenResolver.resolve(index, index.read_object(ref.source))
	check_eq(r.problems, PackedStringArray())
	check_eq(r.size, Vector2i(48, 48))
	check_eq(r.palettes, PackedStringArray(["apartment_palette"]))
	var sources := {}
	var missing := 0
	for y in r.size.y:
		for x in r.size.x:
			var t := r.terrain_at(x, y)
			if t == null or t.id().is_empty() or not index.terrain.has(t.id()):
				missing += 1
			else:
				sources[t.source] = true
	check_eq(missing, 0, "cells without a known terrain")
	check(sources.has("apartment_palette") and sources.has(ResolvedMapgen.SOURCE_FILL),
			"sources: %s" % [sources.keys()])


## Every core json mapgen resolves without problems, except known BN data
## issues, which are listed so a change shows up.
func test_all_core_mapgens_resolve() -> void:
	var index := _core_index()
	if index == null:
		return
	var bad := PackedStringArray()
	var count := _resolve_all(index, "bn", bad)
	check(count > 4000, "mapgens resolved: %d" % count)
	check_eq(bad.size(), 0, "problems")


## Resolves every json om_terrain/nested mapgen from [param only_mod] (all if
## ""), appending problems to [param bad]. Returns how many were resolved.
static func _resolve_all(index: DataIndex, only_mod: String, bad: PackedStringArray) -> int:
	var t := Time.get_ticks_msec()
	var objects := {}
	var count := 0
	for ref in index.mapgens:
		if ref.method != "json" or ref.kind == DataIndex.MapgenRef.UPDATE:
			continue
		if only_mod and ref.source.mod != only_mod:
			continue
		if not objects.has(ref.source.path):
			var json := JSON.new()
			json.parse(FileAccess.get_file_as_string(index.bn_path.path_join(ref.source.path)))
			objects[ref.source.path] = json.data if json.data is Array else [json.data]
		count += 1
		var r := MapgenResolver.resolve(index, objects[ref.source.path][ref.source.index])
		for p in r.problems:
			bad.append("%s: %s" % [ref.source, p])
	print("     resolved %d mapgens in %d ms, %d problems" % [count, Time.get_ticks_msec() - t, bad.size()])
	for i in mini(bad.size(), MAX_REPORTED):
		print("     " + bad[i])
	return count


func test_all_mods_index() -> void:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return
	var catalog := ModCatalog.scan(bn)
	check_eq(catalog.errors, PackedStringArray())
	var all := PackedStringArray()
	for id: String in catalog.mods:
		var mod := catalog.get_mod(id)
		if not mod.core and not mod.obsolete:
			all.append(id)
	all.sort()
	var t := Time.get_ticks_msec()
	var index := DataIndex.load_bn(bn, all, catalog)
	print("     %d mods, %d files in %d ms" % [index.mods.size(), index.file_count, Time.get_ticks_msec() - t])
	check(index.mods.size() > 50, "mods loaded: %d" % index.mods.size())
	for e in index.errors:
		check(e.contains(" conflicts with "), "only mod conflicts expected: " + e)
	var bad := PackedStringArray()
	_resolve_all(index, "", bad)
	check_eq(bad.size(), 0, "problems")
	for id in index.mods:
		for dep in catalog.get_mod(id).dependencies:
			check(index.mods.find(dep) < index.mods.find(id), "%s loads after its dependency %s" % [id, dep])

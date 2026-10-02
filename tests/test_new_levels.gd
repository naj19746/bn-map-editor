extends "res://tests/support/test_case.gd"
## Stage 10d: new levels of a building (its "overmaps" edited through the
## session, overmap_terrain stubs with a level's base, suggested fills) and
## new buildings with their city list entry, against a fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _ws := ""
var _index: DataIndex


static func _map(om: String, fill := "t_floor") -> Dictionary:
	var rows := []
	for y in 24:
		rows.append(".".repeat(24))
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": {"fill_ter": fill, "rows": rows}}


## - tall: z 0 tall_1, z 1 tall_2 (its entry has "locations"); twin copies
##   tall's overmaps; rules is a mutable special.
## - mymod has house_m (no building) for a new building in a mod.
func _setup() -> void:
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/mods/mymod/modinfo.json": [{"type": "MOD_INFO", "id": "mymod", "name": "My mod",
				"dependencies": ["bn"]}],
		"data/mods/mymod/house_m.json": [_map("house_m"),
				{"type": "overmap_terrain", "id": "house_m", "copy-from": "generic_city_building"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_grass", "symbol": ".", "color": "green", "move_cost": 2},
			{"type": "terrain", "id": "t_flat_roof", "symbol": ".", "color": "white", "move_cost": 2}],
		"data/json/palettes.json": [{"type": "palette", "id": "roof_palette", "terrain": {"#": "t_flat_roof"}}],
		"data/json/oter.json": [
			{"type": "overmap_terrain", "abstract": "generic_city_building", "name": "building"},
			{"type": "overmap_terrain", "abstract": "generic_up", "name": "upstairs"},
			{"type": "overmap_terrain", "id": "tall_1", "copy-from": "generic_city_building"},
			{"type": "overmap_terrain", "id": "tall_2", "copy-from": "generic_up"}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "tall", "locations": ["land"], "overmaps": [
				{"point": [0, 0, 0], "overmap": "tall_1_north"},
				{"point": [0, 0, 1], "overmap": "tall_2_north", "locations": ["land"]}]},
			{"type": "city_building", "id": "twin", "copy-from": "tall"},
			{"type": "overmap_special", "id": "rules", "subtype": "mutable",
				"overmaps": {"a": {"overmap": "tall_1_north"}}}],
		"data/json/regional_map_settings.json": [{"type": "region_settings", "id": "default",
				"city": {"shop_radius": 30, "houses": {"tall": 100}}}],
		"data/json/mapgen/tall.json": [_map("tall_1", "t_grass"), _map("tall_2")],
	})
	_ws = TempTree.make({})
	_index = DataIndex.load_bn(_root, PackedStringArray(["mymod"]))


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


func _session() -> EditSession:
	return EditSession.new(_index, Workspace.open(_ws, _root))


func test_suggestions() -> void:
	_setup()
	check_eq(_index.errors, PackedStringArray())
	check_eq(BuildingLevels.new_level_id(_index, "tall_2", 1), "tall_3")
	check_eq(BuildingLevels.new_level_id(_index, "tall_2", 1, true), "tall_roof")
	check_eq(BuildingLevels.new_level_id(_index, "tall_1", -1), "tall_basement")
	check_eq(BuildingLevels.new_level_id(_index, "house", 1), "house_2")
	check_eq(BuildingLevels.new_level_id(_index, "tall_1", 1), "tall_2_2", "tall_2 is taken")
	check_eq(BuildingLevels.new_level_defaults(_index, 2, true, "t_floor", 1),
			["t_flat_roof", PackedStringArray(["roof_palette"])], "a roof")
	check_eq(BuildingLevels.new_level_defaults(_index, 1, false, "t_grass", 0)[0], "t_floor",
			"not the ground floor's grass")
	check_eq(BuildingLevels.new_level_defaults(_index, 2, false, "t_grass", 1)[0], "t_grass",
			"an upper floor's fill")
	check_eq(BuildingLevels.new_level_defaults(_index, -1, false, "t_grass", 0)[0], "t_grass",
			"t_thconc_floor isn't loaded here: the floor's fill")

	var session := _session()
	check_eq(session.level_stub_base("tall", Vector3i(0, 0, 2)), "generic_up", "like z 1's")
	check_eq(session.level_stub_base("tall", Vector3i(0, 0, 2), true), "generic_up")
	check_eq(session.level_stub_base("tall", Vector3i(0, 0, -1)), EditSession.BASEMENT_STUB_BASE)
	check_eq(session.level_stub_base("tall", Vector3i(5, 5, 1), true), EditSession.ROOF_STUB_BASE)
	check_eq(session.level_stub_base("nope", Vector3i(0, 0, 1)), EditSession.OVERMAP_STUB_BASE)

	check(session.check_level_tiles("tall", [[Vector3i(0, 0, 1), "x_north"]]).contains("already has tall_2"))
	check(session.check_level_tiles("rules", []).contains("mutable"))
	check_eq(session.check_level_tiles("twin", [[Vector3i(0, 0, 2), "x_north"]]), "")
	check(session.level_tiles_note("twin").contains("the definition of tall it copies them from"),
			session.level_tiles_note("twin"))
	check(session.level_tiles_note("tall").contains("twin gets them too"), session.level_tiles_note("tall"))
	_cleanup()


func test_new_level() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/tall.json"
	spec.ids = [PackedStringArray(["tall_3"])] as Array[PackedStringArray]
	spec.fill_ter = "t_floor"
	spec.overmap_base = session.level_stub_base("tall", Vector3i(0, 0, 2))
	spec.level = EditSession.LevelTarget.new()
	spec.level.building = "twin"
	spec.level.origin = Vector3i(0, 0, 2)
	var doc := session.create_mapgen(spec)
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	var tall: DataIndex.Building = _index.buildings["tall"]
	var t := tall.at(Vector3i(0, 0, 2))
	if check(t != null, "added to the list twin copies"):
		check_eq(t.oter, "tall_3")
		check_eq(t.dir, "north")
	check(_index.buildings["twin"].at(Vector3i(0, 0, 2)) != null, "twin sees it")
	check_eq(BuildingLevels.places(_index, doc.ref).size(), 2)
	var b_rel := "data/json/buildings.json"
	var dirty := session.dirty_files()
	dirty.sort()
	check_eq(dirty, PackedStringArray([b_rel, spec.rel_path]))
	check_eq(session.linked_files(spec.rel_path), PackedStringArray([b_rel]))
	var entry: Dictionary = session.files[b_rel].objects[0].overmaps[2]
	check_eq(entry.point, [0, 0, 2], "ints")
	check_eq(entry.overmap, "tall_3_north")
	check_eq(entry.get("locations"), ["land"], "like the entries at the same x, y")
	var stub: Dictionary = session.files[spec.rel_path].objects[-1]
	check_eq(stub.get("copy-from"), "generic_up")
	check_eq(stub.id, "tall_3")

	# A second level on top; then discarding the map takes both back out.
	var roof := EditSession.NewMapgen.new()
	roof.rel_path = spec.rel_path
	roof.ids = [PackedStringArray(["tall_roof"])] as Array[PackedStringArray]
	roof.fill_ter = "t_flat_roof"
	roof.level = EditSession.LevelTarget.new()
	roof.level.building = "tall"
	roof.level.origin = Vector3i(0, 0, 3)
	roof.level.dir = ""
	check(session.create_mapgen(roof) != null, session.last_error)
	check_eq(tall.at(Vector3i(0, 0, 3)).oter, "tall_roof", "no rotation suffix")
	check_eq(session.files[b_rel].objects[0].overmaps[3].overmap, "tall_roof")
	session.discard(spec.rel_path)
	check_eq(session.files.size(), 0, "the building file went with the map")
	check_eq(tall.at(Vector3i(0, 0, 2)), null, "back as on disk")
	check_eq(tall.levels(), PackedInt32Array([0, 1]))
	check_eq(_index.buildings_using("tall_3").size(), 0)

	doc = session.create_mapgen(spec)
	check_eq(session.save_all(), PackedStringArray())
	var saved := FileAccess.get_file_as_string(_ws.path_join(b_rel))
	check(saved.contains("{ \"point\": [ 0, 0, 2 ], \"overmap\": \"tall_3_north\", \"locations\": [ \"land\" ] }"), saved)
	var again := DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(again.buildings["twin"].at(Vector3i(0, 0, 2)).oter, "tall_3", "read back")
	_cleanup()


func test_new_building() -> void:
	_setup()
	var session := _session()
	var rel := "data/json/mapgen/tall.json"
	check(session.check_new_building(rel, "tall").contains("already exists"))
	check(session.check_new_building(rel, "x", "villages").contains("Unknown city list"))
	var entries := [[Vector3i.ZERO, "tall_1_north"]]
	check_eq(session.create_building(rel, "tall_again", entries, "shops", 25), "")
	var b: DataIndex.Building = _index.buildings.get("tall_again")
	if check(b != null):
		check_eq(b.at(Vector3i.ZERO).oter, "tall_1")
	var region: Dictionary = session.files[EditSession.REGION_SETTINGS_FILE].objects[0]
	check_eq(region.city.shops, {"tall_again": 25}, "core: in the region settings")
	check_eq(session.linked_files(rel), PackedStringArray([EditSession.REGION_SETTINGS_FILE]))
	check_eq(session.files[rel].objects[-1].overmaps, [{"point": [0, 0, 0], "overmap": "tall_1_north"}])
	session.discard(rel)
	check(not _index.buildings.has("tall_again"), "discarded")
	check_eq(session.files.size(), 0)

	# In a mod: a region_overlay next to it.
	var m_rel := "data/mods/mymod/house_m.json"
	check(session.city_list_note(m_rel).contains("region_overlay"))
	check_eq(session.create_building(m_rel, "house_m_b", [[Vector3i.ZERO, "house_m_north"]], "houses", 50), "")
	var overlay: Dictionary = session.files[m_rel].objects[-1]
	check_eq(overlay, {"type": "region_overlay", "regions": ["all"], "city": {"houses": {"house_m_b": 50}}})
	check_eq(session.dirty_files(), PackedStringArray([m_rel]))
	_cleanup()


func test_main_new_level() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray(["mymod"])
	main.load_index(_root)
	var m: Variant = main.open_id("tall_2")
	main.new_level(1, true)
	var dialog: NewMapDialog = main._new_map_dialog
	check_eq(dialog.base_edit.text, "tall_roof")
	check_eq(dialog.fill_edit.text, "t_flat_roof")
	check_eq(dialog.palettes_edit.text, "roof_palette")
	check_eq(dialog.path_edit.text, "data/json/mapgen/tall.json")
	check_eq(dialog.overmap_base, "generic_up")
	check(dialog._info.text.contains("Adds the new tiles"), dialog._info.text)
	check(not dialog.get_ok_button().disabled, dialog._info.text)
	dialog._on_confirmed()
	var roof: Variant = main.current_map()
	check_eq(roof.ref.title(), "tall_roof")
	if check(roof.place != null, "placed"):
		check_eq(roof.place.building.id, "tall")
		check_eq(roof.place.origin, Vector3i(0, 0, 2))
	check(main._status.text.contains("Added the new tiles"), main._status.text)
	check_eq(main.level_step(-1), m, "back down to tall_2")

	# Where the building already has the level, it goes there.
	main.new_level(1)
	check_eq(main.current_map(), roof)

	# A map no building places: a new building from it.
	var h: Variant = main.open_id("house_m")
	check_eq(h.place, null)
	main.new_level(1)
	check(main._status.text.contains("New building"), main._status.text)
	main.new_building()
	var nb: NewBuildingDialog = main._new_building_dialog
	check_eq(nb.id_edit.text, "house_m")
	nb.id_edit.text = "house_m_building"
	nb._validate()
	check(not nb.get_ok_button().disabled, nb._info.text)
	check(nb._info.text.contains("region_overlay"), nb._info.text)
	nb._on_confirmed()
	check(h.place != null and h.place.building.id == "house_m_building", "now placed")
	check(main._status.text.contains("Created city_building"), main._status.text)
	main.free()
	_cleanup()

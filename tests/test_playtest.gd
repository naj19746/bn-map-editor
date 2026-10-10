extends "res://tests/support/test_case.gd"
## PLAYTEST.MD Step 1: the playtest builder (Playtest), on a fake BN tree.
## Launching the game stays manual.

const TempTree := preload("res://tests/support/temp_tree.gd")
const BnEnv := preload("res://tests/support/bn_env.gd")
const HOUSE := "data/json/mapgen/house.json"
const OTHER := "data/json/mapgen/other.json"
const MOD := "data/mods/" + Playtest.MOD_ID

var _bn := ""
var _ws := ""
var _out := ""
var _template := ""
var _config := ""
var _index: DataIndex
var _session: EditSession


static func _rows(c: String) -> Array:
	var rows := []
	for y in 24:
		rows.append(c.repeat(24))
	return rows


static func _map(om: Variant, c := ".") -> Dictionary:
	return {"type": "mapgen", "method": "json", "om_terrain": om,
		"object": {"rows": _rows(c), "terrain": {".": "t_floor", "#": "t_wall"}}}


func _setup() -> void:
	_bn = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/mods/extra/modinfo.json": [{"type": "MOD_INFO", "id": "extra", "dependencies": ["bn"]}],
		"data/mods/extra/things.json": [],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_wall", "symbol": "#", "color": "white"},
			{"type": "overmap_terrain", "abstract": "generic_city_building", "name": "city building"},
			{"type": "overmap_terrain", "id": ["house", "house_roof", "cabin"], "copy-from": "generic_city_building"},
			{"type": "overmap_terrain", "id": "shed", "flags": ["NO_ROTATE"]},
			{"type": "overmap_terrain", "id": "barn", "copy-from": "shed"},
		],
		"data/json/items/stuff.json": [],
		HOUSE: [_map("house"), _map("house", "#"), {"type": "item_group", "id": "stuff", "items": []}],
		OTHER: [_map(["house", "cabin"], "#"), _map("shed"), _map("barn"), _map("cabin")],
		"data/json/mapgen/roof.json": [_map("house_roof")],
		"data/json/overmap/buildings.json": [{"type": "city_building", "id": "house_bld",
			"locations": ["land"], "overmaps": [{"point": [0, 0, 0], "overmap": "house_north"},
				{"point": [0, 0, 1], "overmap": "house_roof_north"}]}],
		"gfx/tiles.txt": "tiles",
		"lang/en.txt": "en",
	})
	_ws = TempTree.make({})
	_out = TempTree.make({})
	_template = TempTree.make({
		"worldoptions.json": "[{\"name\": \"CITY_SIZE\", \"value\": \"4\"}]",
		"mods.json": ["bn", "extra", "not_here"],
	})
	_config = TempTree.make({"options.json": "[]", "fonts.json": "{}"})
	_reload()


func _reload(selected := PackedStringArray()) -> void:
	_index = DataIndex.load_bn(_bn, selected, null, _ws)
	check_eq(_index.errors, PackedStringArray(), "index errors")
	_session = EditSession.new(_index, Workspace.open(_ws, _bn))


func _cleanup() -> void:
	for dir in [_bn, _ws, _out, _template, _config]:
		TempTree.remove(dir)


func _options() -> Playtest.Options:
	var o := Playtest.Options.new()
	o.root = _out.path_join("playtest")
	o.bn_config_dir = _config
	o.bn_user_dir = ""
	o.template_world = ""
	# Today's behavior (the map's own ids); the own_terrain tests turn it on.
	o.own_start_terrain = false
	# The character and world extras have their own tests.
	o.strong_character = false
	o.daylight = false
	o.reveal_building = false
	return o


func _ref(file: String, i: int) -> DataIndex.MapgenRef:
	for r in _index.mapgens:
		if r.source.path == file and r.source.index == i:
			return r
	return null


func _build(ref: DataIndex.MapgenRef, o := _options()) -> Playtest.Build:
	var b := Playtest.build(_session, ref, o)
	check_eq(b.error, "", "build error")
	return b


static func _is_link(path: String) -> bool:
	return DirAccess.open(path.get_base_dir()).is_link(path)


static func _real_file(path: String) -> bool:
	return FileAccess.file_exists(path) and not _is_link(path)


static func _real_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path) and not _is_link(path)


static func _read(path: String) -> Variant:
	var parsed := BnJson.parse(FileAccess.get_file_as_string(path))
	return parsed.value if parsed.ok() else null


## [param v] as JSON with sorted keys (TempTree's fixtures have them sorted).
static func _sorted(v: Variant) -> String:
	return JSON.stringify(v, "", true)


## Every file of the BN tree with its sha256.
func _snapshot(dir: String, rel := "", out := {}) -> Dictionary:
	for f in DirAccess.get_files_at(dir.path_join(rel)):
		out[rel.path_join(f)] = FileAccess.get_sha256(dir.path_join(rel).path_join(f))
	for d in DirAccess.get_directories_at(dir.path_join(rel)):
		_snapshot(dir, rel.path_join(d), out)
	return out


func test_overlay_links_and_disabled() -> void:
	_setup()
	var before := _snapshot(_bn)
	var b := _build(_ref(HOUSE, 0))
	var o := b.basepath
	check_eq(b.args(), PackedStringArray(["--basepath", o + "/", "--userdir", b.userdir + "/"]))
	check_eq(b.args(true), PackedStringArray(["--basepath", o + "/", "--userdir", b.userdir + "/",
		"--new-game", "Playtest"]))
	check(_is_link(o.path_join("gfx")) and _is_link(o.path_join("lang")), "top-level folders linked")
	for rel in ["data", "data/json", "data/json/mapgen", "data/mods", "data/mods/bn", MOD]:
		check(_real_dir(o.path_join(rel)), rel + " is a real folder")
	for rel in ["data/json/items", "data/json/overmap", "data/mods/extra"]:
		check(_is_link(o.path_join(rel)), rel + " is a link")
	for rel in ["data/json/ter.json", "data/json/mapgen/roof.json", "data/mods/bn/modinfo.json"]:
		check(_is_link(o.path_join(rel)), rel + " is a link")
	check_eq(FileAccess.get_file_as_string(o.path_join("gfx/tiles.txt")), "tiles", "through the link")
	for rel in [HOUSE, OTHER]:
		check(_real_file(o.path_join(rel)), rel + " is a real file")
	check_eq(b.disabled, PackedStringArray([HOUSE + "#1", OTHER + "#0"]), "disabled (not cabin's own)")
	var house: Array = _read(o.path_join(HOUSE))
	check(not house[0].has("disabled"), "the map itself stays enabled")
	check_eq(house[1].get("disabled"), true, "the other house mapgen")
	check_eq(_sorted(house[2]), _sorted({"type": "item_group", "id": "stuff", "items": []}), "other objects kept")
	var other: Array = _read(o.path_join(OTHER))
	check_eq([other[0].get("disabled"), other[1].get("disabled"), other[2].get("disabled"),
		other[3].get("disabled")], [true, null, null, null], "other.json")
	check_eq(b.files, PackedStringArray([HOUSE, OTHER, MOD + "/modinfo.json", MOD + "/" + Playtest.MOD_FILE]))
	check_eq(b.warnings, PackedStringArray())
	check_eq(_snapshot(_bn), before, "BN untouched")
	# Building again replaces the old build without touching BN.
	_build(_ref(HOUSE, 0))
	check_eq(_snapshot(_bn), before, "BN untouched after a rebuild")
	TempTree.remove(_out)
	check_eq(_snapshot(_bn), before, "BN untouched after removing the build")
	_cleanup()


func test_only_my_mapgen_off() -> void:
	_setup()
	var o := _options()
	o.only_my_mapgen = false
	var b := _build(_ref(HOUSE, 0), o)
	check_eq(b.disabled, PackedStringArray())
	check(_is_link(b.basepath.path_join("data/json")), "data/json stays a link")
	check_eq(b.files, PackedStringArray([MOD + "/modinfo.json", MOD + "/" + Playtest.MOD_FILE]))
	_cleanup()


func test_unsaved_edits() -> void:
	_setup()
	# A saved workspace file, and an unsaved edit of another.
	var roof := _session.open(_ref("data/json/mapgen/roof.json", 0))
	roof.paint([Vector2i(1, 1)], "#")
	check_eq(_session.save("data/json/mapgen/roof.json"), "", "save")
	var doc := _session.open(_ref(HOUSE, 0))
	doc.paint([Vector2i(2, 0)], "#")
	var on_disk := FileAccess.get_file_as_string(_bn.path_join(HOUSE))
	var b := _build(_ref(HOUSE, 0))
	var house: Array = _read(b.basepath.path_join(HOUSE))
	check_eq(house[0].object.rows[0], "..#" + ".".repeat(21), "the unsaved edit")
	check_eq(house[1].get("disabled"), true)
	check(not _session.workspace.has_file(HOUSE), "nothing saved to the workspace")
	check_eq(FileAccess.get_file_as_string(_bn.path_join(HOUSE)), on_disk, "BN's file unchanged")
	check(_session.is_dirty(HOUSE), "still dirty")
	var r: Array = _read(b.basepath.path_join("data/json/mapgen/roof.json"))
	check_eq(r[0].object.rows[1], ".#" + ".".repeat(22), "the workspace file")
	_cleanup()


func test_mod_json() -> void:
	_setup()
	var b := _build(_ref(HOUSE, 0))
	var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[0], {"type": "start_location", "id": "bnme_playtest", "name": "Playtest: house",
		"terrain": ["house"]}, "start location")
	check_eq(mod[1], {"type": "scenario", "id": "evacuee", "copy-from": "evacuee", "start_name": "Playtest",
		"allowed_locs": ["bnme_playtest"], "flags": []}, "scenario")
	check_eq(mod[2], {"type": "SCENARIO_BLACKLIST", "subtype": "whitelist", "scenarios": ["evacuee"]},
		"only evacuee")
	check_eq(_sorted(mod[3]), _sorted({"type": "overmap_special", "id": "bnme_playtest_special",
		"overmaps": [{"point": [0, 0, 0], "overmap": "house_north"},
			{"point": [0, 0, 1], "overmap": "house_roof_north"}],
		"locations": ["land"], "occurrences": [1, 1], "flags": ["GLOBALLY_UNIQUE"],
		"absolute_spawn_loc": {"x": 0, "y": 0}}), "special from the building")
	var info: Array = _read(b.basepath.path_join(MOD).path_join("modinfo.json"))
	check_eq(info[0].id, "bnme_playtest")
	check_eq(info[0].dependencies, ["bn"])
	_cleanup()


func test_standalone_maps() -> void:
	_setup()
	# NO_ROTATE (also through copy-from) is named without a direction.
	for i in [1, 2]:
		var b := _build(_ref(OTHER, i))
		var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
		var id: String = ["", "shed", "barn"][i]
		check_eq(mod[3].overmaps, [{"point": [0, 0, 0], "overmap": id}], id)
		check_eq(mod[3].locations, ["land"], id)
		check_eq(mod[0].terrain, [id], id)
	var cabin := _build(_ref(OTHER, 3))
	var mod: Array = _read(cabin.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[3].overmaps, [{"point": [0, 0, 0], "overmap": "cabin_north"}], "a rotating terrain")
	check_eq(cabin.disabled, PackedStringArray([OTHER + "#0"]), "the list mapgen competes for cabin")
	_cleanup()


func test_upper_floor_starts_on_the_ground() -> void:
	_setup()
	var b := _build(_ref("data/json/mapgen/roof.json", 0))
	check_eq(b.start_terrain, PackedStringArray(["house"]))
	check_eq(b.move_to, PackedStringArray(["house_roof"]))
	check_eq(b.move_to_z, 1)
	check_eq(b.warnings, PackedStringArray(), "no warnings")
	check(b.files.has(MOD + "/" + Playtest.MOD_LUA), "the Lua hook is a file: " + str(b.files))
	var info: Array = _read(b.basepath.path_join(MOD).path_join("modinfo.json"))
	check_eq(info[0].get("lua_api_version"), Playtest.LUA_API_VERSION, "the mod runs Lua")
	var lua := FileAccess.get_file_as_string(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA))
	check(lua.contains("local targets = { \"house_roof\" }"), lua)
	check(lua.contains("local level = 1\n"), "level")
	check(lua.contains("local stairs = \"GOES_DOWN\""), "arrives on the stairs down")
	check(lua.contains("game.add_hook(\"on_game_started\""), "the hook")
	check(lua.contains("gdebug.log_error(\"bnme_playtest: "), "a failure names the mod")
	_cleanup()


func test_ground_floor_has_no_lua() -> void:
	_setup()
	var b := _build(_ref(HOUSE, 0))
	check_eq(b.move_to, PackedStringArray())
	check(not b.files.has(MOD + "/" + Playtest.MOD_LUA), "no Lua: " + str(b.files))
	var info: Array = _read(b.basepath.path_join(MOD).path_join("modinfo.json"))
	check(not info[0].has("lua_api_version"), "no lua_api_version")
	# A rebuild for a roof, then the ground floor again: the old script goes.
	_build(_ref("data/json/mapgen/roof.json", 0))
	b = _build(_ref(HOUSE, 0))
	check(not FileAccess.file_exists(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA)), "removed")
	_cleanup()


func test_basement_starts_on_the_tile_above() -> void:
	_setup()
	var f := FileAccess.open(_bn.path_join("data/json/cellar.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify([
		{"type": "overmap_terrain", "id": "cellar"},
		_map("cellar"),
		{"type": "overmap_special", "id": "farm", "locations": ["land"], "overmaps": [
			{"point": [0, 0, 0], "overmap": "shed"}, {"point": [1, 0, 0], "overmap": "barn"},
			{"point": [1, 0, -1], "overmap": "cellar_north"}, {"point": [1, 0, -2], "overmap": "cellar_north"}]},
	]))
	f.close()
	_reload()
	var b := _build(_ref("data/json/cellar.json", 1))
	check_eq(b.start_terrain, PackedStringArray(["barn"]), "the ground tile above it")
	check_eq(b.move_to, PackedStringArray(["cellar"]))
	check_eq(b.move_to_z, -1, "the level nearest the ground")
	var lua := FileAccess.get_file_as_string(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA))
	check(lua.contains("local level = -1\n"), "level")
	check(lua.contains("local stairs = \"GOES_UP\""), "arrives on the stairs up")
	_cleanup()


## A few of the strong character's ids, as BN's types name them.
func _define_character_data(skip := PackedStringArray()) -> void:
	var objects := []
	for id: String in ["melee", "gun"]:
		objects.append({"type": "skill", "id": id})
	objects.append({"type": "mutation", "id": "TOUGH"})
	objects.append({"type": "bionic", "id": "bio_armor_torso"})
	for id: String in ["tank_top", "boots_combat", "katana", "m4a1", "556", "grenade", "mask_gas",
			"flashlight", "light_disposable_cell", "battery"]:
		objects.append({"type": "ARMOR" if id == "tank_top" else "GENERIC", "id": id})
	objects.append({"type": "ITEM_BLACKLIST", "items": ["grenade"]})
	objects = objects.filter(func(o: Dictionary) -> bool: return not skip.has(o.get("id", "")))
	var f := FileAccess.open(_bn.path_join("data/json/character.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(objects))
	f.close()
	_reload()


func test_strong_character() -> void:
	_setup()
	_define_character_data(PackedStringArray(["boots_combat", "gun"]))
	var o := _options()
	o.strong_character = true
	var b := _build(_ref(HOUSE, 0), o)
	var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[1].get("professions"), ["bnme_playtest"], "the evacuee override's only profession")
	var prof: Dictionary = mod[3]
	check_eq([prof.type, prof.id, prof.points], ["profession", "bnme_playtest", 0], "profession")
	check_eq(prof.skills, [{"name": "melee", "level": 8}], "skills the mods have")
	check_eq(prof.traits, ["TOUGH"])
	check_eq(prof.CBMs, ["bio_armor_torso"])
	var group: Dictionary = prof["items"]["both"]
	check_eq(group["items"], ["tank_top"], "boots_combat isn't defined")
	var entries: Array = group["entries"]
	var by_item := {}
	for e: Dictionary in entries:
		by_item[e.get("container-item", e.item)] = e
	check_eq(by_item.keys().size(), entries.size(), "no entry twice")
	check_eq(by_item.get("flashlight"), {"item": "light_disposable_cell", "ammo-item": "battery", "charges": 300,
		"container-item": "flashlight"}, "a flashlight with a charged cell in it")
	check_eq(by_item.get("m4a1"), {"item": "m4a1", "ammo-item": "556", "charges": 30}, "a loaded gun")
	check_eq(by_item.get("katana"), {"item": "katana", "custom-flags": ["auto_wield"]})
	check(not by_item.has("stanag30") and not by_item.has("glock_19") and not by_item.has("grenade"),
		"missing and blacklisted items: " + str(by_item.keys()))
	var text := "\n".join(b.warnings)
	check(text.contains("skills bashing, cutting") and text.contains(", gun,"), text)
	check(text.contains("aren't in the selected mods: left out"), text)
	check(text.contains("boots_combat"), text)
	check(text.contains("items grenade are blacklisted"), text)
	check(text.contains("traits STR_UP_4"), text)
	check_eq(b.warnings.size(), 5, "one warning per kind and the blacklist: " + text)
	check(b.applied[0].begins_with("strong character (1 skills at 8, 1 traits, 1 CBMs"), str(b.applied))
	# A gun whose ammo is missing stays, unloaded.
	_define_character_data(PackedStringArray(["556"]))
	b = _build(_ref(HOUSE, 0), o)
	mod = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	for e: Dictionary in mod[3]["items"]["both"]["entries"]:
		if e.item == "m4a1":
			check_eq(e, {"item": "m4a1"}, "no ammo to load")
	# No flashlight: no cell put in one, the spare cell stays.
	_define_character_data(PackedStringArray(["flashlight"]))
	b = _build(_ref(HOUSE, 0), o)
	mod = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	var cells: Array = mod[3]["items"]["both"]["entries"].filter(
		func(e: Dictionary) -> bool: return e.item == "light_disposable_cell")
	check_eq(cells, [{"item": "light_disposable_cell", "ammo-item": "battery", "charges": 300}], "the spare cell")
	# Off: no profession and no override.
	b = _build(_ref(HOUSE, 0))
	mod = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check(not mod[1].has("professions"), "no professions")
	check_eq(mod.size(), 4, "start location, scenario, whitelist, special")
	_cleanup()


func test_strong_character_data_is_in_core() -> void:
	# The ids the profession names exist in the real BN (when it is here).
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		return skip("no BN checkout (set BN_PATH)")
	var index := DataIndex.load_bn(bn)
	var b := Playtest.Build.new()
	var prof := Playtest._profession(index, b)
	check_eq(b.warnings, PackedStringArray(), "every id is in core")
	check_eq(prof.skills.size(), Playtest.STRONG_SKILLS.size())
	check_eq(prof.traits.size(), Playtest.STRONG_TRAITS.size())
	check_eq(prof.CBMs.size(), Playtest.STRONG_CBMS.size())


func test_world_options_overrides() -> void:
	_setup()
	var o := _options()
	o.daylight = true
	var b := _build(_ref(HOUSE, 0), o)
	var path := b.userdir.path_join("save").path_join(Playtest.WORLD).path_join("worldoptions.json")
	check_eq(_read(path), [{"name": "INITIAL_TIME", "value": "10"}], "on [] without a template")
	check_eq(b.applied, PackedStringArray(["start in daylight (INITIAL_TIME 10)"]))
	o.no_monsters = true
	b = _build(_ref(HOUSE, 0), o)
	check_eq(_read(path), [{"name": "INITIAL_TIME", "value": "10"}, {"name": "SPAWN_DENSITY", "value": "0.00"}])
	o.daylight = false
	o.no_monsters = false
	b = _build(_ref(HOUSE, 0), o)
	check_eq(FileAccess.get_file_as_string(path), "[]", "nothing to override")

	# On a template: its other options stay, a present one is changed, the
	# city size is only raised when it is 0.
	var text := "[{\"info\": \"i\", \"name\": \"INITIAL_TIME\", \"value\": \"8\"}, {\"name\": \"CITY_SIZE\", \"value\": \"0\"}, {\"name\": \"SEASON_LENGTH\", \"value\": \"30\"}]"
	var f := FileAccess.open(_template.path_join("worldoptions.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	o.template_world = _template
	o.daylight = true
	o.no_monsters = true
	b = _build(_ref(HOUSE, 0), o)
	check_eq(_read(path), [{"info": "i", "name": "INITIAL_TIME", "value": "10"},
		{"name": "CITY_SIZE", "value": "1"}, {"name": "SEASON_LENGTH", "value": "30"},
		{"name": "SPAWN_DENSITY", "value": "0.00"}], "template options changed")
	check(b.applied.has("CITY_SIZE raised to 1"), str(b.applied))
	check(b.applied.has("no monsters (SPAWN_DENSITY 0)"), str(b.applied))
	# Nothing to change: the template as written.
	f = FileAccess.open(_template.path_join("worldoptions.json"), FileAccess.WRITE)
	f.store_string("[ {\"name\": \"CITY_SIZE\", \"value\": \"4\"} ]")
	f.close()
	o.daylight = false
	o.no_monsters = false
	b = _build(_ref(HOUSE, 0), o)
	check_eq(FileAccess.get_file_as_string(path), "[ {\"name\": \"CITY_SIZE\", \"value\": \"4\"} ]", "verbatim")
	_cleanup()


func test_reveal_in_the_script() -> void:
	_setup()
	var o := _options()
	o.reveal_building = true
	# The house and its roof: one tile, two levels, ground floor too.
	var b := _build(_ref(HOUSE, 0), o)
	check_eq([b.reveal_radius, b.reveal_levels], [1, [0, 1] as Array[int]], "radius and levels")
	check(b.files.has(MOD + "/" + Playtest.MOD_LUA), "the script is a file even on the ground floor")
	var info: Array = _read(b.basepath.path_join(MOD).path_join("modinfo.json"))
	check_eq(info[0].get("lua_api_version"), Playtest.LUA_API_VERSION, "the mod runs Lua")
	var lua := FileAccess.get_file_as_string(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA))
	check(lua.contains("local reveal_levels = { 0, 1 }"), lua)
	check(lua.contains("local reveal_radius = 1\n"), lua)
	check(lua.contains("overmapbuffer.reveal(TripointAbsOmt.new(here.x, here.y, z), reveal_radius)"), lua)
	check(lua.contains("game.add_hook(\"on_game_started\", function()\n  reveal_building()\nend)"), lua)
	check(not lua.contains("move_player"), "no move on the ground floor")
	check(b.applied.size() == 1 and b.applied[0].begins_with("the building revealed"), str(b.applied))
	# An upper floor: moves, then reveals.
	b = _build(_ref("data/json/mapgen/roof.json", 0), o)
	lua = FileAccess.get_file_as_string(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA))
	check(lua.contains("local targets = { \"house_roof\" }"), "the move is kept")
	check(lua.contains("  move_player()\n  reveal_building()\nend)"), lua)
	# A map alone: the 1x1 special's single level.
	b = _build(_ref(OTHER, 1), o)
	check_eq([b.reveal_radius, b.reveal_levels], [1, [0] as Array[int]], "a standalone map")
	# Off: today's behavior.
	o.reveal_building = false
	b = _build(_ref(HOUSE, 0), o)
	check_eq(b.reveal_radius, 0)
	check(not b.files.has(MOD + "/" + Playtest.MOD_LUA), "no script")
	_cleanup()


func test_world() -> void:
	_setup()
	var o := _options()
	o.mods = PackedStringArray(["extra"])
	var b := _build(_ref(HOUSE, 0), o)
	var world := b.userdir.path_join("save").path_join(Playtest.WORLD)
	check_eq(_read(world.path_join("mods.json")), ["bn", "extra", "bnme_playtest"], "editor mods")
	check_eq(FileAccess.get_file_as_string(world.path_join("worldoptions.json")), "[]", "no template")
	check_eq(DirAccess.get_directories_at(b.userdir.path_join("save")), PackedStringArray(["Playtest"]), "one world")
	check_eq(FileAccess.get_file_as_string(b.userdir.path_join("config/options.json")), "[]", "config copied")
	check(FileAccess.file_exists(b.userdir.path_join("config/fonts.json")), "fonts copied")
	check(not FileAccess.file_exists(b.userdir.path_join("config/keybindings.json")), "no keybindings to copy")

	o.mods = PackedStringArray()
	o.template_world = _template
	b = _build(_ref(HOUSE, 0), o)
	check_eq(b.world_mods, PackedStringArray(["bn", "extra", "bnme_playtest"]), "template mods")
	check_eq(_read(world.path_join("mods.json")), ["bn", "extra", "bnme_playtest"])
	check_eq(FileAccess.get_file_as_string(world.path_join("worldoptions.json")),
		FileAccess.get_file_as_string(_template.path_join("worldoptions.json")), "template options")
	check_eq(b.warnings.size(), 1, "the missing mod")
	check(b.warnings[0].contains("not_here"), str(b.warnings))

	o.template_world = _template.path_join("nope")
	b = _build(_ref(HOUSE, 0), o)
	check_eq(FileAccess.get_file_as_string(world.path_join("worldoptions.json")), "[]", "template gone")
	check(b.warnings[0].contains("not found"), str(b.warnings))
	_cleanup()


static func _put(root: String, rel: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(root.path_join(rel).get_base_dir())
	var f := FileAccess.open(root.path_join(rel), FileAccess.WRITE)
	f.store_string(JSON.stringify(value, " "))
	f.close()


## A map of its own in BN's mod "extra" (an overmap_terrain and its mapgen).
func _put_extra_map() -> void:
	_put(_bn, "data/mods/extra/extra_ter.json", [
		{"type": "overmap_terrain", "id": "extra_house", "copy-from": "generic_city_building"}])
	_put(_bn, "data/mods/extra/extra_map.json", [_map("extra_house")])


func test_mods_of_the_map() -> void:
	_setup()
	# A map in mod "extra", which the editor and the template don't list.
	_put_extra_map()
	_reload(PackedStringArray(["extra"]))
	var ref := _ref("data/mods/extra/extra_map.json", 0)
	check(ref != null, "the map in extra")
	var b := _build(ref)
	var world := b.userdir.path_join("save").path_join(Playtest.WORLD)
	check_eq(b.world_mods, PackedStringArray(["bn", "extra", "bnme_playtest"]), "the map's mod")
	check_eq(_read(world.path_join("mods.json")), ["bn", "extra", "bnme_playtest"])
	check_eq(b.warnings, PackedStringArray(["added extra: data/mods/extra/extra_map.json is in it"]))
	var info: Array = _read(b.basepath.path_join(MOD).path_join("modinfo.json"))
	check_eq(info[0].dependencies, ["bn", "extra"], "the map's mod is a dependency")

	# Already listed by the editor: not added again, no warning.
	var o := _options()
	o.mods = PackedStringArray(["extra"])
	b = _build(ref, o)
	check_eq(b.world_mods, PackedStringArray(["bn", "extra", "bnme_playtest"]), "listed once")
	check_eq(b.warnings, PackedStringArray(), "no warning when listed")
	_cleanup()


func test_mods_of_workspace_files() -> void:
	_setup()
	# Mod "other" is in BN; the workspace adds a file to it.
	_put(_bn, "data/mods/other/modinfo.json", [{"type": "MOD_INFO", "id": "other"}])
	_put(_ws, "data/mods/other/things.json", [])
	_put_extra_map()
	_reload(PackedStringArray(["extra"]))
	var b := _build(_ref("data/mods/extra/extra_map.json", 0))
	check_eq(b.world_mods, PackedStringArray(["bn", "extra", "other", "bnme_playtest"]), "file's mod")
	check_eq(b.warnings, PackedStringArray([
		"added extra: data/mods/extra/extra_map.json is in it",
		"added other: data/mods/other/things.json is in it"]))

	# A core map: the workspace's file in "other" is still in the overlay.
	b = _build(_ref(HOUSE, 0))
	check_eq(b.world_mods, PackedStringArray(["bn", "other", "bnme_playtest"]), "core map only")
	check_eq(b.warnings, PackedStringArray(["added other: data/mods/other/things.json is in it"]))
	_cleanup()


func test_workspace_only_mod() -> void:
	_setup()
	# Mod "wsonly" exists only in the workspace, and needs "extra" (in BN).
	_put(_ws, "data/mods/wsonly/modinfo.json", [{"type": "MOD_INFO", "id": "wsonly",
		"dependencies": ["extra"]}])
	_put(_ws, "data/mods/wsonly/stuff.json", [])
	_reload()
	check(not _index.catalog.has("wsonly"), "BN doesn't have it")
	var b := _build(_ref(HOUSE, 0))
	var world := b.userdir.path_join("save").path_join(Playtest.WORLD)
	check_eq(b.world_mods, PackedStringArray(["bn", "extra", "wsonly", "bnme_playtest"]), "workspace mod")
	check_eq(_read(world.path_join("mods.json")), ["bn", "extra", "wsonly", "bnme_playtest"])
	check_eq(b.warnings, PackedStringArray(["added wsonly: data/mods/wsonly/modinfo.json is in it"]))
	check(FileAccess.file_exists(b.basepath.path_join("data/mods/wsonly/stuff.json")), "file in overlay")
	_cleanup()


func test_refusals() -> void:
	_setup()
	var o := _options()
	o.root = _bn.path_join("playtest")
	var b := Playtest.build(_session, _ref(HOUSE, 0), o)
	check(b.error.contains("can't be inside"), "inside BN: " + b.error)
	check(not DirAccess.dir_exists_absolute(o.root), "nothing made in BN")
	o.root = _ws
	b = Playtest.build(_session, _ref(HOUSE, 0), o)
	check(b.error.contains("can't be inside"), "the workspace: " + b.error)
	_index.om_terrain["house"][1].disabled = true
	var disabled := _ref(HOUSE, 1)
	b = Playtest.build(_session, disabled, _options())
	check(b.error.contains("disabled"), b.error)
	_cleanup()


# --- Own start terrain (TODO 2) ------------------------------------------------

func _own_options() -> Playtest.Options:
	var o := _options()
	o.own_start_terrain = true
	return o


## The playtest mod's copies of the mapgens of BN file [param rel].
func _copies(b: Playtest.Build, rel: String) -> Variant:
	return _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_COPIES).path_join(rel))


func test_own_terrain_standalone() -> void:
	_setup()
	var before := _snapshot(_bn)
	# shed is NO_ROTATE; only my mapgen is on but nothing is disabled.
	var b := _build(_ref(OTHER, 1), _own_options())
	check_eq(b.own_terrain, {"bnme_playtest_shed": "shed"})
	check_eq(b.copied, PackedStringArray([OTHER + "#1"]))
	check_eq(b.disabled, PackedStringArray(), "nothing disabled")
	check_eq(b.start_terrain, PackedStringArray(["bnme_playtest_shed"]))
	check_eq(b.files, PackedStringArray([MOD + "/copies/" + OTHER, MOD + "/modinfo.json",
		MOD + "/" + Playtest.MOD_FILE]), "only the mod")
	check(_is_link(b.basepath.path_join("data/json")), "BN's data stays linked")
	var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[0].terrain, ["bnme_playtest_shed"], "the start location")
	check_eq(mod[3], {"type": "overmap_terrain", "id": "bnme_playtest_shed", "copy-from": "shed"})
	check_eq(mod[4].overmaps, [{"point": [0, 0, 0], "overmap": "bnme_playtest_shed"}], "no direction")
	var copies: Array = _copies(b, OTHER)
	check_eq(copies.size(), 1)
	check_eq(copies[0].om_terrain, "bnme_playtest_shed")
	check_eq(_sorted(copies[0].object), _sorted(_map("shed").object), "the map itself")

	# cabin rotates; the list mapgen [house, cabin] competes for it but isn't
	# copied, and nothing is disabled.
	b = _build(_ref(OTHER, 3), _own_options())
	mod = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[4].overmaps, [{"point": [0, 0, 0], "overmap": "bnme_playtest_cabin_north"}])
	check_eq(b.copied, PackedStringArray([OTHER + "#3"]), "only the map for its own id")
	check_eq(b.disabled, PackedStringArray())
	check_eq(b.warnings, PackedStringArray())
	check_eq(_snapshot(_bn), before, "BN untouched")
	_cleanup()


func test_own_terrain_building() -> void:
	_setup()
	# The house's unsaved edit is what gets copied.
	var doc := _session.open(_ref(HOUSE, 0))
	doc.paint([Vector2i(2, 0)], "#")
	var b := _build(_ref(HOUSE, 0), _own_options())
	check_eq(b.own_terrain, {"bnme_playtest_house": "house", "bnme_playtest_house_roof": "house_roof"})
	check_eq(b.copied, PackedStringArray([HOUSE + "#0", "data/json/mapgen/roof.json#0"]),
		"the map for house (not its competitors), the roof's mapgen")
	check_eq(b.disabled, PackedStringArray())
	check_eq(b.start_terrain, PackedStringArray(["bnme_playtest_house"]))
	var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[3], {"type": "overmap_terrain", "id": "bnme_playtest_house", "copy-from": "house"})
	check_eq(mod[4], {"type": "overmap_terrain", "id": "bnme_playtest_house_roof", "copy-from": "house_roof"})
	check_eq(_sorted(mod[5].overmaps), _sorted([{"point": [0, 0, 0], "overmap": "bnme_playtest_house_north"},
		{"point": [0, 0, 1], "overmap": "bnme_playtest_house_roof_north"}]), "the special")
	var house: Array = _copies(b, HOUSE)
	check_eq(house.size(), 1)
	check_eq(house[0].om_terrain, "bnme_playtest_house")
	check_eq(house[0].object.rows[0], "..#" + ".".repeat(21), "the unsaved edit")
	check(not house[0].has("disabled"), "enabled")
	check_eq(_read(b.basepath.path_join(HOUSE))[1].get("disabled"), null, "the house file's own copy: nothing disabled")
	check_eq(_copies(b, "data/json/mapgen/roof.json")[0].om_terrain, "bnme_playtest_house_roof")
	check_eq(doc.ref.ids, PackedStringArray(["house"]), "the open map is untouched")
	check_eq(_session.files[HOUSE].objects[0].om_terrain, "house", "the open file too")

	# The roof: house is another tile now, so its every mapgen is copied; the
	# list mapgen [house, cabin] only for house.
	b = _build(_ref("data/json/mapgen/roof.json", 0), _own_options())
	check_eq(b.copied, PackedStringArray([HOUSE + "#0", HOUSE + "#1", OTHER + "#0", "data/json/mapgen/roof.json#0"]),
		"the special's tiles in order")
	check_eq(b.start_terrain, PackedStringArray(["bnme_playtest_house"]))
	check_eq(b.move_to, PackedStringArray(["bnme_playtest_house_roof"]))
	var lua := FileAccess.get_file_as_string(b.basepath.path_join(MOD).path_join(Playtest.MOD_LUA))
	check(lua.contains("local targets = { \"bnme_playtest_house_roof\" }"), lua)
	check_eq(_copies(b, OTHER)[0].om_terrain, ["bnme_playtest_house"], "the list: only the ids the building needs")
	check_eq(_copies(b, HOUSE).map(func(o: Dictionary) -> Variant: return o.om_terrain),
		["bnme_playtest_house", "bnme_playtest_house"])
	check(not b.own_terrain.has("bnme_playtest_cabin"), "no cabin of its own")
	_cleanup()


func test_own_terrain_grid() -> void:
	_setup()
	_put(_bn, "data/json/wing.json", [
		{"type": "overmap_terrain", "id": ["wing_a", "wing_b", "wing_roof"], "copy-from": "generic_city_building"},
		{"type": "overmap_terrain", "id": "yard", "flags": ["NO_ROTATE"]},
		{"type": "mapgen", "method": "json", "om_terrain": [["wing_a", "wing_b"]],
			"object": {"rows": _rows(".") , "terrain": {".": "t_floor"}}},
		_map(["cabin", "wing_roof", "yard"]),
		{"type": "city_building", "id": "wing_bld", "locations": ["land"], "overmaps": [
			{"point": [0, 0, 0], "overmap": "wing_a_north"}, {"point": [1, 0, 0], "overmap": "wing_b_north"},
			{"point": [0, 0, 1], "overmap": "wing_roof_north"}, {"point": [1, 0, 1], "overmap": "wing_roof_north"}]},
	])
	_reload()
	var b := _build(_ref("data/json/wing.json", 2), _own_options())
	check_eq(b.own_terrain, {"bnme_playtest_wing_a": "wing_a", "bnme_playtest_wing_b": "wing_b",
		"bnme_playtest_wing_roof": "wing_roof"})
	var copies: Array = _copies(b, "data/json/wing.json")
	check_eq(copies.size(), 2)
	check_eq(copies[0].om_terrain, [["bnme_playtest_wing_a", "bnme_playtest_wing_b"]], "the grid's shape kept")
	check_eq(copies[1].om_terrain, ["bnme_playtest_wing_roof"], "only the ids the building needs")
	check_eq(b.start_terrain, PackedStringArray(["bnme_playtest_wing_a", "bnme_playtest_wing_b"]))
	var mod: Array = _read(b.basepath.path_join(MOD).path_join(Playtest.MOD_FILE))
	check_eq(mod[-1].overmaps.map(func(e: Dictionary) -> Variant: return e.overmap), [
		"bnme_playtest_wing_a_north", "bnme_playtest_wing_b_north",
		"bnme_playtest_wing_roof_north", "bnme_playtest_wing_roof_north"])
	_cleanup()


func test_own_terrain_off() -> void:
	_setup()
	var o := _own_options()
	o.own_start_terrain = false
	var b := _build(_ref(HOUSE, 0), o)
	check_eq(b.own_terrain, {})
	check_eq(b.copied, PackedStringArray())
	check_eq(b.start_terrain, PackedStringArray(["house"]))
	check_eq(b.disabled, PackedStringArray([HOUSE + "#1", OTHER + "#0"]), "today's behavior")
	check(not DirAccess.dir_exists_absolute(b.basepath.path_join(MOD).path_join(Playtest.MOD_COPIES)), "no copies")
	_cleanup()


func test_own_terrain_log() -> void:
	_setup()
	var b := _build(_ref("data/json/mapgen/roof.json", 0), _own_options())
	var names := Playtest.log_names(_session, b)
	for n in ["bnme_playtest_house_roof", "bnme_playtest_house_north", "data/json/mapgen/roof.json", HOUSE]:
		check(names.has(n), "names " + n)
	var copy := b.basepath.path_join(MOD).path_join(Playtest.MOD_COPIES).path_join("data/json/mapgen/roof.json")
	var text := ("10:00:01.000 ERROR : bad terrain in bnme_playtest_house_roof_north\n"
		+ "10:00:02.000 ERROR : Json error: %s:3:4: bad row\n" % copy
		+ "10:00:03.000 ERROR : nothing of mine in bnme_playtest\n"
		+ "10:00:04.000 ERROR : nothing of mine in house_roof\n")
	var mine := Playtest.entries_naming(Playtest.read_log(text), names)
	check_eq(mine.size(), 3, "the rotated own id, the copy's file, the mod")
	var real := Playtest.real_names(mine, b)
	check_eq(real[0].text, "bad terrain in house_roof_north\n(house_roof is the playtest's bnme_playtest_house_roof)")
	check_eq(real[1].text, "Json error: data/json/mapgen/roof.json:3:4: bad row\n"
		+ "(the file is the playtest's copy of yours (line numbers are the copy's))")
	check_eq(real[2].text, "nothing of mine in bnme_playtest", "the mod's id stays")
	check_eq(mine[0].text, "bad terrain in bnme_playtest_house_roof_north", "the entries are left alone")
	_cleanup()


# --- Step 2: settings, the editor's Playtest, debug.log ------------------------

func test_find_binary() -> void:
	var bn := TempTree.make({
		"out/build/old/src/cataclysm-bn-tiles": "old",
		"out/build/new/src/cataclysm-bn-tiles": "new",
		"out/build/curses/src/cataclysm-bn": "curses",
		"data/json/x.json": [],
	})
	OS.execute("touch", ["-d", "2020-01-01", bn.path_join("out/build/old/src/cataclysm-bn-tiles")])
	check_eq(Playtest.find_binary(bn), bn.path_join("out/build/new/src/cataclysm-bn-tiles"), "the newest build")
	var saved := bn.path_join("out/build/curses/src/cataclysm-bn")
	check_eq(Playtest.find_binary(bn, saved), saved, "the saved binary")
	check_eq(Playtest.find_binary(bn, bn.path_join("gone")), bn.path_join("out/build/new/src/cataclysm-bn-tiles"),
			"a saved binary that is gone")
	var f := FileAccess.open(bn.path_join("cataclysm-bn-tiles"), FileAccess.WRITE)
	f.store_string("top")
	f.close()
	check_eq(Playtest.find_binary(bn), bn.path_join("cataclysm-bn-tiles"), "BN's own folder first")
	DirAccess.remove_absolute(bn.path_join("cataclysm-bn-tiles"))
	DirAccess.remove_absolute(bn.path_join("out/build/old/src/cataclysm-bn-tiles"))
	DirAccess.remove_absolute(bn.path_join("out/build/new/src/cataclysm-bn-tiles"))
	check_eq(Playtest.find_binary(bn), saved, "the curses build last")
	DirAccess.remove_absolute(saved)
	check_eq(Playtest.find_binary(bn), "", "none")
	TempTree.remove(bn)


func test_worlds() -> void:
	var user := TempTree.make({
		"save/Rosier/worldoptions.json": [],
		"save/Alpha/master.gsav": "{}",
		"save/junk/notes.txt": "not a world",
	})
	check_eq(Playtest.worlds(user), PackedStringArray(["Alpha", "Rosier"]))
	check_eq(Playtest.default_template_world(user), "Rosier")
	TempTree.remove(user.path_join("save/Rosier"))
	check_eq(Playtest.default_template_world(user), "Alpha", "the first world without Rosier")
	TempTree.remove(user.path_join("save/Alpha"))
	check_eq(Playtest.default_template_world(user), "", "no world")
	check_eq(Playtest.worlds(""), PackedStringArray())
	TempTree.remove(user)


const LOG := """19:35:53.804 INFO : Render driver: 0/opengl
19:36:04.140 INFO LUA : bn: preloaded.
19:36:05.000 ERROR : src/mapgen.cpp:100 [void load()] Json error: data/json/mapgen/house.json:3:4: bad
    "rows": [
        ^
19:36:06.000 WARNING : src/x.cpp:5 [f] unknown terrain t_nope in house_roof
19:36:07.000 ERROR : src/y.cpp:7 [g] (error message will follow backtrace)
#0 0x123 foo()
#1 0x456 bar()
Backtrace emission took 0 seconds.
(continued from above) ERROR: no such item cabins
19:36:42.079 : Log shutdown.
-----------------------------------------
"""


func test_read_log() -> void:
	var entries := Playtest.read_log(LOG)
	check_eq(entries.map(func(e: Playtest.LogEntry) -> String: return e.level), ["ERROR", "WARNING", "ERROR"])
	check_eq(entries[0].time, "19:36:05.000")
	check_eq(entries[0].text, "src/mapgen.cpp:100 [void load()] Json error: data/json/mapgen/house.json:3:4: bad\n"
			+ "    \"rows\": [\n        ^", "lines up to the next entry")
	check_eq(entries[1].describe(), "19:36:06.000 warning: src/x.cpp:5 [f] unknown terrain t_nope in house_roof")
	check_eq(entries[2].text, "src/y.cpp:7 [g] no such item cabins", "the backtrace left out")
	check_eq(Playtest.read_log("").size(), 0)


func test_log_names() -> void:
	_setup()
	var doc := _session.open(_ref(HOUSE, 0))
	doc.paint([Vector2i(2, 0)], "#")
	var b := _build(_ref(HOUSE, 0))
	check_eq(b.log_paths, PackedStringArray([b.userdir.path_join("config/debug.log"), _config.path_join("debug.log")]))
	var names := Playtest.log_names(_session, b)
	for n in [HOUSE, OTHER, "house", "cabin", "shed", "stuff", Playtest.MOD_ID, Playtest.SPECIAL]:
		check(names.has(n), "names " + n)
	check(not names.has(MOD + "/" + Playtest.MOD_FILE), "not the playtest mod's files")
	var mine := Playtest.entries_naming(Playtest.read_log(LOG), PackedStringArray(["cabin", HOUSE]))
	check_eq(mine.size(), 1, "the file, not 'cabins'")
	mine = Playtest.entries_naming(Playtest.read_log(LOG), PackedStringArray(["house"]))
	check_eq(mine.size(), 1, "'house' in house.json, not in house_roof")
	_cleanup()


func test_find_log() -> void:
	var dir := TempTree.make({"a/debug.log": "old", "b/debug.log": "new"})
	var b := Playtest.Build.new()
	b.log_paths = PackedStringArray([dir.path_join("a/debug.log"), dir.path_join("b/debug.log"), dir.path_join("c/debug.log")])
	OS.execute("touch", ["-d", "2020-01-01", dir.path_join("a/debug.log")])
	var now := int(Time.get_unix_time_from_system())
	check_eq(Playtest.find_log(b, now - 60), dir.path_join("b/debug.log"), "the newest")
	check_eq(Playtest.find_log(b, now + 60), "", "nothing written since")
	TempTree.remove(dir)


func test_settings_saved() -> void:
	var dir := TempTree.make({"keep.txt": ""})
	var s := AppSettings.new()
	check_eq([s.game_binary, s.playtest_world, s.only_my_mapgen, s.own_start_terrain], ["", "", true, true], "defaults")
	check_eq([s.strong_character, s.no_monsters, s.start_in_daylight, s.reveal_building], [true, false, true, true], "character defaults")
	s.game_binary = "/x/cataclysm-bn-tiles"
	s.playtest_world = AppSettings.NO_WORLD
	s.only_my_mapgen = false
	s.own_start_terrain = false
	s.strong_character = false
	s.no_monsters = true
	s.start_in_daylight = false
	s.reveal_building = false
	check_eq(s.save_to(dir.path_join("s.cfg")), OK)
	var back := AppSettings.load_from(dir.path_join("s.cfg"))
	check_eq([back.strong_character, back.no_monsters, back.start_in_daylight, back.reveal_building],
		[false, true, false, false], "character settings")
	check_eq([back.game_binary, back.playtest_world, back.only_my_mapgen, back.own_start_terrain],
		["/x/cataclysm-bn-tiles", "/", false, false])
	TempTree.remove(dir)


func test_settings_dialog() -> void:
	var user := TempTree.make({"save/Rosier/worldoptions.json": [], "save/Alpha/worldoptions.json": []})
	var s := AppSettings.new()
	s.playtest_world = "Gone"
	var d := PlaytestDialog.new()
	d.setup(s, "", user)
	check_eq(d.world.item_count, 5, "default, none, two worlds, the missing one")
	check_eq(d.world.get_item_text(0), "Default (Rosier)")
	check_eq(d.world.get_item_text(d.world.selected), "Gone (not found)")
	check(d.own_terrain.button_pressed, "own start terrain on")
	check(d.only_mine.disabled, "only my mapgen doesn't matter with it")
	d.own_terrain.button_pressed = false
	d._update_only_mine()
	check(not d.only_mine.disabled, "it does without")
	check_eq([d.strong.button_pressed, d.no_monsters.button_pressed, d.daylight.button_pressed, d.reveal.button_pressed],
		[true, false, true, true], "character boxes")
	d.strong.button_pressed = false
	d.no_monsters.button_pressed = true
	d.daylight.button_pressed = false
	d.reveal.button_pressed = false
	d.world.select(1)
	d.only_mine.button_pressed = false
	d.binary.text = " /bin/game "
	d.apply()
	check_eq([s.game_binary, s.playtest_world, s.only_my_mapgen, s.own_start_terrain],
		["/bin/game", AppSettings.NO_WORLD, false, false])
	check_eq([s.strong_character, s.no_monsters, s.start_in_daylight, s.reveal_building], [false, true, false, false])
	d.world.select(3)
	d.apply()
	check_eq(s.playtest_world, "Rosier")
	d.free()
	TempTree.remove(user)


## A stand-in for the game: writes a debug.log into the userdir it's given
## (--basepath <dir>/ --userdir <dir>/), and its arguments into args.txt next
## to itself, and exits. Its --help lists --new-game when [param new_game].
## [param check_log] is what the fake game appends to debug.log when asked to
## --check-mods ("" for a clean check); it exits 1 when that has an ERROR.
func _fake_game(dir: String, new_game := false, name := "fake-bn", check_log := "") -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name)
	var help := "--world <name>\n    Load world\n" + ("--new-game <name>\n    Start a new game\n" if new_game else "")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("#!/bin/sh\nif [ \"$1\" = --help ]; then\ncat <<'END'\n" + help + "END\nexit 0\nfi\n"
		+ "case \"$*\" in *--check-mods*)\necho \"$@\" > \"$(dirname \"$0\")/check_args.txt\"\n"
		+ "echo 'Checking mod BN Map Editor playtest [bnme_playtest]'\nmkdir -p \"$4config\"\n"
		+ "cat >> \"$4config/debug.log\" <<'END'\n" + check_log + "END\n"
		+ "exit " + ("1" if check_log.contains(" ERROR ") else "0") + ";;\nesac\n"
		+ "echo \"$@\" > \"$(dirname \"$0\")/args.txt\"\n"
		+ "mkdir -p \"$4config\"\ncat > \"$4config/debug.log\" <<'END'\n" + LOG + "END\n")
	f.close()
	OS.execute("chmod", ["+x", path])
	return path


func _main() -> Control:
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.playtest_root = _out.path_join("playtest")
	main.playtest_config_dir = _config
	main.playtest_user_dir = ""
	main.load_index(_bn)
	return main


func test_main_playtest() -> void:
	_setup()
	var main := _main()
	check(main.playtest().begins_with("Open a map"), "no map")
	var m: Variant = main.open_id("house")
	main.settings.game_binary = _fake_game(_out)
	var doc: MapDocument = m.doc
	doc.paint([Vector2i(2, 0)], "#")
	check_eq(main.playtest(), "", "started")
	check(main.playtest_pid > 0, "a process")
	var b: Playtest.Build = main.playtest_build
	check(not b.new_game, "this game has no --new-game")
	check(main._status.text.contains("Play Now! (Default Scenario)"), main._status.text)
	check(main._report_text.text.contains("Applied: strong character ("), main._report_text.text)
	check(main._report_text.text.contains("start in daylight"), main._report_text.text)
	check(main._report_text.text.contains("the building revealed"), main._report_text.text)
	check(not main._report_text.text.contains("no monsters"), "off by default")
	var house: Array = _read(b.basepath.path_join(HOUSE))
	check_eq(house[0].object.rows[0], "..#" + ".".repeat(21), "the unsaved edit")
	var waited := 0
	while OS.is_process_running(main.playtest_pid) and waited < 5000:
		OS.delay_msec(20)
		waited += 20
	main.check_playtest()
	check_eq(main.playtest_pid, -1, "no longer watched")
	var shown: Array = main._problems_panel.game_log.map(func(e: Playtest.LogEntry) -> String: return e.level)
	# house.json is a changed file; house_roof's file and "cabins" aren't.
	check_eq(shown, ["ERROR"], "debug.log entries naming the user's files")
	check(main._problems_panel.game_log_title.contains("2 others"), main._problems_panel.game_log_title)
	main.free()
	_cleanup()


func test_main_options_from_settings() -> void:
	_setup()
	var main := _main()
	main.settings.strong_character = false
	main.settings.no_monsters = true
	main.settings.start_in_daylight = false
	main.settings.reveal_building = false
	var o: Playtest.Options = main.playtest_options()
	check_eq([o.strong_character, o.no_monsters, o.daylight, o.reveal_building], [false, true, false, false])
	main.free()
	_cleanup()


func test_supports_new_game() -> void:
	var dir := TempTree.make({})
	check(Playtest.supports_new_game(_fake_game(dir, true, "new")), "--help lists --new-game")
	check(not Playtest.supports_new_game(_fake_game(dir, false, "old")), "an older build")
	check(not Playtest.supports_new_game(dir.path_join("gone")), "no such binary")
	TempTree.remove(dir)


func test_main_playtest_new_game() -> void:
	_setup()
	var main := _main()
	main.open_id("house")
	main.settings.game_binary = _fake_game(_out, true)
	check_eq(main.playtest(), "", "started")
	var b: Playtest.Build = main.playtest_build
	check(b.new_game, "launched with --new-game")
	check(main._status.text.contains("starts it by itself"), main._status.text)
	var waited := 0
	while OS.is_process_running(main.playtest_pid) and waited < 5000:
		OS.delay_msec(20)
		waited += 20
	check_eq(FileAccess.get_file_as_string(_out.path_join("args.txt")).strip_edges(),
		" ".join(b.args(true)), "the arguments the game got")
	main.check_playtest()
	main.free()
	_cleanup()


func test_main_playtest_refusals() -> void:
	_setup()
	# A map BN won't load: a row too short.
	var bad := _map("shed")
	bad.object.rows[0] = "..."
	var f := FileAccess.open(_bn.path_join("data/json/mapgen/bad.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify([bad]))
	f.close()
	var main := _main()
	main.open_id("house")
	main.settings.game_binary = _out.path_join("no-such-game")
	check_eq(Playtest.find_binary(_bn), "", "the fake BN has no binary")
	check(main.playtest().begins_with("No Cataclysm-BN game binary"), "no binary")
	main.settings.game_binary = _fake_game(_out)
	var ref: DataIndex.MapgenRef = null
	for r: DataIndex.MapgenRef in main.index.mapgens:
		if r.source.path == "data/json/mapgen/bad.json":
			ref = r
	main.open_ref(ref)
	var why: String = main.playtest()
	check(why.begins_with("BN won't load shed"), why)
	check(why.contains("row"), "names the finding: " + why)
	check_eq(main.playtest_pid, -1, "nothing started")
	check(not DirAccess.dir_exists_absolute(_out.path_join("playtest/overlay")), "nothing built")
	main.free()
	_cleanup()


const CHECK_LOG := """10:00:01.000 INFO : Setting active world
10:00:02.000 ERROR : src/init.cpp:207 Json error: data/json/mapgen/house.json:3:4: bad row
10:00:03.000 ERROR : src/z.cpp:1 [f] something in the base game
10:00:04.000 WARNING : src/x.cpp:5 [f] unknown terrain t_nope in house_roof
10:00:05.000 : Log shutdown.
"""


func _check_target(main: Control, dir: String, log: String) -> void:
	main.open_id("house")
	main.settings.game_binary = _fake_game(dir, false, "fake-bn", log)


func test_check_flag() -> void:
	_setup()
	var main := _main()
	main.open_id("house")
	var b := Playtest.build(main.session, main.current_map().ref, main.playtest_options())
	check_eq(b.check_args(), b.args() + PackedStringArray(["--check-mods", Playtest.MOD_ID]), "check_args")
	main.free()
	_cleanup()


func test_check_reads_what_it_wrote() -> void:
	_setup()
	var before := _snapshot(_bn)
	var main := _main()
	main.open_id("house")
	var b := Playtest.build(main.session, main.current_map().ref, main.playtest_options())
	var names := Playtest.log_names(main.session, b)
	# The user's own debug.log already holds an old error naming house.
	var f := FileAccess.open(b.log_paths[0], FileAccess.WRITE)
	f.store_string("09:00:00.000 ERROR : old house error\n")
	f.close()
	var game := _fake_game(_out, false, "checker", CHECK_LOG)
	var r := Playtest.check(game, b, names)
	check_eq(r.error, "", "ran")
	check_eq(r.exit_code, 1, "the game exits 1 on errors")
	check(r.output.contains("Checking mod"), "stdout")
	check_eq(r.entries.map(func(e: Playtest.LogEntry) -> String: return e.time),
		["10:00:02.000", "10:00:03.000", "10:00:04.000"], "only what the check wrote")
	check_eq(r.mine.map(func(e: Playtest.LogEntry) -> String: return e.level), ["ERROR"],
		"house.json's error; the base game's error and house_roof's warning (no file of its own) are not mine")
	check_eq(r.my_errors(), 1)
	check_eq(FileAccess.get_file_as_string(_out.path_join("check_args.txt")).strip_edges(),
		" ".join(b.check_args()), "the arguments the game got")
	# A clean check.
	var clean := Playtest.check(_fake_game(_out, false, "clean", "10:00:01.000 INFO : fine\n"), b, names)
	check_eq([clean.error, clean.exit_code, clean.entries.size()], ["", 0, 0], "clean")
	# A game that never loads the data (no display).
	var broken := Playtest.check(_out.path_join("no-such-game"), b, names)
	check(broken.error != "", "a game that can't start: " + broken.error)
	check_eq(_snapshot(_bn), before, "BN untouched")
	main.free()
	_cleanup()


func test_main_check_in_game() -> void:
	_setup()
	var before := _snapshot(_bn)
	var main := _main()
	check(main.check_in_game().begins_with("Open a map"), "no map")
	_check_target(main, _out, CHECK_LOG)
	check_eq(main.check_in_game(), "", "started")
	check(main.check_in_game().contains("already running"), "one at a time")
	check(main.playtest().contains("still running"), "no playtest meanwhile")
	var waited := 0
	while main._check and waited < 10000:
		main.poll_check()
		OS.delay_msec(20)
		waited += 20
	check(main._check == null, "finished")
	check_eq(main.playtest_pid, -1, "nothing launched")
	check(not FileAccess.file_exists(_out.path_join("args.txt")), "the game was only asked to check")
	var panel: ProblemsPanel = main._problems_panel
	check_eq(panel.game_log.map(func(e: Playtest.LogEntry) -> String: return e.level), ["ERROR"])
	check(panel.game_log_title.contains("data check, not a playtest"), panel.game_log_title)
	check(panel.game_log_title.contains("2 others"), panel.game_log_title)
	check(main._status.text.contains("1 error"), main._status.text)
	check_eq(_snapshot(_bn), before, "BN untouched")
	main.free()
	_cleanup()


func test_playtest_refuses_after_check() -> void:
	_setup()
	var before := _snapshot(_bn)
	var main := _main()
	_check_target(main, _out, CHECK_LOG)
	main.settings.check_before_playtest = true
	var why: String = main.playtest()
	check(why.begins_with("The game reports 1 error in your files"), why)
	check(why.contains("house.json"), "names the entry: " + why)
	check_eq(main.playtest_pid, -1, "not launched")
	check(not FileAccess.file_exists(_out.path_join("args.txt")), "the game never started")
	check(main._problems_panel.game_log_title.contains("Check before the playtest"), main._problems_panel.game_log_title)
	# Errors that don't name the user's files don't stop it; neither does the setting being off.
	main.settings.game_binary = _fake_game(_out, false, "fake-bn", "10:00:02.000 ERROR : src/z.cpp:1 base game\n")
	check_eq(main.playtest(), "", "started")
	var waited := 0
	while OS.is_process_running(main.playtest_pid) and waited < 5000:
		OS.delay_msec(20)
		waited += 20
	main.check_playtest()
	main.settings.check_before_playtest = false
	main.settings.game_binary = _fake_game(_out, false, "fake-bn", CHECK_LOG)
	check_eq(main.playtest(), "", "started without the check")
	check_eq(_snapshot(_bn), before, "BN untouched")
	waited = 0
	while OS.is_process_running(main.playtest_pid) and waited < 5000:
		OS.delay_msec(20)
		waited += 20
	main.free()
	_cleanup()


func test_check_setting() -> void:
	var s := AppSettings.new()
	check(not s.check_before_playtest, "off by default")
	var dialog := PlaytestDialog.new()
	s.check_before_playtest = true
	dialog.setup(s, "", "")
	check(dialog.check_first.button_pressed, "the dialog shows it")
	dialog.check_first.button_pressed = false
	dialog.apply()
	check(not s.check_before_playtest, "and writes it")
	dialog.free()

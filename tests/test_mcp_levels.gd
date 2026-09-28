extends "res://tests/support/test_case.gd"
## Stage 10e: building levels through the MCP tools (get_map's levels,
## get_building, create_mapgen with a level, create_building) against a
## fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")
const TALL := "data/json/mapgen/tall.json"
const BUILDINGS := "data/json/buildings.json"

var _root := ""
var _ws := ""
var _tools: McpTools


static func _map(om: String, fill := "t_floor") -> Dictionary:
	var rows := []
	for y in 24:
		rows.append(".".repeat(24))
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": {"fill_ter": fill, "rows": rows}}


## - tall: z -1 tall_cellar (no mapgen), z 0 tall_1, z 1 tall_2 (weighted
##   twice); twin copies tall's overmaps; turned places tall_1 facing east
##   with nothing above; rules is a mutable special.
## - mymod has house_m (no building).
func _setup() -> void:
	var weighted := _map("tall_2")
	weighted["weight"] = 50
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
			{"type": "overmap_terrain", "id": "tall_cellar", "copy-from": "generic_city_building"},
			{"type": "overmap_terrain", "id": "tall_1", "copy-from": "generic_city_building"},
			{"type": "overmap_terrain", "id": "tall_2", "copy-from": "generic_up"}],
		BUILDINGS: [
			{"type": "city_building", "id": "tall", "locations": ["land"], "overmaps": [
				{"point": [0, 0, -1], "overmap": "tall_cellar_north"},
				{"point": [0, 0, 0], "overmap": "tall_1_north"},
				{"point": [0, 0, 1], "overmap": "tall_2_north", "locations": ["land"]}]},
			{"type": "city_building", "id": "twin", "copy-from": "tall"},
			{"type": "city_building", "id": "turned", "locations": ["land"], "overmaps": [
				{"point": [0, 0, 0], "overmap": "tall_1_east"}]},
			{"type": "overmap_special", "id": "rules", "subtype": "mutable",
				"overmaps": {"a": {"overmap": "tall_1_north"}}}],
		"data/json/regional_map_settings.json": [{"type": "region_settings", "id": "default",
				"city": {"shop_radius": 30, "houses": {"tall": 100}}}],
		TALL: [_map("tall_1", "t_grass"), _map("tall_2", "t_grass"), weighted],
	})
	_ws = TempTree.make({})
	_tools = McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(["mymod"]), _ws))


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


func _call(name: String, args := {}) -> Dictionary:
	var got: Variant = _tools.call_tool(name, args)
	if got is McpTools.Failure:
		check(false, "%s failed: %s" % [name, got.message])
		return {}
	return got


func _fails(name: String, args: Dictionary, contains: String) -> void:
	var got: Variant = _tools.call_tool(name, args)
	if check(got is McpTools.Failure, "%s %s should fail" % [name, args]):
		check(got.message.contains(contains), "%s: \"%s\" should mention \"%s\"" % [name, got.message, contains])


func _by_building(levels: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in levels:
		out[e.building] = e
	return out


func test_get_map_levels() -> void:
	_setup()
	var got := _call("get_map", {"id": "tall_1"})
	var places := _by_building(got.get("levels", []))
	check_eq(places.keys().size(), 3, str(got.get("levels")))
	var tall: Dictionary = places.get("tall", {})
	check_eq(tall.get("origin"), [0, 0, 0])
	check_eq(tall.get("z_levels"), [-1, 0, 1])
	check_eq(tall.get("dir"), "north")
	var above: Dictionary = tall.get("above", {})
	check_eq(above.get("z"), 1)
	if check_eq(above.get("tiles", []).size(), 1):
		var t: Dictionary = above.tiles[0]
		check_eq(t.om_terrain, "tall_2")
		check_eq(t.point, [0, 0, 1])
		check_eq(t.offset, [0, 0])
		check_eq(t.mapgens, [{"file": TALL, "index": 1}, {"file": TALL, "index": 2, "weight": 50}])
	var below: Dictionary = tall.get("below", {})
	if check_eq(below.get("tiles", []).size(), 1):
		check_eq(below.tiles[0].om_terrain, "tall_cellar")
		check_eq(below.tiles[0].get("no_mapgen"), true)
	var turned: Dictionary = places.get("turned", {})
	check_eq(turned.get("dir"), "east")
	check(str(turned.get("note")).contains("turned east"), str(turned))
	check_eq(turned.above.tiles, [])
	check(turned.above.note.contains("no level z 1"), turned.above.note)
	check(not places.has("rules"), "a mutable special has no place")
	check_eq(_call("get_map", {"id": "house_m"}).get("levels"), [], "no building places it")
	_cleanup()


func test_get_building() -> void:
	_setup()
	var got := _call("get_building", {"id": "tall"})
	check_eq(got.type, "city_building")
	check_eq(got.z_levels, [-1, 0, 1])
	check_eq(got.levels.size(), 3)
	check_eq(got.levels[2].tiles[0].om_terrain, "tall_2")
	check_eq(got.levels[0].tiles[0].get("no_mapgen"), true)
	check_eq(got.get("shares_overmaps_with"), ["twin"])
	var twin := _call("get_building", {"id": "twin", "z": 0})
	check_eq(twin.levels.size(), 1)
	check_eq(twin.overmaps_from.file, BUILDINGS)
	check_eq(twin.overmaps_from.index, 0)
	var rules := _call("get_building", {"id": "rules"})
	check_eq(rules.get("mutable"), true)
	check_eq(rules.pieces, [{"om_terrain": "tall_1", "dir": "north",
		"mapgens": [{"file": TALL, "index": 0}]}])
	_fails("get_building", {"id": "T"}, "tall, turned, twin")
	_fails("get_building", {"id": "tall", "z": 5}, "no level z 5")
	_cleanup()


func test_create_level() -> void:
	_setup()
	# Refusals.
	_fails("create_mapgen", {"file": TALL, "om_terrain": "tall_3", "level": {"building": "nope", "point": [0, 0, 2]}},
			"get_building")
	_fails("create_mapgen", {"file": TALL, "om_terrain": "tall_3", "level": {"building": "tall", "point": [0, 0]}},
			"[x, y, z]")
	_fails("create_mapgen", {"file": TALL, "om_terrain": "tall_3", "level": {"building": "rules", "point": [0, 0, 2]}},
			"mutable")
	_fails("create_mapgen", {"file": TALL, "om_terrain": "tall_3", "level": {"building": "tall", "point": [0, 0, 1]}},
			"already has tall_2")
	_fails("create_mapgen", {"file": TALL, "nested_id": "c", "mapgensize": [2, 2],
		"level": {"building": "tall", "point": [0, 0, 2]}}, "chunk")
	check_eq(_tools.session.dirty_files(), PackedStringArray(), "nothing made")

	# A level through twin: tall's list (twin copies it) gets the tile.
	var got := _call("create_mapgen", {"file": TALL, "om_terrain": "tall_3",
		"level": {"building": "twin", "point": [0, 0, 2]}})
	var level: Dictionary = got.get("level", {})
	check_eq(level.get("tiles_added"), [{"point": [0, 0, 2], "overmap": "tall_3_north"}])
	check_eq(level.get("dir"), "north", "from z 1's tile")
	check(str(level.get("note")).contains("the definition of tall"), str(level.get("note")))
	check_eq(level.get("defaults_used"), {"fill_ter": "t_grass"}, "z 1's fill")
	check_eq(got.get("fill_ter"), "t_grass")
	check_eq(got.get("overmap_terrain_added"), ["tall_3"])
	check_eq(got.get("linked_files"), [BUILDINGS])
	var session := _tools.session
	check_eq(session.files[TALL].objects[-1].get("copy-from"), "generic_up", "like z 1's stub")
	var levels := _by_building(got.get("levels", []))
	check_eq(levels.get("tall", {}).get("below", {}).get("tiles", [{}])[0].get("om_terrain"), "tall_2")
	check_eq(_call("get_building", {"id": "twin"}).z_levels, [-1, 0, 1, 2])

	# A roof: suggestions, no suffix with dir none.
	got = _call("create_mapgen", {"file": TALL, "om_terrain": "tall_roof",
		"level": {"building": "tall", "point": [0, 0, 3], "dir": "none"}})
	check_eq(got.get("level", {}).get("tiles_added"), [{"point": [0, 0, 3], "overmap": "tall_roof"}])
	check_eq(got.get("palettes"), ["roof_palette"])
	check_eq(got.get("fill_ter"), "t_flat_roof")

	# A tile the building lists but no mapgen draws: just drawn.
	got = _call("create_mapgen", {"file": TALL, "om_terrain": "tall_cellar",
		"level": {"building": "tall", "point": [0, 0, -1]}})
	check_eq(got.get("level", {}).get("tiles_added"), [])
	check(str(got.get("level", {}).get("note")).contains("already lists"), str(got.get("level")))
	check_eq(_index_tiles("tall", -1), ["tall_cellar"])

	# save of the map's file saves the building's too; discard takes both back.
	if JsonFormatter.new().is_available():
		var saved := _call("save", {"file": TALL})
		var files: Array = saved.get("saved", []).map(func(e: Dictionary) -> String: return e.file)
		files.sort()
		check_eq(files, [BUILDINGS, TALL])
		var text := FileAccess.get_file_as_string(_ws.path_join(BUILDINGS))
		check(text.contains("\"overmap\": \"tall_3_north\""), text)
	else:
		skip("json_formatter not built (tools/build_json_formatter.sh)")
	_cleanup()


func _index_tiles(id: String, z: int) -> Array:
	return _tools.session.index.buildings[id].level(z).map(func(t: DataIndex.BuildingTile) -> String: return t.oter)


func test_discard_level() -> void:
	_setup()
	_call("create_mapgen", {"file": TALL, "om_terrain": "tall_3", "level": {"building": "tall", "point": [0, 0, 2]}})
	check_eq(_tools.session.dirty_files().size(), 2)
	var d := _call("discard", {"file": TALL})
	check_eq(d.discarded_edits, true)
	check_eq(_tools.session.files.size(), 0, "the building file went with the map")
	check_eq(_call("get_building", {"id": "tall"}).z_levels, [-1, 0, 1])
	_cleanup()


func test_create_building() -> void:
	_setup()
	var rel := "data/mods/mymod/house_m.json"
	var got := _call("create_building", {"id": "house_m", "building": "house_m_b", "city_list": "houses",
		"weight": 50})
	check_eq(got.get("file"), rel)
	check_eq(got.get("tiles"), [{"point": [0, 0, 0], "overmap": "house_m_north"}])
	check_eq(got.get("files_touched"), [rel])
	check(str(got.get("city_list")).contains("region_overlay"), str(got))
	check_eq(_tools.session.files[rel].objects[-1],
			{"type": "region_overlay", "regions": ["all"], "city": {"houses": {"house_m_b": 50}}})
	var levels: Array = _call("get_map", {"id": "house_m"}).get("levels", [])
	check_eq(levels.size(), 1)

	# In core: the region settings are a second file.
	got = _call("create_building", {"id": "tall_1", "building": "tall_again", "city_list": "shops"})
	var touched: Array = got.get("files_touched", [])
	touched.sort()
	check_eq(touched, [TALL, EditSession.REGION_SETTINGS_FILE])
	got = _call("create_building", {"id": "tall_1", "building": "tall_solo"})
	check(str(got.get("note")).contains("won't spawn"), str(got))
	_fails("create_building", {"id": "tall_1", "building": "tall"}, "already exists")
	_fails("create_building", {"id": "tall_1", "building": "x", "city_list": "villages"}, "must be one of")
	_cleanup()

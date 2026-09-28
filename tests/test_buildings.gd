extends "res://tests/support/test_case.gd"
## Stage 11d: buildings as validated objects (Validator.validate_building,
## the Problems tab, MCP validate_building), the other levels named by stair
## and elevator findings, roof hints, and mutable specials in the Level
## picker. Against a fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _ws := ""


## A 24x24 map of [param fill] with [param marks] ({Vector2i: char}) drawn in.
static func _map(om: String, marks: Dictionary, fill := ".") -> Dictionary:
	var rows := []
	for y in 24:
		var row := ""
		for x in 24:
			row += marks.get(Vector2i(x, y), fill)
		rows.append(row)
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": {"fill_ter": "t_grass",
			"rows": rows, "terrain": {".": "t_floor", ",": "t_grass", "#": "t_wall", "<": "t_stairs_up",
				">": "t_stairs_down", "R": "t_flat_roof", " ": "t_open_air"}}}


## [param inside] cells ({Vector2i: char}) for a rectangle: walls on its
## edge, [param fill] inside.
static func _box(r: Rect2i, fill := ".") -> Dictionary:
	var out := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			out[Vector2i(x, y)] = "#" if edge else fill
	return out


## - listed (city_building, named in a mod's region_overlay): z 0 b_ground
##   (a walled room at (2..9, 2..9), grass around, stairs up at (5, 5)), z 1
##   b_roof (roof over the room plus one column east of it, open air over
##   the room's (4, 4)); z 1 above b_side is open_air (a builtin mapgen).
## - broken (city_building, no list): a terrain nobody defines, a point
##   listed twice, a tile nothing draws, a road piece (LINEAR, fine).
## - turned: g_ground (north) with its building half west (x < 12) under
##   g_roof placed east, whose covered rows (y >= 12) are that half.
## - rules: a mutable special with pieces mu_a and mu_b.
func _setup() -> void:
	var ground := _box(Rect2i(2, 2, 8, 8))
	ground[Vector2i(5, 5)] = "<"
	var roof := {}
	for y in range(2, 10):
		for x in range(2, 11):
			roof[Vector2i(x, y)] = "R"
	roof[Vector2i(4, 4)] = " "
	var g_ground := {}
	for y in 24:
		for x in 12:
			g_ground[Vector2i(x, y)] = "."
	var g_roof := {}
	for y in range(12, 24):
		for x in 24:
			g_roof[Vector2i(x, y)] = "R"
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/mods/extra/modinfo.json": [{"type": "MOD_INFO", "id": "extra", "name": "extra",
				"dependencies": ["bn"]}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2, "roof": "t_flat_roof"},
			{"type": "terrain", "id": "t_wall", "symbol": "#", "color": "white", "move_cost": 0, "roof": "t_flat_roof",
				"flags": ["WALL"]},
			{"type": "terrain", "id": "t_grass", "symbol": ",", "color": "green", "move_cost": 2},
			{"type": "terrain", "id": "t_flat_roof", "symbol": "-", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_open_air", "symbol": " ", "color": "white", "move_cost": 2,
				"flags": ["NO_FLOOR"]},
			{"type": "terrain", "id": "t_stairs_up", "symbol": "<", "color": "white", "move_cost": 2,
				"flags": ["GOES_UP"], "roof": "t_flat_roof"},
			{"type": "terrain", "id": "t_stairs_down", "symbol": ">", "color": "white", "move_cost": 2,
				"flags": ["GOES_DOWN"]}],
		"data/json/oter.json": [
			{"type": "overmap_terrain", "id": ["b_ground", "b_roof", "b_side", "open_air", "x_nomap", "g_ground",
				"g_roof", "mu_a", "mu_b"]},
			{"type": "overmap_terrain", "id": "road", "flags": ["LINEAR"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "listed", "overmaps": [
				{"point": [0, 0, 0], "overmap": "b_ground_north"},
				{"point": [1, 0, 0], "overmap": "b_side_north"},
				{"point": [0, 0, 1], "overmap": "b_roof_north"},
				{"point": [1, 0, 1], "overmap": "open_air"}]},
			{"type": "city_building", "id": "broken", "overmaps": [
				{"point": [0, 0, 0], "overmap": "nowhere_north"},
				{"point": [1, 0, 0], "overmap": "x_nomap_north"},
				{"point": [1, 0, 0], "overmap": "b_side_north"},
				{"point": [2, 0, 0], "overmap": "road_ew"}]},
			{"type": "city_building", "id": "turned", "overmaps": [
				{"point": [0, 0, 0], "overmap": "g_ground_north"},
				{"point": [0, 0, 1], "overmap": "g_roof_east"}]},
			{"type": "overmap_special", "id": "rules", "subtype": "mutable", "overmaps": {
				"a": {"overmap": "mu_a_north"}, "b": {"overmap": "mu_b_north"}}}],
		"data/json/mapgen/b.json": [_map("b_ground", ground, ","), _map("b_roof", roof, " "), _map("b_side", {}, ","),
				_map("g_ground", g_ground, ","), _map("g_roof", g_roof, " "), _map("mu_a", {}), _map("mu_b", {})],
		"data/mods/extra/regions.json": [{"type": "region_overlay", "regions": ["all"],
				"city": {"houses": {"listed": 50, "turned": 10}}}],
	})
	_ws = TempTree.make({})


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


static func _codes(list: Array[Validator.Finding]) -> Array:
	return list.map(func(f: Validator.Finding) -> String: return Validator.Code.keys()[f.code])


func test_validate_building() -> void:
	_setup()
	var index := DataIndex.load_bn(_root, PackedStringArray(["extra"]))
	check_eq(index.errors, PackedStringArray())
	check_eq(index.city_listed.get("listed"), PackedStringArray(["houses of overlay for all"]))
	check_eq(Validator.validate_building(index, index.buildings["listed"]).size(), 0,
			"listed, every tile drawn (open_air by BN's builtin)")
	var broken := Validator.validate_building(index, index.buildings["broken"])
	check_eq(_codes(broken), ["CITY_LIST", "BAD_TERRAIN", "NO_MAPGEN", "DUPLICATE_POINT"])
	check(broken[1].describe().begins_with("error: building broken: \"overmaps\" names terrain \"nowhere_north\""),
			broken[1].describe())
	check_eq(broken[1].load_fails, false, "reported on load")
	check(broken[2].text.contains("x_nomap"), broken[2].text)
	check(broken[2].describe().contains("fills it with floor"), broken[2].describe())
	check(broken[3].text.contains("(1, 0, 0)"), broken[3].text)
	check_eq(_codes(Validator.validate_building(index, index.buildings["rules"])), [], "a mutable special: no checks")
	# Without the mod, nothing lists it.
	var core := DataIndex.load_bn(_root)
	check_eq(_codes(Validator.validate_building(core, core.buildings["listed"])), ["CITY_LIST"])
	check(core.has_mapgen_for("open_air") and core.has_mapgen_for("road_ew") and core.has_mapgen_for("b_side"))
	check(not core.has_mapgen_for("x_nomap"))
	_cleanup()


## A stair finding names the other level's mapgen, in MCP too; the
## building's findings reach the Problems tab and validate_building.
func test_findings_name_levels() -> void:
	_setup()
	var index := DataIndex.load_bn(_root, PackedStringArray(["extra"]))
	var objects := MapgenObjects.new(index)
	var ground: DataIndex.MapgenRef = index.mapgens_for("b_ground")[0]
	var roof: DataIndex.MapgenRef = index.mapgens_for("b_roof")[0]
	var mapgen := objects.object_for(ground)
	var r := MapgenResolver.resolve(index, mapgen)
	var found := Validator.validate_map(index, ground, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(index, mapgen, r, objects.object_for), Stairs.new(index, objects.object_for))
	check_eq(_codes(found), ["STAIRS"], "the roof has no stairs down")
	if not found.is_empty():
		check_eq(found[0].levels, [roof])

	var tools := McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(["extra"]), _ws))
	var got: Dictionary = tools.call_tool("validate_map", {"id": "b_ground"})
	check_eq(got.findings[0].get("other_levels"), [{"file": "data/json/mapgen/b.json", "index": 1, "map": "b_roof"}])
	got = tools.call_tool("validate_building", {"id": "broken"})
	check_eq([got.errors, got.warnings, got.notes], [2, 1, 1])
	check_eq(got.findings[0].get("building"), "broken")
	check_eq(got.city_lists, [])
	check_eq(tools.call_tool("validate_building", {"id": "listed"}).city_lists, ["houses of overlay for all"])
	var missing: Variant = tools.call_tool("validate_building", {"id": "BRO"})
	check(missing is McpTools.Failure and missing.message.contains("broken"), "unknown ids list the near ones")

	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	var side: Variant = main.open_id("b_side")
	var place_ids: Array = BuildingLevels.places(main.index, side.ref).map(
			func(p: BuildingLevels.Place) -> String: return p.building.id)
	check_eq(place_ids, ["listed", "broken"])
	check_eq(side.place.building.id, "listed")
	var shown: Array[Validator.Finding] = main._problems_panel.findings
	check_eq(_codes(shown), ["CITY_LIST"], "no mod loaded: listed isn't in a city list")
	main.set_level_place(1)
	shown = main._problems_panel.findings
	check_eq(_codes(shown), ["BAD_TERRAIN", "DUPLICATE_POINT", "NO_MAPGEN", "CITY_LIST"], "broken's, errors first")
	main.free()
	_cleanup()


func test_roof_hints() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray(["extra"])
	main.load_index(_root)
	main.set_ghost(-1)
	var m: Variant = main.open_id("b_roof")
	check(RoofHints.is_roof(m.place, m.ref))
	var hints: Dictionary = m.canvas.roof_hints
	var overhang := hints.keys().filter(func(c: Vector2i) -> bool: return hints[c] == RoofHints.Kind.OVERHANG)
	overhang.sort()
	var want: Array = []
	for y in range(2, 10):
		want.append(Vector2i(10, y))
	check_eq(overhang, want, "the column past the east wall")
	check_eq(hints.get(Vector2i(4, 4)), RoofHints.Kind.UNCOVERED, "open air over the room")
	check_eq(hints.size(), 9)

	# Painting the gap shut clears it; the ghost above shows none.
	main.set_tool(MapTool.Kind.PAINT)
	main.set_brush("R")
	m.canvas.cell_pressed.emit(Vector2i(4, 4), false, false)
	m.canvas.cell_released.emit(Vector2i(4, 4), false)
	check(not m.canvas.roof_hints.has(Vector2i(4, 4)), "painted over")
	main.set_ghost(0)
	check_eq(m.canvas.roof_hints.size(), 0, "no ghost, no hints")
	main.set_ghost(-1)
	var ground: Variant = main.open_id("b_ground")
	check_eq(ground.canvas.roof_hints.size(), 0, "not a roof")

	# Compared turned: g_roof (placed east) covers g_ground's west half.
	var g: Variant = main.open_id("g_roof")
	check_eq(g.canvas.ghosts[0].turns(), 3, "the floor below turned back")
	check_eq(g.canvas.roof_hints.size(), 0, "lines up once turned")
	main.set_view_placed(true)
	check_eq(g.canvas.roof_hints.size(), 0, "and as placed")
	main.free()
	_cleanup()


func test_mutable_picker() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	var m: Variant = main.open_id("mu_a")
	check(m.place == null, "no fixed place")
	var picker: OptionButton = main._level_picker
	check_eq(picker.item_count, 2)
	check_eq(picker.get_item_text(1), "rules (mutable special)")
	check(not picker.disabled)
	check(picker.tooltip_text.contains("no neighbours, ghost or levels"), picker.tooltip_text)
	main.set_level_place(1)
	check_eq(picker.selected, 0, "the picker goes back")
	check(main._status.text.contains("mutable special"), main._status.text)
	var menu: PopupMenu = main._mutable_menu
	check_eq(menu.item_count, 2)
	check(menu.get_item_text(1).begins_with("mu_b"), menu.get_item_text(1))
	menu.index_pressed.emit(1)
	check_eq(main.current_map().ref.title(), "mu_b", "opened the other piece")
	main.free()
	_cleanup()

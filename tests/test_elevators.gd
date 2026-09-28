extends "res://tests/support/test_case.gd"
## Stage 11b: elevators (Stairs' ELEVATOR / CONTROL cells, the Validator's
## elevator findings, the ghost's elevator marks), against a fake BN
## checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _index: DataIndex


## A 24x24 map of "." with [param marks] ({Vector2i: char}) drawn in.
static func _map(om: Variant, marks: Dictionary, extra := {}, w := 1) -> Dictionary:
	var rows := []
	for y in 24:
		var row := ""
		for x in 24 * w:
			row += marks.get(Vector2i(x, y), ".")
		rows.append(row)
	var obj := {"fill_ter": "t_floor", "rows": rows, "terrain": {"E": "t_elevator", "6": "t_elevator_control",
			"5": "t_elevator_control_off", "C": "t_console"}}
	obj.merge(extra)
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": obj}


## Buildings:
## - lift: z 0 has a control at (5, 5) and a car at (6, 5)-(6, 6); z 2 a
##   control at (8, 5) by a car at (7, 5): 2 cells off, within 3. z 1 has
##   neither.
## - far: z 0 a control at (5, 5) by its car; z 1 its car at (20, 20) only.
## - lone: one level, a control with no car next to it; a console turning
##   on elevators that aren't there.
## - powered: an off control, and a console with elevator_on.
## - edge: two 2x1 levels; z 0's control is at (23, 5), its car across the
##   tile edge at (24, 5), as is z 1's (the mine's layout). BN looks across.
func _init_tree() -> void:
	var pc := {"name": "Lift power", "options": [{"name": "Power", "action": "elevator_on"}]}
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_console", "symbol": "6", "color": "blue", "move_cost": 0},
			{"type": "terrain", "id": "t_elevator", "symbol": ".", "color": "magenta", "move_cost": 2,
				"flags": ["ELEVATOR"]},
			{"type": "terrain", "id": "t_elevator_control", "symbol": "6", "color": "light_blue", "move_cost": 0,
				"examine_action": "elevator"},
			{"type": "terrain", "id": "t_elevator_control_off", "symbol": "6", "color": "light_gray",
				"move_cost": 0}],
		"data/json/oter.json": [{"type": "overmap_terrain", "id": ["l_0", "l_1", "l_2", "f_0", "f_1", "lone",
				"pw_0", "e_w", "e_e", "eu_w", "eu_e"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "lift", "overmaps": [
				{"point": [0, 0, 0], "overmap": "l_0_north"},
				{"point": [0, 0, 1], "overmap": "l_1_north"},
				{"point": [0, 0, 2], "overmap": "l_2_east"}]},
			{"type": "city_building", "id": "far", "overmaps": [
				{"point": [0, 0, 0], "overmap": "f_0_north"},
				{"point": [0, 0, 1], "overmap": "f_1_north"}]},
			{"type": "city_building", "id": "lone", "overmaps": [{"point": [0, 0, 0], "overmap": "lone_north"}]},
			{"type": "city_building", "id": "powered", "overmaps": [{"point": [0, 0, 0], "overmap": "pw_0_north"}]},
			{"type": "city_building", "id": "edge", "overmaps": [
				{"point": [0, 0, 0], "overmap": "e_w_north"}, {"point": [1, 0, 0], "overmap": "e_e_north"},
				{"point": [0, 0, 1], "overmap": "eu_w_north"}, {"point": [1, 0, 1], "overmap": "eu_e_north"}]},
		],
		"data/json/mapgen/lift.json": [
			_map("l_0", {Vector2i(5, 5): "6", Vector2i(6, 5): "E", Vector2i(6, 6): "E"}),
			_map("l_1", {}),
			# Turned east, yet paired by mapgen cell: BN turns the spot by the
			# tiles' rotation difference.
			_map("l_2", {Vector2i(8, 5): "6", Vector2i(7, 5): "E"}),
			_map("f_0", {Vector2i(5, 5): "6", Vector2i(6, 5): "E"}),
			_map("f_1", {Vector2i(20, 20): "E"}),
			_map("lone", {Vector2i(5, 5): "6", Vector2i(1, 1): "C"}, {"computers": {"C": pc}}),
			_map("pw_0", {Vector2i(5, 5): "5", Vector2i(6, 5): "E", Vector2i(1, 1): "C"}, {"computers": {"C": pc}}),
			_map([["e_w", "e_e"]], {Vector2i(23, 5): "6", Vector2i(24, 5): "E"}, {}, 2),
			_map([["eu_w", "eu_e"]], {Vector2i(24, 5): "E", Vector2i(24, 6): "6"}, {}, 2),
		],
	})
	_index = DataIndex.load_bn(_root)


func _findings(id: String) -> PackedStringArray:
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for(id)[0]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	var out := PackedStringArray()
	for f in Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for), Stairs.new(_index, objects.object_for)):
		out.append("%s %s %s: %s" % [f.severity_name(), Validator.Code.keys()[f.code], f.cell, f.text])
	return out


func test_elevator_cells() -> void:
	_init_tree()
	check_eq(_index.errors, PackedStringArray())
	check_eq(_index.terrain["t_elevator_control"].examine_action, "elevator")
	var objects := MapgenObjects.new(_index)
	var stairs := Stairs.new(_index, objects.object_for)
	var g := stairs.grid_for(_index.mapgens_for("l_0")[0])
	check_eq(g.cells(Vector2i.ZERO, Stairs.CONTROL), [Vector2i(5, 5)] as Array[Vector2i])
	check_eq(g.cells(Vector2i.ZERO, Stairs.ELEVATOR), [Vector2i(6, 5), Vector2i(6, 6)] as Array[Vector2i])
	check_eq(g.cells(Vector2i.ZERO, Stairs.UP | Stairs.DOWN), [] as Array[Vector2i], "an elevator isn't stairs")
	var off := stairs.grid_for(_index.mapgens_for("pw_0")[0])
	check_eq(off.cells(Vector2i.ZERO, Stairs.CONTROL_OFF), [Vector2i(5, 5)] as Array[Vector2i])
	check_eq(off.cells(Vector2i.ZERO, Stairs.CONTROL), [Vector2i(5, 5)] as Array[Vector2i], "a control once on")

	# The floors the z 0 control offers: z 2, not z 1.
	var lift: DataIndex.Building = _index.buildings["lift"]
	var levels := stairs.elevator_levels(lift, lift.at(Vector3i(0, 0, 0)), Vector2i(5, 5))
	check_eq(levels.keys(), [2], "z 1 has no elevator")
	check_eq(levels[2].near, [_index.mapgens_for("l_2")[0]])
	var from_top := stairs.elevator_levels(lift, lift.at(Vector3i(0, 0, 2)), Vector2i(8, 5))
	check_eq(from_top.keys(), [0])
	var far: DataIndex.Building = _index.buildings["far"]
	var off_levels := stairs.elevator_levels(far, far.at(Vector3i(0, 0, 0)), Vector2i(5, 5))
	check_eq(off_levels[1].near.size(), 0)
	check_eq(off_levels[1].far[0][1], Vector2i(20, 20))
	TempTree.remove(_root)


func test_elevator_findings() -> void:
	_init_tree()
	check_eq(_findings("l_0"), PackedStringArray(), "z 2 is offered")
	check_eq(_findings("l_1"), PackedStringArray(), "no elevator on z 1")
	check_eq(_findings("l_2"), PackedStringArray(), "z 0 is offered")
	check_eq(_findings("f_0"), PackedStringArray([
		"warning ELEVATOR (5, 5): in far (0, 0, z 0): elevator controls at (5, 5): no other level of far (z 1) has elevator floor (ELEVATOR terrain) within 3 cells of the same spot in its tile, so only this floor is offered",
		"note ELEVATOR_OFFSET (5, 5): in far (0, 0, z 0): elevator controls at (5, 5): f_1 (z 1) has its elevator floor farther than 3 cells off, e.g. at (20, 20); BN doesn't offer that floor"]))
	check_eq(_findings("f_1"), PackedStringArray(), "a car with no controls: nothing to check")
	check_eq(_findings("lone"), PackedStringArray([
		"note ELEVATOR_OFFSET (5, 5): in lone (0, 0, z 0): elevator controls at (5, 5): no elevator floor (ELEVATOR terrain) next to them, so the player can't stand in the car to ride it",
		"warning ELEVATOR (5, 5): in lone (0, 0, z 0): elevator controls at (5, 5): no other level of lone (it has one level) has elevator floor (ELEVATOR terrain) within 3 cells of the same spot in its tile, so only this floor is offered",
		"note ELEVATOR_ON (1, 1): console at (1, 1): \"elevator_on\" switches on every t_elevator_control_off on the z-level, and lone has none at z 0 (other buildings nearby may)"]))
	check_eq(_findings("e_w"), PackedStringArray(), "the car and z 1's across the tile edge")
	check_eq(_findings("eu_w"), PackedStringArray(), "and back")
	var pw := _findings("pw_0")
	check(not Array(pw).any(func(t: String) -> bool: return t.contains("ELEVATOR_ON")), "its own off control: %s" % [pw])
	TempTree.remove(_root)


func test_ghost_elevators() -> void:
	_init_tree()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	main.set_ghost(-1)
	var m: Variant = main.open_id("f_1")
	var ghosts: Array[LevelNav.Neighbor] = m.canvas.ghosts
	if check_eq(ghosts.size(), 1, "f_0 below"):
		check_eq(ghosts[0].elevators, [Vector2i(6, 5)] as Array[Vector2i], "its car marked")
	main.free()
	TempTree.remove(_root)
	TempTree.remove(ws)

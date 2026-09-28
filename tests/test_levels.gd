extends "res://tests/support/test_case.gd"
## Stage 10b: a map's levels (LevelNav) and the viewer's level up / down,
## against a fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")


static func _map(om: Variant, extra := {}) -> Dictionary:
	var rows := []
	var w := 1
	if om is Array and om[0] is Array:
		w = om[0].size()
	for y in 24 * (om.size() if om is Array and om[0] is Array else 1):
		rows.append(".".repeat(24 * w))
	var m := {"type": "mapgen", "method": "json", "om_terrain": om,
			"object": {"fill_ter": "t_floor", "rows": rows}}
	m.merge(extra)
	return m


## A map with a "#" in its top-left cell.
static func _corner_map(om: String) -> Dictionary:
	var m := _map(om)
	m.object.rows[0] = "#" + m.object.rows[0].substr(1)
	m.object.terrain = {"#": "t_rock"}
	return m


## Buildings:
## - tall: z -1 tall_basement, 0 tall_1, 1 tall_2 (two mapgens), 2 tall_roof (no
##   mapgen). tall_twin copies it, so each tall map has two buildings.
## - wide (2x1): z 0 one 2x1 mapgen (wide_w, wide_e); z 1 two 1x1 mapgens;
##   z -1 only under the east tile. wide_up_e is placed turned east.
static func _fake_bn() -> String:
	return TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/json/ter.json": [{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white",
				"move_cost": 2},
				{"type": "terrain", "id": "t_rock", "symbol": "#", "color": "white", "move_cost": 0},
				{"type": "terrain", "id": "t_grass", "symbol": ".", "color": "green", "move_cost": 2}],
		"data/json/oter.json": [{"type": "overmap_terrain", "id": ["tall_basement", "tall_1", "tall_2",
				"tall_roof", "wide_w", "wide_e", "wide_up_w", "wide_up_e", "wide_cellar"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "tall", "overmaps": [
				{"point": [0, 0, -1], "overmap": "tall_basement_north"},
				{"point": [0, 0, 0], "overmap": "tall_1_north"},
				{"point": [0, 0, 1], "overmap": "tall_2_north"},
				{"point": [0, 0, 2], "overmap": "tall_roof_north"}]},
			{"type": "city_building", "id": "tall_twin", "copy-from": "tall"},
			{"type": "city_building", "id": "wide", "overmaps": [
				{"point": [0, 0, 0], "overmap": "wide_w_north"},
				{"point": [1, 0, 0], "overmap": "wide_e_north"},
				{"point": [0, 0, 1], "overmap": "wide_up_w_north"},
				{"point": [1, 0, 1], "overmap": "wide_up_e_east"},
				{"point": [1, 0, -1], "overmap": "wide_cellar_north"}]},
		],
		"data/json/mapgen/tall.json": [
			_map("tall_basement"), _map("tall_1"), _map("tall_2", {"weight": 100}),
			_map("tall_2", {"weight": 50})],
		"data/json/mapgen/wide.json": [
			_map([["wide_w", "wide_e"]]), _map("wide_up_w"), _corner_map("wide_up_e"), _map("wide_cellar")],
	})


static func _ref(index: DataIndex, id: String, i := 0) -> DataIndex.MapgenRef:
	return index.mapgens_for(id)[i]


func test_level_nav() -> void:
	var root := _fake_bn()
	var index := DataIndex.load_bn(root)
	check_eq(index.errors, PackedStringArray())

	var tall_1 := _ref(index, "tall_1")
	var places := BuildingLevels.places(index, tall_1)
	check_eq(places.map(func(p: BuildingLevels.Place) -> String: return p.label()),
			["tall (0, 0, z 0)", "tall_twin (0, 0, z 0)"], "a map two buildings use")
	var tall := places[0]
	var up := BuildingLevels.step(index, tall, Vector2i.ONE, 1)
	if check(up != null, "z 1"):
		check_eq(up.tile.oter, "tall_2")
		check_eq(up.refs.size(), 2, "two mapgens (weights)")
		check_eq(up.refs[0].weight, 100)
	var roof := BuildingLevels.step(index, tall, Vector2i.ONE, 2)
	if check(roof != null, "z 2"):
		check(roof.missing(), "no mapgen draws the roof")
	check_eq(BuildingLevels.step(index, tall, Vector2i.ONE, 5), null, "no such level")
	check_eq(LevelNav.neighbors(index, tall, tall_1).size(), 0, "a 1x1 building")

	# A 2x1 floor drawn by one mapgen, the next floor by two.
	var ground := _ref(index, "wide_w")
	var wide := BuildingLevels.places(index, ground)
	check_eq(wide.size(), 1, "wide_w and wide_e give the same place")
	check_eq(wide[0].origin, Vector3i(0, 0, 0))
	check_eq(LevelNav.neighbors(index, wide[0], ground).size(), 0, "the map covers the level")
	var up_w := BuildingLevels.step(index, wide[0], Vector2i(2, 1), 1)
	check_eq(up_w.tile.oter, "wide_up_w", "top-left of the footprint first")
	var cellar := BuildingLevels.step(index, wide[0], Vector2i(2, 1), -1)
	check_eq(cellar.tile.oter, "wide_cellar", "the only tile of the level")
	check_eq(cellar.cell, Vector2i(24, 0))

	var at_up := BuildingLevels.place_of(index, up_w.tile, up_w.refs[0])
	check_eq(at_up.origin, Vector3i(0, 0, 1))
	var beside := LevelNav.neighbors(index, at_up, up_w.refs[0])
	if check_eq(beside.size(), 1, "wide_up_e beside it"):
		check_eq(beside[0].ref, _ref(index, "wide_up_e"))
		check_eq(beside[0].rect(), Rect2i(24, 0, 24, 24))
		check_eq(beside[0].label(), "wide_up_e (turned east)")
		check_eq(beside[0].turns(), 1)
		check_eq(LevelNav.neighbor_at(beside, Vector2i(30, 5)), 0)
		check_eq(LevelNav.neighbor_at(beside, Vector2i(5, 5)), -1)
	# From the up-east map, the 2x1 ground map sits one tile to the west.
	var at_e := BuildingLevels.place_of(index, beside[0].tiles[0].tile, beside[0].ref)
	check_eq(at_e.origin, Vector3i(1, 0, 1))
	var down := BuildingLevels.step(index, at_e, Vector2i.ONE, 0)
	check_eq(down.tile.oter, "wide_e", "straight down")
	var at_ground := BuildingLevels.place_of(index, down.tile, down.refs[0])
	check_eq(at_ground.origin, Vector3i(0, 0, 0), "the grid map's top-left point")
	var from_cellar := BuildingLevels.place_of(index, cellar.tile, cellar.refs[0])
	var cellar_beside := LevelNav.neighbors(index, from_cellar, cellar.refs[0])
	check_eq(cellar_beside.size(), 0, "nothing else below ground")
	var ground_beside := LevelNav.neighbors(index, at_e, beside[0].ref)
	check_eq(ground_beside.size(), 1)
	check_eq(ground_beside[0].cell, Vector2i(-24, 0), "west of the map: negative cells")
	TempTree.remove(root)


func test_main_levels() -> void:
	var root := _fake_bn()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.settings.mods = PackedStringArray()
	main.load_index(root)
	var m: Variant = main.open_id("tall_1")
	if not check(m != null, "opened"):
		main.free()
		TempTree.remove(root)
		TempTree.remove(ws)
		return
	check_eq(main._level_picker.item_count, 2, "two buildings to pick from")
	check(not main._level_picker.disabled)
	check_eq(int(main._z_spin.value), 0)
	check_eq(main._z_spin.min_value, -1.0)
	check_eq(main._z_spin.max_value, 2.0)
	main.set_level_place(1)
	check_eq(m.place.building.id, "tall_twin")

	# Two mapgens for z 1: a menu asks.
	check_eq(main.level_step(1), null)
	check_eq(main._level_menu.item_count, 2)
	check_eq(main.maps.size(), 1, "nothing opened yet")
	var up: Variant = main.open_level_tile(main._level_tile, 1)
	if check(up != null, "picked the second"):
		check_eq(up.ref.weight, 50)
		check_eq(up.place.origin.z, 1)
		check_eq(up.place.building.id, "tall_twin", "same building")
		check_eq(main.current_map(), up)
		check_eq(int(main._z_spin.value), 1)

	# No mapgen for the roof: a new map is offered, in the same file.
	check_eq(main.level_step(1), null)
	check(main._new_level_dialog.dialog_text.contains("tall_roof"), main._new_level_dialog.dialog_text)
	main.new_level_map(main._level_tile)
	check_eq(main._new_map_dialog.base_edit.text, "tall_roof")
	check_eq(main._new_map_dialog.path_edit.text, "data/json/mapgen/tall.json")
	check(not main._new_map_dialog.get_ok_button().disabled, main._new_map_dialog._info.text)
	main._new_map_dialog._on_confirmed()
	var roof: Variant = main.current_map()
	check_eq(roof.ref.title(), "tall_roof")
	check_eq(roof.place.origin.z, 2)
	check_eq(roof.place.building.id, "tall_twin", "created for the building it was asked from")

	var basement: Variant = main.go_to_level(-1)
	if check(basement != null, "straight to z -1"):
		check_eq(basement.ref.title(), "tall_basement")
	check_eq(main.level_step(-1), null)
	check(main._status.text.contains("no level z -2"), main._status.text)

	# The rest of a level around the map; double-click opens a piece.
	var w: Variant = main.open_id("wide_up_w")
	check_eq(w.canvas.neighbors.size(), 1)
	check(w.canvas.neighbors[0].ascii != null, "the neighbor is drawn")
	check_eq(w.canvas.bounds(), Rect2i(0, 0, 48, 24))
	var turned: AsciiMap = w.canvas.neighbors[0].ascii
	check_eq(turned.chars[0], ".", "the corner turned away from the top-left")
	check_eq(turned.chars[23], "#", "one turn clockwise: top-left goes top-right")
	check_eq(turned.rotated(3).chars[0], "#", "four turns in all")
	w.canvas.neighbor_hovered.emit(0)
	check(main._status.text.contains("wide_up_e"), main._status.text)
	w.canvas.neighbor_activated.emit(0)
	var e: Variant = main.current_map()
	check_eq(e.ref.title(), "wide_up_e")
	check_eq(e.place.origin, Vector3i(1, 0, 1))
	check_eq(e.canvas.neighbors[0].cell, Vector2i(-24, 0))
	var ground: Variant = main.level_step(-1)
	check_eq(ground.ref.size_omt(), Vector2i(2, 1), "the 2x1 ground map")
	check_eq(ground.place.origin, Vector3i(0, 0, 0))

	main.free()
	TempTree.remove(root)
	TempTree.remove(ws)

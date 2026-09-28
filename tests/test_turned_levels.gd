extends "res://tests/support/test_case.gd"
## Stage 11a: turned levels. A multi-tile map whose tiles the building turns
## is drawn one turned tile at a time, and "View as placed" draws the current
## map turned, against a fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")


## A 24x24 (or [param w] tiles wide) map of "." with [param marks]
## ({Vector2i: char}) drawn in.
static func _map(om: Variant, marks: Dictionary, w := 1) -> Dictionary:
	var rows := []
	for y in 24:
		var row := ""
		for x in 24 * w:
			row += marks.get(Vector2i(x, y), ".")
		rows.append(row)
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": {"fill_ter": "t_floor",
			"rows": rows, "terrain": {"<": "t_stairs_up", ">": "t_stairs_down", "#": "t_rock"}}}


## Building tw: z 0 a 2x1 map (tw_w, tw_e) placed turned east, and tw_x
## (1x1) east of it; z 1 two 1x1 maps, north. tw_e's top row is rock and its
## stairs up are at its (0, 23): turned east, the rock is the tile's east
## column and the stairs are at its (0, 0), under tw_up_e's stairs down and
## beside its rock column.
## Building tv turns a 2x1 map (tv_w, tv_e) as a whole, south: its tiles
## trade places.
static func _fake_bn() -> String:
	var ground_marks := {Vector2i(24, 23): "<"}
	for x in 24:
		ground_marks[Vector2i(24 + x, 0)] = "#"
	var up_marks := {Vector2i(0, 0): ">"}
	for y in 24:
		up_marks[Vector2i(23, y)] = "#"
	return TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_rock", "symbol": "#", "color": "white", "move_cost": 0},
			{"type": "terrain", "id": "t_stairs_up", "symbol": "<", "color": "white", "move_cost": 2,
				"flags": ["GOES_UP"]},
			{"type": "terrain", "id": "t_stairs_down", "symbol": ">", "color": "white", "move_cost": 2,
				"flags": ["GOES_DOWN"]}],
		"data/json/oter.json": [{"type": "overmap_terrain", "id": ["tw_w", "tw_e", "tw_x", "tw_up_w",
				"tw_up_e", "tv_w", "tv_e"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "tw", "overmaps": [
				{"point": [0, 0, 0], "overmap": "tw_w_east"},
				{"point": [1, 0, 0], "overmap": "tw_e_east"},
				{"point": [2, 0, 0], "overmap": "tw_x_north"},
				{"point": [0, 0, 1], "overmap": "tw_up_w_north"},
				{"point": [1, 0, 1], "overmap": "tw_up_e_north"}]},
			{"type": "city_building", "id": "tv", "overmaps": [
				{"point": [0, 0, 0], "overmap": "tv_e_south"},
				{"point": [1, 0, 0], "overmap": "tv_w_south"}]}],
		"data/json/mapgen/tw.json": [
			_map([["tw_w", "tw_e"]], ground_marks, 2), _map("tw_x", {}),
			_map("tw_up_w", {}), _map("tw_up_e", up_marks), _map([["tv_w", "tv_e"]], {}, 2)],
	})


func test_split_pieces() -> void:
	var root := _fake_bn()
	var index := DataIndex.load_bn(root)
	check_eq(index.errors, PackedStringArray())
	var grid: DataIndex.MapgenRef = index.mapgens_for("tw_w")[0]
	var x: DataIndex.MapgenRef = index.mapgens_for("tw_x")[0]
	var up_e: DataIndex.MapgenRef = index.mapgens_for("tw_up_e")[0]
	var at_x := BuildingLevels.places(index, x)[0]

	# Beside tw_x, the 2x1 map is two pieces, each turned east.
	var beside := LevelNav.neighbors(index, at_x, x)
	if check_eq(beside.size(), 2, "one piece per turned tile"):
		check_eq(beside[0].rect(), Rect2i(-48, 0, 24, 24))
		check_eq(beside[1].rect(), Rect2i(-24, 0, 24, 24))
		check_eq(beside[1].part, Rect2i(24, 0, 24, 24), "tw_e's half of the map")
		check_eq(beside[1].turns(), 1)
		check_eq(beside[1].label(), "tw_e (a tile of a 2x1 map) (turned east)")
		check_eq(beside[1].to_piece(Vector2i(24, 23)), Vector2i(0, 0), "the stairs, turned")
		check_eq(beside[1].to_piece(Vector2i(0, 23)), -Vector2i.ONE, "the other tile's cell")
		check_eq(beside[1].to_ref(Vector2i(0, 0)), Vector2i(24, 23), "and back")
		var whole := AsciiMap.build(index, MapgenResolver.resolve(index, MapgenObjects.new(index).object_for(grid)))
		var e := beside[1].shape(whole)
		check_eq(e.size, Vector2i(24, 24))
		check_eq(e.chars[0], "<", "the stairs at the tile's (0, 0)")
		for y in 24:
			if e.chars[y * 24 + 23] != "#":
				check(false, "the rock row turned into the east column, row %d" % y)
				break

	# The ghost under tw_up_e (north): the grid's east tile, turned east.
	var at_up := BuildingLevels.places(index, up_e)[0]
	var below := LevelNav.ghosts(index, at_up, up_e, 0)
	check_eq(below.map(func(n: LevelNav.Neighbor) -> Array: return [n.cell, n.turns()]),
			[[Vector2i(-24, 0), 1], [Vector2i(0, 0), 1], [Vector2i(24, 0), 0]])

	# The ghost over the grid map (drawn unturned): tw_up_e turned back.
	var at_grid := BuildingLevels.places(index, grid)[0]
	check_eq(at_grid.dir, "east")
	var above := LevelNav.ghosts(index, at_grid, grid, 1)
	check_eq(above.map(func(n: LevelNav.Neighbor) -> Array: return [n.cell, n.turns()]),
			[[Vector2i(0, 0), 3], [Vector2i(24, 0), 3]],
			"north tiles over east ones, as the map is drawn unturned")
	check_eq(above[1].to_piece(Vector2i(0, 0)), Vector2i(0, 23), "over the map's stairs at (24, 23)")
	var placed_above := LevelNav.ghosts(index, at_grid, grid, 1, [], true)
	check(placed_above.all(func(n: LevelNav.Neighbor) -> bool: return n.turns() == 0), "as placed: their own turns")

	# The grid map as placed: two tiles turned east; tw_x isn't turned.
	var placed := LevelNav.placed(at_grid, grid)
	if check_eq(placed.size(), 2):
		check_eq(placed[1].rect(), Rect2i(24, 0, 24, 24))
		check_eq(placed[1].turns(), 1)
		check_eq(placed[1].to_ref(Vector2i(0, 0)), Vector2i(24, 23))
	check_eq(LevelNav.placed(at_x, x).size(), 0, "nothing turned: drawn as it is")
	check_eq(LevelNav.placed_turns(at_grid, grid), [[Vector2i(0, 0), 1], [Vector2i(1, 0), 1]])

	# A 2x1 map turned as a whole: seen from tv_w's place, tv_e is west of it.
	var tv: DataIndex.MapgenRef = index.mapgens_for("tv_w")[0]
	var at_tv := BuildingLevels.places(index, tv)[0]
	check_eq(at_tv.origin, Vector3i(1, 0, 0))
	var tv_placed := LevelNav.placed(at_tv, tv)
	if check_eq(tv_placed.size(), 1, "only tv_w is where the map's layout has it"):
		check_eq(tv_placed[0].rect(), Rect2i(0, 0, 24, 24))
		check_eq(tv_placed[0].turns(), 2)
	var tv_beside := LevelNav.neighbors(index, at_tv, tv)
	check_eq(tv_beside.map(func(n: LevelNav.Neighbor) -> Array: return [n.cell, n.part, n.turns()]),
			[[Vector2i(-24, 0), Rect2i(24, 0, 24, 24), 2]], "tv_e, a tile of the same map, beside it")

	# The stair check already compares tiles turned.
	var objects := MapgenObjects.new(index)
	for ref: DataIndex.MapgenRef in [grid, up_e]:
		var mapgen := objects.object_for(ref)
		var r := MapgenResolver.resolve(index, mapgen)
		check_eq(Validator.validate_map(index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
				ChunkOverlay.build(index, mapgen, r, objects.object_for), Stairs.new(index, objects.object_for)).size(),
				0, "%s: its stairs line up" % ref.title())
	TempTree.remove(root)


func test_view_as_placed() -> void:
	var root := _fake_bn()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = ws
	main.settings.mods = PackedStringArray()
	main.load_index(root)
	main.set_ghost(1)
	var m: Variant = main.open_id("tw_w")
	if not check(m != null, "opened"):
		main.free()
		TempTree.remove(root)
		TempTree.remove(ws)
		return
	check_eq(m.canvas.placed.size(), 0, "drawn as it is by default")
	var ghosts: Array[LevelNav.Neighbor] = m.canvas.ghosts
	check_eq(ghosts[1].stairs, [Vector2i(0, 23)] as Array[Vector2i], "tw_up_e's stairs over the map's")
	check_eq(m.ascii.chars[23 * 48 + 24], "<")
	check_eq(m.canvas.neighbors.size(), 1, "tw_x")

	main.set_view_placed(true)
	var placed: Array[LevelNav.Neighbor] = m.canvas.placed
	if check_eq(placed.size(), 2, "each tile turned"):
		check_eq(placed[1].ascii.chars[0], "<", "the stairs at the east tile's (0, 0)")
		check_eq(placed[1].ascii.chars[23], "#", "its rock row is now its east column")
	ghosts = m.canvas.ghosts
	check_eq(ghosts[1].turns(), 0, "the level above as placed too")
	check_eq(ghosts[1].stairs, [Vector2i(0, 0)] as Array[Vector2i], "over the placed stairs")
	check_eq(ghosts[1].ascii.chars[23], "#", "rock over rock")
	check_eq(m.canvas.to_map(Vector2i(24, 0)), Vector2i(24, 23), "cells map back")
	check_eq(m.canvas.to_map(Vector2i(47, 0)), Vector2i(24, 0))

	# Read-only: painting is refused; Pick works on the map's own cell.
	main.set_tool(MapTool.Kind.PAINT)
	main.set_brush(".")
	m.canvas.cell_pressed.emit(Vector2i(24, 0), false, false)
	m.canvas.cell_released.emit(Vector2i(24, 0), false)
	check(not m.doc.can_undo(), "nothing painted")
	check(main._status.text.contains("read-only"), main._status.text)
	main.set_tool(MapTool.Kind.PICK)
	m.canvas.cell_pressed.emit(m.canvas.to_map(Vector2i(24, 0)), false, false)
	m.canvas.cell_released.emit(m.canvas.to_map(Vector2i(24, 0)), false)
	check_eq(m.brush, "<", "picked the stairs")
	main.open_cell_menu(Vector2i(24, 23))
	check_eq(main._cell_menu.item_count, 1, "only Pick in the cell menu")

	# Edits (undo too) redraw the placed view.
	main.set_view_placed(false)
	check_eq(m.canvas.placed.size(), 0)
	check_eq(m.canvas.ghosts[1].turns(), 3)
	main.set_tool(MapTool.Kind.PAINT)
	main.set_brush("#")
	m.canvas.cell_pressed.emit(Vector2i(24, 22), false, false)
	m.canvas.cell_released.emit(Vector2i(24, 22), false)
	check(m.doc.can_undo(), "painted")
	main.set_view_placed(true)
	check_eq(m.canvas.placed[1].ascii.chars[1], "#", "(24, 22) turned east is the tile's (1, 0)")
	main.undo()
	check_eq(m.canvas.placed[1].ascii.chars[1], ".", "undone")

	# A map nothing turns is drawn as it is.
	var tx: Variant = main.open_id("tw_x")
	check_eq(tx.canvas.placed.size(), 0)
	main.free()
	TempTree.remove(root)
	TempTree.remove(ws)

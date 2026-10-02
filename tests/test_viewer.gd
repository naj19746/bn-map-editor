extends "res://tests/support/test_case.gd"
## Stage 2 acceptance: real BN maps render in ASCII with no undefined symbols,
## and the viewer UI opens them headless.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")
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


func _render(index: DataIndex, id: String) -> AsciiMap:
	var refs := index.mapgens_for(id)
	if not check(not refs.is_empty(), "no mapgen for " + id):
		return null
	return AsciiMap.build(index, MapgenResolver.resolve(index, index.read_object(refs[0].source)))


func _check_all_ok(a: AsciiMap) -> void:
	check_eq(a.resolved.problems, PackedStringArray(), "problems")
	check_eq(a.count_state(AsciiMap.State.OK), a.size.x * a.size.y, "cells drawn with known ids")
	for s: AsciiMap.State in [AsciiMap.State.UNDEFINED, AsciiMap.State.NO_TERRAIN, AsciiMap.State.UNKNOWN_ID]:
		check_eq(a.count_state(s), 0, "cells in state %d" % s)


func test_house_1x1() -> void:
	var index := _core_index()
	if index == null:
		return
	var a := _render(index, "house_01")
	if a == null:
		return
	check_eq(a.size, Vector2i(24, 24))
	_check_all_ok(a)
	check(a.chars.has("┌") or a.chars.has("┐"), "walls are joined")


func test_apartments_mod_tower_2x2() -> void:
	var index := _core_index()
	if index == null:
		return
	var a := _render(index, "apartments_mod_tower_NW")
	if a == null:
		return
	check_eq(a.size, Vector2i(48, 48))
	_check_all_ok(a)
	check(a.describe_cell(30, 40).begins_with("x30 y40   OMT(1,1) apartments_mod_tower_SE local(6,16)"),
			a.describe_cell(30, 40))


## Every color name used by core terrain and furniture is one BN knows.
func test_all_tile_colors_known() -> void:
	var index := _core_index()
	if index == null:
		return
	var bad := PackedStringArray()
	for table: Dictionary in [index.terrain, index.furniture]:
		for id: String in table:
			var t: DataIndex.TileDef = table[id]
			for c in t.color:
				var p := BnColors.parse_bg(c) if t.bgcolor else BnColors.parse(c)
				if not p.known:
					bad.append("%s: %s" % [id, c])
					break
	check_eq(bad.slice(0, MAX_REPORTED), PackedStringArray(), "unknown colors")


## Every core json mapgen renders without undefined symbols or unknown ids.
func test_all_core_mapgens_render() -> void:
	var index := _core_index()
	if index == null:
		return
	var t := Time.get_ticks_msec()
	var objects := {}
	var bad := PackedStringArray()
	var count := 0
	for ref in index.mapgens:
		if ref.method != "json" or ref.kind == DataIndex.MapgenRef.UPDATE:
			continue
		if not objects.has(ref.source.path):
			var json := JSON.new()
			json.parse(FileAccess.get_file_as_string(index.bn_path.path_join(ref.source.path)))
			objects[ref.source.path] = json.data if json.data is Array else [json.data]
		var a := AsciiMap.build(index, MapgenResolver.resolve(index, objects[ref.source.path][ref.source.index]))
		count += 1
		for s: AsciiMap.State in [AsciiMap.State.UNDEFINED, AsciiMap.State.NO_TERRAIN, AsciiMap.State.UNKNOWN_ID]:
			if a.count_state(s):
				bad.append("%s: %d cells in state %d" % [ref.source, a.count_state(s), s])
	print("     rendered %d mapgens in %d ms" % [count, Time.get_ticks_msec() - t])
	check(count > 4000, "rendered: %d" % count)
	check_eq(bad.slice(0, MAX_REPORTED), PackedStringArray())


func test_main_scene_opens_map() -> void:
	var index := _core_index()
	if index == null:
		return
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	# The runner works before the root enters the tree, so _ready won't fire
	# on its own; build the UI directly.
	main._ready()
	var ws := TempTree.make({})
	main._workspace_override = ws
	main.load_index(index.bn_path)
	var m: Variant = main.open_id("apartments_mod_tower_NW")
	if check(m != null, "opened"):
		check_eq(main.maps.size(), 1)
		check_eq(m.ascii.size, Vector2i(48, 48))
		# The stairs above are 3 cells off (BN's data; Stage 10c), and no city
		# list names apartments_mod (Stage 11d).
		check_eq(main._problems_button.text, "2 notes")
		# Opening the same entry again reuses its tab.
		main.open_id("apartments_mod_tower_SE")
		check_eq(main.maps.size(), 1, "same entry, same tab")

		var canvas: MapCanvas = m.canvas
		canvas.cell_size = 10.0
		canvas.origin = Vector2(40, 40)
		check_eq(canvas.cell_at(Vector2(45, 45)), Vector2i(0, 0))
		check_eq(canvas.cell_at(Vector2(40 + 305, 40 + 405)), Vector2i(30, 40))
		check_eq(canvas.cell_at(Vector2(10, 45)), -Vector2i.ONE, "ruler")
		check_eq(canvas.cell_at(Vector2(40 + 485, 45)), -Vector2i.ONE, "past the map")
		canvas.cell_hovered.emit(Vector2i(30, 40))
		check(main._status.text.contains("apartments_mod_tower_SE"), main._status.text)
		canvas.cell_pressed.emit(Vector2i(30, 40), true, false)
		check_eq(canvas.highlight_key, m.ascii.resolved.cells[40][30], "alt+click picks and highlights the symbol")
		check_eq(main.tool.key, m.ascii.resolved.cells[40][30], "and makes it the brush")

		main.set_show_furniture(false)
		check(not m.ascii.show_furniture, "furniture toggle reaches the map")
		main.close_tab(0)
		check_eq(main.maps.size(), 0)
	check(main.open_id("no_such_map") == null, "unknown id")
	main.free()
	TempTree.remove(ws)


## Paint, undo, new symbol and save through the main scene.
func test_main_scene_edits_map() -> void:
	var index := _core_index()
	if index == null:
		return
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	var ws := TempTree.make({})
	main._workspace_override = ws
	main.load_index(index.bn_path)
	var m: Variant = main.open_id("house_01")
	if not check(m != null, "opened"):
		main.free()
		return
	var canvas: MapCanvas = m.canvas
	var wall: String = m.doc.resolved.key_at(0, 0)
	var target := Vector2i(5, 5)
	var before: String = m.doc.resolved.key_at(target.x, target.y)

	canvas.cell_pressed.emit(target, false, false)
	check_eq(m.doc.resolved.key_at(target.x, target.y), before, "no brush, nothing painted")
	canvas.cell_pressed.emit(Vector2i(0, 0), true, false)
	check_eq(main.tool.key, wall, "picked")
	main.set_tool(MapTool.Kind.LINE)
	canvas.cell_pressed.emit(target, false, false)
	canvas.cell_dragged.emit(target + Vector2i(3, 0), false)
	check_eq(canvas.preview.size(), 4, "line preview on the canvas")
	canvas.cell_released.emit(target + Vector2i(3, 0), false)
	check(canvas.preview.is_empty(), "preview cleared")
	check_eq(m.doc.resolved.key_at(target.x + 3, target.y), wall, "line painted")
	check_eq(m.ascii.resolved, m.doc.resolved, "view follows the document")
	check(main._tabs.get_tab_title(0).ends_with(" *"), "tab marked dirty")
	main.undo()
	check_eq(m.doc.resolved.key_at(target.x, target.y), before, "undone")
	main.redo()

	main._new_symbol_dialog.setup(m.doc)
	main._new_symbol_dialog.terrain.select_id("t_floor")
	main._new_symbol_dialog.furniture.select_id("f_chair")
	main._new_symbol_dialog._on_ids_changed()
	var key: String = main._new_symbol_dialog.key_edit.text
	check(not key.is_empty(), "a key is suggested")
	check(not main._new_symbol_dialog.get_ok_button().disabled, "valid")
	main._new_symbol_dialog._on_confirmed()
	check_eq(main.tool.key, key, "the new symbol becomes the brush")
	check_eq(m.doc.object().furniture.get(key), "f_chair")

	check_eq(main.save_current(), "")
	check(not main._tabs.get_tab_title(0).ends_with(" *"), "clean after save")
	check(FileAccess.file_exists(ws.path_join(m.ref.source.path)), "saved into the workspace")

	# New map dialog.
	main._new_map_dialog.setup(main.session)
	main._new_map_dialog.base_edit.text = "stage3_test_map"
	main._new_map_dialog.width.value = 2
	main._new_map_dialog._autofill()
	var fill: IdCompleter = main._new_map_dialog.fill_completer
	main._new_map_dialog.fill_edit.text = "t_nope_"
	main._new_map_dialog.fill_edit.text_changed.emit("t_nope_")
	check(main._new_map_dialog.get_ok_button().disabled, "an unknown fill_ter is refused")
	main._new_map_dialog.fill_edit.text = "t_gras"
	fill.update()
	var grass := range(fill.list.item_count).filter(func(i: int) -> bool:
		return fill.list.get_item_text(i) == "t_grass")
	if check_eq(grass.size(), 1, "fill_ter suggests terrain"):
		fill.accept(grass[0])
	check_eq(main._new_map_dialog.fill_edit.text, "t_grass")
	check(not main._new_map_dialog.get_ok_button().disabled, "taking a suggestion re-checks the dialog: " + main._new_map_dialog._info.text)
	main._new_map_dialog._on_confirmed()
	check_eq(main.maps.size(), 2, "new map opened in a tab")
	check_eq(main.current_map().doc.size(), Vector2i(48, 24))
	check_eq(main.current_map().doc.problems(), PackedStringArray())
	main.free()
	TempTree.remove(ws)


## Stage 10b: level up / down and the level around a map, on core data.
func test_main_levels_bn() -> void:
	var index := _core_index()
	if index == null:
		return
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	var ws := TempTree.make({})
	main._workspace_override = ws
	main.load_index(index.bn_path)
	var m: Variant = main.open_id("2Story02_1")
	if check(m != null and m.place != null, "2Story02_1 has a building"):
		check_eq(m.place.building.id, "2Story02")
		var titles := PackedStringArray()
		var asked := 0
		for dz in [1, 1, -1, -1, -1]:
			var got: Variant = main.level_step(dz)
			if got == null and main._level_menu.item_count > 1:
				asked += 1
				got = main.open_level_tile(main._level_tile, 0)
			titles.append(got.ref.title() if got else main._status.text)
		check_eq(titles, PackedStringArray(["2Story02_2", "2Story02_roof", "2Story02_2", "2Story02_1",
				"2Story02_basement"]))
		check_eq(asked, 2, "asked for 2Story02_2 and the basement (two mapgens each), once each")
		check_eq(main.level_step(-1), null, "no z -2")
	# mansion_entry: 3x3 tiles, each its own mapgen, corners and sides turned.
	var e: Variant = main.open_id("mansion_entry")
	if check(e != null and e.place != null, "mansion_entry has a building"):
		var n: Array = e.canvas.neighbors
		check_eq(n.size(), 8)
		check(n.all(func(x: LevelNav.Neighbor) -> bool: return x.ascii != null), "all drawn")
		check(n.any(func(x: LevelNav.Neighbor) -> bool: return x.turns() > 0), "some turned")
		check_eq(e.canvas.bounds().size, Vector2i(72, 72))
	main.free()
	TempTree.remove(ws)

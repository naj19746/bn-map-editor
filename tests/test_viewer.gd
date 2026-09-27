extends "res://tests/support/test_case.gd"
## Stage 2 acceptance: real BN maps render in ASCII with no undefined symbols,
## and the viewer UI opens them headless.

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
	main.load_index(index.bn_path)
	var m: Variant = main.open_id("apartments_mod_tower_NW")
	if check(m != null, "opened"):
		check_eq(main.maps.size(), 1)
		check_eq(m.ascii.size, Vector2i(48, 48))
		check_eq(main._problems_button.text, "No problems")
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
		canvas.cell_clicked.emit(Vector2i(30, 40))
		check_eq(canvas.highlight_key, m.ascii.resolved.cells[40][30], "click highlights the symbol")

		main.set_show_furniture(false)
		check(not m.ascii.show_furniture, "furniture toggle reaches the map")
		main.close_tab(0)
		check_eq(main.maps.size(), 0)
	check(main.open_id("no_such_map") == null, "unknown id")
	main.free()

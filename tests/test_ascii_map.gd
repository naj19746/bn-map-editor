extends "res://tests/support/test_case.gd"
## BnColors, tile flags and AsciiMap against a small fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _index: DataIndex


func _setup() -> void:
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [
			{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "cyan"},
			{"type": "terrain", "abstract": "t_wall_base", "symbol": "LINE_OXOX", "color": "light_gray",
				"flags": ["WALL", "AUTO_WALL_SYMBOL", "FLAMMABLE"]},
			{"type": "terrain", "id": "t_wall", "copy-from": "t_wall_base"},
			{"type": "terrain", "id": "t_wall_glass", "copy-from": "t_wall_base", "color": "light_cyan",
				"delete": {"flags": ["FLAMMABLE"]}, "extend": {"flags": ["TRANSPARENT"]}},
			# Its own connect group, so it doesn't join t_wall.
			{"type": "terrain", "id": "t_fence", "symbol": "LINE_XOXO", "color": "brown",
				"flags": ["AUTO_WALL_SYMBOL"], "connects_to": "WOODFENCE"},
			# AUTO_WALL_SYMBOL alone gives no group: drawn as its plain symbol.
			{"type": "terrain", "id": "t_column", "symbol": "LINE_XOXO", "color": "white",
				"flags": ["AUTO_WALL_SYMBOL"]},
			{"type": "terrain", "id": "t_water", "symbol": "~", "bgcolor": "blue"},
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
		],
	})
	_index = DataIndex.load_bn(_root)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)


func _build(object: Dictionary, extra := {}) -> AsciiMap:
	var mapgen := {"type": "mapgen", "method": "json", "om_terrain": "x", "object": object}
	mapgen.merge(extra, true)
	return AsciiMap.build(_index, MapgenResolver.resolve(_index, mapgen))


func _grid(ascii: AsciiMap, w: int, h: int) -> PackedStringArray:
	var out := PackedStringArray()
	for y in h:
		var row := ""
		for x in w:
			row += ascii.char_at(x, y)
		out.append(row)
	return out


func _pad(rows: Array) -> Array:
	var out := []
	for y in 24:
		var r: String = rows[y] if y < rows.size() else ""
		out.append(r + ".".repeat(24 - r.length()))
	return out


func test_colors() -> void:
	var p := BnColors.parse("light_gray")
	check_eq(p.fg, BnColors.GRAY)
	check_eq(p.bg, BnColors.BLACK)
	check_eq(BnColors.parse("c_white").fg, BnColors.WHITE)
	check_eq(BnColors.parse("ltred").fg, BnColors.LRED, "deprecated lt")
	check_eq(BnColors.parse("dkgray").fg, BnColors.DGRAY, "deprecated dk")
	p = BnColors.parse("i_red")
	check_eq([p.fg, p.bg], [BnColors.BLACK, BnColors.RED])
	p = BnColors.parse("h_white")
	check_eq([p.fg, p.bg], [BnColors.WHITE, BnColors.BLUE])
	p = BnColors.parse("c_light_gray_yellow")
	check_eq([p.fg, p.bg], [BnColors.GRAY, BnColors.BROWN], "curses yellow background is brown")
	p = BnColors.parse("yellow_white")
	check_eq([p.fg, p.bg], [BnColors.YELLOW, BnColors.GRAY])
	p = BnColors.parse_bg("light_green")
	check_eq([p.fg, p.bg], [BnColors.BLACK, BnColors.LGREEN])
	check(not BnColors.parse("mauve").known, "unknown name")
	check(not BnColors.parse("c_red_blue").known, "no c_*_blue pairs")


func test_flags_and_connect_groups() -> void:
	_setup()
	var wall: DataIndex.TileDef = _index.terrain["t_wall"]
	check_eq(wall.flags, PackedStringArray(["WALL", "AUTO_WALL_SYMBOL", "FLAMMABLE"]))
	check_eq(wall.connect_group, "WALL", "WALL flag implies the WALL group")
	var glass: DataIndex.TileDef = _index.terrain["t_wall_glass"]
	check_eq(glass.flags, PackedStringArray(["WALL", "AUTO_WALL_SYMBOL", "TRANSPARENT"]))
	check_eq(_index.terrain["t_fence"].connect_group, "WOODFENCE")
	check_eq(_index.terrain["t_column"].connect_group, "")
	_cleanup()


func test_wall_corners() -> void:
	_setup()
	var a := _build({
		"rows": _pad([
			"#####...F.",
			"#...#...F.",
			"#.h.G...FF",
			"#...#.....",
			"##G##..C..",
		]),
		"terrain": {"#": "t_wall", "G": "t_wall_glass", ".": "t_floor", "h": "t_floor",
			"F": "t_fence", "C": "t_column"},
		"furniture": {"h": "f_chair"},
	})
	check_eq(a.resolved.problems, PackedStringArray())
	check_eq(_grid(a, 10, 5), PackedStringArray([
		"┌───┐...│.",
		"│...│...│.",
		"│.h.│...└─",
		"│...│.....",
		"└───┘..│..",
	]))
	check_eq(a.count_state(AsciiMap.State.OK), 24 * 24)
	_cleanup()


func test_colors_and_furniture() -> void:
	_setup()
	var a := _build({
		"rows": _pad(["h~#"]),
		"terrain": {".": "t_floor", "h": "t_floor", "~": "t_water", "#": "t_wall"},
		"furniture": {"h": "f_chair"},
	})
	check_eq(a.char_at(0, 0), "h")
	check_eq(a.fg[0], BnColors.BROWN, "furniture color")
	check_eq(a.bg[1], BnColors.BLUE, "bgcolor")
	check_eq(a.char_at(2, 0), "─", "a lone wall keeps its symbol")
	a.show_furniture = false
	a.refresh()
	check_eq(a.char_at(0, 0), ".", "furniture hidden")
	check_eq(a.fg[0], BnColors.CYAN)
	_cleanup()


func test_states() -> void:
	_setup()
	# No fill_ter: '?' is undefined, ' ' has no terrain, 'x' names an unknown id.
	var a := _build({
		"rows": _pad(["? x"]),
		"terrain": {".": "t_floor", "x": "t_nope"},
	})
	check_eq(a.state_at(0, 0), AsciiMap.State.UNDEFINED)
	check_eq(a.state_at(1, 0), AsciiMap.State.NO_TERRAIN)
	check_eq(a.state_at(2, 0), AsciiMap.State.UNKNOWN_ID)
	check_eq(a.state_at(3, 0), AsciiMap.State.OK)
	check_eq(a.char_at(0, 0), "?", "an undefined key shows itself")

	# A nested chunk leaves unset cells alone.
	var mapgen := {"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk",
		"object": {"mapgensize": [3, 1], "rows": [" h."], "furniture": {"h": "f_chair"},
			"terrain": {".": "t_floor"}}}
	var n := AsciiMap.build(_index, MapgenResolver.resolve(_index, mapgen))
	check_eq(n.size, Vector2i(3, 1))
	check_eq(n.state_at(0, 0), AsciiMap.State.EMPTY)
	check_eq(n.state_at(1, 0), AsciiMap.State.EMPTY, "furniture only")
	check_eq(n.char_at(1, 0), "h")
	check_eq(n.state_at(2, 0), AsciiMap.State.OK)
	_cleanup()


func test_describe_cell() -> void:
	_setup()
	var rows := []
	for y in 48:
		rows.append((".".repeat(47) + "h") if y == 30 else ".".repeat(48))
	var a := _build({"rows": rows, "fill_ter": "t_floor", "furniture": {"h": "f_chair"}},
			{"om_terrain": [["a_nw", "a_ne"], ["a_sw", "a_se"]]})
	check_eq(a.describe_cell(47, 30),
			"x47 y30   OMT(1,1) a_se local(23,6)   'h'   t_floor ‹fill_ter› + f_chair ‹map›")
	_cleanup()

extends "res://tests/support/test_case.gd"
## MapgenResolver against a small fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _index: DataIndex


func _setup() -> void:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt", "t_door", "t_roof_a", "t_roof_b"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [
			{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
		],
		"data/json/palettes.json": [
			{"type": "palette", "id": "base", "terrain": {"#": "t_wall", ".": "t_dirt", "d": "t_door"},
				"items": {".": {"item": "trash", "chance": 5}}},
			{"type": "palette", "id": "house", "palettes": ["base"],
				"terrain": {".": "t_floor"}, "furniture": {"h": "f_chair"},
				"items": {".": {"item": "dust", "chance": 5}},
				"mapping": {"t": {"furniture": "f_table", "terrain": "t_floor"}}},
			{"type": "palette", "id": "loop_a", "palettes": ["loop_b"]},
			{"type": "palette", "id": "loop_b", "palettes": ["loop_a"]},
			{"type": "palette", "id": "roofs",
				"parameters": {"roof": {"type": "ter_str_id",
					"default": {"distribution": [["t_roof_a", 3], ["t_roof_b", 1]]}}},
				"terrain": {"r": {"param": "roof", "fallback": "t_roof_a"}}},
		],
	})
	_index = DataIndex.load_bn(_root)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)


func _rows(pattern: String, w := 24, h := 24) -> Array:
	var rows := []
	for y in h:
		var row := ""
		for x in w:
			row += pattern[(x + y) % pattern.length()]
		rows.append(row)
	return rows


func _map(object: Dictionary, om: Variant = "test_house") -> Dictionary:
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": object}


func test_palette_order_and_sources() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, _map({
		"palettes": ["house"], "fill_ter": "t_grass",
		"rows": _rows(".#hdt "),
		"terrain": {"d": "t_floor"}, "furniture": {"d": "f_table"},
	}))
	check_eq(r.problems, PackedStringArray())
	check_eq(r.size, Vector2i(24, 24))
	check_eq(r.palettes, PackedStringArray(["base", "house"]), "includes first")

	var dot: ResolvedMapgen.SymbolInfo = r.symbols["."]
	check_eq(dot.terrain.id(), "t_floor", "the including palette overrides the included one")
	check_eq(dot.terrain.source, "house")
	check_eq(dot.extras["items"].size(), 2, "items from both palettes apply")
	check_eq(dot.extras["items"][0].source, "base")
	check_eq(dot.extras["items"][0].chain, PackedStringArray(["house", "base"]))

	var d: ResolvedMapgen.SymbolInfo = r.symbols["d"]
	check_eq(d.terrain.id(), "t_floor", "the map overrides its palettes")
	check_eq(d.terrain.source, ResolvedMapgen.SOURCE_MAP)
	check_eq(d.furniture.id(), "f_table")
	check_eq(r.symbols["t"].furniture.id(), "f_table", "\"mapping\" form")

	# 'h' has furniture only, so its terrain falls back to fill_ter.
	var h_pos := Vector2i(2, 0)
	check_eq(r.key_at(h_pos.x, h_pos.y), "h")
	check_eq(r.terrain_at(h_pos.x, h_pos.y).source, ResolvedMapgen.SOURCE_FILL)
	check_eq(r.terrain_at(h_pos.x, h_pos.y).id(), "t_grass")
	check_eq(r.furniture_at(h_pos.x, h_pos.y).source, "house")
	_cleanup()


func test_null_terrain_does_not_override() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, _map({
		"palettes": ["base"], "rows": _rows("#"), "terrain": {"#": "t_null"}}))
	check_eq(r.symbols["#"].terrain.id(), "t_wall")
	check_eq(r.symbols["#"].terrain.source, "base")

	# A key whose only terrain is t_null is still defined; the cell keeps fill_ter.
	r = MapgenResolver.resolve(_index, _map({
		"fill_ter": "t_grass", "rows": _rows("|"), "terrain": {"|": "t_null"}}))
	check_eq(r.problems, PackedStringArray())
	check_eq(r.symbols["|"].null_terrain, true)
	check_eq(r.terrain_at(0, 0).source, ResolvedMapgen.SOURCE_FILL)
	_cleanup()


func test_values_and_parameters() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, _map({
		"palettes": ["roofs"], "rows": _rows("rabc"),
		"terrain": {
			"a": ["t_grass", ["t_dirt", 2], {"ter": "t_floor", "colors": []}],
			"b": {"distribution": [["t_dirt", 1], "t_grass"]},
			"c": {"switch": {"param": "roof", "fallback": "t_roof_a"},
				"cases": {"t_roof_a": "t_wall", "t_roof_b": "t_door"}},
		},
	}))
	check_eq(r.problems, PackedStringArray())
	check_eq(r.symbols["r"].terrain.ids, PackedStringArray(["t_roof_a", "t_roof_b"]))
	check_eq(r.symbols["a"].terrain.ids, PackedStringArray(["t_grass", "t_dirt", "t_floor"]))
	check_eq(r.symbols["b"].terrain.ids, PackedStringArray(["t_dirt", "t_grass"]))
	check_eq(r.symbols["c"].terrain.ids, PackedStringArray(["t_wall", "t_door"]))
	check(r.parameters.has("roof"), "palette parameters are merged")
	_cleanup()


func test_multi_tile_size() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, _map(
		{"fill_ter": "t_grass", "rows": _rows(" ", 48, 24)}, [["w", "e"]]))
	check_eq(r.problems, PackedStringArray())
	check_eq(r.size, Vector2i(48, 24))
	check_eq(r.omt_ids, [PackedStringArray(["w", "e"])] as Array[PackedStringArray])
	check_eq(r.terrain_at(47, 23).id(), "t_grass")
	_cleanup()


func test_problems() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, _map({
		"palettes": ["loop_a", "nope"], "rows": _rows("#?", 24, 23) + ["short"],
		"terrain": {"#": "t_unknown"}}))
	var text := "\n".join(r.problems)
	for expected in ["palette loop", "unknown palette \"nope\"", "row 24: expected 24 columns",
			"'?' has no terrain and there is no fill_ter", "unknown terrain \"t_unknown\""]:
		check(text.contains(expected), "expected a problem containing %s in:\n%s" % [expected, text])
	check_eq(r.size, Vector2i(24, 24))
	check_eq(r.key_at(23, 23), "", "short rows are padded")
	_cleanup()


func test_nested_mapgen_draws_over() -> void:
	_setup()
	var r := MapgenResolver.resolve(_index, {"type": "mapgen", "method": "json",
		"nested_mapgen_id": "chunk", "object": {"mapgensize": [3.0, 2.0],
		"rows": ["h h", " h "], "furniture": {"h": "f_chair"}}})
	check_eq(r.problems, PackedStringArray(), "no terrain is fine in a nested chunk")
	check_eq(r.size, Vector2i(3, 2))
	check(r.terrain_at(0, 0) == null)
	_cleanup()

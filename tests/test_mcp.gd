extends "res://tests/support/test_case.gd"
## Stage 9a/9b: the MCP server (McpServer, McpTools) against a small fake BN
## checkout. Handlers are called directly; test_stdio runs the real -s
## process with requests piped into it.

const TempTree := preload("res://tests/support/temp_tree.gd")
const HOUSE := "data/json/mapgen/house.json"
const PALETTES := "data/json/palettes.json"

var _root := ""
var _ws := ""
var _tools: McpTools


func _setup() -> void:
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 or y == 23 else "#" + ".".repeat(22) + "#")
	rows[2] = "#.h....x..............  "
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "Core", "core": true, "path": "../../json"}],
		"data/mods/extra/modinfo.json": [{"type": "MOD_INFO", "id": "extra", "name": "Extra", "dependencies": ["bn"]}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "name": "floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_wall", "name": "wall", "symbol": "#", "color": "white",
				"flags": ["WALL", "AUTO_WALL_SYMBOL"]},
			{"type": "terrain", "id": "t_grass", "name": "grass", "symbol": ",", "color": "green"},
			{"type": "terrain", "id": "t_dirt", "name": "dirt", "symbol": ".", "color": "brown"},
			{"type": "furniture", "id": "f_chair", "name": "chair", "symbol": "h", "color": "brown"},
			{"type": "overmap_terrain", "abstract": "generic_city_building", "name": "city building"},
			{"type": "overmap_terrain", "id": ["house", "broken"], "name": "house"},
			{"type": "item_group", "id": "stuff", "items": [["rock", 10]]},
		],
		# As text: the palettes' ints must come back as ints.
		"data/json/palettes.json": "[\n" \
			+ "  {\"type\": \"palette\", \"id\": \"base\", \"terrain\": {\"#\": \"t_wall\"}},\n" \
			+ "  {\"type\": \"palette\", \"id\": \"pal\", \"palettes\": [\"base\"], \"terrain\": {\".\": \"t_floor\"},\n" \
			+ "    \"furniture\": {\"h\": \"f_chair\"}, \"items\": {\"h\": {\"item\": \"stuff\", \"chance\": 30}}},\n" \
			+ "  {\"type\": \"palette\", \"id\": \"bad_pal\", \"terrain\": {\"z\": \"t_nope\"}}\n]\n",
		HOUSE: [
			{"type": "mapgen", "method": "json", "om_terrain": "house", "object": {
				"fill_ter": "t_grass", "rows": rows, "palettes": ["pal"], "terrain": {"x": "t_dirt"},
				"place_loot": [{"group": "stuff", "x": 3, "y": [4, 6], "chance": 50}],
				"place_nested": [{"chunks": ["chunk_a"], "x": 5, "y": 5}]}},
			{"type": "mapgen", "method": "json", "om_terrain": "house", "weight": 50, "object": {"fill_ter": "t_floor"}},
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk_a", "object": {
				"mapgensize": [2, 2], "rows": ["##", "##"], "terrain": {"#": "t_wall"}}},
		],
		"data/json/mapgen/broken.json": [
			{"type": "mapgen", "method": "json", "om_terrain": "broken", "object": {
				"fill_ter": "t_grass", "rows": _broken_rows(), "terrain": {"x": "t_nope"}}},
		],
	})
	# TempTree writes with JSON.stringify, which sorts keys (place_loot's
	# "chance" comes first).
	_ws = TempTree.make({})
	_tools = McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(), _ws))


static func _broken_rows() -> Array:
	var rows := []
	for y in 24:
		rows.append("xQ" + " ".repeat(22) if y == 0 else " ".repeat(24))
	return rows


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


## Calls [param name] through the registry (arguments checked) and expects
## a result.
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


func test_protocol() -> void:
	var server := McpServer.new(McpTools.new())
	var reply := func(line: String) -> Dictionary:
		var text := server.handle_line(line)
		var parsed := BnJson.parse(text)
		check(parsed.ok() and parsed.value is Dictionary, "reply to %s isn't JSON: %s" % [line, text])
		check(not text.contains("\n"), "a reply is one line")
		return parsed.value if parsed.ok() else {}
	var init: Dictionary = reply.call('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' \
			+ '{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}')
	check_eq(init.get("id"), 1, "int id stays an int")
	check_eq(init.result.protocolVersion, "2025-03-26", "a supported version is echoed")
	check_eq(init.result.capabilities, {"tools": {}})
	check_eq(init.result.serverInfo.name, "bn-map-editor")
	init = reply.call('{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}')
	check_eq(init.get("id"), "a", "string id")
	check_eq(init.result.protocolVersion, McpServer.PROTOCOL_VERSIONS[0], "else the latest")
	check_eq(server.handle_line('{"jsonrpc":"2.0","method":"notifications/initialized"}'), "", "no reply to a notification")
	check_eq(server.handle_line("  "), "", "blank line")
	check_eq(reply.call('{"jsonrpc":"2.0","id":2,"method":"ping"}').result, {})
	var listed: Dictionary = reply.call('{"jsonrpc":"2.0","id":3,"method":"tools/list"}')
	var names := []
	for t: Dictionary in listed.result.tools:
		names.append(t.name)
		check(t.description is String and t.inputSchema.type == "object", "tool %s has a schema" % t.name)
	check_eq(names, ["search_maps", "get_map", "get_palette", "validate_map", "validate_palette", "lookup_id",
		"list_mods", "sync_status", "paint_cells", "paint_rect", "paint_line", "fill", "paint_rows", "add_symbol",
		"remove_symbol", "rename_symbol", "undo", "redo", "save", "discard", "reload", "add_placement", "update_placement",
		"remove_placement", "set_map_palettes", "set_map_fields", "set_symbol_mapping", "create_mapgen", "get_building", "validate_building", "create_building",
		"edit_palette_key", "set_palette_includes", "rename_key", "delete_palette", "create_palette"])
	check_eq(reply.call('{"jsonrpc":"2.0","id":4,"method":"nope"}').error.code, McpServer.METHOD_NOT_FOUND)
	check_eq(reply.call('{"jsonrpc":"2.0","id":5,"method":').error.code, McpServer.PARSE_ERROR)
	check_eq(reply.call('{"id":6,"method":"ping"}').error.code, McpServer.INVALID_REQUEST, "no jsonrpc member")
	check_eq(reply.call('[{"jsonrpc":"2.0","id":7,"method":"ping"}]').error.code, McpServer.INVALID_REQUEST, "batch")
	var call := '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":%s,"arguments":%s}}'
	check_eq(reply.call(call % ['"nope"', "{}"]).error.code, McpServer.INVALID_PARAMS, "unknown tool")
	# Bad arguments and handler failures are tool results with isError.
	var bad: Dictionary = reply.call(call % ['"search_maps"', '{"limit":"x"}'])
	check_eq(bad.result.isError, true)
	check(bad.result.content[0].text.contains("\"limit\" must be an integer"), bad.result.content[0].text)
	bad = reply.call(call % ['"search_maps"', '{"what":1}'])
	check(bad.result.content[0].text.contains("Unknown argument \"what\""), bad.result.content[0].text)
	bad = reply.call(call % ['"get_palette"', "{}"])
	check(bad.result.content[0].text.contains("Missing argument \"id\""), bad.result.content[0].text)
	bad = reply.call(call % ['"lookup_id"', '{"kind":"spaceship"}'])
	check(bad.result.content[0].text.contains("must be one of terrain"), bad.result.content[0].text)
	bad = reply.call(call % ['"paint_cells"', '{"key":"x","cells":[1,2]}'])
	check(bad.result.content[0].text.contains("\"cells\" must be a list of lists"), bad.result.content[0].text)
	bad = reply.call(call % ['"search_maps"', "{}"])
	check(bad.result.content[0].text.contains("No BN data loaded"), "without a loader: %s" % bad.result.content[0].text)


func test_pretty() -> void:
	check_eq(McpServer.pretty({"a": 1, "b": [1.5, "x"]}), '{"a":1,"b":[1.5,"x"]}', "short stays on one line")
	var long := {"rows": ["a".repeat(60), "b".repeat(60)], "n": 3}
	check_eq(McpServer.pretty(long), '{\n  "rows": [\n    "%s",\n    "%s"\n  ],\n  "n": 3\n}' % ["a".repeat(60), "b".repeat(60)])
	check_eq(BnJson.parse(McpServer.pretty(long)).value, long, "reads back the same")


func test_search_maps() -> void:
	_setup()
	var all := _call("search_maps")
	check_eq(all.get("total"), 4, "every mapgen entry")
	var houses := _call("search_maps", {"query": "HOUSE", "kind": "om_terrain"})
	check_eq(houses.get("total"), 2, "ids match case-insensitively")
	check_eq(houses.maps[0], {"ids": ["house"], "kind": "om_terrain", "file": HOUSE, "index": 0, "mod": "bn",
		"variant": 0, "variants": 2})
	check_eq(houses.maps[1].get("weight"), 50)
	check_eq(houses.maps[1].get("variant"), 1)
	var chunk := _call("search_maps", {"query": "chunk", "kind": "nested"})
	check_eq(chunk.maps, [{"ids": ["chunk_a"], "kind": "nested", "file": HOUSE, "index": 2, "mod": "bn",
		"mapgensize": [2, 2]}])
	var by_file := _call("search_maps", {"query": "mapgen/broken", "limit": 1})
	check_eq([by_file.total, by_file.shown, by_file.maps[0].ids], [1, 1, ["broken"]])
	var limited := _call("search_maps", {"limit": 2})
	check_eq([limited.total, limited.shown], [4, 2])
	_cleanup()


func test_get_map() -> void:
	_setup()
	var m := _call("get_map", {"id": "house"})
	check_eq(m.get("size"), [24, 24])
	check_eq(m.get("fill_ter"), "t_grass")
	check_eq(m.get("palettes"), ["pal"])
	check_eq(m.rows[2], "#.h....x..............  ", "raw rows")
	var legend: Dictionary = m.legend
	check_eq(legend.keys(), ["#", ".", "h", "x", " "], "symbols in the order the rows use them")
	check_eq(legend["#"], {"terrain": {"value": "t_wall", "from": "palette base (via pal)"}})
	check_eq(legend["x"], {"terrain": {"value": "t_dirt", "from": "map"}})
	check_eq(legend[" "], {"terrain": {"value": "t_grass", "from": "fill_ter"}}, "undefined ' ' is fill_ter")
	check_eq(legend["h"], {
		"terrain": {"value": "t_grass", "from": "fill_ter"},
		"furniture": {"value": "f_chair", "from": "palette pal"},
		"items": [{"value": {"item": "stuff", "chance": 30}, "from": "palette pal"}],
	}, "palette values as written (ints)")
	check_eq(m.get("placements"), [
		{"member": "place_loot", "index": 0, "entry": {"chance": 50, "group": "stuff", "x": 3, "y": [4, 6]}},
		{"member": "place_nested", "index": 0, "entry": {"chunks": ["chunk_a"], "x": 5, "y": 5}},
	])
	check_eq(m.get("chunks"), [{"chunk": "chunk_a", "at": [5, 5], "by": "place_nested #0"}])
	var ascii: Array = m.get("ascii", [])
	check_eq(ascii.size(), 24)
	check_eq(ascii[2], "│.h...................,,", "furniture, own terrain, fill_ter; walls joined")
	check_eq(ascii[5].substr(5, 2), "┌┐", "the chunk is drawn over")
	check_eq(ascii[0], "┌──────────────────────┐")
	check_eq(m.get("problems"), {"errors": 0, "warnings": 0, "notes": 0})
	check_eq(m.get("dirty"), false)
	var plain := _call("get_map", {"id": "house", "show_chunks": false, "show_furniture": false})
	check_eq(plain.ascii[5].substr(5, 2), "..")
	check_eq(plain.ascii[2].substr(2, 1), ",", "no furniture: the fill_ter under it")
	var other := _call("get_map", {"id": "house", "variant": 1})
	check_eq([other.index, other.rows, other.legend], [1, null, {"": {"terrain": {"value": "t_floor", "from": "fill_ter"}}}])
	var chunk := _call("get_map", {"file": HOUSE, "index": 2})
	check_eq([chunk.ids, chunk.size, chunk.ascii], [["chunk_a"], [2, 2], ["┌┐", "└┘"]])
	_fails("get_map", {"id": "nope"}, "No mapgen for \"nope\"")
	_fails("get_map", {"id": "house", "variant": 2}, "variant 0-1")
	_fails("get_map", {"file": HOUSE}, "Pass \"index\"")
	_fails("get_map", {"file": HOUSE, "index": 7}, "No mapgen at")
	_fails("get_map", {}, "Pass \"id\"")
	_cleanup()


func test_get_palette() -> void:
	_setup()
	var p := _call("get_palette", {"id": "pal"})
	check_eq([p.id, p.file, p.index, p.mod], ["pal", "data/json/palettes.json", 1, "bn"])
	check_eq(p.get("includes"), ["base"])
	check_eq(p.keys, {
		"#": {"terrain": {"value": "t_wall", "from": "palette base"}},
		".": {"terrain": {"value": "t_floor", "from": "this palette"}},
		"h": {"furniture": {"value": "f_chair", "from": "this palette"},
			"items": [{"value": {"item": "stuff", "chance": 30}, "from": "this palette"}]},
	})
	check_eq(p.json.items, {"h": {"item": "stuff", "chance": 30}}, "its own JSON, ints kept")
	check(not _call("get_palette", {"id": "pal", "include_json": false}).has("json"), "json left out")
	_fails("get_palette", {"id": "nope"}, "No palette \"nope\"")
	_cleanup()


func test_validate() -> void:
	_setup()
	var ok := _call("validate_map", {"id": "house"})
	check_eq([ok.errors, ok.warnings, ok.findings], [0, 0, []])
	var broken := _call("validate_map", {"id": "broken"})
	check_eq(broken.get("errors"), 2)
	var by_code := {}
	for f: Dictionary in broken.get("findings", []):
		by_code[f.code] = f
	check_eq(by_code.get("UNDEFINED_SYMBOL"), {"severity": "error", "code": "UNDEFINED_SYMBOL",
		"text": "'Q' has no terrain, furniture or other definition", "reaction": "BN reports this on every load",
		"wont_load": false, "symbol": "Q"})
	check(by_code.has("UNKNOWN_ID") and by_code.UNKNOWN_ID.symbol == "x", "unknown t_nope: %s" % [by_code.get("UNKNOWN_ID")])
	# The same through an open document (get_map opened it).
	_call("get_map", {"id": "broken"})
	check_eq(_call("validate_map", {"id": "broken"}).get("findings"), broken.findings, "open or not")
	var pal := _call("validate_palette", {"id": "bad_pal"})
	check_eq(pal.get("errors"), 1)
	check_eq(pal.findings[0].get("palette"), "bad_pal")
	check_eq(pal.findings[0].get("symbol"), "z")
	check_eq(_call("validate_palette", {"id": "pal"}).get("findings"), [])
	_cleanup()


func test_lookup_id() -> void:
	_setup()
	var t := _call("lookup_id", {"kind": "terrain", "query": "t_floor"})
	check_eq(t, {"query": "t_floor", "known": true, "kind": "terrain", "total": 1, "shown": 1,
		"ids": [{"id": "t_floor", "name": "floor", "symbol": "."}]})
	var walls := _call("lookup_id", {"kind": "terrain", "query": "T_"})
	check_eq([walls.known, walls.total], [false, 5], "substring, case-insensitive (t_null too)")
	var none := _call("lookup_id", {"kind": "furniture", "query": "f_null"})
	check_eq([none.known, none.total], [true, 1], "the nothing id")
	check_eq(_call("lookup_id", {"kind": "item_group"}).get("ids"), ["stuff"], "no query lists all")
	check_eq(_call("lookup_id", {"kind": "chunk", "query": "chunk_a"}).get("known"), true)
	var pals := _call("lookup_id", {"kind": "palette", "query": "pal"})
	check_eq([pals.known, pals.ids], [true, ["bad_pal", "pal"]])
	_cleanup()


func test_list_mods() -> void:
	_setup()
	var m := _call("list_mods")
	check_eq(m.get("loaded"), ["bn"])
	check_eq(m.get("mods"), [
		{"id": "bn", "name": "Core", "path": "data/json", "core": true, "loaded": 0},
		{"id": "extra", "name": "Extra", "path": "data/mods/extra", "dependencies": ["bn"]},
	])
	check(not m.has("load_errors"), "no load errors: %s" % [m.get("load_errors")])
	var with_mod := McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(["extra"]), _ws))
	check_eq(with_mod.call_tool("list_mods", {}).get("loaded"), ["bn", "extra"])
	var missing := McpTools.new(McpTools.load_session.bind(_root.path_join("nowhere"), PackedStringArray(), _ws))
	var failed: Variant = missing.call_tool("search_maps", {})
	check(failed is McpTools.Failure and failed.message.contains("no BN checkout"), "no BN")
	var inside := McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(), _root.path_join("ws")))
	check(str(inside.call_tool("list_mods", {}).get("load_errors")).contains("workspace unusable"), "workspace in BN")
	check(inside.call_tool("sync_status", {}).get("note", "").contains("nothing can be saved"), "sync_status says so")
	_cleanup()


func test_sync_status() -> void:
	_setup()
	check_eq(_call("sync_status"), {"workspace": _ws, "files": [], "unsaved": []})
	_format_in_place(_root.path_join(HOUSE))
	_call("get_map", {"id": "house"})
	var doc := _tools.session.docs[0]
	doc.paint([Vector2i(3, 3)], "x")
	check_eq(_call("sync_status").get("unsaved"), [HOUSE])
	check_eq(_tools.session.save(HOUSE), "", "save")
	var s := _call("sync_status")
	check_eq(s.get("unsaved"), [])
	check_eq(s.get("files"), [{"file": HOUSE, "state": "modified", "summary": "1 changed",
		"changes": ["changed mapgen house"]}])
	check_eq(_call("get_map", {"id": "house"}).rows[3].substr(3, 1), "x", "the open map")
	_cleanup()


const NONE := {"errors": 0, "warnings": 0, "notes": 0}


## Stage 9c: the paint tools, symbols, undo/redo.
func test_paint_tools() -> void:
	_setup()
	var house := {"id": "house"}
	check_eq(_call("paint_cells", house.merged({"key": "x", "cells": [[3, 3], [4, 3], [3, 3]]})),
			{"changed": 2, "keys": {"x": "t_dirt (map)"}, "undo": "Paint 'x'", "problems": NONE, "dirty": true},
			"a cell listed twice counts once")
	check_eq(_call("get_map", house).rows[3], "#..xx" + ".".repeat(18) + "#")
	var outside := _call("paint_cells", house.merged({"key": "#", "cells": [[30, 1], [1, 1]]}))
	check_eq(outside.get("changed"), 1)
	check(str(outside.get("outside")).contains("1 cell(s) outside the 24x24 map"), str(outside))
	check_eq(_call("paint_rect", house.merged({"key": "h", "x": 3, "y": 6, "x2": 1, "y2": 5})).get("changed"), 6,
			"corners in any order")
	check_eq(_call("paint_rect", house.merged({"key": "h", "x": 1, "y": 8, "x2": 4, "y2": 10, "filled": false}))
			.get("changed"), 10, "outline")
	check_eq(_call("paint_line", house.merged({"key": "x", "x": 1, "y": 12, "x2": 4, "y2": 12})).get("undo"), "Line 'x'")
	var filled := _call("fill", house.merged({"key": "x", "x": 2, "y": 5}))
	check_eq([filled.get("changed"), filled.get("undo")], [6, "Fill 'x'"], "the 3x2 'h' block")
	var rows: Array = _call("get_map", house).rows
	check_eq([rows[5].substr(1, 4), rows[9].substr(1, 4), rows[12].substr(1, 4)], ["xxx.", "h..h", "xxxx"])
	_fails("paint_cells", house.merged({"key": "Z", "cells": [[1, 1]]}), "'Z' isn't defined in house")
	_fails("paint_cells", house.merged({"key": "ab", "cells": [[1, 1]]}), "one character wide")
	_fails("paint_cells", house.merged({"key": "x", "cells": [[1]]}), "Each cell is [x, y]")
	_fails("fill", house.merged({"key": "x", "x": 24, "y": 0}), "outside the 24x24 map")
	_fails("paint_cells", {"key": "x", "cells": []}, "Pass \"id\"")

	# paint_rows: text over the rows, skip leaving cells alone, ' ' painted.
	var laid := _call("paint_rows", house.merged({"x": 5, "y": 17, "rows": ["x_x", "_x_"], "skip": "_"}))
	check_eq([laid.get("changed"), laid.get("undo")], [3, "Paint rows"])
	check_eq(_call("paint_rows", house.merged({"x": 5, "y": 20, "rows": ["x x"]})).get("changed"), 3)
	_fails("paint_rows", house.merged({"y": 19, "rows": ["xQ"]}), "Not defined in house: 'Q'")
	_fails("paint_rows", house.merged({"rows": ["x"], "skip": "ab"}), "skip is one character")
	rows = _call("get_map", house).rows
	check_eq([rows[17].substr(5, 3), rows[18].substr(5, 3), rows[19], rows[20].substr(5, 3)],
			["x.x", ".x.", "#" + ".".repeat(22) + "#", "x x"], "nothing painted by the refused call")

	# Symbols.
	check_eq(_call("add_symbol", house.merged({"key": "Z", "terrain": "t_dirt"})).get("symbol"),
			{"Z": {"terrain": {"value": "t_dirt", "from": "map"}}})
	_fails("add_symbol", house.merged({"key": "Z", "terrain": "t_dirt"}), "already defined")
	_fails("add_symbol", house.merged({"key": "h", "furniture": "f_chair"}), "already defined by palette pal")
	_fails("add_symbol", house.merged({"key": "Y", "terrain": "t_nope"}), "Unknown terrain")
	check_eq(_call("add_symbol", house.merged({"terrain": "t_grass"})).get("symbol"),
			{",": {"terrain": {"value": "t_grass", "from": "map"}}}, "no key: the terrain's own symbol")
	check_eq(_call("add_symbol", house.merged({"terrain": "t_grass"})).get("symbol", {}).keys(), ["a"],
			"else the first free one")
	_call("undo", house)
	_call("undo", house)
	check_eq(_call("paint_cells", house.merged({"key": "Z", "cells": [[2, 21]]})).get("changed"), 1)
	var removed := _call("remove_symbol", house.merged({"key": "Z"}))
	check_eq([removed.get("symbol"), removed.get("cells_using_it"), removed.problems.errors], [{"Z": null}, 1, 1])
	_fails("remove_symbol", house.merged({"key": "h"}), "isn't in the map's own terrain/furniture")

	# Undo / redo.
	var undone := _call("undo", house)
	check_eq([undone.get("undone"), undone.get("redo"), undone.problems], ["Remove 'Z' from the map",
		"Remove 'Z' from the map", NONE])
	check_eq(_call("redo", house).get("redone"), "Remove 'Z' from the map")
	_fails("redo", house, "Nothing to redo")
	for i in 20:
		if not _tools.session.docs[0].can_undo():
			break
		_call("undo", house)
	_fails("undo", house, "Nothing to undo")
	check_eq(_call("get_map", house).rows[3], "#" + ".".repeat(22) + "#", "all undone")
	check_eq(_call("get_map", house).get("dirty"), false)
	_cleanup()


## Stage 9c: saving to the workspace.
func test_save_tool() -> void:
	_setup()
	_format_in_place(_root.path_join(HOUSE))
	check_eq(_call("save"), {"saved": [], "note": "Nothing to save."})
	_call("paint_cells", {"id": "house", "key": "x", "cells": [[3, 3]]})
	check_eq(_call("sync_status").get("unsaved"), [HOUSE])
	_fails("save", {"file": "data/json/nope.json"}, "isn't open")
	check_eq(_call("save", {"file": PALETTES}), {"saved": [], "note": PALETTES + " has no unsaved edits."},
			"read for its palettes, not edited")
	var saved := _call("save")
	check_eq(saved.get("saved"), [{"file": HOUSE, "state": "modified", "summary": "1 changed",
		"changes": ["changed mapgen house"]}])
	check_eq(saved.get("workspace"), _ws)
	check(not FileAccess.file_exists(_ws.path_join(PALETTES)), "only the edited file")
	var sync := WorkspaceSync.new(Workspace.open(_ws, _root))
	check_eq(sync.status(HOUSE).unchanged, 2, "the other two objects byte-identical")
	check_eq(Workspace.open(_ws, _root).files[HOUSE].get("base_sha256"), FileAccess.get_sha256(_root.path_join(HOUSE)))
	var got := BnJson.parse(FileAccess.get_file_as_string(_ws.path_join(HOUSE)))
	check(got.ok() and got.value[0].object.rows[3] == "#..x" + ".".repeat(19) + "#", "the painted cell saved")
	check_eq(got.value[0].object.place_loot[0].chance, 50, "ints stay ints")
	check_eq(_call("get_map", {"id": "house"}).get("dirty"), false)
	# Undone and saved again: the file is BN's again.
	_call("undo", {"id": "house"})
	check_eq(_call("save", {"file": HOUSE}).saved[0].state, "same as BN")
	_cleanup()


## Stage 9c: two processes on one workspace (the editor and the server).
func test_save_guards() -> void:
	_setup()
	var house := {"id": "house"}
	var ws_house := _ws.path_join(HOUSE)
	_call("paint_cells", house.merged({"key": "x", "cells": [[3, 3]]}))
	check_eq(_call("save").get("saved", []).size(), 1)
	# The editor saves the workspace copy after this process read it.
	_call("paint_cells", house.merged({"key": "x", "cells": [[4, 4]]}))
	_write(ws_house, FileAccess.get_file_as_string(ws_house).replace("#..x", "#..h"))
	_fails("save", {}, HOUSE + " changed on disk since it was read")
	check(str(_call("get_map", house).get("changed_on_disk")).contains("changed on disk"), "get_map says so")
	check_eq(_call("sync_status").get("changed_on_disk"), [HOUSE])
	_fails("reload", {}, "Unsaved edits in " + HOUSE)
	check_eq(_call("reload", {"discard": true}).get("discarded"), [HOUSE])
	var m := _call("get_map", house)
	check_eq([m.rows[3].substr(3, 1), m.get("changed_on_disk")], ["h", null], "reloaded: the editor's save")

	# The manifest: an entry the other process added since stays.
	var other := Workspace.open(_ws, _root)
	check_eq(other.set_entry("data/json/other.json", {"new": true}), "")
	_call("paint_cells", house.merged({"key": "x", "cells": [[5, 5]]}))
	check_eq(_call("save").get("saved", []).size(), 1)
	var files := Workspace.open(_ws, _root).files
	check(files.has("data/json/other.json") and files.has(HOUSE), "both entries: %s" % [files])
	# ... and one it removed stays removed.
	check_eq(other.set_entry("data/json/other.json", null), "")
	_call("paint_cells", house.merged({"key": "x", "cells": [[6, 6]]}))
	_call("save")
	check(not Workspace.open(_ws, _root).files.has("data/json/other.json"), "removed")

	# Read from BN, and a workspace copy appears.
	_call("paint_cells", {"id": "broken", "key": "x", "cells": [[5, 5]]})
	_write(_ws.path_join("data/json/mapgen/broken.json"), "[]\n")
	_fails("save", {"file": "data/json/mapgen/broken.json"}, "changed on disk")
	# A new file, and another process writes one at that path first.
	_call("create_mapgen", {"file": "data/json/mapgen/new.json", "om_terrain": "n_1"})
	_write(_ws.path_join("data/json/mapgen/new.json"), "[]\n")
	_fails("save", {"file": "data/json/mapgen/new.json"}, "changed on disk")
	check_eq(FileAccess.get_file_as_string(_ws.path_join("data/json/mapgen/new.json")), "[]\n", "not overwritten")
	_cleanup()


## Stage 9d: placements, palettes and symbol mappings.
func test_fields_and_batches() -> void:
	_setup()
	var house := {"id": "house"}
	# set_map_fields: one undo step for all fields; null removes.
	var set := _call("set_map_fields", house.merged({"fill_ter": "t_dirt", "rotation": [0, 3]}))
	check_eq([set.get("fields"), set.get("undo")], [{"fill_ter": "t_dirt", "rotation": [0, 3]},
		"Set fill_ter, rotation"])
	check_eq(_call("get_map", house).get("fill_ter"), "t_dirt")
	check_eq(_call("set_map_fields", house.merged({"rotation": null})).get("fields"), {"rotation": null})
	check_eq(_tools.session.open(_tools.session.index.mapgens_for("house")[0]).object().has("rotation"),
		false)
	_call("undo", house)
	_call("undo", house)
	check_eq(_call("get_map", house).get("fill_ter"), "t_grass", "undone")
	_fails("set_map_fields", house.merged({"fill_ter": "t_nope"}), "Unknown terrain")
	_fails("set_map_fields", house.merged({"fill_ter": {"distribution": [["t_dirt", 1]]}}), "BN ignores")
	check_eq(_call("set_map_fields", house.merged({"fill_ter": ""})).get("fields"), {"fill_ter": null})
	_call("undo", house)
	_fails("set_map_fields", house.merged({"rotation": "x"}), "rotation is an int")
	_fails("set_map_fields", house.merged({"predecessor_mapgen": "nope"}), "overmap_terrain id")
	_fails("set_map_fields", house, "Pass at least one")

	# add_symbol with symbols: all or nothing, one undo step.
	var syms := _call("add_symbol", house.merged({"symbols": [{"key": "A", "terrain": "t_dirt"},
		{"key": "B", "furniture": "f_chair"}]}))
	check_eq(syms.get("symbols", {}).keys(), ["A", "B"])
	check_eq(syms.get("undo"), "New symbols")
	_fails("add_symbol", house.merged({"symbols": [{"key": "C", "terrain": "t_dirt"},
		{"key": "h", "furniture": "f_chair"}]}), "symbols[1]")
	var doc := _tools.session.open(_tools.session.index.mapgens_for("house")[0])
	check_eq([doc.own_keys().has("A"), doc.own_keys().has("C")], [true, false], "the refused batch added nothing")
	_fails("add_symbol", house.merged({"symbols": [{"key": "D", "tree": "t_dirt"}]}), "Unknown argument")
	_fails("add_symbol", house.merged({"key": "E", "symbols": []}), "not both")
	_call("undo", house)
	check_eq([doc.own_keys().has("A"), doc.own_keys().has("B")], [false, false], "one undo takes both back")

	# add_placement with entries: all or nothing.
	var placed := _call("add_placement", house.merged({"entries": [
		{"member": "place_monster", "entry": {"monster": "mon_zombie", "x": 2, "y": 2}},
		{"member": "place_items", "entry": {"item": "stuff", "x": [1, 3], "y": 4, "chance": 50}}]}))
	check_eq(placed.get("placements", []).map(func(p: Dictionary) -> Array: return [p.member, p.index]),
		[["place_monster", 0], ["place_items", 0]])
	_fails("add_placement", house.merged({"entries": [
		{"member": "place_monster", "entry": {"monster": "mon_zombie", "x": 3, "y": 3}},
		{"member": "nope", "entry": {}}]}), "entries[1]")
	_fails("add_placement", house.merged({"entries": [
		{"member": "place_monster", "entry": {"monster": "mon_zombie", "x": 3, "y": 3}},
		{"member": "place_monster", "entry": {"monster": "mon_zombie", "x": [20, 30], "y": 3}}]}), "entries[1]")
	var monsters: Array = _call("get_map", house).placements.filter(func(p: Dictionary) -> bool:
		return p.member == "place_monster")
	check_eq(monsters.size(), 1, "refused batches added nothing")
	_fails("add_placement", house.merged({"member": "place_monster"}), "both member and entry")

	# Paint answers say what each key means, and where from.
	var painted := _call("paint_rows", house.merged({"x": 1, "y": 1, "rows": ["hx"]}))
	check_eq(painted.get("keys"), {"h": "no terrain: fill_ter t_grass; f_chair (palette pal); items (palette pal)",
		"x": "t_dirt (map)"})
	_cleanup()


func test_placement_tools() -> void:
	_setup()
	var house := {"id": "house"}
	var loot := house.merged({"member": "place_loot"})
	_fails("add_placement", loot.merged({"entry": {"group": "stuff", "x": [20, 30], "y": 1}}), "place_loot")
	_fails("add_placement", loot.merged({"entry": {"group": "stuff", "x": 30, "y": 1}}), "place_loot")
	_fails("add_placement", loot.merged({"entry": {"group": "stuff"}}), "x and y")
	var added := _call("add_placement", loot.merged({"entry": {"group": "nope", "x": 2, "y": [2, 3]}}))
	var p: Dictionary = added.get("placement", {})
	check_eq([p.get("index"), p.get("entry")], [1, {"group": "nope", "x": 2, "y": [2, 3]}])
	check_eq(p.get("findings", [{}])[0].get("code"), "UNKNOWN_ID", "an unknown id is reported, not refused")
	check_eq([added.problems.errors, added.undo], [1, "Add place_loot"])

	var moved := _call("update_placement", loot.merged({"index": 0, "move_to": [10, 10], "fields": {"chance": null}}))
	check_eq(moved.get("placement", {}).get("entry"), {"group": "stuff", "x": 10, "y": [10, 12]}, "range kept")
	check_eq(moved.get("undo"), "Edit place_loot #1", "one undo step")
	_fails("update_placement", loot.merged({"index": 0, "move_to": [23, 22]}), "place_loot")
	_fails("update_placement", loot.merged({"index": 5, "fields": {"chance": 1}}), "no place_loot entry #5")
	_fails("update_placement", loot.merged({"index": 0, "move_to": [1, 1], "fields": {"x": 1}}), "not both")
	_fails("update_placement", loot.merged({"index": 0}), "Pass fields")
	check_eq(_call("update_placement", loot.merged({"index": 0, "fields": {"chance": 5}})).placement.entry.chance, 5)

	var removed := _call("remove_placement", loot.merged({"index": 0}))
	check_eq(removed.get("removed"), {"group": "stuff", "x": 10, "y": [10, 12], "chance": 5})
	check(str(removed.get("note")).contains("1 later place_loot"), str(removed.get("note")))
	var placements: Array = _call("get_map", house).placements
	check_eq(placements[0].entry, {"group": "nope", "x": 2, "y": [2, 3]}, "moved down to #0")

	_fails("set_map_palettes", house.merged({"palettes": ["nope"]}), "Unknown palette \"nope\"")
	var none := _call("set_map_palettes", house.merged({"palettes": []}))
	check(none.problems.errors > 1, "'#', '.' and 'h' undefined now")
	check(not _call("get_map", house).has("palettes"), "member removed")
	check_eq(_call("set_map_palettes", house.merged({"palettes": ["pal"]})).get("palettes"), ["pal"])

	var mapped := _call("set_symbol_mapping", house.merged({"key": "x", "kind": "items",
		"value": {"item": "stuff", "chance": 10}}))
	check_eq(mapped.get("symbol"), {"x": {"terrain": {"value": "t_dirt", "from": "map"},
		"items": [{"value": {"item": "stuff", "chance": 10}, "from": "map"}]}})
	check_eq(_call("get_map", house).legend.x.items[0].value.chance, 10)
	_fails("set_symbol_mapping", house.merged({"key": "x", "kind": "items", "value": "stuff"}), "an object or a list")
	_fails("set_symbol_mapping", house.merged({"key": "x", "kind": "traps", "value": null}), "must be one of")
	check_eq(_call("set_symbol_mapping", house.merged({"key": "x", "kind": "items", "value": null})).symbol,
			{"x": {"terrain": {"value": "t_dirt", "from": "map"}}})
	_cleanup()


## Stage 9d: new maps and chunks, saved and read back, or discarded.
func test_create_mapgen() -> void:
	_setup()
	_format_in_place(_root.path_join(HOUSE))
	var rel := "data/json/mapgen/new.json"
	var m := _call("create_mapgen", {"file": rel, "om_terrain": [["n_1", "n_2"]], "palettes": ["pal"]})
	check_eq([m.get("ids"), m.get("size"), m.get("palettes"), m.get("fill_ter"), m.get("dirty")],
			[["n_1", "n_2"], [48, 24], ["pal"], "t_grass", true])
	check_eq(m.get("overmap_terrain_added"), ["n_1", "n_2"])
	check_eq(m.get("problems"), NONE)
	check_eq(_call("search_maps", {"query": "n_2"}).get("total"), 1, "in the index at once")
	_call("paint_rows", {"id": "n_2", "x": 24, "rows": ["#..#"]})
	var chunk := _call("create_mapgen", {"file": HOUSE, "nested_id": "chunk_b", "mapgensize": [3, 3]})
	check_eq([chunk.get("index"), chunk.get("size"), chunk.get("rows")], [3, [3, 3], ["   ", "   ", "   "]])
	check(not chunk.has("overmap_terrain_added"), "a chunk needs none")
	_fails("create_mapgen", {"file": rel}, "Pass om_terrain")
	_fails("create_mapgen", {"file": rel, "om_terrain": "a", "nested_id": "b"}, "Pass om_terrain")
	_fails("create_mapgen", {"file": rel, "om_terrain": ["a", "b"]}, "a grid")
	_fails("create_mapgen", {"file": "../x.json", "om_terrain": "a"}, "relative .json path")
	_fails("create_mapgen", {"file": "data/elsewhere/x.json", "om_terrain": "a"}, "isn't inside a loaded mod")
	_fails("create_mapgen", {"file": rel, "om_terrain": "a", "palettes": ["nope"]}, "Unknown palette")
	_fails("create_mapgen", {"file": rel, "nested_id": "c"}, "needs mapgensize")
	_fails("create_mapgen", {"file": rel, "nested_id": "c", "mapgensize": [3, 3], "fill_ter": "t_dirt"}, "no fill_ter")
	_fails("create_mapgen", {"file": rel, "nested_id": "c", "mapgensize": [30, 3]}, "1-24")

	# Discarded: gone from the index again.
	_call("create_mapgen", {"file": "data/json/mapgen/other.json", "nested_id": "chunk_c", "mapgensize": [2, 2]})
	check_eq(_call("search_maps", {"query": "chunk_c"}).get("total"), 1)
	check_eq(_call("discard", {"file": "data/json/mapgen/other.json"}), {"file": "data/json/mapgen/other.json",
		"discarded_edits": true, "closed": ["chunk_c"]})
	check_eq(_call("search_maps", {"query": "chunk_c"}).get("total"), 0)
	_fails("discard", {"file": "data/json/mapgen/other.json"}, "isn't open")

	var saved: Array = _call("save").get("saved", [])
	var by_file := {}
	for e: Dictionary in saved:
		by_file[e.file] = e
	check_eq(by_file.get(HOUSE, {}).get("changes"), ["added mapgen chunk_b"])
	check_eq(WorkspaceSync.new(Workspace.open(_ws, _root)).status(HOUSE).unchanged, 3, "the others byte-identical")
	check_eq(by_file.get(rel, {}).get("state"), "new")
	check_eq(by_file.get(rel, {}).get("changes"), ["added mapgen n_1, n_2", "added overmap_terrain n_1, n_2"])
	# Read back from the workspace, as a fresh session would.
	check_eq(_call("reload").get("discarded"), null)
	var back := _call("get_map", {"id": "n_1"})
	check_eq([back.get("file"), back.get("in_workspace"), back.get("size"), back.get("palettes")],
			[rel, true, [48, 24], ["pal"]])
	check_eq(back.rows[0].substr(24, 4), "#..#", "n_2's tile holds the painted row")
	check_eq(back.get("problems"), NONE)
	check_eq(_call("get_map", {"id": "chunk_b"}).get("index"), 3)
	check_eq(_call("lookup_id", {"kind": "oter_type", "query": "n_2"}).get("known"), true)
	_cleanup()


## Rewrites [param path] as json_formatter would, as BN's files are, so a
## save only differs where edited.
static func _format_in_place(path: String) -> void:
	var clean := JsonFormatter.format(BnJson.stringify(BnJson.parse(FileAccess.get_file_as_string(path)).value)).text
	_write(path, clean)


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The real process: requests piped in, one reply per request on stdout,
## nothing else there, and it exits when stdin closes.
func test_stdio() -> void:
	_check_stdio('-s tools/mcp_server.gd -- ')


## The same through the main scene, as an exported build runs it: --mcp
## (AppLoop), with the engine's header off and no "--".
func test_stdio_main_loop() -> void:
	_check_stdio('--mcp ')


func _check_stdio(how: String) -> void:
	_setup()
	var requests := PackedStringArray([
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},' \
			+ '"clientInfo":{"name":"test","version":"1"}}}',
		'{"jsonrpc":"2.0","method":"notifications/initialized"}',
		'{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
		'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_maps","arguments":{"query":"chunk"}}}',
		'{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_map","arguments":{"id":"house"}}}',
	])
	DirAccess.make_dir_recursive_absolute(_ws)
	var input := _ws.path_join("requests.txt")
	var f := FileAccess.open(input, FileAccess.WRITE)
	f.store_string("\n".join(requests) + "\n")
	f.close()
	# OS.execute joins its arguments into one shell command, which mangles a
	# quoted "sh -c" script; a script file takes plain paths.
	var runner := _ws.path_join("run.sh")
	f = FileAccess.open(runner, FileAccess.WRITE)
	f.store_string('exec "$1" --headless --path "$2" ' + how \
			+ '--bn "$3" --workspace "$4" --mods bn < "$5" 2>/dev/null\n')
	f.close()
	var output := []
	var code := OS.execute("sh", [runner, OS.get_executable_path(), ProjectSettings.globalize_path("res://"),
		_root, _ws.path_join("ws"), input], output)
	check_eq(code, 0, "exit code")
	var lines := (output[0] as String).strip_edges(false, true).split("\n") if output.size() else PackedStringArray()
	check_eq(lines.size(), 4, "one line per request: %s" % [lines])
	var replies := []
	for line in lines:
		var parsed := BnJson.parse(line)
		check(parsed.ok(), "not JSON: %s" % line.left(200))
		replies.append(parsed.value if parsed.ok() else {})
	if replies.size() != 4:
		_cleanup()
		return
	check_eq(replies.map(func(r: Dictionary) -> Variant: return r.get("id")), [1, 2, 3, 4])
	check_eq(replies[0].result.serverInfo.name, "bn-map-editor")
	check_eq(replies[1].result.tools.size(), 36)
	var found: Dictionary = BnJson.parse(replies[2].result.content[0].text).value
	check_eq(found.maps[0].ids, ["chunk_a"])
	var m: Dictionary = BnJson.parse(replies[3].result.content[0].text).value
	check_eq(m.ascii[0], "┌──────────────────────┐", "UTF-8 through the pipe")
	check_eq(m.legend.h.items[0].value.chance, 30)
	check(not DirAccess.dir_exists_absolute(_ws.path_join("ws")), "reading writes nothing")
	_cleanup()

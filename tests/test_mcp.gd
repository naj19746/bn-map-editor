extends "res://tests/support/test_case.gd"
## Stage 9a/9b: the MCP server (McpServer, McpTools) against a small fake BN
## checkout. Handlers are called directly; test_stdio runs the real -s
## process with requests piped into it.

const TempTree := preload("res://tests/support/temp_tree.gd")
const HOUSE := "data/json/mapgen/house.json"

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
		"list_mods", "sync_status"])
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
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		_cleanup()
		return
	# Formatter-clean, as BN's files are, so a save only differs where edited.
	var path := _root.path_join(HOUSE)
	var clean := JsonFormatter.new().format(BnJson.stringify(BnJson.parse(FileAccess.get_file_as_string(path)).value)).text
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(clean)
	f.close()
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


## The real process: requests piped in, one reply per request on stdout,
## nothing else there, and it exits when stdin closes.
func test_stdio() -> void:
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
	f.store_string('exec "$1" --headless --no-header --path "$2" -s tools/mcp_server.gd -- ' \
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
	check_eq(replies[1].result.tools.size(), 8)
	var found: Dictionary = BnJson.parse(replies[2].result.content[0].text).value
	check_eq(found.maps[0].ids, ["chunk_a"])
	var m: Dictionary = BnJson.parse(replies[3].result.content[0].text).value
	check_eq(m.ascii[0], "┌──────────────────────┐", "UTF-8 through the pipe")
	check_eq(m.legend.h.items[0].value.chance, 30)
	check(not DirAccess.dir_exists_absolute(_ws.path_join("ws")), "reading writes nothing")
	_cleanup()

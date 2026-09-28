class_name McpServer
extends RefCounted
## The MCP protocol over stdio: JSON-RPC 2.0, one message per line.
##
## handle_line() takes one request or notification and returns the reply
## line ("" for a notification). Tool calls go to [member tools] (McpTools).
## Messages are read with BnJson, so an int id stays an int, and written with
## BnJson.stringify, which never puts a raw newline inside a message.
##
## run() reads stdin until it closes, one byte per read:
## OS.read_buffer_from_stdin is a blocking fread that returns only when the
## whole size asked for has arrived (or at EOF), so a larger read would wait
## forever on a client that keeps stdin open. Lines are cut from those bytes,
## so a UTF-8 character is decoded whole. (OS.read_string_from_stdin strips
## the newline, so an empty line would look like EOF.)

const PROTOCOL_VERSIONS := ["2025-06-18", "2025-03-26", "2024-11-05"]
const SERVER_NAME := "bn-map-editor"
const SERVER_VERSION := "0.9"

const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603

const INSTRUCTIONS := "Browse, validate and edit Cataclysm-BN JSON mapgen through the BN Map Editor. " \
		+ "Start with search_maps, then get_map. Coordinates are x (column) and y (row) from the " \
		+ "top-left cell, 0-based; placements are named by member and 0-based index (finding texts count " \
		+ "from 1: place_items #1 is index 0). Edits (paint_*, add_symbol, add_placement, ...) stay in memory, one undo " \
		+ "step per call, until save writes the file to the workspace; nothing is ever written into the BN " \
		+ "checkout (a person pushes workspace files into BN from the editor). A building's floors are " \
		+ "separate om_terrain maps stacked by a city_building / overmap_special: get_map's levels and " \
		+ "get_building show them, create_mapgen's level adds one."

var tools: McpTools
## Where replies go; stdout by default. Tests collect them instead.
var output := func(line: String) -> void: printraw(line + "\n")


func _init(p_tools: McpTools) -> void:
	tools = p_tools


## Reads requests from stdin and answers them until stdin closes.
func run() -> void:
	var buffer := PackedByteArray()
	while true:
		var byte := OS.read_buffer_from_stdin(1)
		if byte.is_empty():
			break
		if byte[0] == 10:
			_answer(buffer.get_string_from_utf8())
			buffer.clear()
		else:
			buffer.append(byte[0])
	if not buffer.is_empty():
		_answer(buffer.get_string_from_utf8())


func _answer(line: String) -> void:
	var reply := handle_line(line)
	if reply:
		output.call(reply)


## The reply to one message, or "" when none is due (a notification, a
## blank line).
func handle_line(line: String) -> String:
	if line.strip_edges().is_empty():
		return ""
	var parsed := BnJson.parse(line)
	if not parsed.ok():
		return _error(null, PARSE_ERROR, "Parse error: " + parsed.error)
	var msg: Variant = parsed.value
	if msg is Array:
		# Batches were dropped from the protocol in 2025-06-18.
		return _error(null, INVALID_REQUEST, "Batches aren't supported")
	if not msg is Dictionary or msg.get("jsonrpc") != "2.0":
		return _error(null, INVALID_REQUEST, "Not a JSON-RPC 2.0 message")
	if not msg.has("method"):
		# A reply to something we sent; we send no requests.
		return ""
	var is_request: bool = msg.has("id")
	var id: Variant = msg.get("id")
	if not msg.method is String or (is_request and not (id is String or id is int)):
		return _error(id if is_request else null, INVALID_REQUEST, "Bad method or id")
	var params: Variant = msg.get("params", {})
	if not params is Dictionary:
		return _error(id, INVALID_PARAMS, "params must be an object") if is_request else ""
	var result: Variant = _dispatch(msg.method, params)
	if not is_request:
		return ""
	if result is Array:
		return _error(id, result[0], result[1])
	return BnJson.stringify({"jsonrpc": "2.0", "id": id, "result": result})


## The result of [param method], or [code, message] for an error.
func _dispatch(method: String, params: Dictionary) -> Variant:
	match method:
		"initialize":
			var asked: Variant = params.get("protocolVersion")
			return {
				"protocolVersion": asked if PROTOCOL_VERSIONS.has(asked) else PROTOCOL_VERSIONS[0],
				"capabilities": {"tools": {}},
				"serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
				"instructions": INSTRUCTIONS,
			}
		"ping":
			return {}
		"tools/list":
			return {"tools": tools.list()}
		"tools/call":
			var name: Variant = params.get("name")
			var args: Variant = params.get("arguments", {})
			if not name is String or not tools.has(name):
				return [INVALID_PARAMS, "Unknown tool: %s" % str(name)]
			if not args is Dictionary:
				return [INVALID_PARAMS, "arguments must be an object"]
			return _tool_result(tools.call_tool(name, args))
	if method.begins_with("notifications/"):
		return {}
	return [METHOD_NOT_FOUND, "Method not found: " + method]


## A tools/call result: the handler's value as indented JSON text, or its
## error (an McpTools.Failure) with isError set.
static func _tool_result(value: Variant) -> Dictionary:
	if value is McpTools.Failure:
		return {"content": [{"type": "text", "text": value.message}], "isError": true}
	return {"content": [{"type": "text", "text": pretty(value)}], "isError": false}


static func _error(id: Variant, code: int, message: String) -> String:
	return BnJson.stringify({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})


## [param value] as JSON a reader can scan: containers that fit in
## [param width] on one line stay there (a row, a coordinate pair), others
## put one member per line. Values are written by BnJson, so ints stay ints.
static func pretty(value: Variant, indent := "", width := 100) -> String:
	var flat := BnJson.stringify(value)
	if not (value is Dictionary or value is Array) or flat.length() + indent.length() <= width \
			or value.is_empty():
		return flat
	var inner := indent + "  "
	var parts := PackedStringArray()
	if value is Array:
		for v: Variant in value:
			parts.append(inner + pretty(v, inner, width))
		return "[\n%s\n%s]" % [",\n".join(parts), indent]
	for k: Variant in value:
		parts.append("%s%s: %s" % [inner, BnJson.encode_string(str(k)), pretty(value[k], inner, width)])
	return "{\n%s\n%s}" % [",\n".join(parts), indent]

extends "res://tests/support/test_case.gd"
## Stage 9b acceptance on core data: validate_map and validate_palette
## through the MCP handlers find no errors in any core json mapgen or
## palette, as test_validation_bn does directly; and get_map / get_palette
## read real maps.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")


func _tools(ws: String) -> McpTools:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	return McpTools.new(McpTools.load_session.bind(bn, PackedStringArray(), ws))


func test_core_maps_validate() -> void:
	var ws := TempTree.make({})
	var tools := _tools(ws)
	if tools == null:
		return
	var errors := PackedStringArray()
	var maps := 0
	var listed: Dictionary = tools.call_tool("search_maps", {"limit": McpTools.MAX_LIMIT})
	for ref in tools.session.index.mapgens:
		if ref.method != "json":
			continue
		maps += 1
		var got: Variant = tools.call_tool("validate_map", {"file": ref.source.path, "index": ref.source.index,
			"include_palettes": false})
		if got is McpTools.Failure:
			errors.append("%s #%d: %s" % [ref.source.path, ref.source.index, got.message])
		elif got.errors > 0:
			for f: Dictionary in got.findings:
				if f.severity == "error":
					errors.append("%s #%d %s: %s" % [ref.source.path, ref.source.index, ref.title(), f.text])
	# Palettes once each, rather than again for every map using them.
	for id: String in tools.session.index.palettes:
		var got: Variant = tools.call_tool("validate_palette", {"id": id, "include_includes": false})
		if got is McpTools.Failure or got.errors > 0:
			errors.append("palette %s: %s" % [id, got.message if got is McpTools.Failure else got.findings[0].text])
	check(maps > 4000, "core has thousands of json maps (%d)" % maps)
	check_eq(listed.get("total"), tools.session.index.mapgens.size(), "search_maps lists every entry")
	check_eq(errors.slice(0, 20), PackedStringArray(), "%d errors" % errors.size())
	check_eq(tools.session.docs.size(), 0, "validating opens no map")
	TempTree.remove(ws)


func test_core_reads() -> void:
	var ws := TempTree.make({})
	var tools := _tools(ws)
	if tools == null:
		return
	var m: Variant = tools.call_tool("get_map", {"id": "house_01"})
	if check(m is Dictionary, "get_map house_01: %s" % [m.message if m is McpTools.Failure else ""]):
		check_eq(m.size, [24, 24])
		check_eq(m.ascii.size(), 24)
		check_eq(m.rows.size(), 24)
		check_eq(m.problems.errors, 0)
		for key: String in m.legend:
			check(not m.legend[key].has("undefined"), "house_01 '%s' is defined" % key)
		# Palette values as written: a chance of 30 stays an int.
		check_eq(m.legend.p.items[0].value.chance, 30)
	var p: Variant = tools.call_tool("get_palette", {"id": "standard_domestic_palette"})
	if check(p is Dictionary, "get_palette"):
		check(p.keys.size() > 20, "keys")
		check_eq(p.json.id, "standard_domestic_palette")
	var v: Variant = tools.call_tool("validate_palette", {"id": "standard_domestic_palette"})
	check(v is Dictionary and v.errors == 0, "the palette validates")
	var lua: Variant = null
	for ref in tools.session.index.mapgens:
		if ref.method != "json":
			lua = tools.call_tool("get_map", {"file": ref.source.path, "index": ref.source.index})
			break
	if lua != null:
		check(lua is McpTools.Failure and lua.message.contains("only json mapgen"), "a lua map is refused")
	check(not DirAccess.dir_exists_absolute(ws) or DirAccess.get_files_at(ws).is_empty(), "nothing written")
	TempTree.remove(ws)

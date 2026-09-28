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
	# Stage 10e: a floor's building and its neighbours above and below.
	var floor1: Variant = tools.call_tool("get_map", {"id": "2Story02_1"})
	if check(floor1 is Dictionary, "get_map 2Story02_1"):
		var place: Dictionary = {}
		for e: Dictionary in floor1.levels:
			if e.building == "2Story02":
				place = e
		check_eq(place.get("origin"), [0, 0, 0])
		check_eq(place.get("above", {}).get("tiles", [{}])[0].get("om_terrain"), "2Story02_2")
		check_eq(place.get("below", {}).get("tiles", [{}])[0].get("om_terrain"), "2Story02_basement")
	var b: Variant = tools.call_tool("get_building", {"id": "2Story02"})
	if check(b is Dictionary, "get_building 2Story02"):
		check_eq(b.levels.size(), 4)
		check_eq(b.levels[3].tiles[0].om_terrain, "2Story02_roof")
	check(not DirAccess.dir_exists_absolute(ws) or DirAccess.get_files_at(ws).is_empty(), "nothing written")
	TempTree.remove(ws)


## Stage 9c/9d on core data: edit house_01 through the tools (paint rows, a
## new symbol, a placement), save into a temp workspace, and every other
## object of its file stays byte-identical; BN is untouched.
func test_core_edit_and_save() -> void:
	var ws := TempTree.make({})
	var tools := _tools(ws)
	if tools == null:
		return
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		TempTree.remove(ws)
		return
	var m: Dictionary = tools.call_tool("get_map", {"id": "house_01"})
	var rel: String = m.file
	var bn_file := tools.session.index.bn_path.path_join(rel)
	var bn_sha := FileAccess.get_sha256(bn_file)
	var key: String = m.legend.keys()[0]
	var r: Variant = tools.call_tool("paint_rows", {"id": "house_01", "x": 1, "y": 1, "rows": [key.repeat(3)]})
	check(r is Dictionary, "paint_rows: %s" % [r.message if r is McpTools.Failure else ""])
	r = tools.call_tool("add_symbol", {"id": "house_01", "terrain": "t_dirt", "furniture": "f_chair"})
	if check(r is Dictionary, "add_symbol: %s" % [r.message if r is McpTools.Failure else ""]):
		var new_key: String = r.symbol.keys()[0]
		r = tools.call_tool("paint_cells", {"id": "house_01", "key": new_key, "cells": [[2, 2]]})
		check(r is Dictionary and r.changed == 1, "paint the new symbol: %s" % [r])
	r = tools.call_tool("add_placement", {"id": "house_01", "member": "place_loot",
		"entry": {"group": "trash", "x": [2, 4], "y": 2, "chance": 30}})
	check(r is Dictionary and r.problems.errors == 0, "add_placement: %s" % [r.message if r is McpTools.Failure else r])
	var saved: Variant = tools.call_tool("save", {})
	if check(saved is Dictionary, "save: %s" % [saved.message if saved is McpTools.Failure else ""]):
		check_eq(saved.saved[0].changes, ["changed mapgen house_01"])
	var s := WorkspaceSync.new(tools.session.workspace).status(rel)
	var objects: Array = BnJson.parse(FileAccess.get_file_as_string(bn_file)).value
	check_eq(s.unchanged, objects.size() - 1, "every other object byte-identical")
	check_eq(FileAccess.get_sha256(bn_file), bn_sha, "BN untouched")
	var back: Variant = tools.call_tool("validate_map", {"id": "house_01"})
	check(back is Dictionary and back.errors == 0, "still valid: %s" % [back])
	TempTree.remove(ws)


## Stage 9e on core: a dry run on a widely used palette names its users
## and leaves the palette as it was; a real edit, saved, changes only the
## palette's object.
func test_core_palette_edit() -> void:
	var ws := TempTree.make({})
	var tools := _tools(ws)
	if tools == null:
		return
	var start := Time.get_ticks_msec()
	var dry: Variant = tools.call_tool("edit_palette_key", {"id": "standard_domestic_palette", "key": "h",
		"furniture": "f_stool", "dry_run": true, "limit": 5})
	var ms := Time.get_ticks_msec() - start
	if check(dry is Dictionary, "dry run: %s" % [dry.message if dry is McpTools.Failure else ""]):
		check(dry.would_change.count > 50, "many houses use its chairs: %d" % dry.would_change.count)
		check_eq(dry.would_change.maps.size(), 5)
		check_eq(dry.key.h.furniture.value, "f_stool")
	check(ms < 20000, "measured in %d ms" % ms)
	var pal: Variant = tools.call_tool("get_palette", {"id": "standard_domestic_palette", "include_json": false})
	check_eq(pal.keys.h.furniture.value, "f_chair", "a dry run edits nothing")
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		TempTree.remove(ws)
		return
	var r: Variant = tools.call_tool("edit_palette_key", {"id": "standard_domestic_palette", "key": "h",
		"furniture": "f_stool"})
	check(r is Dictionary and r.maps_changed.count == dry.would_change.count, "edit: %s" % [r])
	var saved: Variant = tools.call_tool("save", {})
	if check(saved is Dictionary, "save: %s" % [saved.message if saved is McpTools.Failure else ""]):
		check_eq(saved.saved[0].changes, ["changed palette standard_domestic_palette"])
	TempTree.remove(ws)

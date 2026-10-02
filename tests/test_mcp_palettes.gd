extends "res://tests/support/test_case.gd"
## Stage 9e: palette editing through the MCP tools (edit_palette_key,
## set_palette_includes, create_palette, undo/redo with a palette) against
## the fake BN checkout of test_palettes.gd, plus a map placing the chunk.

const TempTree := preload("res://tests/support/temp_tree.gd")

const HOUSE := "data/json/mapgen/house.json"
const PALETTES := "data/json/mapgen_palettes/pal.json"

var _root := ""
var _ws := ""
var _tools: McpTools


static func _rows(fill: String) -> Array:
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 or y == 23 else "#" + fill.repeat(22) + "#")
	return rows


static func _map(id: String, palettes: Array, fill := ".", extra := {}) -> Dictionary:
	var obj := {"fill_ter": "t_grass", "rows": _rows(fill), "palettes": palettes}
	obj.merge(extra)
	return {"type": "mapgen", "method": "json", "om_terrain": id, "object": obj}


func _setup() -> void:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt", "t_rock", "t_console"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
			{"type": "item_group", "id": "junk", "items": [["rock", 10]]},
		],
		PALETTES: [
			{"type": "palette", "id": "pal", "terrain": {"#": "t_wall", ".": "t_floor"},
				"furniture": {"h": "f_chair"}, "items": {"h": {"item": "junk", "chance": 5}}},
			{"type": "palette", "id": "inner", "terrain": {"#": "t_rock"}},
			{"type": "palette", "id": "outer", "palettes": ["inner"], "terrain": {".": "t_dirt"}},
			{"type": "palette", "id": "other", "terrain": {"#": "t_dirt", ".": "t_dirt", "o": "t_dirt"}},
		],
		HOUSE: [
			_map("house", ["pal", "house_pal"]),
			{"type": "palette", "id": "house_pal", "furniture": {"x": "f_table"}},
			_map("house_2", ["house_pal"], "x"),
		],
		"data/json/mapgen/others.json": [
			# Through an include.
			_map("shed", ["outer"]),
			# As the second option of a distribution.
			_map("cabin", [{"distribution": [["other", 1], ["pal", 1]]}]),
			# Overrides '#' itself, so a palette '#' edit doesn't reach it.
			_map("bunker", ["pal"], ".", {"terrain": {"#": "t_rock"}}),
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk",
				"object": {"mapgensize": [2, 2], "rows": ["..", ".."], "palettes": ["pal"]}},
			# No palette: changes only through the chunk it places.
			_map("plain", [], ".", {"terrain": {"#": "t_wall", ".": "t_floor"},
				"place_nested": [{"chunks": ["chunk"], "x": 3, "y": 3}]}),
		],
	}
	for rel: String in files:
		files[rel] = BnJson.stringify(files[rel])
	_root = TempTree.make(files)
	_ws = TempTree.make({})
	_tools = McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(), _ws))


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


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


## The changed maps' ids, as listed.
static func _ids(impact: Variant) -> Array:
	if not impact is Dictionary:
		return []
	return impact.maps.map(func(m: Dictionary) -> String: return m.id)


func _terrain(id: String, key: String) -> Variant:
	var got := _call("get_palette", {"id": id, "include_json": false})
	return got.get("keys", {}).get(key, {}).get("terrain", {}).get("value")


func test_edit_palette_key() -> void:
	_setup()
	# As test_palettes::test_impact: bunker overrides '#', chunk doesn't use
	# it; cabin gets it from its second option.
	var dry := _call("edit_palette_key", {"id": "pal", "key": "#", "terrain": "t_dirt", "dry_run": true})
	check_eq(_ids(dry.get("would_change")), ["cabin", "house"])
	check_eq(dry.would_change.count, 2)
	check_eq(dry.would_change.maps[0], {"id": "cabin", "file": "data/json/mapgen/others.json", "index": 1,
		"symbols": ["#"]})
	check_eq(dry.get("key"), {"#": {"terrain": {"value": "t_dirt", "from": "this palette"}}}, "what it would be")
	check_eq(_terrain("pal", "#"), "t_wall", "a dry run changes nothing")
	check_eq(_call("sync_status").get("unsaved", []), [])

	# '.' reaches the chunk, and plain through it.
	var floor := _call("edit_palette_key", {"id": "pal", "key": ".", "terrain": "t_dirt"})
	check_eq(_ids(floor.get("maps_changed")), ["bunker", "cabin", "chunk", "house", "plain"])
	var plain: Dictionary = floor.maps_changed.maps[4]
	check_eq(plain.get("via_chunk"), "chunk")
	check_eq(floor.get("undo"), "Edit '.'")
	check_eq(floor.get("dirty"), true)
	check_eq(_terrain("pal", "."), "t_dirt")
	check_eq(_call("get_map", {"id": "house"}).legend["."].terrain.value, "t_dirt", "maps see the edit")
	var listed := _call("edit_palette_key", {"id": "pal", "key": "#", "terrain": "t_rock", "limit": 1,
		"dry_run": true})
	check_eq(listed.would_change.count, 2)
	check_eq(listed.would_change.get("not_listed"), 1)

	# An unused new key changes no map; several kinds in one undo step.
	var q := _call("edit_palette_key", {"id": "pal", "key": "q", "terrain": "t_floor", "furniture": "f_table",
		"mappings": {"items": {"item": "junk", "chance": 50}}})
	check_eq(q.maps_changed, {"count": 0, "maps": []})
	check_eq(q.key.q.furniture.value, "f_table")
	check_eq(q.key.q.items[0].value, {"item": "junk", "chance": 50}, "ints stay ints")
	# null / "" remove; the furniture and items of 'h' go, its terrain was never there.
	var h := _call("edit_palette_key", {"id": "pal", "key": "h", "furniture": null, "mappings": {"items": null}})
	check_eq(h.get("key"), {"h": null})
	# An unknown group isn't refused, but reported.
	var bad := _call("edit_palette_key", {"id": "pal", "key": "h", "mappings": {"items": {"item": "nope"}}})
	check(bad.get("findings", []).size() > 0 and bad.findings[0].symbol == "h", "unknown group reported: %s" % bad)

	# A computer: t_console comes with it on a key without terrain; null removes it.
	var comp := _call("edit_palette_key", {"id": "pal", "key": "6", "computer": {"name": "Terminal"}})
	check_eq(comp.key["6"].terrain.value, "t_console")
	_call("edit_palette_key", {"id": "pal", "key": "6", "computer": null})
	var json: Dictionary = _call("get_palette", {"id": "pal"}).json
	check(not json.has("computers"), "computer removed")

	_fails("edit_palette_key", {"id": "pal", "key": "#"}, "Give terrain")
	_fails("edit_palette_key", {"id": "pal", "key": "#", "terrain": "t_nope"}, "Unknown terrain")
	_fails("edit_palette_key", {"id": "pal", "key": "##", "terrain": "t_dirt"}, "one character")
	_fails("edit_palette_key", {"id": "pal", "key": ".", "terrain": "t_dirt"}, "Nothing changes")
	_fails("edit_palette_key", {"id": "pal", "key": ".", "mappings": {"bogus": {}}}, "Unknown mapping kind")
	_fails("edit_palette_key", {"id": "pal", "key": ".", "terrain": 3}, "mapgen value")
	_fails("edit_palette_key", {"id": "nope", "key": ".", "terrain": "t_dirt"}, "No palette")
	_cleanup()


func test_includes_and_history() -> void:
	_setup()
	check_eq(_ids(_call("set_palette_includes", {"id": "outer", "palettes": [], "dry_run": true}).would_change),
			["shed"])
	var inc := _call("set_palette_includes", {"id": "pal", "palettes": ["other"]})
	check_eq(_ids(inc.maps_changed), [], "pal defines # and . itself")
	check_eq(inc.get("includes"), ["other"])
	_fails("set_palette_includes", {"id": "inner", "palettes": ["outer"]}, "include itself")
	_fails("set_palette_includes", {"id": "pal", "palettes": ["nope"]}, "Unknown palette")
	_fails("set_palette_includes", {"id": "pal", "palettes": ["other"]}, "Nothing changes")

	_call("edit_palette_key", {"id": "pal", "key": "#", "terrain": "t_dirt"})
	var undone := _call("undo", {"palette": "pal"})
	check_eq(undone.get("undone"), "Edit '#'")
	check_eq(undone.get("redo"), "Edit '#'")
	check_eq(_terrain("pal", "#"), "t_wall")
	check_eq(_call("get_map", {"id": "house"}).legend["#"].terrain.value, "t_wall", "maps follow undo")
	check_eq(_call("redo", {"palette": "pal"}).get("redone"), "Edit '#'")
	check_eq(_terrain("pal", "#"), "t_dirt")
	_call("undo", {"palette": "pal"})
	_call("undo", {"palette": "pal"})
	check_eq(_call("get_palette", {"id": "pal"}).json.has("palettes"), false, "includes undone")
	check_eq(_call("sync_status").get("unsaved", []), [], "back as read")
	_fails("undo", {"palette": "pal"}, "Nothing to undo")
	_fails("redo", {"palette": "inner"}, "Nothing to redo")
	_cleanup()


func test_create_save_discard() -> void:
	_setup()
	# As BN's files are, so objects the save doesn't touch compare equal.
	var path := _root.path_join(HOUSE)
	var clean := JsonFormatter.format(FileAccess.get_file_as_string(path)).text
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(clean)
	f.close()
	var rel := "data/json/mapgen_palettes/mine.json"
	var made := _call("create_palette", {"file": rel, "id": "mine"})
	check_eq(made, {"palette": "mine", "file": rel, "index": 0, "dirty": true})
	_fails("create_palette", {"file": rel, "id": "pal"}, "already exists")
	_fails("create_palette", {"file": "../x.json", "id": "zz"}, "relative .json path")
	_call("edit_palette_key", {"id": "mine", "key": "#", "terrain": "t_rock"})
	_call("set_map_palettes", {"id": "plain", "palettes": ["mine"]})
	check_eq(_ids(_call("edit_palette_key", {"id": "mine", "key": "#", "terrain": "t_wall",
		"dry_run": true}).would_change), [], "plain defines # itself")
	check_eq(_ids(_call("edit_palette_key", {"id": "mine", "key": "o", "terrain": "t_wall",
		"dry_run": true}).would_change), [], "no row uses o")

	# A palette in a BN file: only the palette changes in the saved copy.
	_call("edit_palette_key", {"id": "house_pal", "key": "x", "furniture": "f_chair"})
	var saved := _call("save", {"file": HOUSE})
	check_eq(saved.get("saved", [{}])[0].get("changes"), ["changed palette house_pal"])
	var got := BnJson.parse(FileAccess.get_file_as_string(_ws.path_join(HOUSE)))
	check(got.ok() and got.value[1].furniture.x == "f_chair", "the edit saved")
	# Discard takes the new palette out of the index again.
	_call("discard", {"file": rel})
	_fails("get_palette", {"id": "mine"}, "No palette")
	_cleanup()

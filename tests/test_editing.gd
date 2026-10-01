extends "res://tests/support/test_case.gd"
## Editing (MapDocument, MapTool, JsonFile, EditSession, Workspace) against a
## small fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _ws := ""
var _index: DataIndex


func _setup(extra := {}) -> void:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/mods/other/modinfo.json": [{"type": "MOD_INFO", "id": "other", "dependencies": ["bn"]}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
			{"type": "overmap_terrain", "abstract": "generic_city_building", "name": "city building"},
			{"type": "overmap_terrain", "id": ["house", "ants", "lawn"], "name": "house"},
		],
		"data/json/palettes.json": [
			{"type": "palette", "id": "pal", "terrain": {"#": "t_wall", ".": "t_floor"},
				"furniture": {"h": "f_chair"}},
		],
		# The map has no own "terrain" member yet; its rows use the palette.
		"data/json/mapgen/house.json": "[\n  {\n    \"type\": \"mapgen\",\n    \"om_terrain\": \"house\",\n" \
			+ "    \"object\": {\"fill_ter\": \"t_grass\", \"rows\": %s, \"palettes\": [\"pal\"]}\n  },\n" % JSON.stringify(_rows()) \
			+ "  {\"type\": \"item_group\", \"id\": \"odd\", \"//\": \"caf\\u00e9\", \"items\": [1.50, 2]},\n" \
			+ "  {\"type\": \"mapgen\", \"om_terrain\": [\"lawn\"], \"object\": {\"fill_ter\": \"t_grass\"}}\n]\n",
	}
	files.merge(extra, true)
	_root = TempTree.make(files)
	_ws = TempTree.make({})
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


static func _rows() -> Array:
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 or y == 23 else "#" + ".".repeat(22) + "#")
	return rows


func _session() -> EditSession:
	return EditSession.new(_index, Workspace.open(_ws, _root))


func _open(session: EditSession, id: String) -> MapDocument:
	var doc := session.open(_index.mapgens_for(id)[0])
	check(doc != null, "open %s: %s" % [id, session.last_error])
	return doc


func _formatter_or_skip() -> bool:
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		return false
	return true


func test_top_level_spans() -> void:
	var text := "[ {\"a\": 1} ,\n  [2, 3], \"x\" ]"
	var r := BnJson.parse(text)
	check_eq(r.spans.size(), 3)
	var bytes := text.to_utf8_buffer()
	check_eq(bytes.slice(r.spans[0].x, r.spans[0].y).get_string_from_utf8(), "{\"a\": 1}")
	check_eq(bytes.slice(r.spans[1].x, r.spans[1].y).get_string_from_utf8(), "[2, 3]")
	check_eq(bytes.slice(r.spans[2].x, r.spans[2].y).get_string_from_utf8(), "\"x\"")
	check_eq(BnJson.parse("{\"a\": [1]}").spans.size(), 0, "no spans for a bare object")


## Untouched objects are written back as their original text, so escapes and
## number spellings BnJson would normalize survive.
func test_json_file_keeps_untouched_text() -> void:
	var text := "[{\"s\": \"caf\\u00e9\", \"n\": 1.50}, {\"k\": 1}]"
	var err := []
	var path := TempTree.make({"f.json": text})
	var f := JsonFile.load_file(path.path_join("f.json"), "f.json", err)
	check_eq(f.warnings.size(), 1, "the \\u escape is reported")
	var compact := "[{\"s\": \"caf\\u00e9\", \"n\": 1.50},{\"k\": 1}]"
	check_eq(f.compose(), compact, "nothing touched: each object's original text")
	check(not f.is_dirty(), "clean")
	f.touch(1)
	f.objects[1]["k"] = 2
	check(f.is_dirty(), "dirty after a change")
	check_eq(f.compose(), "[{\"s\": \"caf\\u00e9\", \"n\": 1.50},{\"k\":2}]")
	check_eq(f.lossy_warnings(), PackedStringArray(), "the lossy object isn't re-encoded")
	f.objects[1]["k"] = 1
	check(not f.is_dirty(), "changed back")
	check_eq(f.compose(), compact, "changed back: original text again")
	f.touch(0)
	f.objects[0]["n"] = 2.5
	check_eq(f.lossy_warnings().size(), 1, "now the \\u escape gets normalized")
	TempTree.remove(path)


func test_layered_data_files() -> void:
	var bn := TempTree.make({"d/a.json": "[]", "d/b.json": "[]", "d/sub/c.json": "[]"})
	var ws := TempTree.make({"d/b.json": "[]", "d/a2.json": "[]", "d/new/x.json": "[]"})
	var files := DataIndex.data_files(bn.path_join("d"), true, ws.path_join("d"))
	var expected := PackedStringArray([bn + "/d/a.json", ws + "/d/a2.json", ws + "/d/b.json",
			ws + "/d/new/x.json", bn + "/d/sub/c.json"])
	check_eq(files, expected)
	check_eq(DataIndex.data_files(bn.path_join("d"), true, ws.path_join("missing")).size(), 3,
			"a missing overlay folder is fine")
	TempTree.remove(bn)
	TempTree.remove(ws)


func test_index_layers_workspace() -> void:
	_setup()
	TempTree.remove(_ws)
	_ws = TempTree.make({
		"data/json/palettes.json": [{"type": "palette", "id": "pal", "terrain": {"#": "t_dirt"}}],
		"data/json/mapgen/extra.json": [{"type": "mapgen", "nested_mapgen_id": "chunk",
			"object": {"mapgensize": [2, 2], "rows": ["##", "##"]}}],
	})
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.palette("pal").data.terrain["#"], "t_dirt", "the workspace file replaces BN's")
	check_eq(_index.palette("pal").source.path, "data/json/palettes.json", "paths stay relative")
	check_eq(_index.mapgens_for("chunk").size(), 1, "a new workspace file loads")
	check(_index.in_workspace("data/json/palettes.json"))
	check_eq(_index.file_path("data/json/palettes.json"), _ws.path_join("data/json/palettes.json"))
	check_eq(_index.file_path("data/json/ter.json"), _root.path_join("data/json/ter.json"))
	check_eq(_index.mod_for_path("data/json/mapgen/x.json"), "bn")
	check_eq(_index.mod_for_path("data/mods/other/x.json"), "", "mod not loaded")
	check_eq(_index.mod_for_path("elsewhere/x.json"), "")
	check(_index.has_overmap_terrain("house"))
	check(_index.has_overmap_terrain("ants_four_way"), "LINEAR suffix")
	check(not _index.has_overmap_terrain("generic_city_building"), "abstracts aren't ids")
	_cleanup()


func test_paint_undo_redo() -> void:
	_setup()
	var session := _session()
	var doc := _open(session, "house")
	if doc == null:
		_cleanup()
		return
	var original := BnJson.stringify(doc.mapgen())
	var events := []
	doc.cells_changed.connect(func(c: Array[Vector2i]) -> void: events.append(c.size()))
	doc.begin_stroke("Paint")
	doc.set_cells([Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 1)], "h")
	doc.set_cells([Vector2i(3, 1), Vector2i(99, 1)], "h")
	doc.end_stroke()
	check_eq(events, [2, 1], "cells_changed per set_cells, skipping repeats and out-of-map cells")
	var rows: Array = doc.object().rows
	check_eq(rows[1], "#hhh" + ".".repeat(19) + "#")
	check_eq(rows[2], _rows()[2], "other rows untouched")
	check_eq(doc.resolved.key_at(1, 1), "h")
	check(session.is_dirty("data/json/mapgen/house.json"))
	check_eq(doc.undo_name(), "Paint")

	doc.paint([Vector2i(1, 2)], "#")
	doc.undo()
	doc.undo()
	check_eq(BnJson.stringify(doc.mapgen()), original, "undo restores the object exactly")
	check(not session.is_dirty("data/json/mapgen/house.json"), "back to clean")
	check(not doc.can_undo())
	doc.redo()
	check_eq(doc.object().rows[1], "#hhh" + ".".repeat(19) + "#", "redo")
	check_eq(doc.redo_name(), "Paint")
	doc.paint([Vector2i(5, 5)], ".")
	check(doc.can_redo(), "painting what's there changes nothing")
	doc.paint([Vector2i(5, 5)], "h")
	check(not doc.can_redo(), "a new change clears redo")
	_cleanup()


func test_new_symbol() -> void:
	_setup()
	var session := _session()
	var doc := _open(session, "house")
	if doc == null:
		_cleanup()
		return
	var original := BnJson.stringify(doc.mapgen())
	check(doc.check_new_key("#").contains("palette pal"), doc.check_new_key("#"))
	check(not doc.check_new_key(" ").is_empty(), "space is reserved")
	check(not doc.check_new_key(".").is_empty(), "dot is reserved")
	check(not doc.check_new_key("ab").is_empty(), "two columns")
	check(not doc.check_new_key("̱").is_empty(), "a combining mark isn't a column")
	check(not doc.check_new_key("中").is_empty(), "double width")
	check_eq(doc.check_new_key("é"), "")
	check_eq(doc.suggest_key("t_floor", "f_table"), "t", "the furniture's own symbol")
	check_eq(doc.suggest_key("t_wall", ""), "w", "else the terrain's")
	check_eq(doc.suggest_key("", "f_chair"), "a", "'h' is taken by the palette")
	check_eq(doc.matching_keys("t_grass", "f_chair"), PackedStringArray(["h"]), "h falls back to fill_ter")
	check_eq(doc.matching_keys("t_floor", ""), PackedStringArray(["."]))

	check(not doc.add_symbol("t", "t_nope", "").is_empty(), "unknown id")
	check(not doc.add_symbol("t", "", "").is_empty(), "nothing picked")
	check_eq(doc.add_symbol("t", "t_floor", "f_table"), "")
	check_eq(doc.object().keys(), ["fill_ter", "rows", "palettes", "terrain", "furniture"],
			"new members go after rows/palettes")
	check_eq(doc.object().terrain, {"t": "t_floor"})
	check_eq(doc.resolved.symbols["t"].furniture.source, ResolvedMapgen.SOURCE_MAP)
	check(not doc.add_symbol("t", "t_floor", "").is_empty(), "now taken")
	doc.paint([Vector2i(4, 4)], "t")
	check_eq(doc.problems(), PackedStringArray())

	doc.undo()
	doc.undo()
	check_eq(BnJson.stringify(doc.mapgen()), original, "undo removes the members again")
	doc.redo()
	check_eq(doc.object().keys(), ["fill_ter", "rows", "palettes", "terrain", "furniture"], "redo")
	check(doc.resolved.symbols.has("t"))
	_cleanup()


func test_map_without_rows() -> void:
	_setup()
	var session := _session()
	var doc := _open(session, "lawn")
	if doc == null:
		_cleanup()
		return
	check(not doc.has_rows())
	check_eq(doc.add_symbol("#", "t_wall", ""), "")
	var changed := [0]
	doc.changed.connect(func(full: bool) -> void: changed[0] += 1 if full else 0)
	doc.paint([Vector2i(0, 0)], "#")
	check(doc.has_rows(), "the first paint creates rows")
	check_eq(doc.object().keys(), ["fill_ter", "rows", "terrain"])
	check_eq(doc.object().rows.size(), 24)
	check_eq(doc.object().rows[0], "#" + " ".repeat(23))
	check_eq(doc.object().rows[1], " ".repeat(24))
	check_eq(doc.problems(), PackedStringArray(), "undefined ' ' is fine with fill_ter")
	check_eq(changed[0], 2, "full redraws: rows appear, then the change completes")
	doc.undo()
	check(not doc.has_rows(), "undo removes the rows again")
	check_eq(doc.resolved.key_at(0, 0), "")
	doc.redo()
	check_eq(doc.object().rows[0], "#" + " ".repeat(23))
	_cleanup()


func test_shapes_and_tools() -> void:
	check_eq(Shapes.line(Vector2i(0, 0), Vector2i(3, 1)),
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i])
	check_eq(Shapes.rect(Vector2i(2, 2), Vector2i(0, 0)).size(), 8, "outline")
	check_eq(Shapes.rect(Vector2i(0, 0), Vector2i(2, 2), true).size(), 9, "filled")
	var grid: Array[PackedStringArray] = [PackedStringArray(["a", "a", "b"]), PackedStringArray(["b", "a", "a"])]
	check_eq(Shapes.flood(grid, Vector2i(0, 0)).size(), 4)

	_setup()
	var doc := _open(_session(), "house")
	if doc == null:
		_cleanup()
		return
	var tool := MapTool.new()
	check(not tool.press(doc, Vector2i(1, 1)), "no symbol, nothing to draw")
	var picked := []
	tool.picked.connect(func(k: String) -> void: picked.append(k))
	check(tool.press(doc, Vector2i(0, 0), true), "alt picks")
	check_eq(picked, ["#"])
	tool.key = "h"
	tool.press(doc, Vector2i(1, 1))
	tool.move(Vector2i(4, 1))
	tool.release(Vector2i(4, 1))
	check_eq(doc.object().rows[1], "#hhhh" + ".".repeat(18) + "#", "a drag paints a joined line")
	check_eq(doc.undo_name(), "Paint 'h'")

	tool.kind = MapTool.Kind.RECT
	tool.press(doc, Vector2i(2, 3))
	tool.move(Vector2i(4, 5))
	check_eq(tool.preview.size(), 8, "rect preview")
	check_eq(doc.resolved.key_at(2, 3), ".", "nothing painted before release")
	tool.release(Vector2i(4, 5), true)
	check_eq(doc.object().rows[4], "#.hhh" + ".".repeat(18) + "#", "shift fills")
	check(tool.preview.is_empty())

	tool.kind = MapTool.Kind.LINE
	tool.press(doc, Vector2i(10, 10))
	tool.cancel()
	check_eq(doc.resolved.key_at(10, 10), ".", "cancelled line")

	tool.kind = MapTool.Kind.FILL
	tool.key = "#"
	tool.press(doc, Vector2i(10, 10))
	check_eq(doc.object().rows[10], "#".repeat(24), "fill")
	check_eq(doc.object().rows[1], "#hhhh" + "#".repeat(19), "fill stops at other symbols")
	doc.undo()
	check_eq(doc.object().rows[10], "#" + ".".repeat(22) + "#", "fill is one undo step")

	tool.kind = MapTool.Kind.ERASE
	tool.key = ""
	check(tool.press(doc, Vector2i(1, 1)), "erase needs no brush")
	tool.move(Vector2i(3, 1))
	tool.release(Vector2i(3, 1))
	check_eq(doc.object().rows[1], "#   h" + ".".repeat(18) + "#", "a drag erases to ' '")
	check_eq(doc.undo_name(), "Erase")
	check_eq(doc.problems(), PackedStringArray(), "undefined ' ' is fine with fill_ter")
	doc.undo()
	check_eq(doc.object().rows[1], "#hhhh" + ".".repeat(18) + "#", "erase is one undo step")
	var res := ResolvedMapgen.new()
	check_eq(MapTool.blank_key(res), " ")
	res.symbols[" "] = ResolvedMapgen.SymbolInfo.new()
	check_eq(MapTool.blank_key(res), ".", "' ' means something, '.' is the blank")
	res.symbols["."] = ResolvedMapgen.SymbolInfo.new()
	check_eq(MapTool.blank_key(res), "", "no blank left")
	_cleanup()


func test_save_to_workspace() -> void:
	_setup()
	if not _formatter_or_skip():
		_cleanup()
		return
	var bn_file := _root.path_join("data/json/mapgen/house.json")
	var bn_before := FileAccess.get_file_as_bytes(bn_file)
	var session := _session()
	var doc := _open(session, "house")
	if doc == null:
		_cleanup()
		return
	var rel := "data/json/mapgen/house.json"
	check_eq(session.dirty_files(), PackedStringArray())
	doc.paint([Vector2i(1, 1)], "h")
	check_eq(session.dirty_files(), PackedStringArray([rel]))
	check_eq(session.save(rel), "")
	check_eq(session.dirty_files(), PackedStringArray(), "clean after saving")
	check_eq(FileAccess.get_file_as_bytes(bn_file), bn_before, "BN's file is untouched")

	var saved := FileAccess.get_file_as_string(_ws.path_join(rel))
	check(saved.contains("\"#h" + ".".repeat(21) + "#\""), "the edit is saved")
	check(saved.contains("caf\\u00e9"), "the untouched item_group keeps its escape")
	var ws := Workspace.open(_ws, _root)
	check_eq(ws.error, "")
	check_eq(ws.files.keys(), [rel])
	check_eq(ws.files[rel].get("base_sha256"), FileAccess.get_sha256(bn_file))

	# The index now reads the workspace copy, and a later save keeps the base.
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	session = _session()
	doc = _open(session, "house")
	if doc:
		check_eq(doc.resolved.key_at(1, 1), "h", "reopened from the workspace")
		check(doc.file.in_workspace)
		doc.paint([Vector2i(2, 2)], "h")
		check_eq(session.save(rel), "")
		check_eq(Workspace.open(_ws, _root).files[rel].get("base_sha256"), FileAccess.get_sha256(bn_file))
	_cleanup()


func test_workspace_refuses_bn_folder() -> void:
	_setup()
	var ws := Workspace.open(_root.path_join("data"), _root)
	check(not ws.write_file("x.json", "[]", "").is_empty(), "inside BN")
	check(not FileAccess.file_exists(_root.path_join("data/x.json")))
	check(not Workspace.check_root(_root.get_base_dir(), _root).is_empty(), "containing BN")
	check_eq(Workspace.check_root(_ws, _root), "")
	_cleanup()


func test_bn_commit() -> void:
	var repo := TempTree.make({
		".git/HEAD": "ref: refs/heads/main\n",
		".git/packed-refs": "# pack-refs\nabc123 refs/heads/main\n",
	})
	check_eq(Workspace.bn_commit(repo), "abc123", "packed ref")
	DirAccess.make_dir_recursive_absolute(repo.path_join(".git/refs/heads"))
	var f := FileAccess.open(repo.path_join(".git/refs/heads/main"), FileAccess.WRITE)
	f.store_string("def456\n")
	f.close()
	check_eq(Workspace.bn_commit(repo), "def456", "loose ref wins")
	check_eq(Workspace.bn_commit(repo.path_join("nowhere")), "")
	TempTree.remove(repo)


func test_create_mapgen() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/shed.json"
	spec.ids = EditSession.default_ids("shed", 2, 1)
	check_eq(spec.ids, [PackedStringArray(["shed_1_1", "shed_2_1"])] as Array[PackedStringArray])
	spec.palettes = PackedStringArray(["pal"])
	check_eq(session.check_new_mapgen(spec), "")

	var bad := EditSession.NewMapgen.new()
	bad.ids = EditSession.default_ids("x", 1, 1)
	for path in ["/abs/x.json", "data/json/x.txt", "elsewhere/x.json", "data/mods/other/x.json"]:
		bad.rel_path = path
		check(not session.check_new_mapgen(bad).is_empty(), "bad path " + path)
	bad.rel_path = "data/json/x.json"
	bad.fill_ter = "t_nope"
	check(not session.check_new_mapgen(bad).is_empty(), "unknown fill_ter")
	bad.fill_ter = "t_grass"
	bad.ids = [PackedStringArray(["a", "b"]), PackedStringArray(["c"])]
	check(not session.check_new_mapgen(bad).is_empty(), "ragged grid")

	var doc := session.create_mapgen(spec)
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	check_eq(doc.size(), Vector2i(48, 24))
	check_eq(doc.problems(), PackedStringArray(), "stubs were added")
	check_eq(_index.mapgens_for("shed_2_1").size(), 1, "indexed")
	check(_index.has_overmap_terrain("shed_1_1"))
	var stub: Dictionary = doc.file.objects[1]
	check_eq(stub, {"type": "overmap_terrain", "id": ["shed_1_1", "shed_2_1"],
		"copy-from": "generic_city_building", "name": "shed 1 1", "color": "light_gray"})
	check(session.is_dirty(spec.rel_path), "new file is dirty")

	# Discarding a new, unsaved map takes it out of the index again.
	session.close(doc)
	check_eq(_index.mapgens_for("shed_1_1").size(), 0)
	check(not _index.has_overmap_terrain("shed_1_1"))

	# Without the auto-fix, the missing overmap_terrain is a problem.
	spec.add_overmap_terrain = false
	doc = session.create_mapgen(spec)
	check(doc.problems().size() == 2 and doc.problems()[0].contains("shed_1_1"), str(doc.problems()))
	check_eq(session.add_missing_overmap_terrain(doc), PackedStringArray(["shed_1_1", "shed_2_1"]))
	check_eq(doc.problems(), PackedStringArray())

	if _formatter_or_skip():
		check_eq(session.save(spec.rel_path), "")
		check_eq(Workspace.open(_ws, _root).files[spec.rel_path], {"new": true})
		_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
		check_eq(_index.mapgens_for("shed_1_1").size(), 1, "loads from the workspace")
		check(_index.has_overmap_terrain("shed_2_1"))
		var r := MapgenResolver.resolve(_index, _index.read_object(_index.mapgens_for("shed_1_1")[0].source))
		check_eq(r.problems, PackedStringArray())
		check_eq(r.size, Vector2i(48, 24))
	_cleanup()


## A new mapgen added to an existing file keeps the file's other objects.
func test_create_mapgen_in_existing_file() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/house.json"
	spec.ids = EditSession.default_ids("house_variant", 1, 1)
	var doc := session.create_mapgen(spec)
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	check_eq(doc.object_index, 3)
	check_eq(doc.file.objects.size(), 5, "3 old + mapgen + stub")
	check(doc.file.is_original(0) and doc.file.is_original(1) and doc.file.is_original(2))
	_cleanup()

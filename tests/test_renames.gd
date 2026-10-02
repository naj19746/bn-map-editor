extends "res://tests/support/test_case.gd"
## Stage 11e: renames and removals. Taking an object out of a file
## (JsonFile.remove / insert, DataIndex.shift_sources), a map's own symbol
## renamed or removed, a palette key renamed with the maps using it
## repainted (PaletteImpact.plan_rename), an unused palette deleted and
## restored, the overmap_terrain stub as an undo step; the MCP tools and
## the UI for them; and the accept on real BN data.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")

const PALETTES := "data/json/mapgen_palettes/pal.json"
const MAPS := "data/json/mapgen/maps.json"
const MIXED := "data/json/mapgen/mixed.json"

var _root := ""
var _ws := ""
var _index: DataIndex


static func _rows(fill: String) -> Array:
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 or y == 23 else "#" + fill.repeat(22) + "#")
	return rows


static func _map(id: String, palettes: Array, fill := ".", extra := {}) -> Dictionary:
	var obj := {"fill_ter": "t_grass", "rows": _rows(fill), "palettes": palettes}
	obj.merge(extra)
	return {"type": "mapgen", "method": "json", "om_terrain": id, "object": obj}


func _files() -> Dictionary:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt", "t_rock"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	return {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
			{"type": "item_group", "id": "junk", "items": [["rock", 10]]},
		],
		PALETTES: [
			{"type": "palette", "id": "pal", "terrain": {"#": "t_wall", ".": "t_floor"},
				"furniture": {"h": "f_chair", "t": "f_table"}, "items": {"h": {"item": "junk", "chance": 5}}},
			{"type": "palette", "id": "later", "furniture": {"h": "f_table"}},
			{"type": "palette", "id": "inner", "terrain": {"#": "t_rock"}},
			{"type": "palette", "id": "outer", "palettes": ["inner"], "terrain": {".": "t_dirt"}},
			{"type": "palette", "id": "lonely", "terrain": {"z": "t_dirt"}},
		],
		MAPS: [
			# Takes 'h' from pal: repainted.
			_map("a", ["pal"], "h"),
			# Its own 'h' furniture wins but pal's items reach it: keeps 'h',
			# changed. Defines 'q' too (unused).
			_map("b", ["pal"], "h", {"terrain": {"q": "t_dirt"}, "furniture": {"h": "f_table"}}),
			# later's furniture wins for 'h': repainted, but the new key
			# means pal's chair, so it changes too.
			_map("c", ["pal", "later"], "h"),
			# Uses pal, but not 'h'.
			_map("d", ["pal"], "."),
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "hchunk",
				"object": {"mapgensize": [2, 2], "rows": ["hh", "hh"], "palettes": ["pal"]}},
			# Places the chunk: it looks the same after the rename.
			_map("plain", [], ".", {"terrain": {"#": "t_wall", ".": "t_floor"},
				"place_nested": [{"chunks": ["hchunk"], "x": 3, "y": 3}]}),
			# Its own symbols: 'k' in terrain, items and mapping.
			_map("own", ["pal"], "k", {"terrain": {"k": "t_dirt", "o": "t_rock"},
				"items": {"k": {"item": "junk", "chance": 10}},
				"mapping": {"k": {"furniture": "f_table"}}}),
		],
		# A palette in the middle of a file, maps before and after it.
		MIXED: [
			_map("m1", ["pal"]),
			{"type": "palette", "id": "doomed", "terrain": {"z": "t_dirt"}},
			_map("m2", ["pal"]),
			{"type": "item_group", "id": "tail_group", "items": [["rock", 5]]},
		],
	}


func _setup(extra := {}) -> void:
	var files := _files()
	files.merge(extra, true)
	for rel: String in files:
		files[rel] = BnJson.stringify(files[rel])
	_root = TempTree.make(files)
	_ws = TempTree.make({})
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


func _session() -> EditSession:
	return EditSession.new(_index, Workspace.open(_ws, _root))


func _open(session: EditSession, id: String) -> MapDocument:
	var doc := session.open(_index.mapgens_for(id)[0])
	check(doc != null, "open %s: %s" % [id, session.last_error])
	return doc


static func _titles(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for a: Variant in list:
		out.append((a.ref if a is PaletteImpact.Affected else a).title())
	out.sort()
	return out


static func _count(doc: MapDocument, key: String) -> int:
	var n := 0
	for row in doc.resolved.cells:
		n += row.count(key)
	return n


# --- JsonFile ----------------------------------------------------------------------

func test_json_file_remove_insert() -> void:
	var text := "[ {\"id\": \"a\",  \"v\": 1},\n  {\"id\": \"b\"} ,{\"id\":\"c\"} ]"
	var dir := TempTree.make({"f.json": text})
	var f := JsonFile.load_file(dir.path_join("f.json"), "f.json")
	f.touch(2)
	f.objects[2]["v"] = 3
	var edited := f.compose()
	check_eq(edited, "[{\"id\": \"a\",  \"v\": 1},{\"id\": \"b\"},{\"id\":\"c\",\"v\":3}]")

	var r := f.remove(1)
	check_eq(f.objects.size(), 2)
	check(f.is_dirty())
	check_eq(f.compose(), "[{\"id\": \"a\",  \"v\": 1},{\"id\":\"c\",\"v\":3}]", "the others as they were")
	check(f.is_original(0) and not f.is_original(1))
	f.insert(r)
	check_eq(f.compose(), edited, "back as its original text")
	f.objects[2].erase("v")
	check(not f.is_dirty(), "as read again")

	# An appended object taken out again leaves the file as read.
	var i := f.append({"id": "d"})
	check(f.is_dirty())
	r = f.remove(i)
	check(not f.is_dirty())
	f.insert(r)
	check_eq(f.objects.size(), 4)

	# A bare object file.
	var one := TempTree.make({"g.json": "{\"id\": \"x\"}"})
	var g := JsonFile.load_file(one.path_join("g.json"), "g.json")
	r = g.remove(0)
	check_eq(g.compose(), "[]")
	g.insert(r)
	check_eq(g.compose(), "{\"id\": \"x\"}")
	check(not g.is_dirty())
	TempTree.remove(dir)
	TempTree.remove(one)


# --- A map's own symbols -----------------------------------------------------------

func test_rename_map_symbol() -> void:
	_setup()
	var session := _session()
	var doc := _open(session, "own")
	if doc == null:
		_cleanup()
		return
	var original := doc.file.compose()
	check_eq(doc.defined_keys(), PackedStringArray(["k", "o"]))
	check(doc.check_rename("h", "m").contains("isn't defined in the map itself"), doc.check_rename("h", "m"))
	check(doc.check_rename("k", "#").contains("already defined"), doc.check_rename("k", "#"))
	check(doc.check_rename("k", "o").contains("already defined"))
	check(doc.check_rename("k", " ").contains("left undefined"))
	var cells := _count(doc, "k")
	check_eq(cells, 22 * 22)

	check_eq(doc.rename_own_symbol("k", "m"), "")
	var obj := doc.object()
	check_eq(obj.terrain.keys(), ["m", "o"], "renamed in place")
	check_eq(obj.items.keys(), ["m"])
	check_eq(obj.mapping.keys(), ["m"])
	check_eq(_count(doc, "m"), cells)
	check_eq(_count(doc, "k"), 0)
	check_eq(doc.resolved.symbols["m"].furniture.id(), "f_table", "mapping follows")
	check_eq(doc.undo_name(), "Rename 'k' to 'm'")
	check_eq(doc.object().rows[1], "#" + "m".repeat(22) + "#")
	doc.undo()
	check_eq(doc.file.compose(), original, "one undo step")
	check(not doc.file.is_dirty())
	doc.redo()
	check_eq(_count(doc, "m"), cells)

	# 'h' in b takes pal's items too: refused.
	var b := _open(session, "b")
	check(b.check_rename("h", "m").contains("palette pal"), b.check_rename("h", "m"))
	# The map's other own symbol, unused, renames without cells.
	check_eq(b.rename_own_symbol("q", "r"), "")
	check_eq(b.object().terrain.keys(), ["r"])
	_cleanup()


func test_remove_symbol_every_kind() -> void:
	_setup()
	var session := _session()
	var doc := _open(session, "own")
	if doc == null:
		_cleanup()
		return
	var original := doc.file.compose()
	doc.remove_own_symbol("k")
	check(doc.object().has("items") and doc.object().has("mapping"), "terrain/furniture only")
	check(not doc.object().terrain.has("k"))
	doc.undo()
	doc.remove_own_symbol("k", "", true)
	check(not doc.object().has("items") and not doc.object().has("mapping"), "every kind; empty members go")
	check_eq(doc.object().terrain.keys(), ["o"])
	check(not doc.resolved.symbols.has("k"))
	doc.undo()
	check_eq(doc.file.compose(), original)
	_cleanup()


# --- A palette key -----------------------------------------------------------------

func test_rename_palette_key() -> void:
	_setup()
	var session := _session()
	var pal := session.open_palette(_index.palette("pal"))
	if not check(pal != null, session.last_error):
		_cleanup()
		return
	check(pal.check_rename("z", "m").contains("doesn't define"))
	check(pal.check_rename("h", "t").contains("already defined by the palette itself"), pal.check_rename("h", "t"))
	var refused := PaletteImpact.plan_rename(session, pal, "h", "q")
	check(refused.problem.contains("b"), "b uses 'h' and defines 'q': " + refused.problem)
	check(refused.change == null)

	var plan := PaletteImpact.plan_rename(session, pal, "h", "m")
	check_eq(plan.problem, "")
	check_eq(_titles(plan.repainted), PackedStringArray(["a", "c", "hchunk"]))
	check_eq(_titles(plan.changed), PackedStringArray(["b", "c"]), "b keeps 'h' without pal's items; c's 'm' is pal's chair")
	for a in plan.changed:
		check_eq(a.keys, PackedStringArray(["h"] if a.ref.title() == "b" else ["m"]))
	check_eq(pal.tile_value("h", "furniture"), "f_chair", "planning changes nothing")
	check(session.docs.is_empty(), "nor opens maps")

	var palette_file := pal.file.compose()
	var maps_file := FileAccess.get_file_as_string(_root.path_join(MAPS))
	check_eq(session.rename_palette_key(pal, plan), "")
	check_eq(pal.palette().furniture.keys(), ["m", "t"], "renamed in place")
	check_eq(pal.palette().items.keys(), ["m"])
	var a := _open(session, "a")
	var b := _open(session, "b")
	var chunk := _open(session, "hchunk")
	check_eq(_count(a, "m"), 22 * 22)
	check_eq(_count(a, "h"), 0)
	check_eq(a.resolved.symbols["m"].furniture.id(), "f_chair")
	check_eq(_count(b, "h"), 22 * 22, "b keeps its own 'h'")
	check_eq(chunk.object().rows, ["mm", "mm"])
	check_eq(a.undo_name(), "Rename 'h' to 'm' (palette pal)")
	check(session.is_dirty(MAPS) and session.is_dirty(PALETTES))

	# Undo in the palette undoes the maps' repaint too.
	pal.undo()
	check_eq(_count(a, "h"), 22 * 22)
	check_eq(chunk.object().rows, ["hh", "hh"])
	check_eq(pal.file.compose(), palette_file)
	check(not session.is_dirty(MAPS), "the maps' file as read")
	pal.redo()
	check_eq(_count(a, "m"), 22 * 22)
	check_eq(chunk.object().rows, ["mm", "mm"])
	# A map undone on its own no longer follows the palette.
	a.undo()
	pal.undo()
	check_eq(_count(a, "h"), 22 * 22)
	check(not a.can_redo() or a.redo_name() == "Rename 'h' to 'm' (palette pal)")
	check_eq(_titles(PaletteImpact.plan_rename(session, pal, "h", "m").repainted),
			PackedStringArray(["a", "c", "hchunk"]), "the same plan again")
	check_eq(maps_file, FileAccess.get_file_as_string(_root.path_join(MAPS)), "BN untouched")
	_cleanup()


# --- Deleting a palette ------------------------------------------------------------

func test_delete_palette() -> void:
	_setup()
	var session := _session()
	check(session.check_delete_palette(_index.palette("pal")).contains("a, b"), "names the maps")
	check(session.check_delete_palette(_index.palette("inner")).contains("including it: outer"),
			session.check_delete_palette(_index.palette("inner")))
	check_eq(session.check_delete_palette(_index.palette("doomed")), "")

	var m2 := _open(session, "m2")
	if m2 == null:
		_cleanup()
		return
	var f := m2.file
	var original := f.compose()
	var doomed := _index.palette("doomed")
	check_eq(session.delete_palette(doomed), "")
	check(_index.palette("doomed") == null)
	check_eq(m2.object_index, 1, "the map after it moved down")
	check_eq(m2.ref.source.index, 1)
	check_eq(_index.item_groups["tail_group"][0].source.index, 2)
	check_eq(_index.mapgens_for("m1")[0].source.index, 0)
	check(session.is_dirty(MIXED))
	check_eq(session.deleted_palettes().size(), 1)
	m2.paint([Vector2i(1, 1)] as Array[Vector2i], "#")
	check_eq(m2.object().rows[1].substr(0, 2), "##", "edits the right object")

	check_eq(session.restore_palette("doomed"), "")
	check(_index.palette("doomed") == doomed)
	check_eq(doomed.source.index, 1)
	check_eq(m2.object_index, 2)
	check_eq(_index.item_groups["tail_group"][0].source.index, 3)
	m2.undo()
	check_eq(f.compose(), original, "byte-identical again")
	check(not f.is_dirty())
	check(session.restore_palette("doomed").contains("No deleted palette"))

	# Discarding the file puts the index back as on disk.
	check_eq(session.delete_palette(doomed), "")
	session.discard(MIXED)
	check(_index.palette("doomed") == doomed)
	check_eq(doomed.source.index, 1)
	check_eq(_index.mapgens_for("m2")[0].source.index, 2)
	check_eq(session.deleted_palettes().size(), 0)

	# A palette open in the editor closes with its deletion; the file stays open.
	var lonely := session.open_palette(_index.palette("lonely"))
	check_eq(session.delete_palette(lonely.def), "")
	check(session.palette_doc_for(lonely.def) == null)
	check(session.files.has(PALETTES) and session.is_dirty(PALETTES))
	check_eq(_index.palette("inner").source.index, 2, "before it: unmoved")

	m2 = _open(session, "m2")
	check_eq(session.delete_palette(_index.palette("doomed")), "")
	m2.paint([Vector2i(1, 1)] as Array[Vector2i], "#")
	check_eq(session.save_all(), PackedStringArray())
	check_eq(session.deleted_palettes().size(), 0, "saved: for good")
	check(session.restore_palette("doomed").contains("No deleted palette"))
	var saved := BnJson.parse(FileAccess.get_file_as_string(_ws.path_join(MIXED))).value as Array
	check_eq(saved.map(func(o: Dictionary) -> String: return str(o.get("om_terrain", o.get("id")))),
			["m1", "m2", "tail_group"])
	check_eq(saved[1].object.rows[1].substr(0, 2), "##")
	var again := DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check(again.palette("doomed") == null and again.palette("lonely") == null)
	check_eq(again.mapgens_for("m2")[0].source.index, 1)
	_cleanup()


# --- The overmap_terrain stub ------------------------------------------------------

func test_overmap_stub_undo() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/new.json"
	spec.ids = EditSession.default_ids("shed", 1, 1)
	var doc := session.create_mapgen(spec)
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	check_eq(doc.undo_name(), "Add overmap_terrain shed")
	check_eq(doc.file.objects.size(), 2)
	check_eq(doc.undo(), "")
	check_eq(doc.file.objects.size(), 1, "the stub is gone")
	check(not _index.has_overmap_terrain("shed"))
	check(doc.problems().size() == 1 and doc.problems()[0].contains("shed"), str(doc.problems()))
	check_eq(doc.redo(), "")
	check(_index.has_overmap_terrain("shed"))
	check_eq(doc.problems(), PackedStringArray())

	# Something appended after it: the undo is refused, nothing changes.
	spec.ids = EditSession.default_ids("barn", 1, 1)
	var barn := session.create_mapgen(spec)
	check_eq(barn.object_index, 2)
	var err := doc.undo()
	check(err.contains("something was added"), err)
	check_eq(doc.file.objects.size(), 4)
	check(_index.has_overmap_terrain("shed"))
	check_eq(doc.undo_name(), "Add overmap_terrain shed", "still to undo")
	check_eq(barn.undo(), "", "barn's own stub is last")
	check_eq(doc.undo(), "Can't undo adding the overmap_terrain for shed: something was added to data/json/mapgen/new.json after it (a new map, level or palette); undo or discard that first.",
			"barn's mapgen is still after it")

	# In an existing file: undone, the file is as read.
	var a := _open(session, "a")
	var before := a.file.compose()
	check_eq(session.add_missing_overmap_terrain(a), PackedStringArray(["a"]))
	check(a.file.is_dirty())
	check_eq(a.undo(), "")
	check(not a.file.is_dirty())
	check_eq(a.file.compose(), before)
	_cleanup()


func test_stub_undo_after_a_deletion() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/new.json"
	spec.ids = EditSession.default_ids("shed", 1, 1)
	var doc := session.create_mapgen(spec)
	var pal := session.create_palette(spec.rel_path, "newpal")
	if not check(doc != null and pal != null, session.last_error):
		_cleanup()
		return
	check_eq(session.delete_palette(pal.def), "")
	# The palette went after the stub: it comes back first.
	var err := doc.undo()
	check(err.contains("palette newpal was deleted"), err)
	check_eq(doc.file.objects.size(), 2, "the stub stays")
	check_eq(session.restore_palette("newpal"), "")
	check_eq(doc.file.objects.size(), 3)
	check(is_same(doc.file.objects[2], _index.palette("newpal").data), "the palette is back at #2")
	check_eq(_index.palette("newpal").source.index, 2)
	_cleanup()


func test_stub_saved_undone_discarded() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/new.json"
	spec.ids = EditSession.default_ids("shed", 1, 1)
	var doc := session.create_mapgen(spec)
	check_eq(session.save(spec.rel_path), "")
	# Undone and redone: the file is as saved again.
	check_eq(doc.undo(), "")
	check(doc.file.is_dirty())
	check_eq(doc.redo(), "")
	check(not doc.file.is_dirty(), "as saved")
	session.discard(spec.rel_path)
	check(_index.has_overmap_terrain("shed"), "saved stub still indexed after discard")
	# Undone, then discarded: the index has the stub on disk again.
	doc = _open(session, "shed")
	check_eq(doc.object_index, 0)
	check_eq(doc.undo_name(), "", "a fresh document: no history")
	_cleanup()
	_setup()
	session = _session()
	doc = session.create_mapgen(spec)
	check_eq(session.save(spec.rel_path), "")
	check_eq(doc.undo(), "")
	check(not _index.has_overmap_terrain("shed"))
	session.discard(spec.rel_path)
	var src: DataIndex.Source = _index.overmap_terrain.get("shed")
	check(src != null, "back from disk")
	if src:
		check_eq([src.path, src.index], [spec.rel_path, 1])
	_cleanup()


func test_discard_resolves_maps_again() -> void:
	_setup()
	var session := _session()
	var pdoc := session.open_palette(_index.palette("pal"))
	var plan := PaletteImpact.plan_rename(session, pdoc, "h", "H")
	check_eq(session.rename_palette_key(pdoc, plan), "")
	var a := _open(session, "a")
	check(a.resolved.symbols.has("H"))
	var d := _open(session, "d")
	var changed := [0]
	d.changed.connect(func(_full: bool) -> void: changed[0] += 1)
	session.discard(PALETTES)
	check(not a.resolved.symbols.has("H"), "pal is back as on disk: 'H' is undefined in a")
	check(a.resolved.symbols.has("h"))
	check_eq(changed[0], 1, "d uses pal: resolved again")
	_cleanup()


func test_rename_refused_when_a_map_cant_open() -> void:
	_setup()
	var session := _session()
	var pdoc := session.open_palette(_index.palette("pal"))
	var plan := PaletteImpact.plan_rename(session, pdoc, "h", "H")
	check_eq(plan.problem, "")
	# The maps' file goes away before the rename runs.
	DirAccess.remove_absolute(_root.path_join(MAPS))
	var err := session.rename_palette_key(pdoc, plan)
	check(err.begins_with("Not renamed") and err.contains("a: "), err)
	check(not pdoc.can_undo(), "the palette is as it was")
	check(pdoc.own_keys().has("h"))
	check_eq(session.docs.size(), 0, "no map left open")
	check_eq(session.dirty_files(), PackedStringArray())
	_cleanup()


## Two definitions of "lonely": the undo of deleting the one in effect
## and edits of the other go last first.
func test_mcp_undo_order_with_a_second_definition() -> void:
	_setup({"data/json/mapgen_palettes/twice.json": [{"type": "palette", "id": "lonely", "terrain": {"z": "t_rock"}}]})
	var tools := _tools()
	_call(tools, "get_palette", {"id": "lonely"})
	var session := tools.session
	var defs: Array = session.index.palettes["lonely"]
	if not check_eq(defs.size(), 2):
		_cleanup()
		return
	var older: DataIndex.Definition = defs[0]
	var later: DataIndex.Definition = defs[1]
	check_eq(later.source.path, "data/json/mapgen_palettes/twice.json")
	var od := session.open_palette(older)
	od.commit(od.build_set_tiles("y", "t_dirt", ""))
	# Edited before the deletion: undo brings the deleted one back first.
	check_eq(session.delete_palette(later), "")
	var got := _call(tools, "undo", {"palette": "lonely"})
	check_eq(got.get("restored"), true, str(got))
	check(session.index.palette("lonely") == later)
	check_eq(od.undo_count(), 1, "the older definition's edit stays")
	# Edited after the deletion: that edit goes first.
	check_eq(session.delete_palette(later), "")
	od.commit(od.build_set_tiles("w", "t_dirt", ""))
	got = _call(tools, "undo", {"palette": "lonely"})
	check_eq(got.get("undone"), "Set 'w'", str(got))
	check(session.deleted_palette("lonely") != null, "still deleted")
	got = _call(tools, "undo", {"palette": "lonely"})
	check_eq(got.get("restored"), true, str(got))
	_cleanup()


# --- MCP ---------------------------------------------------------------------------

func _tools() -> McpTools:
	return McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(), _ws))


func _call(tools: McpTools, name: String, args := {}) -> Dictionary:
	var got: Variant = tools.call_tool(name, args)
	if got is McpTools.Failure:
		check(false, "%s failed: %s" % [name, got.message])
		return {}
	return got


func _fails(tools: McpTools, name: String, args: Dictionary, contains: String) -> void:
	var got: Variant = tools.call_tool(name, args)
	if check(got is McpTools.Failure, "%s %s should fail" % [name, args]):
		check(got.message.contains(contains), "%s: \"%s\" should mention \"%s\"" % [name, got.message, contains])


static func _ids(impact: Variant) -> Array:
	return impact.maps.map(func(m: Dictionary) -> String: return m.id) if impact is Dictionary else []


func test_mcp() -> void:
	_setup()
	var tools := _tools()
	# rename_symbol
	var got := _call(tools, "rename_symbol", {"id": "own", "key": "k", "new_key": "m"})
	check_eq(got.get("cells_repainted"), 22 * 22)
	check_eq(got.get("renamed"), {"from": "k", "to": "m"})
	check_eq(got.get("undo"), "Rename 'k' to 'm'")
	_fails(tools, "rename_symbol", {"id": "own", "key": "m", "new_key": "#"}, "already defined")
	_fails(tools, "rename_symbol", {"id": "b", "key": "h", "new_key": "m"}, "palette pal")
	_call(tools, "undo", {"id": "own"})
	got = _call(tools, "remove_symbol", {"id": "own", "key": "k", "every_kind": true})
	check_eq(got.get("symbol"), {"k": null})
	check_eq(got.get("cells_using_it"), 22 * 22)
	_call(tools, "undo", {"id": "own"})

	# rename_key
	got = _call(tools, "rename_key", {"id": "pal", "key": "h", "new_key": "m", "dry_run": true})
	check_eq(_ids(got.get("would_repaint")), ["a", "c", "hchunk"])
	check_eq(_ids(got.get("would_change")), ["b", "c"])
	check(not tools.session.is_dirty(PALETTES), "dry run")
	_fails(tools, "rename_key", {"id": "pal", "key": "h", "new_key": "q"}, "already means something")
	got = _call(tools, "rename_key", {"id": "pal", "key": "h", "new_key": "m"})
	check_eq(got.get("repainted", {}).get("count"), 3)
	check_eq(got.get("dirty_files"), [MAPS, PALETTES])
	var a := _call(tools, "get_map", {"id": "a"})
	check(a.rows[1] == "#" + "m".repeat(22) + "#", str(a.get("rows", [""])[1]))
	got = _call(tools, "undo", {"palette": "pal"})
	check_eq(got.get("undone"), "Rename 'h' to 'm'")
	check_eq(tools.session.dirty_files(), PackedStringArray())

	# delete_palette
	_fails(tools, "delete_palette", {"id": "pal"}, "stop using it first")
	got = _call(tools, "delete_palette", {"id": "doomed", "dry_run": true})
	check_eq(got.get("can_delete"), true)
	check(tools.session.index.palette("doomed") != null)
	got = _call(tools, "delete_palette", {"id": "doomed"})
	check_eq(got.get("deleted"), true)
	check_eq(got.get("index"), 1)
	_fails(tools, "get_palette", {"id": "doomed"}, "No palette")
	check_eq(_call(tools, "get_map", {"id": "m2"}).get("index"), 1, "m2 moved down")
	got = _call(tools, "undo", {"palette": "doomed"})
	check_eq(got.get("restored"), true)
	check_eq(got.get("dirty"), false)
	check_eq(_call(tools, "get_map", {"id": "m2"}).get("index"), 2)

	# The overmap stub's undo, refused.
	got = _call(tools, "create_mapgen", {"file": "data/json/mapgen/new.json", "om_terrain": "shed"})
	_call(tools, "create_mapgen", {"file": "data/json/mapgen/new.json", "om_terrain": "barn"})
	_fails(tools, "undo", {"id": "shed"}, "something was added")
	_cleanup()


# --- UI ----------------------------------------------------------------------------

func test_main_scene() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m: Variant = main.open_id("own")
	if not check(m != null, "open own"):
		main.free()
		return
	var legend: LegendPanel = main._legend
	legend.select_key("#")
	check(legend.own_state().contains("isn't defined in the map itself"), "own state: " + legend.own_state())
	check(legend._rename_button.disabled)
	legend.select_key("k")
	check(not legend._rename_button.disabled and not legend._remove_button.disabled)
	legend.open_rename_dialog()
	check(legend.rename_dialog.visible)
	legend.rename_edit.text = "#"
	legend._update_rename()
	check(legend.rename_dialog.get_ok_button().disabled, legend._rename_info.text)
	legend.rename_edit.text = "m"
	legend._update_rename()
	check(not legend.rename_dialog.get_ok_button().disabled, "ok enabled: " + legend._rename_info.text)
	legend.rename_dialog.confirmed.emit()
	check_eq(m.doc.object().terrain.keys(), ["m", "o"])
	check_eq(m.brush, "m", "the brush follows")
	check_eq(m.ascii.resolved.cells[1][1], "m", "redrawn")
	check(main._status.text.contains("Renamed 'k' to 'm'"), "main status: " + main._status.text)
	main.undo()
	check_eq(m.doc.object().terrain.keys(), ["k", "o"])
	legend.select_key("k")
	check_eq(legend.remove_selected(), "")
	check(main._status.text.contains("undefined now"), "main status: " + main._status.text)
	main.undo()

	# The overmap_terrain auto-fix is an undo step of the map.
	main.add_missing_overmap_terrain()
	check_eq(m.doc.undo_name(), "Add overmap_terrain own")
	main.undo()
	check_eq(main._status.text, "Undid Add overmap_terrain own")
	check(not main.session.is_dirty(MAPS))

	# The palette editor: rename a key others use (asks), delete a palette.
	main.open_palette_editor("pal")
	var ed: PaletteEditor = main._palette_editor
	ed.show_key("h")
	check(not ed._rename_button.disabled)
	ed.open_rename_dialog()
	ed.rename_edit.text = "t"
	ed._update_rename()
	check(ed.rename_dialog.get_ok_button().disabled, "ed info: " + ed._rename_info.text)
	check_eq(ed.rename_key("m"), "")
	check(ed.confirm.visible, "asks first")
	check(ed.confirm.dialog_text.contains("repaints 3 maps") and ed.confirm.dialog_text.contains("changes how 2 maps"),
			ed.confirm.dialog_text)
	ed.confirm.confirmed.emit()
	check_eq(ed.doc.own_keys(), PackedStringArray(["#", ".", "m", "t"]))
	check(ed.status.text.contains("repainted 3 maps"), "ed status: " + ed.status.text)
	check_eq(ed.key_edit.text, "m")
	check(main._all_dirty().has(MAPS), "quitting asks about the maps")
	ed.undo()
	check_eq(main.session.dirty_files(), PackedStringArray())
	# Confirmed after another palette is shown: nothing happens.
	ed.show_key("h")
	check_eq(ed.rename_key("m"), "")
	ed.show_palette(main.index.palette("later"))
	ed.confirm.confirmed.emit()
	check(ed.status.text.contains("isn't shown any more"), "ed status: " + ed.status.text)
	check_eq(main.session.dirty_files(), PackedStringArray())
	ed.show_palette(main.index.palette("lonely"))
	# Enter in the rename dialog renames (lonely's 'z' is used by nothing).
	ed.show_key("z")
	ed.open_rename_dialog()
	ed.rename_edit.text = "Z"
	ed._update_rename()
	ed.rename_edit.text_submitted.emit("Z")
	check(not ed.rename_dialog.visible)
	check_eq(ed.doc.own_keys(), PackedStringArray(["Z"]))
	ed.undo()

	ed.show_palette(main.index.palette("pal"))
	check(ed.ask_delete_palette().contains("stop using it first"))
	ed.show_palette(main.index.palette("doomed"))
	check_eq(ed.ask_delete_palette(), "")
	check(ed.confirm.visible and ed.confirm.dialog_text.contains("Delete palette doomed"))
	ed.confirm.confirmed.emit()
	check(ed.doc == null)
	check(main.index.palette("doomed") == null)
	check(not ed._undo_button.disabled and not ed._save_button.disabled)
	var listed := PackedStringArray()
	for i in ed.palette_list.item_count:
		listed.append(ed.palette_list.get_item_text(i))
	check(not listed.has("doomed"), str(listed))
	ed.undo()
	check(ed.doc != null and ed.doc.id == "doomed", "restored and shown")
	check(not main.session.is_dirty(MIXED))
	main.free()


# --- The accept, on BN's data ------------------------------------------------------

## Top-level object texts of [param path], by index.
static func _object_texts(path: String) -> PackedStringArray:
	var bytes := FileAccess.get_file_as_bytes(path)
	var parsed := BnJson.parse_bytes(bytes)
	var out := PackedStringArray()
	for span: Vector2i in parsed.spans:
		out.append(bytes.slice(span.x, span.y).get_string_from_utf8())
	return out


## Renaming a core palette key in a temp workspace repaints every map
## taking it from the palette, and each file's other objects stay
## byte-identical. Deleting an unused palette from the middle of a core
## file keeps the objects around it byte-identical.
func test_accept_bn() -> void:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return
	var ws := TempTree.make({})
	var index := DataIndex.load_bn(bn, PackedStringArray(), null, ws)
	var session := EditSession.new(index, Workspace.open(ws, bn))
	var pal := session.open_palette(index.palette("state_police"))
	if not check(pal != null, session.last_error):
		TempTree.remove(ws)
		return
	# A key the maps paint, and a free key to rename it to.
	var plan: PaletteImpact.RenamePlan
	var old := ""
	for key in pal.own_keys():
		var p := PaletteImpact.plan_rename(session, pal, key, "Ж")
		if p.problem.is_empty() and p.repainted.size() >= 2:
			plan = p
			old = key
			break
	if not check(plan != null, "a state_police key two maps paint"):
		TempTree.remove(ws)
		return
	check_eq(plan.changed, [] as Array[PaletteImpact.Affected], "no map looks different")
	# Every map using the palette whose rows use the key.
	var expected := PackedStringArray()
	for ref in index.maps_using("state_police"):
		var o := session.objects.object_for(ref)
		if MapgenResolver.resolve(index, o).used_keys().has(old):
			expected.append(ref.title())
	expected.sort()
	check_eq(_titles(plan.repainted), expected)
	var rows_before := {}
	for a in plan.repainted:
		rows_before[a.ref] = session.objects.object_for(a.ref).object.rows.duplicate()
	check_eq(session.rename_palette_key(pal, plan), "")
	for a in plan.repainted:
		var rows: Array = session.open(a.ref).object().rows
		var want: Array = rows_before[a.ref].map(func(r: String) -> String: return r.replace(old, "Ж"))
		check_eq(rows, want, "%s: only the key's cells change" % a.ref.title())

	# Delete an unused palette in the middle of a file.
	var fema := index.palette("FEMA_camp_interior")
	check_eq(session.check_delete_palette(fema), "")
	var fema_rel := fema.source.path
	var fema_at := fema.source.index
	check_eq(session.delete_palette(fema), "")

	check_eq(session.save_all(), PackedStringArray())
	var touched := {}
	for a in plan.repainted:
		touched["%s#%d" % [a.ref.source.path, a.ref.source.index]] = true
	touched["%s#%d" % [pal.file.rel_path, pal.object_index]] = true
	var saved_files := PackedStringArray([pal.file.rel_path, fema_rel])
	for a in plan.repainted:
		if not saved_files.has(a.ref.source.path):
			saved_files.append(a.ref.source.path)
	for rel in saved_files:
		var before := _object_texts(bn.path_join(rel))
		var after := _object_texts(ws.path_join(rel))
		if rel == fema_rel:
			before.remove_at(fema_at)
		if not check_eq(after.size(), before.size(), rel):
			continue
		var same := 0
		for i in before.size():
			if touched.has("%s#%d" % [rel, i]):
				check(after[i] != before[i], "%s #%d changed" % [rel, i])
			elif check(after[i] == before[i], "%s #%d byte-identical" % [rel, i]):
				same += 1
		print("     %s: %d of %d objects byte-identical" % [rel, same, before.size()])
	TempTree.remove(ws)

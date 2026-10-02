extends "res://tests/support/test_case.gd"
## Palette editing (PaletteDocument, PaletteImpact, EditSession, the reverse
## palette index) against a small fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

const HOUSE := "data/json/mapgen/house.json"
const PALETTES := "data/json/mapgen_palettes/pal.json"

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


func _setup(extra := {}) -> void:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt", "t_rock"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/mods/other/modinfo.json": [{"type": "MOD_INFO", "id": "other", "dependencies": ["bn"]}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
		],
		PALETTES: [
			{"type": "palette", "id": "pal", "terrain": {"#": "t_wall", ".": "t_floor"},
				"furniture": {"h": "f_chair"}, "items": {"h": {"item": "junk", "chance": 5}}},
			{"type": "palette", "id": "inner", "terrain": {"#": "t_rock"}},
			{"type": "palette", "id": "outer", "palettes": ["inner"], "terrain": {".": "t_dirt"}},
			{"type": "palette", "id": "other", "terrain": {"#": "t_dirt", ".": "t_dirt", "o": "t_dirt"}},
		],
		# A palette defined inside a mapgen file, used by both maps there.
		HOUSE: [
			_map("house", ["pal", "house_pal"]),
			{"type": "palette", "id": "house_pal", "furniture": {"x": "f_table"}, "toilets": {"x": {}}},
			_map("house_2", ["house_pal"], "x"),
		],
		"data/json/mapgen/others.json": [
			# Through an include.
			_map("shed", ["outer"]),
			# As the second option of a distribution.
			_map("cabin", [{"distribution": [["other", 1], ["pal", 1]]}]),
			# Overrides '#' itself, so a palette '#' edit doesn't reach it.
			_map("bunker", ["pal"], ".", {"terrain": {"#": "t_rock"}}),
			# Uses pal but never 'h'... nor '#': rows of 'o' only.
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk",
				"object": {"mapgensize": [2, 2], "rows": ["..", ".."], "palettes": ["pal"]}},
			_map("plain", []),
		],
	}
	files.merge(extra, true)
	# TempTree's JSON.stringify sorts keys; keep them as written.
	for rel: String in files:
		if not files[rel] is String:
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


func _titles(refs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Variant in refs:
		out.append((r.ref if r is PaletteImpact.Affected else r).title())
	out.sort()
	return out


func _open_palette(session: EditSession, id: String) -> PaletteDocument:
	var doc := session.open_palette(_index.palette(id))
	check(doc != null, "open palette %s: %s" % [id, session.last_error])
	return doc


func test_reverse_index() -> void:
	_setup()
	check_eq(_titles(_index.maps_using("pal")), PackedStringArray(["bunker", "cabin", "chunk", "house"]))
	check_eq(_titles(_index.maps_using("inner")), PackedStringArray(["shed"]), "through outer")
	check_eq(_titles(_index.maps_using("house_pal")), PackedStringArray(["house", "house_2"]))
	check_eq(_titles(_index.maps_using("nope")), PackedStringArray())
	check_eq(_index.palette_closure(PackedStringArray(["outer"])), PackedStringArray(["outer", "inner"]))
	var cabin: DataIndex.MapgenRef = _index.mapgens_for("cabin")[0]
	check_eq(cabin.palettes, PackedStringArray(["other", "pal"]), "every option")
	_cleanup()


func test_resolve_variants() -> void:
	_setup()
	var cabin := _index.read_object(_index.mapgens_for("cabin")[0].source)
	var variants := MapgenResolver.resolve_variants(_index, cabin)
	check_eq(variants.size(), 2)
	check_eq(variants[0].palettes, PackedStringArray(["other"]))
	check_eq(variants[1].palettes, PackedStringArray(["pal"]))
	check_eq(variants[0].choice_options, [PackedStringArray(["other", "pal"])] as Array[PackedStringArray])
	check_eq(variants[1].symbols["#"].terrain.id(), "t_wall")

	# 'h' comes only from the second option, but BN adds it too.
	var session := _session()
	var doc := session.open(_index.mapgens_for("cabin")[0])
	check(not doc.resolved.symbols.has("h"), "not in the displayed option")
	check(doc.check_new_key("h").contains("another option"), doc.check_new_key("h"))
	check_eq(doc.check_new_key("q"), "")
	_cleanup()


func test_edit_undo_is_byte_identical() -> void:
	_setup()
	var session := _session()
	var doc := _open_palette(session, "pal")
	if doc == null:
		_cleanup()
		return
	var f := doc.file
	var original := f.compose()
	check_eq(doc.tile_value("h", "furniture"), "f_chair")
	check_eq(doc.own_keys(), PackedStringArray(["#", ".", "h"]))

	# Removing the last furniture drops the member; undo puts it back where it was.
	doc.commit(doc.build_remove_key("h"))
	check(not doc.palette().has("furniture"), "empty member removed")
	check_eq(doc.palette().keys(), ["type", "id", "terrain", "items"])
	check(f.is_dirty())
	doc.undo()
	check_eq(doc.palette().keys(), ["type", "id", "terrain", "furniture", "items"], "member order restored")
	check_eq(f.compose(), original, "undo restores the original text")
	check(not f.is_dirty())
	doc.redo()
	check_eq(doc.undo_name(), "Remove 'h'")
	doc.undo()

	check_eq(doc.build_set_tiles("#", "t_wall", null), null, "no change")
	check(doc.check_tiles("#", "t_nope", null).contains("Unknown terrain"))
	check(doc.check_tiles("ab", "t_wall", null) != "", "two columns")
	var c := doc.build_set_tiles("n", "t_dirt", "f_table")
	check_eq(doc.tile_value("n", "terrain"), null, "build doesn't apply")
	doc.commit(c)
	check_eq(doc.palette().terrain, {"#": "t_wall", ".": "t_floor", "n": "t_dirt"})
	check_eq(doc.palette().furniture, {"h": "f_chair", "n": "f_table"})
	check_eq(doc.view().symbols["n"].terrain.source, ResolvedMapgen.SOURCE_MAP, "own definitions")

	doc.commit(doc.build_set_includes(["inner"]))
	check_eq(doc.palette().keys(), ["type", "id", "palettes", "terrain", "furniture", "items"],
			"palettes go before the definitions")
	check_eq(doc.view().symbols["#"].terrain.id(), "t_wall", "own definitions win over includes")
	check_eq(_index.palette_closure(PackedStringArray(["pal"])), PackedStringArray(["pal", "inner"]),
			"the index sees the live object")
	doc.undo()
	doc.undo()
	check_eq(f.compose(), original)
	_cleanup()


## A "mapping" entry is edited where it's written.
func test_mapping_entries() -> void:
	_setup({"data/json/mapgen_palettes/m.json": [{"type": "palette", "id": "m",
		"mapping": {"z": {"terrain": "t_floor", "items": {"item": "junk"}}}}]})
	var session := _session()
	var doc := _open_palette(session, "m")
	if doc == null:
		_cleanup()
		return
	check_eq(doc.tile_value("z", "terrain"), "t_floor")
	doc.commit(doc.build_set_tiles("z", "t_dirt", "f_chair"))
	check_eq(doc.palette().mapping, {"z": {"terrain": "t_dirt", "items": {"item": "junk"}}})
	check_eq(doc.palette().furniture, {"z": "f_chair"}, "a kind the mapping lacks goes in the plain member")
	doc.commit(doc.build_set_tiles("z", "", null))
	check_eq(doc.palette().mapping, {"z": {"items": {"item": "junk"}}})
	_cleanup()


## Editing a palette redraws the open maps that use it, in the same file
## or not, and leaves the others alone; undo restores them.
func test_open_maps_follow_palette() -> void:
	_setup()
	var session := _session()
	var house := session.open(_index.mapgens_for("house")[0])
	var house_2 := session.open(_index.mapgens_for("house_2")[0])
	var plain := session.open(_index.mapgens_for("plain")[0])
	var doc := _open_palette(session, "house_pal")
	if doc == null or house == null:
		_cleanup()
		return
	check(doc.file == house.file, "one JsonFile for the maps and the palette")
	var refreshed := {}
	for d: MapDocument in [house, house_2, plain]:
		var on_changed := func(full: bool, title: String) -> void: refreshed[title] = full
		d.changed.connect(on_changed.bind(d.ref.title()))
	doc.commit(doc.build_set_tiles("x", null, "f_chair"))
	check_eq(refreshed, {"house": true, "house_2": true}, "full redraw of the users only")
	check_eq(house_2.resolved.furniture_at(1, 1).id(), "f_chair")
	check(house.file.is_dirty())
	check(house.file.is_original(0) and house.file.is_original(2), "the maps' objects are untouched")
	doc.undo()
	check_eq(house_2.resolved.furniture_at(1, 1).id(), "f_table", "undo")
	check(not house.file.is_dirty())

	# The file stays open while the palette is, and the other way round.
	doc.commit(doc.build_set_tiles("x", null, "f_chair"))
	session.close(house)
	session.close(house_2)
	check(session.files.has(HOUSE), "the palette keeps the file open")
	check_eq(session.open_count(HOUSE), 1)
	session.close_palette(doc)
	check(not session.files.has(HOUSE), "dropped with its last document")
	var data: Dictionary = _index.palette("house_pal").data
	check_eq(data.furniture.x, "f_table", "discarding puts the index back as on disk")
	var r := MapgenResolver.resolve(_index, _index.read_object(_index.mapgens_for("house_2")[0].source))
	check_eq(r.furniture_at(1, 1).id(), "f_table")
	_cleanup()


func test_impact() -> void:
	_setup()
	var session := _session()
	var doc := _open_palette(session, "pal")
	if doc == null:
		_cleanup()
		return
	var wall := session.impact_of(doc, doc.build_set_tiles("#", "t_dirt", null))
	# bunker overrides '#', chunk doesn't use it; cabin gets it from its
	# second option; house lists house_pal after pal, which doesn't define '#'.
	check_eq(_titles(wall), PackedStringArray(["cabin", "house"]))
	check_eq(wall[0].keys, PackedStringArray(["#"]))
	check_eq(doc.palette().terrain["#"], "t_wall", "measuring leaves the edit undone")

	var floor := session.impact_of(doc, doc.build_set_tiles(".", "t_dirt", null))
	check_eq(_titles(floor), PackedStringArray(["bunker", "cabin", "chunk", "house"]))
	check_eq(session.impact_of(doc, doc.build_set_tiles("q", "t_dirt", null)), [] as Array[PaletteImpact.Affected],
			"an unused new key changes no map")

	# An include edit: inner's '#' now reaches pal's users, but pal's own '#' wins.
	var inc := session.impact_of(doc, doc.build_set_includes(["other"]))
	check_eq(_titles(inc), PackedStringArray(), "pal defines # and . itself")
	var outer := _open_palette(session, "outer")
	check_eq(_titles(session.impact_of(outer, outer.build_set_includes([]))), PackedStringArray(["shed"]))

	# Unsaved edits in an open map count.
	var chunk := session.open(_index.mapgens_for("chunk")[0])
	chunk.paint([Vector2i(0, 0)], "#")
	check_eq(_titles(session.impact_of(doc, doc.build_set_tiles("#", "t_dirt", null))),
			PackedStringArray(["cabin", "chunk", "house"]))
	_cleanup()


func test_move_symbol() -> void:
	_setup()
	var session := _session()
	var house := session.open(_index.mapgens_for("house")[0])
	var pal := _open_palette(session, "pal")
	var house_pal := _open_palette(session, "house_pal")
	if house == null or pal == null:
		_cleanup()
		return
	check_eq(house.add_symbol("k", "t_dirt", "f_table"), "")
	house.paint([Vector2i(2, 2)], "k")
	check_eq(house.own_keys(), PackedStringArray(["k"]))
	check(session.check_move_symbol(house, pal, "q").contains("isn't defined"))
	check(session.check_move_symbol(house, _open_palette(session, "outer"), "k").contains("doesn't use"))
	check_eq(session.check_move_symbol(house, house_pal, "k"), "")

	# house is the only user of house_pal with 'k' in its rows, and it keeps its look.
	check_eq(session.move_symbol_impact(house, house_pal, "k"), [] as Array[PaletteImpact.Affected])
	var before := house.resolved.key_signature("k")
	check_eq(session.move_symbol(house, house_pal, "k"), "")
	check_eq(house.own_keys(), PackedStringArray())
	check(not house.object().has("terrain") and not house.object().has("furniture"), "empty members go")
	check_eq(house_pal.palette().terrain, {"k": "t_dirt"})
	check_eq(house_pal.palette().furniture, {"x": "f_table", "k": "f_table"})
	check_eq(house.resolved.key_signature("k"), before, "the map looks the same")
	check_eq(house.resolved.symbols["k"].terrain.source, "house_pal")
	check_eq(house.undo_name(), "Move 'k' from house to house_pal")
	house.undo()
	house_pal.undo()
	check_eq(house.own_keys(), PackedStringArray(["k"]))
	check(not house_pal.palette().has("terrain"))
	_cleanup()


func test_map_palette_list() -> void:
	_setup()
	var session := _session()
	var plain := session.open(_index.mapgens_for("plain")[0])
	if plain == null:
		_cleanup()
		return
	var original := BnJson.stringify(plain.mapgen())
	check(not plain.uses_palette("pal"))
	plain.add_palette("pal")
	check(plain.uses_palette("pal"))
	check_eq(plain.resolved.symbols["#"].terrain.source, "pal")
	check(_titles(_index.maps_using("pal")).has("plain"), "the reverse index follows")
	plain.remove_palette("pal")
	check(not plain.object().has("palettes"), "an empty list goes")
	plain.undo()
	plain.undo()
	check_eq(BnJson.stringify(plain.mapgen()), original, "undo")
	check(not plain.file.is_dirty())
	plain.add_palette("outer")
	session.close(plain)
	check(not _titles(_index.maps_using("outer")).has("plain"), "discarding restores the reverse index")
	_cleanup()


func test_create_palette() -> void:
	_setup()
	var session := _session()
	check_eq(session.default_palette_path("mine"), "data/json/mapgen_palettes/mine.json")
	check(session.check_new_palette(PALETTES, "pal").contains("already exists"))
	check(session.check_new_palette("elsewhere/x.json", "mine").contains("isn't inside"))
	check(session.check_new_palette(PALETTES, "a b") != "")
	var doc := session.create_palette(PALETTES, "mine")
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	check_eq(doc.object_index, 4)
	check(_index.palette("mine") == doc.def)
	doc.commit(doc.build_set_tiles("m", "t_dirt", null))
	var plain := session.open(_index.mapgens_for("plain")[0])
	plain.add_palette("mine")
	plain.paint([Vector2i(3, 3)], "m")
	check_eq(plain.resolved.terrain_at(3, 3).id(), "t_dirt")
	check_eq(plain.resolved.terrain_at(3, 3).source, "mine")
	# Discarding drops the new palette from the index.
	session.close(plain)
	session.close_palette(doc)
	check(_index.palette("mine") == null)

	doc = session.create_palette("data/json/mapgen_palettes/new.json", "mine")
	doc.commit(doc.build_set_tiles("m", "t_dirt", "f_chair"))
	check_eq(session.save(doc.file.rel_path), "")
	check_eq(FileAccess.get_file_as_string(_ws.path_join("data/json/mapgen_palettes/new.json")),
			"[\n  {\n    \"type\": \"palette\",\n    \"id\": \"mine\",\n    \"terrain\": { \"m\": \"t_dirt\" },\n    \"furniture\": { \"m\": \"f_chair\" }\n  }\n]\n")
	session.close_palette(doc)
	check(_index.palette("mine") != null, "saved, so it stays")
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.palette("mine").data.terrain, {"m": "t_dirt"}, "loads from the workspace")
	_cleanup()


## A mod's palette with the same id replaces the core one.
func test_overridden_palette() -> void:
	_setup({"data/mods/other/pal.json": [{"type": "palette", "id": "pal", "terrain": {"#": "t_rock"}}]})
	_index = DataIndex.load_bn(_root, PackedStringArray(["other"]), null, _ws)
	var session := _session()
	var core_def: DataIndex.Definition = _index.palettes["pal"][0]
	var doc := session.open_palette(core_def)
	if not check(doc != null, session.last_error):
		_cleanup()
		return
	check_eq(doc.overridden_by().source.mod, "other")
	check_eq(session.impact_of(doc, doc.build_set_tiles("#", "t_dirt", null)), [] as Array[PaletteImpact.Affected],
			"editing the replaced one changes no map")
	var mod_doc := session.open_palette(_index.palette("pal"))
	check(mod_doc.overridden_by() == null)
	check_eq(session.default_palette_path("x", "data/mods/other/pal.json"), "data/mods/other/mapgen_palettes/x.json")
	_cleanup()


## The palette editor window, driven through the main scene.
func test_main_scene_palette_editor() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m: Variant = main.open_id("house_2")
	if not check(m != null, "open house_2"):
		main.free()
		return
	var ed: PaletteEditor = main._palette_editor
	main._legend.select_key("x")
	main._legend._selected = "x"
	check_eq(main._legend.selected_palette(), "house_pal")
	main.open_palette_editor(main._legend.selected_palette())
	check(ed.doc != null and ed.doc.id == "house_pal", "opened at the symbol's palette")
	check(ed.map_doc == m.doc, "knows the current map")
	var listed := PackedStringArray()
	for i in ed.palette_list.item_count:
		listed.append(ed.palette_list.get_item_text(i))
	check_eq(listed, PackedStringArray(["house_pal", "inner", "other", "outer", "pal"]))
	check_eq(ed.users.item_count, 2, "house and house_2")
	check(ed._header.text.contains("share this file"), ed._header.text)

	# Pick 'x' in the symbol tree: the pickers show its values.
	var item: TreeItem = ed.symbols.get_root().get_first_child()
	while item and item.get_metadata(0) != "x":
		item = item.get_next()
	item.select(0)
	check_eq(ed.key_edit.text, "x")
	check_eq(ed.furniture.selected(), "f_table")
	check_eq(ed.terrain.selected(), "", "no terrain")

	# Only the current map uses 'x': applied without asking, and redrawn.
	ed.furniture.select_id("f_chair")
	ed.apply_edit()
	check(not ed.confirm.visible, "no other map changes")
	check_eq(m.doc.resolved.furniture_at(1, 1).id(), "f_chair")
	check_eq(m.ascii.char_at(1, 1), "h", "the canvas data is redrawn")
	check(main._tabs.get_tab_title(0).ends_with(" *"), main._tabs.get_tab_title(0))
	check(ed.status.text.contains("changes 1 map"), ed.status.text)
	ed.undo()
	check_eq(m.ascii.char_at(1, 1), "t", "undo redraws")
	check(not main._tabs.get_tab_title(0).ends_with(" *"))

	# pal is used by other maps: the edit waits for a confirmation.
	ed.show_palette(main.index.palette("pal"))
	ed.key_edit.text = "#"
	ed.terrain.select_id("t_dirt")
	ed.furniture.select_id(NewSymbolDialog.IdPicker.KEEP)
	ed.apply_edit()
	check(ed.confirm.visible, "asks first")
	check(ed.confirm.dialog_text.contains("cabin") and ed.confirm.dialog_text.contains("house"), ed.confirm.dialog_text)
	check_eq(ed.doc.tile_value("#", "terrain"), "t_wall", "not applied yet")
	ed.confirm.confirmed.emit()
	check_eq(ed.doc.tile_value("#", "terrain"), "t_dirt")
	ed.undo()
	check(not ed.doc.file.is_dirty())

	# Includes.
	ed.include_edit.text = "inn"
	ed.include_completer.update()
	check_eq(ed.include_completer.list.get_item_text(0), "inner", "palette ids suggested")
	ed.include_completer.accept(0)
	check_eq(ed.doc.includes(), ["inner"])
	check_eq(ed.includes.item_count, 1)
	ed.include_edit.text = "pal"
	ed.add_include()
	check(ed.status.text.contains("loop") or ed.doc.includes().size() == 1, ed.status.text)
	ed.undo()

	# A new palette, used in the map, gets a symbol moved into it.
	check_eq(m.doc.add_symbol("k", "t_dirt", ""), "")
	m.doc.paint([Vector2i(2, 2)] as Array[Vector2i], "k")
	ed.open_new_dialog()
	ed.new_id.text = "fresh"
	ed._update_new_path()
	check_eq(ed.new_path.text, "data/json/mapgen_palettes/fresh.json")
	check(not ed.new_dialog.get_ok_button().disabled, ed._new_info.text)
	check_eq(ed.create_palette(), "")
	check_eq(ed.doc.id, "fresh")
	ed.toggle_use_in_map()
	check(m.doc.palette_list().has("fresh"))
	check(ed._use_button.text.begins_with("Stop using"))
	check_eq(ed.move_keys.item_count, 1)
	ed.move_symbol()
	check_eq(ed.doc.tile_value("k", "terrain"), "t_dirt")
	check_eq(m.doc.own_keys(), PackedStringArray())
	check_eq(m.doc.resolved.terrain_at(2, 2).source, "fresh")
	check(main._all_dirty().has("data/json/mapgen_palettes/fresh.json"), "quitting asks about it")

	ed.save()
	check(FileAccess.file_exists(_ws.path_join("data/json/mapgen_palettes/fresh.json")), ed.status.text)
	main.free()

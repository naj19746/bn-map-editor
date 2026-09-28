extends "res://tests/support/test_case.gd"
## Placements (Placement, MapDocument's placement edits, PlacementTool, the
## Placements panel and canvas overlay) against a small fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _ws := ""
var _index: DataIndex


## A 2x2 map ("tower", 48x48) whose placements cover BN's odd cases, a 1x1
## map without placements ("lawn") and a 5x5 nested chunk.
func _setup() -> void:
	var tower := {
		"type": "mapgen", "method": "json",
		"om_terrain": [["tower_nw", "tower_ne"], ["tower_sw", "tower_se"]],
		"object": {
			"fill_ter": "t_floor",
			"place_items": [
				{"item": "stuff", "x": [0, 23], "y": [24, 47], "chance": 50},
				{"item": "stuff", "x": [31, 16], "y": 5, "chance": 5, "repeat": [1, 3]},
				{"item": "stuff", "x": 50, "y": 5},
				{"item": "stuff", "x": [20, 30], "y": [3], "chance": 0},
			],
			"place_monsters": [{"monster": "GROUP_ZOMBIE", "x": [24, 47], "y": [0, 23], "chance": 10}],
			"set": [
				{"point": "terrain", "id": "t_wall", "x": 3, "y": 4},
				{"square": "terrain", "id": "t_wall", "x": 5, "y": 5, "x2": 7, "y2": 6},
				{"point": "terrain", "id": "t_wall", "x": 30, "y": 4},
			],
			"place_vehicles": [{"vehicle": "car", "x": 10, "y": 10, "rotation": 90}],
		},
	}
	var chunk := {
		"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk",
		"object": {
			"mapgensize": [5, 5], "rows": ["#####", "#...#", "#...#", "#...#", "#####"],
			"terrain": {"#": "t_wall", ".": "t_floor"},
			"place_items": [{"item": "stuff", "x": [0, 10], "y": 1, "chance": 20}],
			"set": [{"point": "terrain", "id": "t_floor", "x": 6, "y": 1}],
		},
	}
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_wall", "symbol": "#", "color": "white"},
			{"type": "terrain", "id": "t_grass", "symbol": ".", "color": "green"},
			{"type": "overmap_terrain", "id": ["tower_nw", "tower_ne", "tower_sw", "tower_se", "lawn"], "name": "x"},
			{"type": "item_group", "id": "stuff", "items": []},
			{"type": "monstergroup", "name": "GROUP_ZOMBIE", "monsters": []},
			{"type": "MONSTER", "id": "mon_zombie"},
			{"type": "MONSTER", "id": "mon_dog"},
			{"type": "GENERIC", "id": "rock"},
			{"type": "item_group", "id": "rocks_pile", "items": []},
			{"type": "palette", "id": "pal", "terrain": {"x": "t_grass"}, "items": {"x": {"item": "stuff", "chance": 5}}},
		],
		# Written in key order (TempTree's JSON.stringify would sort keys).
		"data/json/mapgen/tower.json": JSON.stringify([tower,
			{"type": "mapgen", "method": "json", "om_terrain": "lawn",
				"object": {"fill_ter": "t_grass", "rows": _rows(), "palettes": ["pal"]}},
			chunk], " ", false),
	}
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
		rows.append("x".repeat(24) if y == 3 else " ".repeat(24))
	return rows


func _session() -> EditSession:
	return EditSession.new(_index, Workspace.open(_ws, _root))


func _open(session: EditSession, id: String) -> MapDocument:
	var doc := session.open(_index.mapgens_for(id)[0])
	check(doc != null, "open %s: %s" % [id, session.last_error])
	return doc


func _by_title(doc: MapDocument) -> Dictionary:
	var out := {}
	for p in doc.placements():
		out[p.title()] = p
	return out


func test_range_forms() -> void:
	var R := Placement.IntRange
	for v: Variant in [5, [5], [1, 3], [3, 1]]:
		check_eq(R.parse(v).to_json(), v, "round trip " + str(v))
	check_eq(R.parse([5]).second, 5, "x/y [n] is n..n")
	check_eq(R.parse([3], 1, 1, false).second, 1, "repeat [3] is 3..default (1-3 once swapped)")
	check_eq(R.parse(null, 1, 1).form, R.Form.MISSING)
	check_eq(R.parse("a").form, R.Form.INVALID)
	check_eq(R.parse([1, 2, 3]).form, R.Form.INVALID)
	check_eq(R.parse(4.0).to_json(), 4, "a float read by Godot's JSON counts as an int")
	check_eq(R.parse([31, 16]).lo(), 16)
	check_eq(R.parse([31, 16]).spanning(2, 9).to_json(), [9, 2], "a reversed range stays reversed")
	check_eq(R.parse(7).spanning(4, 4).to_json(), 4, "one cell stays an int")
	check_eq(R.parse([7]).spanning(4, 4).to_json(), [4], "and [n] stays [n]")
	check_eq(R.parse(7).spanning(4, 6).to_json(), [4, 6], "grown into a range")
	check_eq(R.parse([2, 5]).shifted(3).to_json(), [5, 8])


func test_read_follows_bn() -> void:
	_setup()
	var doc := _open(_session(), "tower_nw")
	var ps := _by_title(doc)
	var ok: Placement = ps["place_items #1"]
	check_eq(ok.status, Placement.Status.OK)
	check_eq(ok.anchor_omt, Vector2i(0, 1))
	check_eq(ok.label(), "I 50%")
	var back: Placement = ps["place_items #2"]
	check_eq(back.status, Placement.Status.SPANS_BACK, "reversed range reaching into the previous tile")
	check_eq(back.anchor_omt, Vector2i(1, 0), "anchored at its first value")
	check_eq(back.span(), Rect2i(16, 5, 16, 1), "drawn with the span BN uses")
	check_eq(back.label(), "I 5% x1-3")
	check_eq(ps["place_items #3"].status, Placement.Status.DROPPED, "anchored outside the map")
	check_eq(ps["place_items #4"].status, Placement.Status.CROSSES, "range leaves its tile")
	check(ps["place_items #4"].problems.size() == 2, "and chance 0 places nothing: %s" % ps["place_items #4"].problems)
	check_eq(ps["place_monsters #1"].label(), "M 1/10", "one in N")
	check_eq(ps["place_vehicles #1"].label(), "V 1%", "vehicles default to 1%")
	check_eq(ps["place_vehicles #1"].layer(), Placement.Layer.VEHICLES)

	var point: Placement = ps["set #1"]
	check_eq(point.status, Placement.Status.OK)
	check_eq(point.instances(), [Rect2i(3, 4, 1, 1), Rect2i(27, 4, 1, 1), Rect2i(3, 28, 1, 1),
			Rect2i(27, 28, 1, 1)] as Array[Rect2i], "a set entry runs in every tile")
	check_eq(ps["set #2"].span(), Rect2i(5, 5, 3, 2), "a square covers x..x2, y..y2")
	var far: Placement = ps["set #3"]
	check_eq(far.status, Placement.Status.DROPPED, "a set coordinate past 23 runs in no tile")
	check_eq(far.instances(), [Rect2i(30, 4, 1, 1)] as Array[Rect2i], "drawn where it's written")

	check_eq(doc.save_problems().size(), 1, "the crossing range blocks saving")
	check(doc.problems().size() >= 5, "placement problems are listed: %s" % doc.problems())
	_cleanup()


func test_chunk_bounds() -> void:
	_setup()
	var doc := _open(_session(), "chunk")
	var ps := _by_title(doc)
	check_eq(ps["place_items #1"].status, Placement.Status.OUTSIDE_CHUNK,
			"place_* in a chunk is bounded by 24x24, so this loads but runs past the chunk")
	check_eq(ps["set #1"].status, Placement.Status.DROPPED, "set uses the real mapgensize")
	check_eq(doc.check_placement("place_items", 1, {"item": "stuff", "x": 30, "y": 1}),
			"place_items #2 is anchored at (30, 1), outside the map, so BN drops it")
	_cleanup()


func test_symbol_extras_marked() -> void:
	_setup()
	var doc := _open(_session(), "lawn")
	var info: ResolvedMapgen.SymbolInfo = doc.resolved.symbols["x"]
	check_eq(Placement.mapping_layers(info), 1 << Placement.Layer.ITEMS)
	var a := AsciiMap.build(_index, doc.resolved)
	check_eq(a.look_for("x").layers, 1 << Placement.Layer.ITEMS, "the look carries it for the canvas")
	check_eq(doc.placements().size(), 0)
	_cleanup()


## Edits change only the entry, keep field order and forms, and undo gives
## back the exact object (so the file is written as its original text).
func test_edit_and_undo() -> void:
	_setup()
	var doc := _open(_session(), "tower_nw")
	var original := BnJson.stringify(doc.mapgen())
	var obj := doc.object()

	check_eq(doc.set_placement_fields("place_items", 0, {"chance": 75, "repeat": [2, 4]}), "")
	check_eq(obj.place_items[0].keys(), ["item", "x", "y", "chance", "repeat"], "new field after chance")
	check_eq(obj.place_items[0].chance, 75)
	check_eq(doc.placement("place_items", 0).label(), "I 75% x2-4")
	check_eq(doc.set_placement_fields("place_items", 0, {"repeat": null}), "")
	check(not obj.place_items[0].has("repeat"), "null removes a field")
	check_eq(doc.set_placement_fields("place_items", 0, {"x": [20, 30]}),
			"place_items #1: its range leaves overmap tile (0, 1); BN refuses to load the map (\"coordinate range cannot cross grid boundaries\")")
	check_eq(obj.place_items[0].x, [0, 23], "refused edit leaves the entry")
	check_eq(doc.set_placement_fields("place_items", 2, {"chance": 3}), "",
			"an entry BN drops can still be edited in place")

	# Move the reversed range: it keeps its order and lands in one tile.
	check_eq(doc.place_at("place_items", 1, Rect2i(26, 7, 16, 1), true), "")
	check_eq(obj.place_items[1].x, [41, 26])
	check_eq(obj.place_items[1].y, 7)
	check_eq(doc.placement("place_items", 1).status, Placement.Status.OK)

	# A new list goes after the others; deleting its last entry removes it.
	check_eq(doc.add_placement("place_loot", Placement.template("place_loot", Rect2i(2, 3, 1, 1))), "")
	check_eq(obj.keys()[-1], "place_loot")
	check_eq(obj.place_loot, [{"group": "", "x": 2, "y": 3}])
	check_eq(doc.add_placement("place_loot", {"group": "g", "x": 60, "y": 3}),
			"place_loot #2 is anchored at (60, 3), outside the map, so BN drops it")
	doc.remove_placement("place_loot", 0)
	check(not obj.has("place_loot"), "emptied list removed")

	# Set entries move within their tile, in tile coordinates.
	check_eq(doc.place_at("set", 1, Rect2i(30, 10, 3, 2), true, 1), "")
	check_eq([obj.set[1].x, obj.set[1].y, obj.set[1].x2, obj.set[1].y2], [6, 10, 8, 11], "moved in the NE instance")

	while doc.can_undo():
		doc.undo()
	check_eq(BnJson.stringify(doc.mapgen()), original, "undo restores the exact object")
	check(doc.file.is_original(doc.object_index), "so it's written as its original text")
	check(not doc.file.is_dirty(), "and the file is clean")
	while doc.can_redo():
		doc.redo()
	check_eq(obj.keys()[-1], "place_vehicles", "redo gives the same member order")
	_cleanup()


func test_placement_edit_is_not_a_full_redraw() -> void:
	_setup()
	var doc := _open(_session(), "tower_nw")
	var fulls := []
	doc.changed.connect(func(full: bool) -> void: fulls.append(full))
	doc.set_placement_fields("place_items", 0, {"chance": 60})
	doc.undo()
	check_eq(fulls, [false, false])
	_cleanup()


## Random drags never leave a range crossing a tile boundary, and never
## touch placements that weren't dragged.
func test_tool_keeps_ranges_in_one_tile() -> void:
	_setup()
	var doc := _open(_session(), "tower_nw")
	var tool := PlacementTool.new()
	var errors := []
	tool.failed.connect(func(m: String) -> void: errors.append(m))
	var edits := [0]
	doc.changed.connect(func(_full: bool) -> void: edits[0] += 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Start from entries BN reads plainly.
	doc.remove_placement("place_items", 3)
	doc.remove_placement("place_items", 2)
	doc.remove_placement("set", 2)
	for n in 300:
		var ps := doc.placements()
		var p: Placement = ps[rng.randi_range(0, ps.size() - 1)]
		var r: Rect2i = p.instances()[rng.randi_range(0, p.instances().size() - 1)]
		var from := r.position + Vector2i(rng.randi_range(0, r.size.x - 1), rng.randi_range(0, r.size.y - 1))
		var to := Vector2i(rng.randi_range(0, 47), rng.randi_range(0, 47))
		var others := {}
		for q in ps:
			if q.member != p.member or q.index != p.index:
				others[q.title()] = BnJson.stringify(q.entry)
		tool.select(p.member, p.index)
		tool.press(doc, from, rng.randf() < 0.4)
		if tool.member != p.member or tool.index != p.index:
			continue  # a smaller placement on top was picked
		tool.move(to)
		tool.release(to)
		for q in doc.placements():
			if q.member == "place_items" and q.index == 1 and q.status == Placement.Status.SPANS_BACK:
				continue  # the reversed entry until it's first dragged
			if not check_eq(q.status, Placement.Status.OK, "%s after drag %d" % [q.title(), n]):
				return
			var tile := q.geometry.tile_of(q.span().position)
			if q.is_set():
				check(q.span().end <= Vector2i(24, 24), "set stays in tile coordinates")
			elif not check(tile.encloses(q.span()), "%s span %s in one tile" % [q.title(), q.span()]):
				return
			if others.has(q.title()):
				check_eq(BnJson.stringify(q.entry), others[q.title()], "untouched " + q.title())
	check_eq(errors, [], "no refused drags")
	check(edits[0] > 150, "drags made edits: %d" % edits[0])
	_cleanup()


func test_tool_select_create_and_click() -> void:
	_setup()
	var doc := _open(_session(), "tower_nw")
	var tool := PlacementTool.new()
	var seen := []
	tool.selection_changed.connect(func(m: String, i: int) -> void: seen.append([m, i]))
	# The vehicle point sits inside the big place_items range: the smaller wins.
	tool.press(doc, Vector2i(10, 10))
	tool.release(Vector2i(10, 10))
	check_eq([tool.member, tool.index], ["place_vehicles", 0])
	check(not doc.can_undo(), "a click changes nothing")
	# A click on the reversed range changes nothing either (it isn't normalized).
	tool.press(doc, Vector2i(20, 5))
	tool.release(Vector2i(20, 5))
	check_eq([tool.member, tool.index], ["place_items", 1])
	check(not doc.can_undo(), "still nothing")
	tool.press(doc, Vector2i(47, 47))
	check_eq(tool.member, "place_monsters" if doc.placements_at(Vector2i(47, 47)).size() else "")
	tool.cancel()
	# Hidden layers can't be picked.
	tool.layer_mask = 1 << Placement.Layer.VEHICLES
	tool.press(doc, Vector2i(20, 5))
	check_eq(tool.member, "", "items hidden")
	tool.layer_mask = 1 << Placement.Layer.ITEMS
	tool.press(doc, Vector2i(20, 5))
	check_eq(tool.member, "place_items", "items shown")
	tool.cancel()

	tool.armed = "place_monster"
	tool.press(doc, Vector2i(20, 20))
	tool.move(Vector2i(30, 22))
	check_eq(tool.preview, Rect2i(20, 20, 4, 3), "a new range is cut at its tile's edge")
	tool.release(Vector2i(30, 22))
	check_eq(tool.armed, "", "disarmed after adding")
	check_eq([tool.member, tool.index], ["place_monster", 0])
	check_eq(doc.object().place_monster, [{"monster": "", "x": [20, 23], "y": [20, 22]}])
	check_eq(seen[-1], ["place_monster", 0])
	_cleanup()


func test_save_refuses_crossing_range() -> void:
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built")
		return
	_setup()
	var session := _session()
	var doc := _open(session, "tower_nw")
	doc.set_placement_fields("place_items", 0, {"chance": 60})
	var err := session.save(doc.file.rel_path)
	check(err.contains("coordinate range cannot cross grid boundaries"), err)
	doc.remove_placement("place_items", 3)
	check_eq(session.save(doc.file.rel_path), "", "saves once it's gone")
	_cleanup()


func test_field_text() -> void:
	var P := PlacementsPanel
	check_eq(P.parse_text("1-3", "range"), [[1, 3], ""])
	check_eq(P.parse_text("[31, 16]", "xy"), [[31, 16], ""])
	check_eq(P.parse_text("5", "range"), [5, ""])
	check_eq(P.parse_text("0.1", "float"), [0.1, ""])
	check_eq(P.parse_text("2", "float"), [2, ""], "an int stays an int")
	check_eq(P.parse_text("GROUP_X", "id"), ["GROUP_X", ""])
	check_eq(P.parse_text("[[\"a\", 10]]", "id"), [[["a", 10]], ""], "a weighted list")
	check_eq(P.parse_text("", "int"), [null, ""], "empty removes the field")
	check_eq(P.parse_text("true", "bool"), [true, ""])
	check(P.parse_text("1.5", "int")[1] != "", "not an int")
	check(P.parse_text("[1, 2, 3]", "range")[1] != "", "not a range")
	check(P.parse_text("{", "json")[1] != "", "bad JSON")
	check_eq(P.value_text([1, 3], "range"), "[1, 3]")
	check_eq(P.value_text("GROUP_X", "id"), "GROUP_X")
	check_eq(P.value_text(null, "int"), "")


func test_id_completion() -> void:
	var V := Validator
	check_eq(V.field_id_kind("place_items", "item", {}), "group_or_item")
	check_eq(V.field_id_kind("place_item", "item", {}), "item")
	check_eq(V.field_id_kind("place_loot", "group", {}), "item_group")
	check_eq(V.field_id_kind("place_loot", "item", {}), "item")
	check_eq(V.field_id_kind("place_monster", "monster", {}), "monster")
	check_eq(V.field_id_kind("place_monster", "group", {}), "monster_group")
	check_eq(V.field_id_kind("place_monsters", "monster", {}), "monster_group")
	check_eq(V.field_id_kind("place_vehicles", "vehicle", {}), "vehicle_group")
	check_eq(V.field_id_kind("place_terrain", "ter", {}), "terrain")
	check_eq(V.field_id_kind("place_traps", "trap", {}), "trap")
	check_eq(V.field_id_kind("set", "id", {"point": "furniture"}), "furniture")
	check_eq(V.field_id_kind("set", "id", {"point": "radiation"}), "")
	check_eq(V.field_id_kind("place_items", "chance", {}), "")
	check_eq(V.field_id_kind("place_nested", "chunks", {}), "")

	_setup()
	check_eq(V.id_candidates(_index, "group_or_item"), PackedStringArray(["rock", "rocks_pile", "stuff"]))
	check_eq(V.id_candidates(_index, "monster"), PackedStringArray(["mon_dog", "mon_zombie"]))
	check_eq(V.id_candidates(_index, "monster_group"), PackedStringArray(["GROUP_ZOMBIE"]))
	_cleanup()

	var ids := PackedStringArray(["a_rock", "rock", "rocks_pile", "Rocky", "stuff"])
	check_eq(IdCompleter.matches(ids, "rock"), PackedStringArray(["rock", "rocks_pile", "Rocky", "a_rock"]),
			"prefix matches first, case ignored")
	check_eq(IdCompleter.matches(ids, ""), ids, "everything for no text")
	check_eq(IdCompleter.matches(ids, "ROCK", 2), PackedStringArray(["rock", "rocks_pile"]), "limited")

	var edit := LineEdit.new()
	var submitted := []
	edit.text_submitted.connect(func(t: String) -> void: submitted.append(t))
	var c := IdCompleter.new(edit, func() -> PackedStringArray: return ids)
	edit.text = "stuff"
	c.update()
	check(not c.is_open(), "closed when only the text itself matches")
	edit.text = "[\"rock\", 5]"
	c.update()
	check(not c.is_open(), "no suggestions for JSON")
	edit.text = "roc"
	c.update()
	check_eq(c.list.item_count, 4)
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	c._on_edit_input(down)
	c._on_edit_input(down)
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	c._on_edit_input(enter)
	check_eq(edit.text, "rocks_pile", "Down, Down, Enter takes the second")
	check_eq(submitted, ["rocks_pile"], "and submits it")
	check(not c.is_open())
	edit.free()


func test_main_scene_placements() -> void:
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built")
		return
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m: Variant = main.open_id("tower_nw")
	if not check(m != null, "opened"):
		main.free()
		_cleanup()
		return
	var doc: MapDocument = m.doc
	var canvas: MapCanvas = m.canvas
	var panel: PlacementsPanel = main._placements_panel
	check_eq(canvas.placements.size(), doc.placements().size(), "the canvas has the placements")
	check_eq(panel.list.get_root().get_child_count(), 4, "four lists in the panel")

	main.set_tool(MapTool.Kind.PLACE)
	canvas.cell_pressed.emit(Vector2i(10, 10), false, false)
	check_eq([panel.member, panel.index], ["place_vehicles", 0], "clicked on the map, selected in the panel")
	check_eq(canvas.selected_member, "place_vehicles")
	canvas.cell_dragged.emit(Vector2i(12, 11), false)
	check_eq(canvas.placement_preview, Rect2i(12, 11, 1, 1), "drag preview")
	canvas.cell_released.emit(Vector2i(12, 11), false)
	check(not canvas.placement_preview.has_area(), "preview cleared")
	check_eq([doc.object().place_vehicles[0].x, doc.object().place_vehicles[0].y], [12, 11], "moved")
	check(main._tabs.get_tab_title(0).ends_with(" *"), "tab marked dirty")
	canvas.cell_hovered.emit(Vector2i(12, 11))
	check(main._status.text.contains("place_vehicles #1 V 1% car"), main._status.text)

	# Inspector.
	panel.editors["chance"].text = "100"
	check_eq(panel.commit_field("chance"), "")
	check_eq(doc.object().place_vehicles[0].chance, 100)
	check_eq(doc.object().place_vehicles[0].keys(), ["vehicle", "x", "y", "chance", "rotation"])
	check_eq(panel.editors["chance"].text, "100", "the inspector was rebuilt with the value")
	panel.editors["x"].text = "[20, 30]"
	check(panel.commit_field("x").contains("cannot cross grid boundaries"), "crossing refused")
	check_eq(doc.object().place_vehicles[0].x, 12)
	check_eq(panel.editors["x"].text, "12", "the text is put back")
	panel.editors["rotation"].text = ""
	check_eq(panel.commit_field("rotation"), "")
	check(not doc.object().place_vehicles[0].has("rotation"), "emptied field removed")

	# Hidden layers can't be picked.
	main.set_layer_visible(Placement.Layer.VEHICLES, false)
	check_eq(canvas.layer_mask & (1 << Placement.Layer.VEHICLES), 0)
	canvas.cell_pressed.emit(Vector2i(12, 11), false, false)
	canvas.cell_released.emit(Vector2i(12, 11), false)
	check_eq(panel.member, "", "nothing picked")
	main.set_layer_visible(Placement.Layer.VEHICLES, true)

	# Add, undo.
	main.arm_placement("place_monster")
	canvas.cell_pressed.emit(Vector2i(2, 2), false, false)
	canvas.cell_dragged.emit(Vector2i(4, 3), false)
	canvas.cell_released.emit(Vector2i(4, 3), false)
	check_eq(doc.object().get("place_monster"), [{"monster": "", "x": [2, 4], "y": [2, 3]}])
	check_eq([panel.member, panel.index], ["place_monster", 0], "the new entry is selected")
	var completer: IdCompleter = panel.completers.get("monster")
	if check(completer != null, "the monster field suggests ids"):
		panel.editors["monster"].text = "zom"
		completer.update()
		check(completer.is_open(), "suggestions shown")
		check_eq(completer.list.get_item_text(0), "mon_zombie")
		completer.accept(0)
	check_eq(doc.object().place_monster[0].monster, "mon_zombie", "taking a suggestion commits it")
	check_eq(panel.editors["monster"].text, "mon_zombie")
	check(panel.completers.has("group"), "and the group field")
	check(not panel.completers.has("chance"), "not a number field")
	main.undo()
	main.undo()
	check(not doc.object().has("place_monster"), "undone")
	check_eq(panel.member, "", "the selection went with it")

	# Duplicate and delete through the panel.
	main.select_placement("place_monsters", 0)
	panel.duplicate_selected()
	check_eq(doc.object().place_monsters.size(), 2)
	check_eq([panel.member, panel.index], ["place_monsters", 1])
	panel.delete_selected()
	check_eq(doc.object().place_monsters.size(), 1)
	check_eq([panel.member, canvas.selected_member], ["", ""], "nothing selected after a delete")

	# Saving refuses the crossing range until it's fixed.
	check(main.save_current().contains("cannot cross grid boundaries"), "save refused")
	main.select_placement("place_items", 3)
	panel.delete_selected()
	check_eq(main.save_current(), "")
	check(FileAccess.file_exists(_ws.path_join(doc.file.rel_path)), "saved")
	main.free()
	_cleanup()

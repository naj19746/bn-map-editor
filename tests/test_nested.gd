extends "res://tests/support/test_case.gd"
## Nested chunks (Stage 6) against a small fake BN checkout: the overlay
## follows BN's order, rotation, recursion and loop rules; edits to a chunk
## or its palette reach the open parents and the palette warning; new chunks
## are created and placed with the Place tool and the chunk picker.

const TempTree := preload("res://tests/support/temp_tree.gd")

const MAPS := "data/json/mapgen/maps.json"
const CHUNKS := "data/json/mapgen/nested/chunks.json"
const PALETTES := "data/json/mapgen_palettes/pal.json"

var _root := ""
var _ws := ""
var _index: DataIndex


static func _blank(w: int, h: int, fill := " ") -> Array:
	var rows := []
	for y in h:
		rows.append(fill.repeat(w))
	return rows


static func _chunk(id: String, rows: Array, extra := {}, weight := -1) -> Dictionary:
	var obj := {"mapgensize": [rows[0].length(), rows.size()], "rows": rows}
	obj.merge(extra)
	var o := {"type": "mapgen", "method": "json", "nested_mapgen_id": id, "object": obj}
	if weight >= 0:
		o["weight"] = weight
	return o


func _setup() -> void:
	var house_rows := _blank(24, 24, ".")
	var via_rows := _blank(24, 24, ".")
	via_rows[3] = "...N" + ".".repeat(20)
	via_rows[6] = "......M" + ".".repeat(17)
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_dirt", "symbol": ":", "color": "brown"},
			{"type": "terrain", "id": "t_grass", "symbol": "\"", "color": "green"},
			{"type": "terrain", "id": "t_wall", "symbol": "#", "color": "white", "flags": ["WALL"]},
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "furniture", "id": "f_table", "symbol": "t", "color": "brown"},
			{"type": "overmap_terrain", "id": ["house", "via_pal", "tower_w", "tower_e"], "name": "x"},
		],
		PALETTES: [
			{"type": "palette", "id": "cpal", "terrain": {"c": "t_dirt"}},
			{"type": "palette", "id": "npal", "nested": {"N": {"chunks": ["room"]}}},
		],
		CHUNKS: [
			# 3x2: a wall (removes furniture below), a chair over the parent's
			# terrain, undefined '.'/' ' that leave the parent's cell.
			_chunk("room", ["#h.", "c  "], {"palettes": ["cpal"], "terrain": {"#": "t_wall"},
				"furniture": {"h": "f_chair"}}),
			# A lighter variant: the overlay draws the heaviest.
			_chunk("room", ["hhh", "hhh"], {"furniture": {"h": "f_table"}}, 10),
			# Not square: 3x1.
			_chunk("wide", ["abc"], {"terrain": {"a": "t_floor", "b": "t_dirt", "c": "t_wall"}}),
			# Places room at (1, 1) itself.
			_chunk("outer", _blank(4, 4, "."), {"place_nested": [{"chunks": ["room"], "x": 1, "y": 1}]}),
			_chunk("loop_a", ["."], {"place_nested": [{"chunks": ["loop_b"], "x": 0, "y": 0}]}),
			_chunk("loop_b", ["."], {"place_nested": [{"chunks": ["loop_a"], "x": 0, "y": 0}]}),
		],
		MAPS: [
			{"type": "mapgen", "method": "json", "om_terrain": "house", "object": {
				"fill_ter": "t_grass", "rows": house_rows, "terrain": {".": "t_floor"},
				"place_nested": [
					{"chunks": ["room"], "x": 2, "y": 2},
					{"chunks": [["null", 50], ["wide", 10]], "rotation": 1, "x": 10, "y": 2},
					{"chunks": ["outer"], "x": 22, "y": 5},
					{"chunks": ["nope"], "x": 0, "y": 20},
					{"chunks": ["loop_a"], "x": 5, "y": 15},
					# Later draws over room's second row.
					{"chunks": ["wide"], "x": 2, "y": 3},
					# outer turned once: room's anchor turns, room itself doesn't.
					{"chunks": ["outer"], "rotation": 1, "x": 5, "y": 10},
				]}},
			{"type": "mapgen", "method": "json", "om_terrain": "via_pal", "object": {
				"fill_ter": "t_grass", "rows": via_rows, "palettes": ["npal"],
				"terrain": {".": "t_floor"},
				"nested": {"M": {"chunks": ["wide"], "rotation": 2}},
				# Mappings run before place_nested, so this draws over N's room.
				"place_nested": [{"chunks": ["wide"], "x": 3, "y": 3}]}},
			{"type": "mapgen", "method": "json", "om_terrain": [["tower_w", "tower_e"]], "object": {
				"fill_ter": "t_grass", "rows": _blank(48, 24, "."), "terrain": {".": "t_floor"},
				"place_nested": [{"chunks": ["room"], "x": 30, "y": 1}]}},
		],
	}
	for rel: String in files:
		files[rel] = BnJson.stringify(files[rel])
	_root = TempTree.make(files)
	_ws = TempTree.make({})
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


func _overlay(id: String) -> ChunkOverlay:
	var objects := MapgenObjects.new(_index)
	var mapgen := objects.object_for(_index.mapgens_for(id)[0])
	return ChunkOverlay.build(_index, mapgen, MapgenResolver.resolve(_index, mapgen), objects.object_for)


## [terrain, furniture, owner stamp's path] written at a cell.
static func _cell(o: ChunkOverlay, x: int, y: int) -> Array:
	var i := y * o.size.x + x
	return [o.ter[i], o.furn[i], o.stamps[o.owner[i]].path if o.owner[i] >= 0 else ""]


func _session() -> EditSession:
	return EditSession.new(_index, Workspace.open(_ws, _root))


func test_order_rotation_and_cells() -> void:
	_setup()
	var o := _overlay("house")
	# room at (2, 2): the wall removes furniture, the chair keeps the map's
	# terrain, '.' leaves the cell alone.
	check_eq(_cell(o, 2, 2), ["t_wall", "f_null", "place_nested #1"])
	check_eq(_cell(o, 3, 2), ["", "f_chair", "place_nested #1"])
	check_eq(_cell(o, 4, 2), ["", "", ""], "undefined '.' leaves the parent's cell")
	# wide at (2, 3) comes later in the list and draws over room's 'c'.
	check_eq(_cell(o, 2, 3), ["t_floor", "", "place_nested #6"], "later chunks draw over earlier ones")
	check_eq(_cell(o, 3, 3), ["t_dirt", "", "place_nested #6"])
	var room := o.stamp_for(0)
	check_eq([room.chunk_id, room.variants, room.ref.weight], ["room", 2, 1000], "the heaviest variant")
	check_eq(room.footprint, Rect2i(2, 2, 3, 2))
	# One turn: the 3x1 chunk becomes 1x3; "null" isn't drawn but counted.
	var turned := o.stamp_for(1)
	check_eq([turned.chunk_id, turned.size, turned.footprint, turned.others()], ["wide", Vector2i(1, 3), Rect2i(10, 2, 1, 3), 1])
	check_eq([_cell(o, 10, 2)[0], _cell(o, 10, 3)[0], _cell(o, 10, 4)[0]], ["t_floor", "t_dirt", "t_wall"])
	check(not turned.overhangs(), "inside its tile")
	# outer at (22, 5) is 4 wide: it reaches past the tile. Its room sits at
	# (23, 6), cut at the map's edge.
	var outer := o.stamp_for(2)
	check(outer.overhangs(), "outer overhangs")
	check(outer.label().ends_with("!"), outer.label())
	var inner: ChunkOverlay.Stamp = o.stamps[o.stamps.find(outer) + 1]
	check_eq([inner.depth, inner.chunk_id, inner.footprint, inner.path],
			[1, "room", Rect2i(23, 6, 3, 2), "place_nested #3 > outer > place_nested #1"])
	check_eq(_cell(o, 23, 6)[0], "t_wall")
	# outer turned once: its piece at (1, 1) turns to (2, 1); room itself not.
	var outer_r := o.stamp_for(6)
	var inner_r: ChunkOverlay.Stamp = o.stamps[o.stamps.find(outer_r) + 1]
	check_eq([inner_r.anchor, inner_r.rotation, inner_r.footprint], [Rect2i(7, 11, 1, 1), 0, Rect2i(7, 11, 3, 2)])
	check_eq(_cell(o, 8, 11), ["", "f_chair", "place_nested #7 > outer > place_nested #1"])
	# Unknown ids and loops are problems; nothing is drawn for them.
	var problems := o.problems()
	check(problems.has("place_nested #4: unknown chunk \"nope\" (BN places nothing)"), str(problems))
	check(problems.has("place_nested #5 > loop_a > place_nested #1 > loop_b > place_nested #1: chunk loop: loop_a > loop_b > loop_a"),
			str(problems))
	check_eq(problems.size(), 2)
	check_eq(o.drawn_ids.keys(), ["room", "wide", "outer", "loop_a", "loop_b"])
	check_eq(o.palette_ids.keys(), ["cpal"])
	_cleanup()


func test_mappings_and_tiles() -> void:
	_setup()
	var o := _overlay("via_pal")
	# 'N' (from palette npal) places room at (3, 3); 'M' (the map's own) wide
	# turned twice at (6, 6); place_nested runs after both.
	check_eq([o.stamps[0].member, o.stamps[0].key, o.stamps[0].chunk_id, o.stamps[0].anchor],
			["nested", "N", "room", Rect2i(3, 3, 1, 1)])
	check_eq(_cell(o, 3, 4), ["t_dirt", "", "'N' nested"])
	check_eq(_cell(o, 3, 3), ["t_floor", "f_null", "place_nested #1"], "place_nested after mappings")
	check_eq(_cell(o, 4, 3), ["t_dirt", "f_chair", "place_nested #1"], "the chair stays under new terrain")
	check_eq([_cell(o, 6, 6)[0], _cell(o, 7, 6)[0], _cell(o, 8, 6)[0]], ["t_wall", "t_dirt", "t_floor"], "turned twice")
	var tower := _overlay("tower_w")
	var st := tower.stamp_for(0)
	check_eq([st.tile, st.overhangs()], [Rect2i(24, 0, 24, 24), false], "the anchor's tile")
	# Which maps place a chunk.
	var refs := _index.maps_placing("room").map(func(r: DataIndex.MapgenRef) -> String: return r.title())
	refs.sort()
	check_eq(refs, ["house", "outer", "tower_w", "via_pal"])
	var via := _index.mapgens_for("via_pal")[0]
	var mapgen := MapgenObjects.new(_index).object_for(via)
	check_eq(ChunkOverlay.placed_ids(mapgen, MapgenResolver.resolve(_index, mapgen)), PackedStringArray(["wide", "room"]))
	check_eq(via.chunks, PackedStringArray(["wide"]), "ref.chunks: the map's own")
	_cleanup()


func test_ascii_shows_chunks() -> void:
	_setup()
	var o := _overlay("house")
	var mapgen := MapgenObjects.new(_index).object_for(_index.mapgens_for("house")[0])
	var a := AsciiMap.build(_index, MapgenResolver.resolve(_index, mapgen), 0, true, o)
	check_eq([a.char_at(2, 2), a.char_at(3, 2), a.char_at(4, 2), a.char_at(0, 0)], ["#", "h", ".", "."])
	check_eq(a.count_state(AsciiMap.State.OK), 24 * 24)
	check(a.describe_cell(3, 2).contains("chunk room 'h': f_chair ‹place_nested #1›"), a.describe_cell(3, 2))
	# Without the overlay the map's own cell shows.
	a.overlay = null
	a.refresh()
	check_eq(a.char_at(3, 2), ".")
	_cleanup()


func test_chunk_edits_reach_parents() -> void:
	_setup()
	var session := _session()
	var house := session.open(_index.mapgens_for("house")[0])
	var room := session.open(_index.mapgens_for("room")[0])
	var via := session.open(_index.mapgens_for("via_pal")[0])
	check_eq(_cell(house.chunk_overlay(), 4, 2)[1], "")
	via.chunk_overlay()
	var seen := []
	house.overlay_changed.connect(func() -> void: seen.append("house"))
	via.overlay_changed.connect(func() -> void: seen.append("via"))
	# Paint the chair symbol into room's '.' corner: both parents redraw.
	room.paint([Vector2i(2, 0)] as Array[Vector2i], "h")
	check_eq(seen, ["house", "via"], "open parents told")
	check_eq(_cell(house.chunk_overlay(), 4, 2), ["", "f_chair", "place_nested #1"], "the parent sees the unsaved edit")
	room.undo()
	check_eq(_cell(house.chunk_overlay(), 4, 2)[1], "", "and its undo")

	# A palette only the chunk uses: parents redraw, and the warning names
	# them via the chunk.
	var pal := session.open_palette(_index.palette("cpal"))
	var c := pal.build_set_tiles("c", "t_grass", null, "c")
	var affected := session.impact_of(pal, c)
	var names := affected.map(func(x: PaletteImpact.Affected) -> String: return "%s:%s" % [x.ref.title(), x.what()])
	names.sort()
	check_eq(names, ["house:via chunk room", "outer:via chunk room", "room:c", "tower_w:via chunk room",
			"via_pal:via chunk room"])
	# (The app rebuilds an overlay as soon as it's told; until then a map has
	# nothing drawn to be told about.)
	via.chunk_overlay()
	seen.clear()
	pal.commit(c)
	check_eq(seen, ["house", "via"], "parents of a chunk using the palette redraw")
	check_eq(_cell(house.chunk_overlay(), 2, 3)[0], "t_floor", "wide still draws over room there")
	check_eq(_cell(house.chunk_overlay(), 23, 7)[0], "t_grass", "outer's room shows the palette edit")

	# The parents list for a chunk.
	var parents := session.chunk_parents(_index.mapgens_for("room")[0]).map(
			func(x: PaletteImpact.Affected) -> String: return "%s:%s" % [x.ref.title(), x.via])
	parents.sort()
	check_eq(parents, ["house:room", "outer:room", "tower_w:room", "via_pal:room"])
	var via_outer := session.chunk_parents(_index.mapgens_for("outer")[0]).map(
			func(x: PaletteImpact.Affected) -> String: return "%s:%s" % [x.ref.title(), x.via])
	check_eq(via_outer, ["house:outer"])

	# Discarding the palette's file puts the chunk back as on disk.
	session.close_palette(pal)
	check_eq(_cell(house.chunk_overlay(), 23, 7)[0], "t_dirt", "the palette as on disk")
	_cleanup()


func test_new_chunk() -> void:
	_setup()
	var session := _session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = CHUNKS
	spec.ids = [PackedStringArray(["closet"])] as Array[PackedStringArray]
	spec.chunk_size = Vector2i(25, 2)
	check_eq(session.check_new_mapgen(spec), "A chunk's mapgensize is 1-24 cells each way.")
	spec.chunk_size = Vector2i(2, 3)
	spec.fill_ter = ""
	check_eq(session.check_new_mapgen(spec), "")
	var doc := session.create_mapgen(spec)
	check_eq(BnJson.stringify(doc.mapgen()), BnJson.stringify({"type": "mapgen", "method": "json",
			"nested_mapgen_id": "closet", "object": {"mapgensize": [2, 3], "rows": ["  ", "  ", "  "]}}))
	check_eq(doc.chunk_id(), "closet")
	check_eq(doc.missing_overmap_terrain(), PackedStringArray(), "a chunk needs no overmap_terrain")
	check(_index.nested.has("closet"), "indexed")
	check_eq(doc.problems(), PackedStringArray())
	check_eq(doc.size(), Vector2i(2, 3))
	_cleanup()


func test_main_scene_places_new_chunk() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)

	# New chunk through the dialog.
	var dialog: NewMapDialog = main._new_map_dialog
	dialog.setup(main.session)
	dialog.set_kind(NewMapDialog.Kind.CHUNK)
	dialog.base_edit.text = "closet"
	dialog._autofill()
	dialog.width.value = 2
	dialog.height.value = 2
	check_eq(dialog.path_edit.text, "data/json/mapgen/nested/closet.json")
	check(not dialog.ids_edit.visible and not dialog.fill_edit.visible, "map-only fields hidden")
	check(not dialog.get_ok_button().disabled, dialog._info.text)
	dialog._on_confirmed()
	var chunk_map = main.current_map()
	check_eq(chunk_map.ref.title(), "closet")
	var chunk: MapDocument = chunk_map.doc
	check_eq(chunk.add_symbol("x", "t_dirt", "f_table"), "")
	chunk.paint([Vector2i(0, 0), Vector2i(1, 1)] as Array[Vector2i], "x")

	# Place it in the house with the Place tool and the chunk picker.
	var m = main.open_id("house")
	var canvas: MapCanvas = m.canvas
	var panel: PlacementsPanel = main._placements_panel
	main.arm_placement("place_nested")
	canvas.cell_pressed.emit(Vector2i(15, 15), false, false)
	canvas.cell_released.emit(Vector2i(15, 15), false)
	check_eq([panel.member, panel.index], ["place_nested", 7], "the new entry is selected")
	check(panel._chunk_box.visible, "the chunk info shows")
	check_eq(panel.add_chunk("nope"), "There's no nested chunk \"nope\".")
	var chunks: WeightedIdList = panel.lists.get("chunks")
	if not check(chunks != null and panel.lists.has("else_chunks"), "chunks are edited as lists"):
		main.free()
		_cleanup()
		return
	check_eq(chunks.rows.size(), 0)
	chunks.add_edit.text = "closet"
	chunks.add_edit.text_submitted.emit("closet")
	check_eq(m.doc.object().place_nested[7], {"chunks": ["closet"], "x": 15, "y": 15})
	check_eq(panel.lists.get("chunks"), chunks, "updated in place, not rebuilt")
	check_eq(chunks.rows.size(), 1)
	check_eq([chunks.rows[0].id.text, chunks.rows[0].note.text], ["closet", "2x2"])
	chunks.add("nope", 5)
	check_eq(m.doc.object().place_nested[7].chunks, ["closet", ["nope", 5]])
	check_eq(chunks.rows[1].note.text, "unknown", "an unknown id is marked")
	check(panel._problems.text.contains("nope"), panel._problems.text)
	chunks.rows[1].weight.value = 100
	chunks.rows[1].weight.value_changed.emit(100.0)
	check_eq(m.doc.object().place_nested[7].chunks, ["closet", "nope"], "weight 100 writes a plain id")
	check_eq(chunks.set_id(1, "null"), "")
	chunks.move(1, 0)
	check_eq(m.doc.object().place_nested[7].chunks, ["null", "closet"])
	chunks.remove(0)
	var else_chunks: WeightedIdList = panel.lists["else_chunks"]
	else_chunks.add("closet", 0)
	check_eq(m.doc.object().place_nested[7], {"chunks": ["closet"], "x": 15, "y": 15,
			"else_chunks": [["closet", 0]]})
	else_chunks.remove(0)
	check(not m.doc.object().place_nested[7].has("else_chunks"), "an emptied else_chunks goes")
	chunks.remove(0)
	check_eq(m.doc.object().place_nested[7].chunks, [], "an emptied chunks stays")
	for i in 8:
		main.undo()
	check_eq(m.doc.object().place_nested[7], {"chunks": ["closet"], "x": 15, "y": 15}, "one undo step each")
	check_eq(chunks.value, ["closet"], "the list follows undo")
	check(panel._chunk_info.text.begins_with("Draws: chunk closet (2x2)"), panel._chunk_info.text)
	check_eq([m.ascii.char_at(15, 15), m.ascii.char_at(16, 15), m.ascii.char_at(16, 16)], ["t", ".", "t"],
			"the chunk draws on the parent")
	check_eq(canvas.chunks, m.doc.chunk_overlay(), "the canvas has the footprints")

	# Editing the (unsaved) chunk redraws the open parent.
	var other_tab: int = main.maps.find(chunk_map)
	main._tabs.current_tab = other_tab
	chunk.paint([Vector2i(1, 0)] as Array[Vector2i], "x")
	check_eq(m.ascii.char_at(16, 15), "t", "the parent redrew")

	# Drag the chunk by its body (not its anchor cell).
	main._tabs.current_tab = main.maps.find(m)
	main.set_tool(MapTool.Kind.PLACE)
	canvas.cell_pressed.emit(Vector2i(16, 16), false, false)
	check_eq([panel.member, panel.index], ["place_nested", 7], "picked by the chunk's body")
	canvas.cell_dragged.emit(Vector2i(18, 17), false)
	canvas.cell_released.emit(Vector2i(18, 17), false)
	check_eq(m.doc.object().place_nested[7], {"chunks": ["closet"], "x": 17, "y": 16})
	check_eq(m.ascii.char_at(17, 16), "t")
	check_eq(m.ascii.char_at(15, 15), ".", "gone from the old spot")

	# The Chunks toggle hides what chunks draw.
	main.set_show_chunks(false)
	check_eq(m.ascii.char_at(17, 16), ".")
	main.set_show_chunks(true)
	check_eq(m.ascii.char_at(17, 16), "t")
	canvas.cell_hovered.emit(Vector2i(17, 16))
	check(main._status.text.contains("chunk closet 'x'"), main._status.text)

	# The chunk's parents.
	main._tabs.current_tab = main.maps.find(chunk_map)
	main.show_chunk_parents()
	check(main._report_text.text.begins_with("house (data/json/mapgen/maps.json #0)"), main._report_text.text)

	check_eq(main.save_all(), "")
	var saved := FileAccess.get_file_as_string(_ws.path_join("data/json/mapgen/nested/closet.json"))
	check(saved.contains("\"nested_mapgen_id\": \"closet\""), saved)
	check(saved.contains("\"mapgensize\": [ 2, 2 ]"), saved)
	main.free()
	_cleanup()


func test_symbol_piece_data() -> void:
	# The plain member, or mapping[key][kind] where it's written there.
	var obj := {"terrain": {"a": "t_floor"}, "mapping": {"b": {"nested": {"chunks": ["x"]}, "item": {}}}}
	check_eq(ObjectMembers.key_member(obj, "b", "nested"), "mapping")
	check_eq(ObjectMembers.key_value(obj, "b", "nested"), {"chunks": ["x"]})
	check_eq(ObjectMembers.set_key_value(obj, "b", "nested", {"chunks": ["y"]}, MapDocument.MEMBER_ORDER), "")
	check_eq(obj.mapping.b.nested, {"chunks": ["y"]}, "edited where it is")
	check_eq(ObjectMembers.set_key_value(obj, "a", "nested", {"chunks": []}, MapDocument.MEMBER_ORDER), "")
	check_eq(obj.keys(), ["terrain", "nested", "mapping"], "a new member goes by the order")
	ObjectMembers.set_key_value(obj, "b", "nested", null, [])
	check_eq(obj.mapping, {"b": {"item": {}}}, "removed from the mapping entry")
	ObjectMembers.set_key_value(obj, "b", "item", null, [])
	check(not obj.has("mapping"), "an emptied mapping goes")
	ObjectMembers.set_key_value(obj, "a", "nested", null, [])
	check(not obj.has("nested"), "an emptied member goes")
	check_eq(ObjectMembers.set_key_value({"nested": []}, "a", "nested", {}, []), "\"nested\" isn't an object.")
	check_eq(Placement.mapping_template("nested"), {"chunks": []})
	check_eq(Placement.mapping_template("monster"), {"monster": ""})
	check_eq(Placement.mapping_template("items"), {"item": "", "chance": 100})
	check_eq(Placement.mapping_template("item"), {"item": ""})
	check_eq(Placement.mapping_template("vehicles"), {"vehicle": "", "chance": 100, "rotation": 0})
	check_eq(Placement.mapping_template("monsters"), {"monster": ""})
	check_eq(Placement.mapping_template("toilets"), {})
	check_eq(Placement.mapping_template("vendingmachines"), {}, "BN's default stock")
	check_eq(Placement.mapping_skip("items"), ["x", "y"], "items reads its own repeat")
	check_eq(Placement.mapping_skip("item"), ["x", "y"])
	check_eq(Placement.mapping_skip("toilets"), ["x", "y", "repeat"])
	for kind: String in Placement.MAPPING_KINDS:
		check(MapDocument.MEMBER_ORDER.has(kind) and PaletteDocument.MEMBER_ORDER.has(kind)
				and PaletteDocument.EDITED.has(kind), kind + " has a place and is snapshotted")

	_setup()
	var session := _session()
	var via := session.open(_index.mapgens_for("via_pal")[0])
	check_eq(via.own_piece("M", "nested"), {"chunks": ["wide"], "rotation": 2})
	check_eq(via.own_piece("N", "nested"), null, "N's comes from the palette")
	check_eq(via.set_own_piece("M", "nested", {"chunks": ["room"], "rotation": 2}), "")
	check_eq(via.chunk_overlay().stamps[1].chunk_id, "room", "the overlay follows")
	check_eq(via.set_own_piece("N", "monster", [{"monster": "mon_x"}, {"group": "G"}]), "")
	check_eq(via.object().monster, {"N": [{"monster": "mon_x"}, {"group": "G"}]})
	check_eq(via.resolved.symbols["N"].extras.monster.size(), 1)
	check_eq(via.set_own_piece("N", "monster", "mon_x"), "A \"monster\" mapping is an object or a list of objects.")
	check_eq(via.set_own_piece("ab", "monster", {}), "A symbol must be one character wide.")
	via.undo()
	via.undo()
	check(not via.object().has("monster"), "undone")
	check_eq(via.own_piece("M", "nested"), {"chunks": ["wide"], "rotation": 2})

	var pal := session.open_palette(_index.palette("npal"))
	check_eq(pal.piece("N", "nested"), {"chunks": ["room"]})
	var c := pal.build_set_piece("N", "nested", {"chunks": ["wide"]})
	check_eq(session.impact_of(pal, c).map(func(x: PaletteImpact.Affected) -> String: return x.to_string()),
			["via_pal (data/json/mapgen/maps.json#1): N"], "the map painting N changes")
	pal.commit(c)
	check_eq(pal.palette().nested, {"N": {"chunks": ["wide"]}})
	check_eq(pal.build_set_piece("N", "nested", {"chunks": ["wide"]}), null, "nothing changes")
	check_eq(pal.check_piece("N", "nested", 5), "A \"nested\" mapping is an object or a list of objects.")
	pal.commit(pal.build_set_piece("N", "nested", null))
	check(not pal.palette().has("nested"), "removed")
	pal.undo()
	pal.undo()
	check_eq(pal.palette().nested, {"N": {"chunks": ["room"]}})
	_cleanup()


func test_main_scene_symbol_pieces() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m = main.open_id("via_pal")
	var legend: LegendPanel = main._legend
	var pieces := legend.pieces

	# The map's own 'M': editable fields, lists included.
	legend.select_key("M")
	check(pieces.visible and pieces.editors.has("nested"), "M's nested is shown")
	var ed: PieceEditor = pieces.editors.nested[0]
	check(not ed.editors.has("x") and not ed.editors.has("repeat"), "no x/y/repeat for a mapping")
	check_eq(ed.editors.rotation.text, "2")
	var chunks: WeightedIdList = ed.lists.chunks
	check_eq([chunks.rows[0].id.text, chunks.rows[0].note.text], ["wide", "3x1"])
	chunks.add("room", 5)
	check_eq(m.doc.object().nested.M, {"chunks": ["wide", ["room", 5]], "rotation": 2})
	check(pieces.editors.nested[0] == ed, "updated in place")
	ed.editors.rotation.text = "1"
	check_eq(ed.commit_field("rotation"), "")
	check_eq(m.doc.object().nested.M.rotation, 1)
	check(main._tabs.get_tab_title(0).ends_with(" *"), "dirty")

	# Add a monster to M, then another: the mapping becomes a list.
	check_eq(pieces.add_buttons.monster.text, "Add monster")
	pieces.add_buttons.monster.pressed.emit()
	check_eq(m.doc.object().monster, {"M": {"monster": ""}})
	var mon: PieceEditor = pieces.editors.monster[0]
	mon.editors.monster.text = "mon_x"
	check_eq(mon.commit_field("monster"), "")
	check_eq(pieces.add_buttons.monster.text, "Add another monster")
	pieces.add_buttons.monster.pressed.emit()
	check_eq(m.doc.object().monster.M, [{"monster": "mon_x"}, {"monster": ""}])
	check_eq(pieces.editors.monster.size(), 2)
	check_eq(pieces.remove_piece("monster", 1), "")
	check_eq(m.doc.object().monster.M, [{"monster": "mon_x"}], "a list stays a list")
	pieces.remove_buttons.monster.pressed.emit()
	check(not m.doc.object().has("monster"), "removed")
	for i in 7:
		main.undo()
	check_eq(m.doc.object().nested.M, {"chunks": ["wide"], "rotation": 2}, "all undone")
	check_eq(pieces.editors.nested[0].lists.chunks.value, ["wide"], "the legend follows undo")

	# N's nested comes from npal: listed, opened in the palette editor.
	legend.select_key("N")
	check(pieces.editors.get("nested", []).is_empty(), "not the map's own")
	check(not pieces.remove_buttons.has("nested"), "nothing of its own to remove")
	var open: Button = null
	for b in pieces.find_children("*", "Button", true, false):
		if b.text == "Open":
			open = b
	if not check(open != null, "an Open button for the palette's piece"):
		main.free()
		_cleanup()
		return
	open.pressed.emit()
	var pe: PaletteEditor = main._palette_editor
	check(pe.doc != null and pe.doc.id == "npal", "the palette editor opened at npal")
	check_eq(pe.key_edit.text, "N")
	var pal_ed: PieceEditor = pe.pieces.editors.nested[0]
	pal_ed.lists.chunks.set_id(0, "wide")
	check(not pe.confirm.visible, "only the current map changes")
	check_eq(pe.doc.palette().nested.N, {"chunks": ["wide"]})
	check_eq(m.doc.chunk_overlay().stamps[0].chunk_id, "wide", "the map draws the palette's new chunk")
	check_eq(pe.pieces.editors.nested[0], pal_ed, "updated in place")
	pe.pieces.add_piece("monster")
	check_eq(pe.doc.palette().monster, {"N": {"monster": ""}})
	check(pe.status.text.contains("changes 1 map"), pe.status.text)
	# A key typed into the Key box that isn't defined yet can get pieces.
	pe.key_edit.text = "Q"
	pe.key_edit.text_changed.emit("Q")
	check(pe.pieces.visible and pe.pieces.key == "Q")
	check_eq(pe.pieces.add_piece("nested"), "")
	check_eq(pe.doc.palette().nested.Q, {"chunks": []})
	check_eq(main.save_all(), "")
	var saved := FileAccess.get_file_as_string(_ws.path_join(PALETTES))
	check(saved.contains("\"Q\": { \"chunks\": [  ] }"), saved)
	main.free()
	_cleanup()


## The other mapping kinds (items, toilets, vendingmachines, ...) in the
## legend and the palette editor.
func test_main_scene_item_pieces() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m = main.open_id("via_pal")
	var legend: LegendPanel = main._legend
	var pieces := legend.pieces

	legend.select_key("M")
	for kind: String in Placement.MAPPING_KINDS:
		check(pieces.add_buttons.has(kind), "an Add button for " + kind)
	pieces.add_buttons.items.pressed.emit()
	check_eq(m.doc.object().items, {"M": {"item": "", "chance": 100}})
	var ed: PieceEditor = pieces.editors.items[0]
	check(not ed.editors.has("x") and ed.editors.has("repeat"), "items keeps its own repeat")
	check(ed.completers.has("item"), "item suggests groups and items")
	ed.editors.item.text = "grp"
	check_eq(ed.commit_field("item"), "")
	ed.editors.repeat.text = "1-3"
	check_eq(ed.commit_field("repeat"), "")
	check_eq(m.doc.object().items.M, {"item": "grp", "chance": 100, "repeat": [1, 3]})
	check(pieces.editors.items[0] == ed, "updated in place")
	# An inline item group is JSON in the id field and stays an object.
	ed.editors.item.text = "{\"items\": [\"x\"]}"
	check_eq(ed.commit_field("item"), "")
	check_eq(m.doc.object().items.M.item, {"items": ["x"]})

	pieces.add_buttons.toilets.pressed.emit()
	check_eq(m.doc.object().toilets, {"M": {}})
	var toilet: PieceEditor = pieces.editors.toilets[0]
	check(toilet.editors.has("amount") and not toilet.editors.has("repeat"), "toilet fields")
	toilet.editors.amount.text = "[5, 10]"
	check_eq(toilet.commit_field("amount"), "")
	check_eq(m.doc.object().toilets.M, {"amount": [5, 10]})
	pieces.add_buttons.vendingmachines.pressed.emit()
	var vend: PieceEditor = pieces.editors.vendingmachines[0]
	check(vend.completers.has("item_group"), "the stock suggests item groups")
	vend.editors.reinforced.text = "true"
	check_eq(vend.commit_field("reinforced"), "")
	check_eq(m.doc.object().vendingmachines, {"M": {"reinforced": true}})
	check_eq(m.doc.resolved.symbols["M"].extras.keys().filter(func(k: String) -> bool:
			return k in ["items", "toilets", "vendingmachines"]).size(), 3, "M resolves with its new pieces")
	check_eq(m.doc.object().keys().slice(-5), ["toilets", "vendingmachines", "items", "nested", "place_nested"],
			"new members go by MEMBER_ORDER")

	# A palette's items: edited in the palette editor, the map using it named.
	main.open_palette_key("npal", "N")
	var pe: PaletteEditor = main._palette_editor
	check_eq(pe.pieces.key, "N")
	check_eq(pe.pieces.add_piece("items"), "")
	check(pe.status.text.contains("changes 1 map"), pe.status.text)
	check_eq(pe.doc.palette().items, {"N": {"item": "", "chance": 100}})
	var pal_ed: PieceEditor = pe.pieces.editors.items[0]
	pal_ed.editors.item.text = "pal_grp"
	check_eq(pal_ed.commit_field("item"), "")
	check_eq(m.doc.resolved.symbols["N"].extras.items.size(), 1, "the map sees the palette's piece")
	# The legend lists it as inherited, with Open.
	legend.select_key("N")
	check(pieces.editors.get("items", []).is_empty(), "N's items aren't the map's own")

	check_eq(main.save_all(), "")
	var saved := FileAccess.get_file_as_string(_ws.path_join(PALETTES))
	check(saved.contains("\"items\": { \"N\": { \"item\": \"pal_grp\", \"chance\": 100 } }"), saved)
	var saved_map := FileAccess.get_file_as_string(_ws.path_join(MAPS))
	check(saved_map.contains("\"repeat\": [ 1, 3 ]") and saved_map.contains("\"reinforced\": true"), saved_map)
	main.free()
	_cleanup()

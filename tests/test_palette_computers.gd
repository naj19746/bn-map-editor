extends "res://tests/support/test_case.gd"
## Computers in palettes (Stage 8d) on a small fake BN: PaletteDocument
## edits a key's computer with undo, the computer dialog in palette mode
## lists what each using map's console reaches, and the legend's "Edit
## computer..." on a palette's symbol goes through the palette editor, which
## names the other maps that change before applying.

const TempTree := preload("res://tests/support/temp_tree.gd")

const MAPS := "data/json/mapgen/users.json"
const PALS := "data/json/mapgen_palettes/lab.json"
const DOOR_PC := {"name": "Door", "options": [{"name": "Unlock", "action": "unlock"}]}

var _root := ""
var _index: DataIndex


static func _rows(marks: Dictionary) -> Array:
	var rows := []
	for y in 24:
		var row := PackedStringArray()
		for x in 24:
			row.append(marks.get(Vector2i(x, y), "."))
		rows.append("".join(row))
	return rows


static func _map(id: String, obj: Dictionary) -> Dictionary:
	var o := {"fill_ter": "t_floor", "palettes": ["lab_pal"]}
	o.merge(obj, true)
	return {"type": "mapgen", "method": "json", "om_terrain": id, "object": o}


func _setup() -> void:
	var things := []
	for t: Array in [["t_floor", ".", 2], ["t_wall", "#", 0], ["t_console", "6", 0],
			["t_door_metal_locked", "+", 0], ["t_door_metal_c", "'", 2]]:
		things.append({"type": "terrain", "id": t[0], "symbol": t[1], "color": "white", "move_cost": t[2]})
	things.append({"type": "overmap_terrain", "id": ["m_a", "m_b", "m_c"], "name": "x"})
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/things.json": things,
		PALS: [
			{"type": "palette", "id": "lab_pal", "terrain": {".": "t_floor", "6": "t_console", "D": "t_door_metal_locked",
				"7": "t_floor"}, "computers": {"6": DOOR_PC}},
			{"type": "palette", "id": "bare_pal", "furniture": {"8": "f_null"}},
		],
		MAPS: [
			# Its door is 3 below the console.
			_map("m_a", {"rows": _rows({Vector2i(5, 5): "6", Vector2i(5, 8): "D"})}),
			# No door.
			_map("m_b", {"rows": _rows({Vector2i(3, 3): "6"})}),
			# Uses the palette, doesn't paint the console.
			_map("m_c", {"rows": _rows({})}),
		],
	}
	_root = TempTree.make(files)
	_index = DataIndex.load_bn(_root)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)


func test_document_edits_computers() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var doc := session.open_palette(_index.palette("lab_pal"))
	check_eq(JSON.stringify(doc.computer("6")), JSON.stringify(DOOR_PC), "(sorted: TempTree sorts keys)")
	check(doc.has_computer("6") and not doc.has_computer("7"))
	var data: Dictionary = doc.computer("6").duplicate(true)
	Computer.of(data).set_security(2)
	var c := doc.build_set_computer("6", data)
	check_eq(c.name, "Edit computer '6'")
	doc.commit(c)
	check_eq(doc.computer("6").security, 2)
	check_eq(doc.palette().terrain["6"], "t_console", "the terrain is left alone")
	check(doc.build_set_computer("6", data) == null, "no change: nothing to do")
	doc.undo()
	check(not doc.computer("6").has("security"), "undone")
	doc.redo()
	check_eq(doc.computer("6").security, 2, "redone")
	# A new computer on a key with terrain keeps it; on a bare key it gets
	# t_console.
	doc.commit(doc.build_set_computer("7", Computer.preset("door")))
	check_eq(doc.palette().terrain["7"], "t_floor")
	check_eq(doc.palette().computers.keys(), ["6", "7"])
	var bare := session.open_palette(_index.palette("bare_pal"))
	var nc := bare.build_set_computer("8", Computer.preset("door"))
	check_eq(nc.name, "New computer '8'")
	bare.commit(nc)
	check_eq(bare.palette().keys(), ["furniture", "id", "type", "terrain", "computers"], "(TempTree sorts keys)")
	check_eq(bare.palette().terrain, {"8": "t_console"})
	bare.undo()
	check(not bare.palette().has("computers") and not bare.palette().has("terrain"), "one undo step")
	# Several computers on one key: not here.
	bare.file.touch(bare.object_index)
	bare.palette()["computers"] = {"9": [DOOR_PC, DOOR_PC]}
	check_eq(bare.check_computer("9"), "'9' places several computers; edit them as JSON.")
	TempTree.remove(ws)
	_cleanup()


func test_consoles_of_using_maps() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var found := PaletteImpact.palette_consoles(session, "lab_pal", "6")
	check_eq(found[1], 2, "m_a and m_b paint it; m_c doesn't")
	var titles := (found[0] as Array).map(func(m: Array) -> String: return m[0].title())
	check_eq(titles, ["m_a", "m_b"])
	check_eq(found[0][0][3], [Vector2i(5, 5)] as Array[Vector2i])
	# The impact of an edit names both.
	var doc := session.open_palette(_index.palette("lab_pal"))
	var data: Dictionary = doc.computer("6").duplicate(true)
	Computer.of(data).set_security(1)
	var affected := session.impact_of(doc, doc.build_set_computer("6", data))
	check_eq(affected.map(func(a: PaletteImpact.Affected) -> String: return "%s %s" % [a.ref.title(), a.what()]),
			["m_a 6", "m_b 6"])
	TempTree.remove(ws)
	_cleanup()


func test_main_scene_edits_palette_computer() -> void:
	_setup()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.load_index(_root)
	var m = main.open_id("m_a")
	var legend: LegendPanel = main._legend
	legend.select_key("6")
	check_eq(legend.computer_state("6"), "", "editable")
	check_eq(legend.computer_palette("6"), "lab_pal")
	check(not legend._edit_computer_button.disabled)
	check(legend._edit_computer_button.tooltip_text.contains("palette lab_pal"), legend._edit_computer_button.tooltip_text)
	main.edit_computer("6")
	var editor: PaletteEditor = main._palette_editor
	check(editor.visible, "the palette editor opened")
	check_eq(editor.doc.id, "lab_pal")
	check_eq(editor.key_edit.text, "6")
	var dialog := editor.computer_dialog
	check(dialog.visible, "its computer dialog opened")
	check_eq(dialog.title, "Computer '6' in palette lab_pal")
	check_eq(dialog.reach_text(), "\n".join([
		"Painted in 2 maps using lab_pal (a change here changes all of them):",
		"m_a: At (5, 5): unlock reaches 1 door: (5, 8)",
		"m_b: At (3, 3): unlock reaches 0 doors (nothing)",
	]))
	# Make it a secured computer: m_b changes too, so the editor asks.
	dialog.editor.security.value = 3
	dialog.editor.security.value_changed.emit(3.0)
	check(not editor.doc.computer("6").has("security"), "nothing changes before OK")
	dialog.confirmed.emit()
	check(editor.confirm.visible, "asks: other maps change")
	check(editor.confirm.dialog_text.contains("m_b"), editor.confirm.dialog_text)
	check(not editor.doc.computer("6").has("security"), "nothing changes before confirming")
	editor.confirm.confirmed.emit()
	check_eq(editor.doc.computer("6").security, 3)
	check_eq(Computer.of(m.doc.resolved.symbols["6"].extras.computers[-1].value).security(), 3, "the map sees it")
	check(legend.selected_palette() == "lab_pal")
	editor.undo()
	check(not editor.doc.computer("6").has("security"), "undone in the palette")
	# Add a computer to a key without one.
	check_eq(editor.edit_computer("7"), "")
	check_eq(dialog.title, "New computer '7' in palette lab_pal")
	check_eq(dialog.reach_text(), "No map using lab_pal paints '7' with this computer yet; each map that does is checked on its own.")
	dialog.confirmed.emit()
	check_eq(editor.doc.computer("7"), Computer.preset("door"), "no map changes: applied right away")
	check_eq(editor._computer_button.text, "Edit computer...")
	main.free()
	TempTree.remove(ws)
	_cleanup()

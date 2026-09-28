extends "res://tests/support/test_case.gd"
## Computers (Stage 8) against a small fake BN checkout: the Computer model
## keeps what it doesn't change, the validator finds each seeded problem
## at BN's severity (and door reach per overmap tile), the map document
## adds and edits computers with undo, and the main scene makes a door
## computer from the "Door control" preset.

const TempTree := preload("res://tests/support/temp_tree.gd")

const MAPS := "data/json/mapgen/computers.json"

var _root := ""
var _index: DataIndex


## 24 rows of [param w] floor cells, with [param marks] ({Vector2i: key})
## put in.
static func _rows(marks: Dictionary, w := 24, fill := ".") -> Array:
	var rows := []
	for y in 24:
		var row := PackedStringArray()
		for x in w:
			row.append(marks.get(Vector2i(x, y), fill))
		rows.append("".join(row))
	return rows


static func _map(id: Variant, obj: Dictionary) -> Dictionary:
	return {"type": "mapgen", "method": "json", "om_terrain": id, "object": obj}


## A wall across row 10 with a door "d" at (10, 10).
static func _wall_with_door() -> Dictionary:
	var marks := {}
	for x in 24:
		marks[Vector2i(x, 10)] = "#"
	marks[Vector2i(10, 10)] = "d"
	return marks


const DOOR_PC := {"name": "Door", "options": [{"name": "Unlock", "action": "unlock"}]}
const TER := {".": "t_floor", "#": "t_wall", "D": "t_door_metal_locked", "L": "t_door_locked"}


func _setup() -> void:
	var things := []
	for t: Array in [["t_floor", ".", 2], ["t_wall", "#", 0], ["t_console", "6", 0],
			["t_door_metal_locked", "+", 0], ["t_door_metal_c", "'", 2], ["t_door_locked", "+", 0],
			["t_door_c", "'", 2]]:
		things.append({"type": "terrain", "id": t[0], "symbol": t[1], "color": "white", "move_cost": t[2]})
	things.append({"type": "overmap_terrain", "id": ["cmp_ok", "cmp_far", "cmp_w", "cmp_e", "cmp_walled",
		"cmp_bad", "cmp_set", "cmp_shared", "cmp_pal", "cmp_new", "cmp_new_e", "cmp_place", "cmp_door"], "name": "x"})
	var walled := {}
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		walled[Vector2i(5, 5) + d] = "#"
	walled[Vector2i(5, 5)] = "6"
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/things.json": things,
		"data/json/mapgen_palettes/pal.json": [
			{"type": "palette", "id": "comp_pal", "computers": {"C": {"name": "x", "options": [{"action": "bogus"}]}}},
		],
		MAPS: [
			# Reaches its door 4 cells away; a plain locked door is in reach too.
			_map("cmp_ok", {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows({Vector2i(5, 5): "6", Vector2i(5, 10): "D", Vector2i(7, 7): "L"})}),
			# The door is 14 away.
			_map("cmp_far", {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows({Vector2i(5, 5): "6", Vector2i(5, 20): "D"})}),
			# The door is 3 away, but in the next overmap tile.
			_map([["cmp_w", "cmp_e"]], {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows({Vector2i(21, 5): "6", Vector2i(25, 5): "D"}, 48)}),
			_map("cmp_walled", {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows(walled.merged({Vector2i(5, 8): "D"}))}),
			_map("cmp_bad", {"fill_ter": "t_floor", "terrain": TER, "computers": {
				"6": {"name": "x", "options": [{"name": "a", "action": "unlock_everything"}], "failures": [{"action": "explode"}]},
				"7": {"name": "y", "options": "unlock"},
				"8": {"name": "z", "options": [{"name": "no action"}, "unlock"]}},
				"rows": _rows({Vector2i(5, 5): "6", Vector2i(9, 5): "7", Vector2i(13, 5): "8"})}),
			# A "set" makes the door: the rows don't show one.
			_map("cmp_set", {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows({Vector2i(5, 5): "6"}),
				"set": [{"point": "terrain", "id": "t_door_metal_locked", "x": 5, "y": 8}]}),
			# Two consoles reach the same door.
			_map("cmp_shared", {"fill_ter": "t_floor", "terrain": TER, "computers": {"6": DOOR_PC},
				"rows": _rows({Vector2i(5, 5): "6", Vector2i(5, 11): "6", Vector2i(5, 8): "D"})}),
			# The palette's computer is its own finding.
			_map("cmp_pal", {"fill_ter": "t_floor", "palettes": ["comp_pal"], "rows": _rows({Vector2i(3, 3): "C"})}),
			_map("cmp_new", {"fill_ter": "t_floor", "terrain": {".": "t_floor"}, "rows": _rows({})}),
			_map([["cmp_new_e", "cmp_place"]], {"fill_ter": "t_floor", "terrain": {".": "t_floor"},
				"rows": _rows({}, 48), "place_computers": [{"name": "P", "x": 5, "y": 5, "options": [{"name": "Unlock", "action": "unlock"}]}]}),
			# A plain closed door in a wall, for "Control with a computer...".
			_map("cmp_door", {"fill_ter": "t_floor", "terrain": {".": "t_floor", "#": "t_wall", "d": "t_door_c"},
				"rows": _rows(_wall_with_door())}),
		],
	}
	_root = TempTree.make(files)
	_index = DataIndex.load_bn(_root)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)


func _validate(id: String) -> Array[Validator.Finding]:
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for(id)[0]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	return Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for))


## "severity code target" per finding (see test_validation.gd).
static func _summary(list: Array[Validator.Finding]) -> PackedStringArray:
	var out := PackedStringArray()
	for f in list:
		var sev: String = ["E", "W", "N"][f.severity] + ("!" if f.load_fails else "")
		var where := ""
		match f.target:
			Validator.Target.SYMBOL: where = "'%s'" % f.key
			Validator.Target.CELL: where = "%s@%d,%d" % [f.key, f.cell.x, f.cell.y]
			Validator.Target.PLACEMENT: where = "%s#%d" % [f.member, f.index]
			Validator.Target.PALETTE_KEY: where = "%s:'%s'" % [f.palette, f.key]
		out.append("%s %s %s" % [sev, Validator.Code.keys()[f.code], where])
	return out


func test_model_keeps_form() -> void:
	var data := {"name": "A", "options": [{"name": "o", "security": 2, "action": "unlock"}]}
	var c := Computer.of(data)
	c.set_security(0)
	check(not data.has("security"), "0 isn't written when it wasn't")
	c.set_security(3)
	check_eq(data.keys(), ["name", "security", "options"], "security goes after name")
	check_eq(data.security, 3)
	c.set_security(0)
	check_eq(data.security, 0, "an explicit 0 stays written")
	c.set_option(0, "o2", "unlock", 2)
	check_eq(data.options[0].keys(), ["name", "security", "action"], "an option keeps its key order")
	check_eq(data.options[0].name, "o2")
	c.set_option(0, "o2", "lock", 0)
	check_eq(data.options[0], {"name": "o2", "security": 0, "action": "lock"})
	c.set_failure("alarm", true)
	c.set_failure("shutdown", true)
	check_eq(data.failures, [{"action": "alarm"}, {"action": "shutdown"}])
	check_eq(data.keys(), ["name", "security", "options", "failures"])
	c.set_failure("alarm", false)
	c.set_failure("shutdown", false)
	check(not data.has("failures"), "an empty failure list goes")
	c.add_option("Open", "open")
	c.add_option("Lock", "lock", 4)
	check_eq(c.actions(), PackedStringArray(["lock", "open", "lock"]))
	check_eq(data.options[2], {"name": "Lock", "action": "lock", "security": 4})
	c.move_option(2, 0)
	check_eq(c.actions(), PackedStringArray(["lock", "lock", "open"]))
	check_eq(data.options[0].name, "Lock")
	c.remove_option(0)
	c.remove_option(0)
	c.remove_option(0)
	check(not data.has("options"), "no options left")
	check_eq(c.issues().map(func(i: Array) -> int: return i[0]), [Computer.Issue.NO_OPTIONS])
	c.set_target(true)
	c.set_access_denied("Go away")
	check_eq(data.keys(), ["name", "access_denied", "security", "target"])
	c.apply_preset("secured")
	check_eq(data, {"name": "A", "access_denied": "Go away", "security": 3, "target": true,
		"options": [{"name": "Unlock doors", "action": "unlock"}],
		"failures": [{"action": "shutdown"}, {"action": "alarm"}, {"action": "manhacks"}]})
	for id: String in Computer.PRESETS:
		check_eq(Computer.of(Computer.preset(id)).issues(), [], id)
	# Every action and failure has a label and a description.
	for a: String in Computer.ACTIONS:
		check(Computer.ACTIONS[a][0] and Computer.ACTIONS[a][2], a)
	for a: String in Computer.EFFECTS:
		check(Computer.ACTIONS.has(a), "effect of a known action: " + a)


func test_seeded_problems() -> void:
	_setup()
	check_eq(_summary(_validate("cmp_ok")), PackedStringArray(["N OTHER_LOCKED 6@5,5"]))
	check_eq(_summary(_validate("cmp_far")), PackedStringArray(["W NO_DOOR 6@5,5"]))
	check_eq(_summary(_validate("cmp_w")), PackedStringArray(["W NO_DOOR 6@21,5"]), "the next overmap tile")
	check_eq(_summary(_validate("cmp_walled")), PackedStringArray(["W NO_STAND 6@5,5"]))
	check_eq(_summary(_validate("cmp_bad")), PackedStringArray([
		"E! COMPUTER '6'", "E! COMPUTER '6'",
		"W COMPUTER_IGNORED '7'", "W NO_OPTIONS '7'",
		"E! COMPUTER '8'", "E! COMPUTER '8'",
	]))
	var texts := _validate("cmp_bad").map(func(f: Validator.Finding) -> String: return f.describe())
	check(texts.has("error: '6' computers: option #1: unknown action \"unlock_everything\" (BN won't load this map)"), str(texts))
	check(texts.has("error: '6' computers: failure #1: unknown action \"explode\" (BN won't load this map)"), str(texts))
	check_eq(_summary(_validate("cmp_set")), PackedStringArray(["N DOOR_ELSEWHERE 6@5,5"]))
	check_eq(_summary(_validate("cmp_shared")), PackedStringArray(["N SHARED_DOOR 6@5,5"]))
	# The palette's bad action is the palette's (once), not the map's.
	check_eq(_summary(_validate("cmp_pal")), PackedStringArray())
	check_eq(_summary(Validator.validate_palette(_index, "comp_pal", _index.palette("comp_pal").data)),
			PackedStringArray(["E! COMPUTER comp_pal:'C'"]))
	# place_computers: checked like a symbol's computer, at its cell.
	check_eq(_summary(_validate("cmp_place")), PackedStringArray(["W NO_DOOR place_computers#0"]))
	_cleanup()


func test_reach() -> void:
	# Trig distance, cut at the stand cell's overmap tile.
	check(Computer.in_reach(Vector2i(5, 6), Vector2i(5, 14), 8), "8 straight down")
	check(not Computer.in_reach(Vector2i(5, 6), Vector2i(11, 12), 8), "6,6 is 8.49 away")
	check(not Computer.in_reach(Vector2i(22, 5), Vector2i(24, 5), 8), "next tile")
	check_eq(Computer.reach_rect(Vector2i(22, 5), 8, Vector2i(48, 24)), Rect2i(14, 0, 10, 14))
	check(Computer.is_locked_door("t_door_locked", ["t_door_metal_locked"]))
	check(not Computer.is_locked_door("t_door_metal_locked", ["t_door_metal_locked"]))
	check(not Computer.is_locked_door("t_door_c", []))


func test_ascii_and_document() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var doc := session.open(_index.mapgens_for("cmp_new")[0])
	# A console symbol, drawn as t_console.
	check_eq(doc.check_new_computer("."), "' ' and '.' are left undefined on purpose (keep fill_ter or what's below).")
	check_eq(doc.suggest_key(Computer.CONSOLE), "6", "the console's own symbol")
	check_eq(doc.add_computer_symbol("6", Computer.preset("door")), "")
	# (TempTree writes keys sorted.)
	check_eq(doc.object().keys(), ["fill_ter", "rows", "terrain", "computers"])
	check_eq(doc.object().terrain, {".": "t_floor", "6": "t_console"})
	check_eq(doc.computer("6"), Computer.preset("door"))
	check_eq(doc.computer_source("6"), "map")
	doc.paint([Vector2i(2, 2)], "6")
	var ascii := AsciiMap.build(_index, doc.resolved)
	check_eq(ascii.char_at(2, 2), "6")
	check_eq(ascii.look_for("6").terrain.id, "t_console")
	# Edit, undo, redo.
	var data: Dictionary = doc.computer("6").duplicate(true)
	Computer.of(data).set_security(2)
	check_eq(doc.set_computer("6", data), "")
	check_eq(doc.computer("6").security, 2)
	check_eq(doc.undo_name(), "Edit computer '6'")
	check_eq(doc.set_computer("6", data), "", "no change: nothing to do")
	check_eq(doc.undo_name(), "Edit computer '6'")
	doc.undo()
	check(not doc.computer("6").has("security"), "undone")
	doc.undo()
	doc.undo()
	check(not doc.object().has("computers"), "the new computer is undone")
	check_eq(doc.object().terrain, {".": "t_floor"})
	doc.redo()
	check_eq(doc.computer("6"), Computer.preset("door"))
	# A computer the map defines in "mapping" is edited there.
	var obj := doc.object()
	doc.file.touch(doc.object_index)
	obj["mapping"] = {"M": {"computers": {"name": "m", "options": []}}}
	check_eq(doc.set_computer("M", {"name": "m2", "options": []}), "")
	check_eq(obj.mapping.M.computers.name, "m2")
	check(not obj.computers.has("M"), "not duplicated into \"computers\"")
	session.close(doc)
	TempTree.remove(ws)
	_cleanup()


func _formatter_or_skip() -> bool:
	if not JsonFormatter.new().is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		return false
	return true


## The acceptance flow: New computer -> Door control -> paint the console ->
## paint the door within 8 -> save; then move the door out of reach and
## into the next overmap tile.
func test_main_scene_door_computer() -> void:
	if not _formatter_or_skip():
		return
	_setup()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.load_index(_root)
	var m = main.open_id("cmp_new")
	var dialog: ComputerDialog = main._computer_dialog
	dialog.setup_new(m.doc)
	check_eq(dialog.key_edit.text, "6")
	check_eq(Computer.of(dialog.editor.data).actions(), PackedStringArray(["unlock"]), "starts as Door control")
	check(dialog.door_check.visible, "offers a door symbol: the map has none")
	check_eq(dialog.door_key(), "+", "the door's own symbol")
	dialog.editor.apply_preset("door")
	dialog.confirmed.emit()
	check_eq(m.brush, "6", "the console is the brush")
	_paint(m.doc, Vector2i(5, 5), "6")
	_paint(m.doc, Vector2i(5, 11), "+")
	check_eq(main._problems_panel.findings.size(), 0, "no problems: " + "\n".join(m.doc.problems()))
	check_eq(main._problems_button.text, "No problems")
	check_eq(main.save_current(), "")
	var saved := BnJson.parse(FileAccess.get_file_as_string(ws.path_join(MAPS))).value as Array
	var obj: Dictionary = saved[_index.mapgens_for("cmp_new")[0].source.index].object
	check_eq(obj.keys(), ["fill_ter", "rows", "terrain", "computers"])
	check_eq(obj.terrain, {".": "t_floor", "6": "t_console", "+": "t_door_metal_locked"})
	check_eq(obj.computers, {"6": {"name": "Door control", "options": [{"name": "Unlock doors", "action": "unlock"}]}})
	check_eq(obj.rows[5], ".....6" + ".".repeat(18))
	check_eq(obj.rows[11], ".....+" + ".".repeat(18))

	# Out of reach (the nearest stand cell is 9 away).
	_paint(m.doc, Vector2i(5, 11), ".")
	_paint(m.doc, Vector2i(5, 15), "+")
	check_eq(_summary(m.doc.findings()), PackedStringArray(["W NO_DOOR 6@5,5"]))
	check_eq(main._problems_button.text, "1 warning")
	# Selecting the warning draws that console's reach.
	main.show_drawer_tab(main._problems_panel)
	main.show_finding(m.doc.findings()[0])
	check(m.canvas.reach != null, "the Problems tab shows the console's reach")
	check_eq(m.canvas.reach.consoles, [Vector2i(5, 5)] as Array[Vector2i])
	check(m.canvas.reach.targets.is_empty(), "reaching nothing")
	main.show_drawer_tab(main._legend)
	# Back within 8: fine again.
	_paint(m.doc, Vector2i(5, 15), ".")
	_paint(m.doc, Vector2i(5, 14), "+")
	check_eq(_summary(m.doc.findings()), PackedStringArray())

	# Next to an overmap tile edge: the door 3 cells away in the next tile
	# isn't reached.
	var wide = main.open_id("cmp_new_e")
	dialog.setup_new(wide.doc)
	dialog.confirmed.emit()
	_paint(wide.doc, Vector2i(21, 5), "6")
	_paint(wide.doc, Vector2i(25, 5), "+")
	check(_summary(wide.doc.findings()).has("W NO_DOOR 6@21,5"), str(_summary(wide.doc.findings())))
	_paint(wide.doc, Vector2i(25, 5), ".")
	_paint(wide.doc, Vector2i(23, 5), "+")
	check(not _summary(wide.doc.findings()).has("W NO_DOOR 6@21,5"), "same tile: reached")

	# The legend edits a map computer; the dialog applies a copy.
	main._legend.select_key("6")
	check_eq(main._legend.computer_state("6"), "")
	main.edit_computer("6")
	check_eq(dialog.key_edit.text, "6")
	check_eq(dialog.reach_text(), "At (21, 5): unlock reaches 1 door: (23, 5)")
	dialog.editor.security.value = 3
	# (A Range outside the tree doesn't emit value_changed itself.)
	dialog.editor.security.value_changed.emit(3.0)
	check(not wide.doc.computer("6").has("security"), "nothing changes before OK")
	dialog.confirmed.emit()
	check_eq(wide.doc.computer("6").security, 3)
	main.free()
	TempTree.remove(ws)
	_cleanup()


func test_placements_panel_computer() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var doc := session.open(_index.mapgens_for("cmp_place")[0])
	var panel := PlacementsPanel.new()
	panel.show_map(doc)
	panel.select("place_computers", 0)
	check(panel.computer_editor.visible, "a computer editor instead of JSON fields")
	check(not panel.editors.has("options"), "no raw options field")
	check(panel.editors.has("x"), "x/y stay fields")
	panel.computer_editor.failure_boxes["alarm"].button_pressed = true
	var e: Dictionary = doc.placement("place_computers", 0).entry
	check_eq(e.keys(), ["name", "options", "x", "y", "failures"], "(TempTree sorts keys)")
	check_eq(e.failures, [{"action": "alarm"}])
	panel.computer_editor.option_rows[0].action.select(_item_of(panel.computer_editor.option_rows[0].action, "lock"))
	panel.computer_editor.option_rows[0].action.item_selected.emit(panel.computer_editor.option_rows[0].action.selected)
	check_eq(doc.placement("place_computers", 0).entry.options, [{"action": "lock", "name": "Unlock"}])
	check_eq(doc.undo_name(), "Edit computer of place_computers #1")
	# New entries start as a door control.
	check_eq(Placement.template("place_computers", Rect2i(1, 2, 1, 1)).keys(), ["name", "x", "y", "options"])
	panel.free()
	session.close(doc)
	TempTree.remove(ws)
	_cleanup()


static func _paint(doc: MapDocument, cell: Vector2i, key: String) -> void:
	doc.paint([cell], key)


static func _item_of(b: OptionButton, action: String) -> int:
	for i in b.item_count:
		if b.get_item_metadata(i) == action:
			return i
	return -1


## ConsoleReachView: stand cells, targets (full or from some stand cells
## only), other locked doors, and the reach area cut at the stand cells'
## overmap tile, also for a radius-25 action.
func test_reach_view() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var doc := session.open(_index.mapgens_for("cmp_ok")[0])
	var v := doc.reach_view("6")
	check_eq(v.consoles, [Vector2i(5, 5)] as Array[Vector2i])
	check_eq(v.stands.size(), 8, "all eight neighbours are floor")
	check_eq(v.targets, {Vector2i(5, 10): true}, "every stand cell reaches the door")
	check_eq(v.other_locked.keys(), [Vector2i(7, 7)], "the plain locked door")
	check(v.area.has(Vector2i(5, 14)) and not v.area.has(Vector2i(5, 15)), "8 below the lowest stand cell")
	check(not v.outline.is_empty() and v.outline.size() % 2 == 0, "outline segments")
	check(v.lines[0] == "At (5, 5): unlock reaches 1 door: (5, 10)", v.lines[0])
	check_eq(v.lines[-1], "Doors a \"set\" or place_terrain entry makes aren't shown.")
	check(doc.reach_view("6") == v, "cached until the map changes")
	check(doc.reach_view(".") == null, "no computer")
	# 13 below the console: only the stand cell straight above reaches it.
	_paint(doc, Vector2i(5, 10), ".")
	_paint(doc, Vector2i(5, 14), "D")
	check(doc.reach_view("6") != v, "a change drops the cached view")
	v = doc.reach_view("6")
	check_eq(v.targets, {Vector2i(5, 14): false}, "from some stand cells only")
	check_eq(doc.door_controllers(Vector2i(5, 14)), [[Vector2i(5, 5), "6"]])
	check_eq(doc.door_controllers(Vector2i(7, 7)), [], "unlock never opens t_door_locked")
	session.close(doc)

	# Radius 25 (open), next to an overmap tile edge: the area stops at x 23.
	var wide := session.open(_index.mapgens_for("cmp_w")[0])
	var data: Dictionary = wide.computer("6").duplicate(true)
	Computer.of(data).set_option(0, "Open", "open", 0)
	check_eq(wide.set_computer("6", data), "")
	v = wide.reach_view("6")
	check(v.area.has(Vector2i(0, 0)) and v.area.has(Vector2i(23, 23)), "most of the tile")
	check(v.area.keys().all(func(c: Vector2i) -> bool: return c.x < 24), "cut at the tile")
	check_eq(v.targets, {}, "the door is in the next tile")
	# A range place_computers entry has no single console cell.
	var placed := session.open(_index.mapgens_for("cmp_place")[0])
	check_eq(placed.reach_view("", 0).consoles, [Vector2i(5, 5)] as Array[Vector2i])
	placed.set_placement_fields("place_computers", 0, {"x": [3, 6]})
	v = placed.reach_view("", 0)
	check(v.consoles.is_empty() and v.lines[-1].contains("random cell"), str(v.lines))
	session.close(wide)
	session.close(placed)
	TempTree.remove(ws)
	_cleanup()


## Changes between begin_group() and end_group() undo as one.
func test_grouped_undo() -> void:
	_setup()
	var ws := TempTree.make({})
	var session := EditSession.new(_index, Workspace.open(ws, _root))
	var doc := session.open(_index.mapgens_for("cmp_new")[0])
	var before := BnJson.stringify(doc.object())
	doc.begin_group("Both")
	check_eq(doc.add_computer_symbol("6", Computer.preset("door")), "")
	doc.paint([Vector2i(2, 2)], "6")
	doc.paint([Vector2i(3, 2), Vector2i(2, 2)], "6")
	doc.end_group()
	check_eq(doc.undo_name(), "Both")
	var after := BnJson.stringify(doc.object())
	doc.undo()
	check_eq(BnJson.stringify(doc.object()), before, "one undo reverts all")
	check(not doc.can_undo(), "nothing else recorded")
	doc.redo()
	check_eq(BnJson.stringify(doc.object()), after)
	check_eq(doc.resolved.cells[2][3], "6")
	session.close(doc)
	TempTree.remove(ws)
	_cleanup()


## "Control with a computer..." on a plain closed door: it becomes a locked
## metal door, the cells a console could go are offered, and a click puts a
## Door control there; the Problems tab is empty and the reach is drawn.
func test_main_scene_control_door() -> void:
	_setup()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.load_index(_root)
	var m = main.open_id("cmp_door")
	var door := Vector2i(10, 10)
	var menu: PopupMenu = main._cell_menu
	var item: int = main.Menu.CELL_DOOR_COMPUTER
	main.open_cell_menu(Vector2i(3, 3))
	check(menu.is_item_disabled(menu.get_item_index(item)), "floor isn't a door")
	check_eq(menu.get_item_tooltip(menu.get_item_index(item)), "Not a door (t_floor).")
	main.open_cell_menu(door)
	check(not menu.is_item_disabled(menu.get_item_index(item)), "a door")
	main._on_cell_menu(item)
	check(main._door_dialog.dialog_text.contains("t_door_c"), main._door_dialog.dialog_text)
	check(main._door_dialog.dialog_text.contains("'+'"), "offers the locked door's own symbol")
	main._door_dialog.confirmed.emit()
	check_eq(m.doc.terrain_at(door), "t_door_metal_locked")
	check_eq(m.doc.undo_name(), "Lock door at (10, 10)")
	check_eq(m.console_door, door, "placing a console")
	var spots: Array[Vector2i] = m.canvas.spots
	check(spots.has(Vector2i(10, 12)) and spots.has(Vector2i(10, 8)), "both sides of the wall")
	check(not spots.has(door) and not spots.has(Vector2i(9, 10)), "not the door, not the wall")
	check(not spots.has(Vector2i(10, 20)), "too far")
	# A click off the spots does nothing; on one, places the console.
	check(main.place_door_console(Vector2i(10, 22)) != "", "too far")
	main._on_cell_pressed(Vector2i(10, 12), false, false, m)
	check_eq(m.console_door, -Vector2i.ONE, "done")
	check(m.canvas.spots.is_empty(), "spots cleared")
	check_eq(m.doc.resolved.cells[12][10], "6")
	check_eq(m.doc.computer("6"), Computer.preset("door"))
	check_eq(m.doc.undo_name(), "Door console at (10, 12)")
	check_eq(m.brush, "6", "the console is selected")
	check_eq(main._problems_panel.findings.size(), 0, "no problems: " + "\n".join(m.doc.problems()))
	check(m.canvas.reach != null, "its reach is drawn")
	check_eq(m.canvas.reach.targets, {door: true})
	check(main._legend.reach_label.visible, "and explained in the legend")
	main.show_drawer_tab(main._browser)
	check(m.canvas.reach == null, "only while the Legend shows the computer")
	# Again on the same door: already unlocked, nothing added.
	main.control_door(door)
	check_eq(m.console_door, -Vector2i.ONE)
	check(main._status.text.begins_with("The console at (10, 12) already unlocks"), main._status.text)
	# A second door reuses the console symbol; Esc-style cancel works.
	_paint(m.doc, Vector2i(20, 10), "d")
	main.control_door(Vector2i(20, 10))
	main._door_dialog.confirmed.emit()
	check_eq(m.console_door, Vector2i(20, 10))
	main.cancel_console_mode()
	check_eq(m.console_door, -Vector2i.ONE)
	main.control_door(Vector2i(20, 10))
	check_eq(m.console_door, Vector2i(20, 10), "already locked: straight to the spots")
	check_eq(main.place_door_console(Vector2i(20, 8)), "")
	check_eq(m.doc.resolved.cells[8][20], "6", "reused")
	check_eq(m.doc.object().computers.keys(), ["6"])
	# A secured computer isn't reused.
	var data: Dictionary = m.doc.computer("6").duplicate(true)
	Computer.of(data).set_security(3)
	m.doc.set_computer("6", data)
	check_eq(m.doc.door_console_key(), "", "security 3")
	m.doc.undo()
	# Each step undoes as one.
	m.doc.undo()
	m.doc.undo()
	check_eq(m.doc.resolved.cells[10][20], "d")
	main.free()
	TempTree.remove(ws)
	_cleanup()


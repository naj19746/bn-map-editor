class_name ComputerDialog
extends ConfirmationDialog
## "New computer..." and "Edit computer..." for a map's own symbols, and
## for a palette's keys (setup_palette()).
##
## New: picks a free key (the console's own "6" if free), starts from the
## "Door control" preset, and on OK defines the key in the map itself as
## terrain t_console plus the computer (MapDocument.add_computer_symbol).
## When the computer has a door action and the map has no symbol for the
## door it works on, it offers to add one too, so both can be painted
## right away. Edit: changes a copy of the key's computer and writes it on
## OK (MapDocument.set_computer), one undo step either way.
##
## Palette: edits (or adds) the computer of a palette key and hands it back
## on OK (palette_computer_ready); the palette editor then checks which maps
## change before committing. The reach list names the maps using the key,
## with what each painted console reaches.

## The computer symbol [param key] was added; [param door_key] is the door
## symbol added with it, or "".
signal computer_added(key: String, door_key: String)
## The computer of [param key] was changed.
signal computer_edited(key: String)
## OK in palette mode: [param data] is the computer for palette key
## [param key] (nothing is written yet).
signal palette_computer_ready(key: String, data: Dictionary)

const INFO_COLOR := Color(0.8, 0.8, 0.85)
const PROBLEM_COLOR := Color(1, 0.6, 0.6)

var editor: ComputerEditor
var key_edit: LineEdit
## "Also add a symbol for the door" (new computers with a door action).
var door_check: CheckBox
var _key_row: HBoxContainer
var _info: Label
## What each painted console reaches (editing only).
var reach_label: Label
var _doc: MapDocument
var _editing := ""
## Palette mode: the palette, and PaletteImpact.palette_consoles() of the key.
var _pal: PaletteDocument
var _pal_consoles := []


func _init() -> void:
	title = "New computer"
	min_size = Vector2i(700, 760)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var how := Label.new()
	how.text = "Paint the symbol where the console goes: BN puts a console (t_console) there. The player " \
			+ "uses it from a cell next to it; door actions change doors within their range of that cell, " \
			+ "in the same overmap tile only. \"Unlock\" works on locked metal doors (t_door_metal_locked) " \
			+ "within 8 cells."
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", INFO_COLOR)
	box.add_child(how)
	reach_label = Label.new()
	reach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reach_label)
	_key_row = HBoxContainer.new()
	box.add_child(_key_row)
	_key_row.add_child(ComputerEditor._label("Symbol:"))
	key_edit = LineEdit.new()
	key_edit.custom_minimum_size = Vector2(60, 0)
	key_edit.max_length = 4
	key_edit.text_changed.connect(func(_t: String) -> void: _validate())
	_key_row.add_child(key_edit)
	door_check = CheckBox.new()
	door_check.button_pressed = true
	door_check.toggled.connect(func(_on: bool) -> void: _validate())
	_key_row.add_child(door_check)
	editor = ComputerEditor.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.changed.connect(_validate)
	box.add_child(editor)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	confirmed.connect(_on_confirmed)


## Sets up a new computer for [param doc] and shows the dialog.
func open_new(doc: MapDocument) -> void:
	setup_new(doc)
	if is_inside_tree():
		popup_centered()
		key_edit.grab_focus()


## Sets up editing [param key]'s computer of [param doc] and shows it.
func open_edit(doc: MapDocument, key: String) -> void:
	if setup_edit(doc, key) and is_inside_tree():
		popup_centered()


## Like open_new() without showing the window (for tests).
func setup_new(doc: MapDocument) -> void:
	_doc = doc
	_pal = null
	_editing = ""
	title = "New computer"
	ok_button_text = "Add computer"
	key_edit.editable = true
	key_edit.text = doc.suggest_key(Computer.CONSOLE)
	editor.edit(Computer.preset("door"))
	_validate()


## Like open_edit() without showing the window. False if the map itself
## doesn't define a computer for [param key].
func setup_edit(doc: MapDocument, key: String) -> bool:
	var data: Variant = doc.computer(key)
	if data == null:
		return false
	_doc = doc
	_pal = null
	_editing = key
	title = "Computer '%s'" % key
	ok_button_text = "Apply"
	key_edit.editable = false
	key_edit.text = key
	editor.edit(data.duplicate(true))
	_validate()
	return true


## Sets up the computer of palette [param pal]'s key [param key]: its own
## computer, or a new Door control if it has none. False (see
## PaletteDocument.check_computer) if it can't be edited here.
func setup_palette(session: EditSession, pal: PaletteDocument, key: String) -> bool:
	if pal.check_computer(key):
		return false
	var data: Variant = pal.computer(key)
	_doc = null
	_pal = pal
	_editing = key
	title = ("Computer '%s' in palette %s" if data else "New computer '%s' in palette %s") % [key, pal.id]
	ok_button_text = "Apply" if data else "Add computer"
	key_edit.editable = false
	key_edit.text = key
	_pal_consoles = PaletteImpact.palette_consoles(session, pal.id, key)
	editor.edit(data.duplicate(true) if data else Computer.preset("door"))
	_validate()
	return true


## Like setup_palette(), then shows the dialog.
func open_palette(session: EditSession, pal: PaletteDocument, key: String) -> void:
	if setup_palette(session, pal, key) and is_inside_tree():
		popup_centered()


## The door terrain the edited computer's first door action works on, if
## the map has no symbol placing it (else "").
func missing_door() -> String:
	if _doc == null or _editing:
		return ""
	for action in Computer.of(editor.data).door_actions():
		var e: Array = Computer.EFFECTS[action]
		if e[2] <= 0:
			continue
		for t: String in e[0]:
			if not _doc.matching_keys(t, "").is_empty():
				return ""
		return e[0][-1] if action == "lock" else e[0][0]
	return ""


## The key to use for the door symbol ("" if none is needed).
func door_key() -> String:
	var door := missing_door()
	if door.is_empty() or not door_check.button_pressed:
		return ""
	var candidates := PackedStringArray([_doc.suggest_key(door)])
	for i in MapDocument.KEY_CANDIDATES.length():
		candidates.append(MapDocument.KEY_CANDIDATES[i])
	for k in candidates:
		if k != key_edit.text and _doc.check_new_key(k).is_empty():
			return k
	return ""


func _validate() -> void:
	if _doc == null and _pal == null:
		return
	var problem := _doc.check_new_computer(key_edit.text) if _editing.is_empty() and _doc else ""
	var door := missing_door()
	door_check.visible = not door.is_empty()
	if door:
		door_check.text = "Also add a symbol for the door (%s)" % door
		var dk := door_key()
		if dk:
			door_check.text = "Also add '%s' for the door (%s)" % [dk, door]
	reach_label.text = reach_text()
	reach_label.visible = not reach_label.text.is_empty()
	var bad := editor.problems()
	get_ok_button().disabled = not problem.is_empty()
	var lines := PackedStringArray()
	if problem:
		lines.append(problem)
	if bad:
		lines.append("BN: " + bad.replace("\n", "; "))
	_info.text = "\n".join(lines)
	_info.add_theme_color_override("font_color", PROBLEM_COLOR if problem or bad else INFO_COLOR)


## One line per painted console of the edited key: what its door actions
## reach. "" for a new computer or one without door actions. For a palette
## key, the same per map using it.
func reach_text() -> String:
	if _pal:
		return _palette_reach_text()
	if _doc == null or _editing.is_empty():
		return ""
	var actions := Computer.of(editor.data).door_actions()
	if actions.is_empty():
		return ""
	var lines := PackedStringArray()
	var reaches := _doc.console_reaches(_editing, editor.data)
	if reaches.is_empty():
		return "'%s' isn't painted yet." % _editing
	for pair: Array in reaches:
		lines.append(ConsoleReachView.line(pair[0], pair[1], actions))
	return "\n".join(lines)


## reach_text() for a palette key: each map's consoles (maps judge the
## palette's computer where they paint it).
func _palette_reach_text() -> String:
	var maps: Array = _pal_consoles[0]
	var total: int = _pal_consoles[1]
	if total == 0:
		return "No map using %s paints '%s' with this computer yet; each map that does is checked on its own." % [_pal.id, _editing]
	var actions := Computer.of(editor.data).door_actions()
	var lines := PackedStringArray(["Painted in %d map%s using %s (a change here changes all of them):" % [
			total, "" if total == 1 else "s", _pal.id]])
	for m: Array in maps:
		var ref: DataIndex.MapgenRef = m[0]
		if actions.is_empty():
			lines.append("%s: %d console%s" % [ref.title(), m[3].size(), "" if m[3].size() == 1 else "s"])
			continue
		for at: Vector2i in m[3]:
			var reach := Validator.console_reach(_pal.index, m[1], m[2], at, editor.data)
			lines.append("%s: %s" % [ref.title(), ConsoleReachView.line(at, reach, actions)])
	if total > maps.size():
		lines.append("... and %d more map%s" % [total - maps.size(), "" if total - maps.size() == 1 else "s"])
	return "\n".join(lines)


func _on_confirmed() -> void:
	if _pal:
		palette_computer_ready.emit(_editing, editor.data.duplicate(true))
		return
	if _doc == null:
		return
	if _editing:
		if _doc.set_computer(_editing, editor.data).is_empty():
			computer_edited.emit(_editing)
		return
	var key := key_edit.text
	var dk := door_key()
	var door := missing_door()
	if _doc.add_computer_symbol(key, editor.data):
		return
	if dk and _doc.add_symbol(dk, door, "").is_empty():
		computer_added.emit(key, dk)
	else:
		computer_added.emit(key, "")

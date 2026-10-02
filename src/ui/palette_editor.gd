class_name PaletteEditor
extends Window
## The palette editor window: pick a palette, edit the terrain/furniture and
## computers of its keys and its included palettes, see which maps use it,
## create new palettes, and move a symbol from the current map into one of
## its palettes.
##
## Before an edit is made, every map using the palette is checked
## (PaletteImpact); if it changes maps other than the current one, they are
## named and the edit waits for a confirmation. Undo belongs to the palette.
## A key's "nested", "monster", "items", ... mappings
## (Placement.MAPPING_KINDS) are edited under the pickers (SymbolPieces);
## other per-key kinds (traps, signs, ...) are shown read-only. A key's computer opens in the same ComputerDialog as a map's
## ("Edit computer...", or "Add computer..." for a key without one).
##
## "Rename key..." renames a key the palette defines and repaints the maps
## taking it from the palette (PaletteImpact.plan_rename; asks first when
## other maps change). "Delete palette" takes an unused palette out of its
## file; Undo brings it back until the file is saved.

## Files changed (an edit, undo, save): tab titles and the browser may need
## updating.
signal files_changed
## A map in the "Used by" list was activated.
signal open_map_requested(ref: DataIndex.MapgenRef)

const MAX_NAMED := 25
## The most height the key's pieces take before they scroll.
const MAX_PIECES_HEIGHT := 260.0

var session: EditSession
## The palette shown, or null.
var doc: PaletteDocument
## The current map in the main window, or null.
var map_doc: MapDocument

var palette_list: ItemList
var symbols: Tree
var key_edit: LineEdit
var terrain: NewSymbolDialog.IdPicker
var furniture: NewSymbolDialog.IdPicker
var includes: ItemList
var include_edit: LineEdit
## Suggests palette ids in [member include_edit].
var include_completer: IdCompleter
var users: ItemList
var move_keys: OptionButton
var status: Label
## What BN would say about the palette's own definitions (see Validator).
var problems: Label
var confirm: ConfirmationDialog
var new_dialog: ConfirmationDialog
var new_id: LineEdit
var new_path: LineEdit
var computer_dialog: ComputerDialog
## The Key box's "nested", "items", ... mappings.
var pieces: SymbolPieces

var _search: LineEdit
var _symbol_filter: LineEdit
var _header: Label
var _undo_button: Button
var _redo_button: Button
var _save_button: Button
var _use_button: Button
var _apply_button: Button
var _remove_button: Button
var _computer_button: Button
var _rename_button: Button
var _delete_button: Button
## Asks for the new key of "Rename key...".
var rename_dialog: ConfirmationDialog
var rename_edit: LineEdit
var _rename_info: Label
## The palette deleted last while none is shown ("" for none), and its file.
var _deleted_id := ""
var _deleted_rel := ""
var _move_button: Button
var _move_label: Label
var _new_info: Label
var _pending := Callable()
var _new_path_touched := false
var _shown_key := ""


func _init() -> void:
	title = "Palettes"
	size = Vector2i(1180, 720)
	min_size = Vector2i(820, 520)
	transient = true
	exclusive = false
	visible = false
	close_requested.connect(hide)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var split := HSplitContainer.new()
	panel.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	split.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search palettes"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh_list())
	left.add_child(_search)
	palette_list = ItemList.new()
	palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_list.item_selected.connect(func(i: int) -> void: show_palette(palette_list.get_item_metadata(i)))
	left.add_child(palette_list)
	var new_button := Button.new()
	new_button.text = "New palette..."
	new_button.pressed.connect(open_new_dialog)
	left.add_child(new_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_header)
	problems = Label.new()
	problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	problems.add_theme_color_override("font_color", ProblemsPanel.COLORS[0])
	right.add_child(problems)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_undo_button = _button(bar, "Undo", undo, KEY_MASK_CTRL | KEY_Z)
	_redo_button = _button(bar, "Redo", redo, KEY_MASK_CTRL | KEY_Y)
	_save_button = _button(bar, "Save", save, KEY_MASK_CTRL | KEY_S)
	_save_button.tooltip_text = "Save the palette's file to the workspace"
	bar.add_child(VSeparator.new())
	_use_button = _button(bar, "Use in map", toggle_use_in_map)
	bar.add_child(VSeparator.new())
	_delete_button = _button(bar, "Delete palette", ask_delete_palette)

	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(middle)
	var sym_box := VBoxContainer.new()
	sym_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(sym_box)
	_symbol_filter = LineEdit.new()
	_symbol_filter.placeholder_text = "Filter symbols, ids"
	_symbol_filter.clear_button_enabled = true
	_symbol_filter.text_changed.connect(func(_t: String) -> void: _rebuild_symbols())
	sym_box.add_child(_symbol_filter)
	symbols = Tree.new()
	symbols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	symbols.hide_root = true
	symbols.columns = 4
	symbols.column_titles_visible = true
	for c in 4:
		symbols.set_column_title(c, ["Key", "Terrain", "Furniture", "Also / from"][c])
	symbols.set_column_expand(0, false)
	symbols.set_column_custom_minimum_width(0, 64)
	symbols.item_selected.connect(_on_symbol_selected)
	sym_box.add_child(symbols)

	var edit := VBoxContainer.new()
	edit.custom_minimum_size = Vector2(360, 0)
	middle.add_child(edit)
	var key_row := HBoxContainer.new()
	edit.add_child(key_row)
	key_row.add_child(_label("Key:"))
	key_edit = LineEdit.new()
	key_edit.custom_minimum_size = Vector2(50, 0)
	key_edit.max_length = 4
	key_edit.tooltip_text = "The symbol to set; type a new one to add it"
	key_edit.text_changed.connect(func(_t: String) -> void:
		_update_buttons()
		_show_pieces())
	key_row.add_child(key_edit)
	_apply_button = _button(key_row, "Apply", apply_edit)
	_apply_button.tooltip_text = "Set this key's terrain and furniture in the palette"
	_remove_button = _button(key_row, "Remove key", remove_key)
	_remove_button.tooltip_text = "Remove this key's terrain and furniture from the palette"
	_rename_button = _button(key_row, "Rename key...", open_rename_dialog)
	_rename_button.tooltip_text = "Give this key another symbol here and in every map taking it from the palette"
	_computer_button = _button(key_row, "Add computer...", func() -> void: edit_computer())
	terrain = NewSymbolDialog.IdPicker.new("Terrain")
	furniture = NewSymbolDialog.IdPicker.new("Furniture")
	for p: NewSymbolDialog.IdPicker in [terrain, furniture]:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.list.custom_minimum_size = Vector2(0, 80)
		edit.add_child(p)
	var pieces_scroll := ScrollContainer.new()
	pieces_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	edit.add_child(pieces_scroll)
	pieces = SymbolPieces.new()
	# As tall as the pieces need, up to MAX_PIECES_HEIGHT (then it scrolls).
	pieces.minimum_size_changed.connect(func() -> void:
		pieces_scroll.custom_minimum_size.y = minf(pieces.get_combined_minimum_size().y, MAX_PIECES_HEIGHT))
	pieces.get_own = func(key: String, kind: String) -> Variant:
		return doc.piece(key, kind) if doc else null
	pieces.set_own = set_piece
	pieces.message.connect(func(text: String) -> void: status.text = text)
	pieces.open_palette_requested.connect(func(id: String, key: String) -> void:
		var def := session.index.palette(id) if session else null
		if def:
			show_palette(def)
			show_key(key))
	pieces_scroll.add_child(pieces)

	var lower := HBoxContainer.new()
	lower.custom_minimum_size = Vector2(0, 140)
	right.add_child(lower)
	var inc_box := VBoxContainer.new()
	inc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(inc_box)
	inc_box.add_child(_label("Includes (applied before the palette's own keys)"))
	includes = ItemList.new()
	includes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	includes.item_selected.connect(func(_i: int) -> void: _update_buttons())
	inc_box.add_child(includes)
	var inc_buttons := HBoxContainer.new()
	inc_box.add_child(inc_buttons)
	include_edit = LineEdit.new()
	include_edit.placeholder_text = "palette id"
	include_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	include_edit.text_submitted.connect(func(_t: String) -> void: add_include())
	inc_buttons.add_child(include_edit)
	include_completer = IdCompleter.new(include_edit, func() -> PackedStringArray:
		var ids := PackedStringArray(session.index.palettes.keys() if session else [])
		ids.sort()
		return ids)
	_button(inc_buttons, "Add", add_include)
	_button(inc_buttons, "Remove", remove_include)
	_button(inc_buttons, "Up", move_include.bind(-1))
	_button(inc_buttons, "Down", move_include.bind(1))
	var users_box := VBoxContainer.new()
	users_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(users_box)
	users_box.add_child(_label("Used by (double-click to open)"))
	users = ItemList.new()
	users.size_flags_vertical = Control.SIZE_EXPAND_FILL
	users.item_activated.connect(func(i: int) -> void: open_map_requested.emit(users.get_item_metadata(i)))
	users_box.add_child(users)

	var move_row := HBoxContainer.new()
	right.add_child(move_row)
	_move_label = _label("")
	move_row.add_child(_move_label)
	move_keys = OptionButton.new()
	move_keys.custom_minimum_size = Vector2(60, 0)
	move_keys.item_selected.connect(func(_i: int) -> void: _update_buttons())
	move_row.add_child(move_keys)
	_move_button = _button(move_row, "Move into this palette", move_symbol)
	_move_button.tooltip_text = "Take the symbol's terrain/furniture out of the map and define it in this palette"
	status = _label("")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(status)

	confirm = ConfirmationDialog.new()
	confirm.title = "Other maps change"
	confirm.ok_button_text = "Apply anyway"
	confirm.canceled.connect(_show_pieces)
	confirm.confirmed.connect(func() -> void:
		var then := _pending
		_pending = Callable()
		if then.is_valid():
			then.call())
	add_child(confirm)
	_build_new_dialog()
	_build_rename_dialog()
	computer_dialog = ComputerDialog.new()
	computer_dialog.palette_computer_ready.connect(_on_computer_ready)
	add_child(computer_dialog)


## Uses [param p_session] (after a reload, the old one is gone).
func setup(p_session: EditSession) -> void:
	session = p_session
	doc = null
	map_doc = null
	_deleted_id = ""
	_deleted_rel = ""
	terrain.table = session.index.terrain
	furniture.table = session.index.furniture
	terrain.refresh()
	furniture.refresh()
	refresh_list()
	_refresh()


## Shows the window with palette [param id] (the one in effect), or the
## current selection if "".
func open(p_session: EditSession, id := "") -> void:
	if session != p_session:
		setup(p_session)
	if id and session.index.palette(id):
		show_palette(session.index.palette(id))
	_popup(self)


## The main window's current map changed ([param p_map] may be null).
func set_map(p_map: MapDocument) -> void:
	if map_doc and map_doc.changed.is_connected(_on_map_changed):
		map_doc.changed.disconnect(_on_map_changed)
	map_doc = p_map
	if map_doc:
		map_doc.changed.connect(_on_map_changed)
	_refresh_map_part()


## Opens [param def] for editing and shows it. The previous palette is
## closed unless its file has unsaved changes.
func show_palette(def: DataIndex.Definition) -> void:
	if doc and doc.def == def:
		return
	var next := session.open_palette(def)
	if next == null:
		status.text = session.last_error
		return
	if doc:
		doc.changed.disconnect(_on_doc_changed)
		if not doc.file.is_dirty():
			session.close_palette(doc)
	doc = next
	doc.changed.connect(_on_doc_changed)
	_shown_key = ""
	key_edit.text = ""
	status.text = ""
	_refresh()
	for i in palette_list.item_count:
		if palette_list.get_item_metadata(i) == def:
			palette_list.select(i)
			palette_list.ensure_current_is_visible()


## Lists every palette definition matching the search.
func refresh_list() -> void:
	palette_list.clear()
	if session == null:
		return
	var q := _search.text.strip_edges().to_lower()
	var ids: Array = session.index.palettes.keys()
	ids.sort()
	for id: String in ids:
		if q and not id.to_lower().contains(q):
			continue
		var defs: Array = session.index.palettes[id]
		for def: DataIndex.Definition in defs:
			var text := id
			if def.source.mod != "bn" and def.source.mod:
				text += "  [%s]" % def.source.mod
			if def != defs[-1]:
				text += "  (replaced)"
			var open_doc := session.palette_doc_for(def)
			if open_doc and open_doc.file.is_dirty():
				text += " *"
			var i := palette_list.add_item(text)
			palette_list.set_item_metadata(i, def)
			palette_list.set_item_tooltip(i, str(def.source))
			if doc and doc.def == def:
				palette_list.select(i)


# --- Edits ---------------------------------------------------------------------

## Sets the key in the Key box to the chosen terrain/furniture.
func apply_edit() -> void:
	if doc == null:
		return
	var key := key_edit.text
	var ter: Variant = _picked(terrain)
	var furn: Variant = _picked(furniture)
	var problem := doc.check_tiles(key, ter, furn)
	if problem:
		status.text = problem
		return
	_try(doc.build_set_tiles(key, ter, furn))


func remove_key() -> void:
	if doc and key_edit.text:
		_try(doc.build_remove_key(key_edit.text))


## Opens the computer of [param key] (the Key box's if "") in the
## computer dialog: the palette's own, or a new Door control. Returns why it
## can't, or "".
func edit_computer(key := "") -> String:
	if doc == null:
		return "No palette."
	if key.is_empty():
		key = key_edit.text
	elif key != key_edit.text:
		select_key(key)
		key_edit.text = key
		_update_buttons()
	var problem := "Type a key first." if key.is_empty() else doc.check_computer(key)
	if problem:
		status.text = problem
		return problem
	computer_dialog.setup_palette(session, doc, key)
	_popup(computer_dialog)
	return ""


## The computer dialog's OK: commits the computer for [param key] once the
## maps it changes are confirmed.
func _on_computer_ready(key: String, data: Dictionary) -> void:
	if doc:
		_try(doc.build_set_computer(key, data))


## Sets the palette's own [param kind] mapping for [param key] (null
## removes it), once the maps it changes are confirmed. Returns an error,
## or "" (also while it waits for the confirmation).
func set_piece(key: String, kind: String, value: Variant) -> String:
	if doc == null:
		return "No palette."
	var problem := doc.check_piece(key, kind, value)
	if problem:
		status.text = problem
		return problem
	var c := doc.build_set_piece(key, kind, value)
	if c:
		_try(c)
	return ""


func add_include() -> void:
	var id := include_edit.text.strip_edges()
	if doc == null or id.is_empty():
		return
	if session.index.palette(id) == null:
		status.text = "Unknown palette \"%s\"." % id
		return
	if session.index.palette_closure(PackedStringArray([id])).has(doc.id):
		status.text = "%s includes %s already, so that would be a loop." % [id, doc.id]
		return
	var list := doc.includes().duplicate()
	list.append(id)
	include_edit.text = ""
	_try(doc.build_set_includes(list, "Include " + id))


func remove_include() -> void:
	var sel := includes.get_selected_items()
	if doc == null or sel.is_empty():
		return
	var list := doc.includes().duplicate()
	list.remove_at(sel[0])
	_try(doc.build_set_includes(list, "Remove include"))


func move_include(step: int) -> void:
	var sel := includes.get_selected_items()
	if doc == null or sel.is_empty():
		return
	var i := sel[0]
	var j := i + step
	var list := doc.includes().duplicate()
	if j < 0 or j >= list.size():
		return
	var v: Variant = list[i]
	list[i] = list[j]
	list[j] = v
	_try(doc.build_set_includes(list, "Reorder includes"))
	includes.select(j)


func undo() -> void:
	if doc and doc.can_undo():
		var name := doc.undo_name()
		doc.undo()
		status.text = "Undid " + name
	elif doc == null and _deleted_id and session.deleted_palette(_deleted_id):
		var id := _deleted_id
		var def := session.deleted_palette(id).def
		var err := session.restore_palette(id)
		if err:
			status.text = err
			return
		_deleted_id = ""
		refresh_list()
		# The definition deleted, even when another of its id is in effect.
		show_palette(def)
		status.text = "Restored palette %s." % id
		files_changed.emit()


func redo() -> void:
	if doc and doc.can_redo():
		var name := doc.redo_name()
		doc.redo()
		status.text = "Redid " + name


func save() -> void:
	var rel := doc.file.rel_path if doc else _deleted_rel
	if rel.is_empty() or not session.is_dirty(rel):
		return
	var err := session.save(rel)
	status.text = "Save failed: " + err if err else "Saved %s to the workspace." % rel
	if not err and doc == null:
		_deleted_id = ""
	_after_change()


# --- Rename and delete -----------------------------------------------------------

func open_rename_dialog() -> void:
	if doc == null or key_edit.text.is_empty():
		return
	rename_edit.text = ""
	rename_dialog.title = "Rename '%s' in %s" % [LegendPanel._show_key(key_edit.text), doc.id]
	_update_rename()
	_popup(rename_dialog)
	if rename_edit.is_inside_tree():
		rename_edit.grab_focus()


func _build_rename_dialog() -> void:
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.ok_button_text = "Rename"
	var box := VBoxContainer.new()
	rename_dialog.add_child(box)
	box.add_child(_label("New key (maps taking the key from this palette are repainted):"))
	rename_edit = LineEdit.new()
	rename_edit.max_length = 4
	rename_edit.text_changed.connect(func(_t: String) -> void: _update_rename())
	rename_edit.text_submitted.connect(func(_t: String) -> void:
		if not rename_dialog.get_ok_button().disabled:
			rename_dialog.hide()
			rename_key(rename_edit.text))
	box.add_child(rename_edit)
	_rename_info = _label("")
	_rename_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rename_info.custom_minimum_size = Vector2(420, 0)
	box.add_child(_rename_info)
	rename_dialog.confirmed.connect(func() -> void: rename_key(rename_edit.text))
	add_child(rename_dialog)


func _update_rename() -> void:
	var why := doc.check_rename(key_edit.text, rename_edit.text) if doc else "No palette."
	_rename_info.text = why if why else "The maps using %s are checked when you press Rename." % doc.id
	rename_dialog.get_ok_button().disabled = not why.is_empty()


## Renames the Key box's key to [param new_key] (see
## PaletteImpact.plan_rename), asking first when maps other than the
## current one are repainted or change. Returns an error, or "" (also while
## it waits for the confirmation).
func rename_key(new_key: String) -> String:
	if doc == null:
		return "No palette."
	var old := key_edit.text
	var plan := PaletteImpact.plan_rename(session, doc, old, new_key)
	if plan.problem:
		status.text = plan.problem
		return plan.problem
	# The plan is for this palette as it is now; the confirmation may come
	# after another palette is shown.
	var planned := doc
	var run := func() -> void:
		if doc != planned:
			status.text = "Not renamed: palette %s isn't shown any more." % planned.id
			return
		var err := session.rename_palette_key(doc, plan)
		if err:
			status.text = err
			return
		key_edit.text = new_key
		_shown_key = new_key
		_after_change()
		show_key(new_key)
		status.text = "Renamed '%s' to '%s': repainted %s%s (unsaved: Save all saves the maps; Undo here undoes them too)." % [
			old, new_key, _count_text(plan.repainted),
			", changed %s" % _count_text(plan.changed) if not plan.changed.is_empty() else ""]
	var others := (plan.repainted + plan.changed).filter(func(a: PaletteImpact.Affected) -> bool:
		return map_doc == null or a.ref != map_doc.ref)
	if others.is_empty():
		run.call()
		return ""
	var lines := PackedStringArray()
	lines.append("Renaming '%s' to '%s' repaints %s:" % [old, new_key, _count_text(plan.repainted)])
	lines.append_array(_named(plan.repainted))
	if not plan.changed.is_empty():
		lines.append("and changes how %s look (they keep '%s' themselves, or get part of it elsewhere):" % [
			_count_text(plan.changed), old])
		lines.append_array(_named(plan.changed))
	confirm.dialog_text = "\n".join(lines)
	_pending = run
	_popup(confirm)
	return ""


## Deletes the palette shown, after asking. Returns why it can't, or "".
func ask_delete_palette() -> String:
	if doc == null:
		return "No palette."
	var problem := session.check_delete_palette(doc.def)
	if problem:
		status.text = problem
		return problem
	confirm.dialog_text = "Delete palette %s from %s? Unsaved until you save the file; Undo brings it back until then." % [
		doc.id, doc.file.rel_path]
	_pending = delete_palette
	_popup(confirm)
	return ""


## Deletes the palette shown (see EditSession.delete_palette). Returns an
## error, or "".
func delete_palette() -> String:
	if doc == null:
		return "No palette."
	var id := doc.id
	var rel := doc.file.rel_path
	var old := doc
	var err := session.delete_palette(doc.def)
	if err:
		status.text = err
		return err
	old.changed.disconnect(_on_doc_changed)
	doc = null
	_deleted_id = id
	_deleted_rel = rel
	key_edit.text = ""
	_shown_key = ""
	status.text = "Deleted palette %s from %s (unsaved; Undo brings it back, Save writes the file)." % [id, rel]
	_after_change()
	return ""


## Adds this palette to the current map's "palettes" (last, so it wins), or
## takes it out again.
func toggle_use_in_map() -> void:
	if doc == null or map_doc == null:
		return
	if map_doc.palette_list().has(doc.id):
		map_doc.remove_palette(doc.id)
		status.text = "%s no longer lists %s." % [map_doc.ref.title(), doc.id]
	else:
		map_doc.add_palette(doc.id)
		status.text = "%s now lists %s last (undo in the map)." % [map_doc.ref.title(), doc.id]
	_after_change()


## Moves the chosen own symbol of the current map into this palette.
func move_symbol() -> void:
	if doc == null or map_doc == null or move_keys.selected < 0:
		return
	var key: String = move_keys.get_item_metadata(move_keys.selected)
	var problem := session.check_move_symbol(map_doc, doc, key)
	if problem:
		status.text = problem
		return
	var affected := session.move_symbol_impact(map_doc, doc, key)
	var run := func() -> void:
		session.move_symbol(map_doc, doc, key)
		status.text = "Moved '%s' into %s (one undo step here, one in the map)." % [key, doc.id]
		_after_change()
	if affected.is_empty():
		run.call()
	else:
		_ask(affected, run)


## Makes [param c] after checking which maps it changes; asks first if that
## includes maps other than the current one.
func _try(c: PaletteDocument.Change) -> void:
	if c == null:
		status.text = "Nothing to change."
		return
	var affected := session.impact_of(doc, c)
	var run := func() -> void:
		doc.commit(c)
		status.text = "%s: changes %s." % [c.name, _count_text(affected)]
	var others := affected.filter(func(a: PaletteImpact.Affected) -> bool:
		return map_doc == null or a.ref != map_doc.ref)
	if others.is_empty():
		run.call()
	else:
		_ask(affected, run)


func _ask(affected: Array[PaletteImpact.Affected], then: Callable) -> void:
	var lines := _named(affected)
	confirm.dialog_text = "This changes %s (the symbols listed, or via a nested chunk they place):\n%s" % [_count_text(affected), "\n".join(lines)]
	_pending = then
	_popup(confirm)


## One line per map of [param affected] (at most MAX_NAMED).
static func _named(affected: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for a: PaletteImpact.Affected in affected.slice(0, MAX_NAMED):
		lines.append("  %s (%s): %s" % [a.ref.title(), a.ref.source.path, a.what()])
	if affected.size() > MAX_NAMED:
		lines.append("  ... and %d more" % (affected.size() - MAX_NAMED))
	return lines


static func _count_text(affected: Array) -> String:
	return "no map" if affected.is_empty() else ("1 map" if affected.size() == 1 else "%d maps" % affected.size())


static func _picked(p: NewSymbolDialog.IdPicker) -> Variant:
	var v := p.selected()
	return null if v == NewSymbolDialog.IdPicker.KEEP else v


# --- New palette ---------------------------------------------------------------

func open_new_dialog() -> void:
	_new_path_touched = false
	new_id.text = ""
	_update_new_path()
	_popup(new_dialog)
	if new_id.is_inside_tree():
		new_id.grab_focus()


## Creates the palette the New palette dialog describes. Returns an error or "".
func create_palette() -> String:
	var d := session.create_palette(new_path.text.strip_edges(), new_id.text.strip_edges())
	if d == null:
		status.text = session.last_error
		return session.last_error
	refresh_list()
	show_palette(d.def)
	status.text = "Created %s in %s (unsaved)." % [d.id, d.file.rel_path]
	files_changed.emit()
	return ""


func _build_new_dialog() -> void:
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "New palette"
	new_dialog.ok_button_text = "Create"
	var box := VBoxContainer.new()
	new_dialog.add_child(box)
	box.add_child(_label("Palette id:"))
	new_id = LineEdit.new()
	new_id.text_changed.connect(func(_t: String) -> void: _update_new_path())
	box.add_child(new_id)
	box.add_child(_label("File (relative to BN; new or existing):"))
	new_path = LineEdit.new()
	new_path.custom_minimum_size = Vector2(460, 0)
	new_path.text_changed.connect(func(_t: String) -> void:
		_new_path_touched = true
		_validate_new())
	box.add_child(new_path)
	_new_info = _label("")
	_new_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_new_info)
	new_dialog.confirmed.connect(func() -> void: create_palette())
	add_child(new_dialog)


func _update_new_path() -> void:
	if not _new_path_touched and session:
		new_path.text = session.default_palette_path(new_id.text.strip_edges(),
				map_doc.file.rel_path if map_doc else "")
		_new_path_touched = false
	_validate_new()


func _validate_new() -> void:
	if session == null:
		return
	var problem := session.check_new_palette(new_path.text.strip_edges(), new_id.text.strip_edges())
	_new_info.text = problem
	new_dialog.get_ok_button().disabled = not problem.is_empty()


# --- Display -------------------------------------------------------------------

func _on_doc_changed() -> void:
	_after_change()


func _on_map_changed(_full: bool) -> void:
	if visible:
		_refresh_map_part()
		_refresh_users()


func _after_change() -> void:
	_refresh()
	refresh_list()
	files_changed.emit()


func _refresh() -> void:
	_rebuild_symbols()
	_show_pieces()
	_refresh_includes()
	_refresh_users()
	_refresh_map_part()
	_show_problems()
	if doc == null:
		_header.text = "Pick a palette on the left, or create one." if session else ""
		_update_buttons()
		return
	var lines := PackedStringArray(["Palette %s   %s #%d (%s)%s" % [doc.id, doc.file.rel_path,
			doc.object_index, doc.def.source.mod, "  *" if doc.file.is_dirty() else ""]])
	var over := doc.overridden_by()
	if over:
		lines.append("Replaced by the definition in %s: editing this one changes nothing in game while that is loaded." % over.source)
	var others := session.docs_for(doc.file.rel_path).size()
	if others:
		lines.append("%d open map(s) share this file; saving saves them too." % others)
	_header.text = "\n".join(lines)
	_update_buttons()


func _rebuild_symbols() -> void:
	symbols.clear()
	if doc == null:
		return
	var view := doc.view()
	var ascii := AsciiMap.build(session.index, view)
	var root := symbols.create_item()
	var q := _symbol_filter.text.strip_edges().to_lower()
	var keys: Array = view.symbols.keys()
	keys.sort()
	var by_key := findings_by_key()
	for key: String in keys:
		var info: ResolvedMapgen.SymbolInfo = view.symbols[key]
		var ter := _binding_text(info.terrain, "t_null" if info.null_terrain else "")
		var furn := _binding_text(info.furniture, "")
		var also := PackedStringArray()
		for kind: String in info.extras:
			var srcs := PackedStringArray()
			for b: ResolvedMapgen.Binding in info.extras[kind]:
				if b.from_palette() and not srcs.has(b.source):
					srcs.append(b.source)
			var what := kind
			var last: ResolvedMapgen.Binding = info.extras[kind][-1]
			if kind == "computers" and last.value is Dictionary:
				what = "computer \"%s\"" % Computer.of(last.value).name()
			also.append(what + (" (%s)" % ", ".join(srcs) if srcs.size() else ""))
		if q and not (key + " " + ter + " " + furn + " " + " ".join(also)).to_lower().contains(q):
			continue
		var item := symbols.create_item(root)
		var look := ascii.look_for(key)
		item.set_text(0, "%s  %s" % [LegendPanel._show_key(key), look.ch])
		item.set_custom_color(0, look.colors.fg)
		item.set_custom_bg_color(0, look.colors.bg)
		item.set_text(1, ter)
		item.set_text(2, furn)
		item.set_text(3, ", ".join(also))
		if by_key.has(key):
			var texts: Array = by_key[key].map(func(f: Validator.Finding) -> String: return f.describe())
			item.set_text(0, item.get_text(0) + "  !")
			item.set_tooltip_text(0, "\n".join(texts))
		item.set_tooltip_text(1, JSON.stringify(info.terrain.value) if info.terrain else "")
		item.set_tooltip_text(2, JSON.stringify(info.furniture.value) if info.furniture else "")
		item.set_metadata(0, key)
		if key == _shown_key:
			item.select(0)


## The palette's findings, by key ("" for the palette itself).
func findings_by_key() -> Dictionary:
	var out := {}
	if doc == null:
		return out
	for f in Validator.sorted(Validator.validate_palette(session.index, doc.id, doc.def.data)):
		if not out.has(f.key):
			out[f.key] = []
		out[f.key].append(f)
	return out


func _show_problems() -> void:
	var lines := PackedStringArray()
	var by_key := findings_by_key()
	for key: String in by_key:
		for f: Validator.Finding in by_key[key]:
			lines.append(f.describe())
	if lines.size() > 6:
		lines = lines.slice(0, 5) + PackedStringArray(["... %d more (keys marked ! in the list)" % (lines.size() - 5)])
	problems.text = "\n".join(lines)
	problems.visible = not lines.is_empty()


## Selects [param key] and shows it in the Key box, its pickers and pieces.
## False if the palette doesn't define it.
func show_key(key: String) -> bool:
	var found := select_key(key)
	if found and _shown_key != key:
		_on_symbol_selected()
	elif not found:
		key_edit.text = key
		_update_buttons()
		_show_pieces()
	return found


## The Key box's "nested", "items", ... mappings (none without a palette).
func _show_pieces() -> void:
	pieces.index = session.index if session else null
	var key := key_edit.text if doc and MapDocument.check_key_shape(key_edit.text).is_empty() else ""
	pieces.show_key(key, doc.view().symbols.get(key) if key else null)


## Selects [param key] in the symbol list (clearing the filter), as if
## clicked. False if the palette doesn't define it.
func select_key(key: String) -> bool:
	if _symbol_filter.text:
		_symbol_filter.text = ""
		_rebuild_symbols()
	var root := symbols.get_root()
	var it := root.get_first_child() if root else null
	while it:
		if it.get_metadata(0) == key:
			it.select(0)
			symbols.scroll_to_item(it)
			return true
		it = it.get_next()
	return false


## An id (with "(from p)" when an included palette defines it), or a short
## form of a distribution etc.
func _binding_text(b: ResolvedMapgen.Binding, none: String) -> String:
	if b == null:
		return none
	var text := b.id() if b.value is String else "%s (one of %d)" % [b.id(), b.ids.size()]
	if b.from_palette():
		text += "  (from %s)" % b.source
	return text


func _on_symbol_selected() -> void:
	var item := symbols.get_selected()
	if item == null or doc == null:
		return
	_shown_key = item.get_metadata(0)
	key_edit.text = _shown_key
	_show_value(terrain, doc.tile_value(_shown_key, "terrain"))
	_show_value(furniture, doc.tile_value(_shown_key, "furniture"))
	var info: ResolvedMapgen.SymbolInfo = doc.view().symbols.get(_shown_key)
	# The palette's own definitions resolve as "map"; included ones by id.
	var from := PackedStringArray()
	for b: ResolvedMapgen.Binding in [info.terrain, info.furniture]:
		if b and b.from_palette() and not from.has(b.source):
			from.append(b.source)
	status.text = "'%s' comes from %s here; Apply defines it in %s itself, over the include." % [
		_shown_key, ", ".join(from), doc.id] if from.size() else ""
	var comp: Variant = doc.computer(_shown_key)
	if comp:
		status.text = ("Computer: %s   " % Computer.of(comp).summary()) + status.text
	elif info.extras.has("computers"):
		var b: ResolvedMapgen.Binding = info.extras.computers[-1]
		if b.from_palette():
			status.text = "Its computer comes from %s; edit it there (Add computer... here gives %s its own). " % [
				b.source, doc.id] + status.text
	_update_buttons()
	_show_pieces()


## Puts [param value] (the palette's own, or null) in [param p]: an id is
## selected, anything else is kept as written.
func _show_value(p: NewSymbolDialog.IdPicker, value: Variant) -> void:
	p.keep_text = ""
	p.table = session.index.terrain if p == terrain else session.index.furniture
	if value is String:
		p.select_id(value)
	elif value == null:
		p.select_id("")
	else:
		p.keep_text = LegendPanel._short_value(value)
		p.select_id(NewSymbolDialog.IdPicker.KEEP)


func _refresh_includes() -> void:
	includes.clear()
	if doc == null:
		return
	for v: Variant in doc.includes():
		includes.add_item(v if v is String else JSON.stringify(v))


func _refresh_users() -> void:
	users.clear()
	if doc == null:
		return
	var refs := session.index.maps_using(doc.id)
	refs.sort_custom(func(a: DataIndex.MapgenRef, b: DataIndex.MapgenRef) -> bool: return a.title() < b.title())
	for ref in refs:
		var i := users.add_item("%s   %s" % [ref.title(), ref.source.path])
		users.set_item_metadata(i, ref)
		users.set_item_tooltip(i, "%s #%d" % [ref.source.path, ref.source.index])


func _refresh_map_part() -> void:
	move_keys.clear()
	var has_map := map_doc != null and doc != null
	_use_button.disabled = not has_map
	_use_button.text = "Use in map"
	_move_label.text = "Current map: none"
	if not has_map:
		_update_buttons()
		return
	var listed := map_doc.palette_list().has(doc.id)
	_use_button.text = ("Stop using in %s" if listed else "Use in %s") % map_doc.ref.title()
	_move_label.text = "Symbols defined in %s itself:" % map_doc.ref.title()
	for key in map_doc.own_keys():
		var ter: Variant = map_doc.own_value(key, "terrain")
		var furn: Variant = map_doc.own_value(key, "furniture")
		var ids := PackedStringArray()
		for v: Variant in [ter, furn]:
			if v != null:
				ids.append(v if v is String else "…")
		move_keys.add_item("%s  %s" % [LegendPanel._show_key(key), " + ".join(ids)])
		move_keys.set_item_metadata(move_keys.item_count - 1, key)
	_update_buttons()


func _update_buttons() -> void:
	var has := doc != null
	var restorable := not has and _deleted_id and session != null and session.deleted_palette(_deleted_id) != null
	_undo_button.disabled = not ((has and doc.can_undo()) or restorable)
	_undo_button.tooltip_text = "Undo " + doc.undo_name() if has and doc.can_undo() else (
			"Undo deleting palette " + _deleted_id if restorable else "Undo")
	_redo_button.disabled = not (has and doc.can_redo())
	_redo_button.tooltip_text = "Redo " + doc.redo_name() if has and doc.can_redo() else "Redo"
	_save_button.disabled = not ((has and doc.file.is_dirty()) or (not has and _deleted_rel and session != null \
			and session.is_dirty(_deleted_rel)))
	_delete_button.disabled = not has
	_rename_button.disabled = not has or not doc.own_keys().has(key_edit.text)
	_apply_button.disabled = not has or key_edit.text.is_empty()
	_remove_button.disabled = not has or key_edit.text.is_empty() \
			or (doc.tile_value(key_edit.text, "terrain") == null and doc.tile_value(key_edit.text, "furniture") == null)
	var editing := has and doc.has_computer(key_edit.text)
	_computer_button.text = "Edit computer..." if editing else "Add computer..."
	var why := "Type or pick a key first." if not has or key_edit.text.is_empty() else doc.check_computer(key_edit.text)
	_computer_button.disabled = not why.is_empty()
	_computer_button.tooltip_text = why if why else ("Edit this key's computer (every map painting the key changes)" \
			if editing else "Give this key a computer (a console; Door control to start with)")
	_move_button.disabled = not has or map_doc == null or move_keys.item_count == 0


## Shows [param w]; headless tests run outside the tree, where they just
## check what would be shown.
static func _popup(w: Window) -> void:
	if w.is_inside_tree():
		w.popup_centered()
	else:
		w.visible = true


func _button(parent: Control, text: String, handler: Callable, key := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	if key:
		var ev := InputEventKey.new()
		ev.keycode = key & KEY_CODE_MASK
		ev.ctrl_pressed = key & KEY_MASK_CTRL != 0
		b.shortcut = Shortcut.new()
		b.shortcut.events = [ev]
	parent.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

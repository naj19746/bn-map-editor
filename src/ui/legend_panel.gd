class_name LegendPanel
extends VBoxContainer
## Lists the symbols of the open map: how each one looks, its terrain and
## furniture, and where every definition comes from (the map, fill_ter, or
## which palette). Symbols the rows don't use are listed separately.
## Selecting a symbol makes it the brush; "New symbol..." defines another.
## "New computer..." defines a console symbol, and "Edit computer..." (or a
## double-click) edits the selected symbol's computer: in the map when the
## map defines it, else in the palette editor at the palette defining it.
## Below the list, the selected symbol's "nested", "items", ... mappings
## (SymbolPieces): the map's own are edited there, a palette's open in the
## palette editor. "Rename..." and "Remove" act on a symbol the map defines
## itself (every kind it defines; renaming repaints its cells too), each one
## undo step of the map. The fill_ter row above the list sets the map's
## fill_ter (the terrain of cells whose symbol gives none), or removes it
## when left blank; chunks have none.

## A symbol was selected ("" when the selection was cleared).
signal key_selected(key: String)
## The "New symbol..." button was pressed.
signal new_symbol_requested
## "New computer..." was pressed.
signal new_computer_requested
## "Edit computer..." was pressed (or a computer symbol double-clicked).
signal edit_computer_requested(key: String)
## "Palette..." was pressed: open the palette editor at [param id] (the
## selected symbol's palette), or "" for no particular one.
signal palette_requested(id: String)
## "Open" next to a piece from a palette: edit [param key] in palette
## [param id].
signal palette_key_requested(id: String, key: String)
## Something to tell the user (an edit was refused).
signal message(text: String)

const MAX_VALUE_TEXT := 90

var _filter: LineEdit
var _tree: Tree
var _ascii: AsciiMap
## The map shown (for editing its own symbol pieces), or null.
var doc: MapDocument
## The selected symbol's "nested", "items", ... mappings.
var pieces: SymbolPieces
## key -> the symbol's TreeItem.
var _items := {}
var _selecting := false
## The selected symbol, kept across rebuilds; null for none.
var _selected: Variant = null
var _editable := true
var _new_button: Button
var _new_computer_button: Button
var _edit_computer_button: Button
var _rename_button: Button
var _remove_button: Button
## Asks for the new symbol of "Rename...".
var rename_dialog: ConfirmationDialog
var rename_edit: LineEdit
var _rename_info: Label
## What the selected computer reaches (see set_reach()).
var reach_label: Label
## The fill_ter row (hidden for chunks): the map's fill_ter, applied on
## Enter or when it loses focus.
var fill_row: HBoxContainer
var fill_edit: LineEdit
var fill_completer: IdCompleter
## The map whose fill_ter the row holds (typed text never moves to another).
var _fill_doc: MapDocument


func _init() -> void:
	name = "Legend"
	var top := HBoxContainer.new()
	add_child(top)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter symbols, ids, palettes"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	top.add_child(_filter)
	_new_button = Button.new()
	_new_button.text = "New symbol..."
	_new_button.tooltip_text = "Define a new symbol in this map (Ctrl+E)"
	_new_button.disabled = true
	_new_button.pressed.connect(func() -> void: new_symbol_requested.emit())
	top.add_child(_new_button)
	var palette_button := Button.new()
	palette_button.text = "Palette..."
	palette_button.tooltip_text = "Edit the palette that defines the selected symbol (Ctrl+Shift+E)"
	palette_button.pressed.connect(func() -> void: palette_requested.emit(selected_palette()))
	top.add_child(palette_button)
	var row := HFlowContainer.new()
	add_child(row)
	_new_computer_button = Button.new()
	_new_computer_button.text = "New computer..."
	_new_computer_button.tooltip_text = "Define a console symbol with a computer (e.g. one that unlocks doors) in this map"
	_new_computer_button.disabled = true
	_new_computer_button.pressed.connect(func() -> void: new_computer_requested.emit())
	row.add_child(_new_computer_button)
	_edit_computer_button = Button.new()
	_edit_computer_button.text = "Edit computer..."
	_edit_computer_button.disabled = true
	_edit_computer_button.pressed.connect(func() -> void:
		if _selected is String:
			edit_computer_requested.emit(_selected))
	row.add_child(_edit_computer_button)
	row.add_child(VSeparator.new())
	_rename_button = Button.new()
	_rename_button.text = "Rename..."
	_rename_button.disabled = true
	_rename_button.pressed.connect(open_rename_dialog)
	row.add_child(_rename_button)
	_remove_button = Button.new()
	_remove_button.text = "Remove"
	_remove_button.disabled = true
	_remove_button.pressed.connect(func() -> void: remove_selected())
	row.add_child(_remove_button)
	_build_rename_dialog()
	_build_fill_row()
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(0, 160)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 3
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 84)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 48)
	_tree.item_selected.connect(_on_selected)
	_tree.item_activated.connect(func() -> void:
		if _selected is String and computer_state(_selected).is_empty():
			edit_computer_requested.emit(_selected))
	_tree.nothing_selected.connect(func() -> void:
		_tree.deselect_all()
		key_selected.emit(""))
	split.add_child(_tree)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	split.add_child(scroll)
	pieces = SymbolPieces.new()
	pieces.get_own = func(key: String, kind: String) -> Variant:
		return doc.own_piece(key, kind) if doc else null
	pieces.set_own = func(key: String, kind: String, value: Variant) -> String:
		return doc.set_own_piece(key, kind, value) if doc else "No map."
	pieces.message.connect(func(text: String) -> void: message.emit(text))
	pieces.open_palette_requested.connect(func(id: String, key: String) -> void:
		palette_key_requested.emit(id, key))
	pieces.visible = false
	pieces.visibility_changed.connect(func() -> void: scroll.visible = pieces.visible)
	scroll.add_child(pieces)
	reach_label = reach_label_new()
	add_child(reach_label)


## A label for set_reach() text.
static func reach_label_new() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible = false
	l.custom_minimum_size = Vector2(200, 0)
	return l


## Shows what [param view] (the selected computer's reach, drawn on the
## map) means, or hides the text for null.
func set_reach(view: ConsoleReachView) -> void:
	show_reach(reach_label, view)


static func show_reach(label: Label, view: ConsoleReachView) -> void:
	label.visible = view != null
	if view == null:
		return
	var lines := PackedStringArray(["Console reach (on the map): blue = where the player stands, " \
			+ "outline = what door actions reach, green = doors they change (faded: from some stand cells " \
			+ "only), red X = other locked doors they never open."])
	lines.append_array(view.lines)
	label.text = "\n".join(lines)


## Shows [param ascii]'s symbols. [param editable] enables "New symbol..."
## and editing [param p_doc]'s own symbol pieces.
func show_map(ascii: AsciiMap, editable := true, p_doc: MapDocument = null) -> void:
	if ascii != _ascii:
		_selected = null
	_ascii = ascii
	doc = p_doc
	_new_button.disabled = ascii == null or not editable
	_new_computer_button.disabled = _new_button.disabled
	_editable = editable
	_update_fill_row()
	_rebuild()


func _build_fill_row() -> void:
	fill_row = HBoxContainer.new()
	fill_row.visible = false
	add_child(fill_row)
	var l := Label.new()
	l.text = "fill_ter:"
	fill_row.add_child(l)
	fill_edit = LineEdit.new()
	fill_edit.placeholder_text = "none: every cell needs a terrain"
	fill_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_edit.tooltip_text = "Terrain of cells whose symbol sets none (and of undefined ' ' / '.'). " \
			+ "Leave blank for none: then BN only loads the map if every cell gets a terrain " \
			+ "(or it has a predecessor_mapgen)."
	fill_edit.text_submitted.connect(func(_t: String) -> void: apply_fill())
	fill_edit.focus_exited.connect(func() -> void: apply_fill())
	fill_row.add_child(fill_edit)
	fill_completer = IdCompleter.new(fill_edit, func() -> PackedStringArray:
		return Validator.id_candidates(doc.index, "terrain") if doc else PackedStringArray())


## Shows the map's fill_ter in the row (unless it's being typed in).
func _update_fill_row() -> void:
	fill_row.visible = doc != null and doc.ref.kind == DataIndex.MapgenRef.OM_TERRAIN
	if not fill_row.visible:
		_fill_doc = null
		return
	fill_edit.editable = _editable
	if doc != _fill_doc or not fill_edit.has_focus():
		fill_edit.text = _fill_text()
	_fill_doc = doc


## The map's fill_ter as written (JSON for a non-string, which BN ignores).
func _fill_text() -> String:
	var v: Variant = doc.object().get("fill_ter")
	return "" if v == null else (v if v is String else JSON.stringify(v))


## Sets the map's fill_ter to the row's text (none when blank). An unknown
## terrain is refused and the row shows the map's again. Returns an error,
## or "".
func apply_fill() -> String:
	if doc == null or not fill_row.visible or not _editable:
		return ""
	var id := fill_edit.text.strip_edges()
	if id == _fill_text():
		return ""
	var why := doc.set_fill_ter(id)
	if why:
		fill_edit.text = _fill_text()
		message.emit(why)
		return why
	var bare := doc.keys_without_terrain()
	var shown := ", ".join(Array(bare).map(func(k: String) -> String: return "'%s'" % _show_key(k)))
	if id:
		message.emit("fill_ter is now %s%s (undo with Ctrl+Z)." % [id,
				": %s show it" % shown if shown else ""])
	elif bare.is_empty() or not doc.resolved.predecessor_mapgen.is_empty():
		message.emit("Removed fill_ter (undo with Ctrl+Z).")
	else:
		message.emit("Removed fill_ter: %s now have no terrain, so BN won't load the map until they do (undo with Ctrl+Z)." % shown)
	return ""


## Selects [param key]'s entry without emitting key_selected.
func select_key(key: String) -> void:
	_selected = key
	_update_computer_button()
	_show_pieces()
	var item: TreeItem = _items.get(key)
	if item == null:
		return
	_selecting = true
	item.select(0)
	_tree.scroll_to_item(item)
	_selecting = false


## Why [param key]'s computer can't be edited ("" if it can): it places
## none, or it's a list of several.
func computer_state(key: String) -> String:
	if _ascii == null or not _editable:
		return "Nothing to edit."
	var info: ResolvedMapgen.SymbolInfo = _ascii.resolved.symbols.get(key)
	if info == null or not info.extras.has("computers"):
		return "'%s' places no computer." % key
	var b: ResolvedMapgen.Binding = info.extras.computers[-1]
	if not b.value is Dictionary:
		return "'%s' places several computers; edit them as JSON." % key
	return ""


## The palette defining [param key]'s computer, or "" (the map's own, or
## none).
func computer_palette(key: String) -> String:
	if _ascii == null:
		return ""
	var info: ResolvedMapgen.SymbolInfo = _ascii.resolved.symbols.get(key)
	if info == null or not info.extras.has("computers"):
		return ""
	var b: ResolvedMapgen.Binding = info.extras.computers[-1]
	return b.source if b.from_palette() else ""


## Why the selected symbol can't be renamed or removed ("" if it can): the
## map must define it itself.
func own_state() -> String:
	if doc == null or not _editable:
		return "Nothing to edit."
	if not _selected is String:
		return "Select a symbol."
	if not doc.defined_keys().has(_selected):
		return "'%s' isn't defined in the map itself; rename or remove it in its palette." % _show_key(_selected)
	return ""


## Renames the selected symbol (the map's own) to [param new_key],
## repainting its cells; it stays selected (and the brush) under its new
## name. Returns an error, or "".
func rename_selected(new_key: String) -> String:
	var why := own_state()
	if why.is_empty():
		why = doc.rename_own_symbol(_selected, new_key)
	if why:
		message.emit(why)
		return why
	var old: String = _selected
	_selected = new_key
	message.emit("Renamed '%s' to '%s' (undo with Ctrl+Z)." % [_show_key(old), _show_key(new_key)])
	select_key(new_key)
	key_selected.emit(new_key)
	return ""


## Removes the map's own definitions of the selected symbol (every kind).
## Returns an error, or "".
func remove_selected() -> String:
	var why := own_state()
	if why:
		message.emit(why)
		return why
	var key: String = _selected
	doc.remove_own_symbol(key, "", true)
	var cells := 0
	for row in doc.resolved.cells:
		cells += row.count(key)
	var left := ""
	if cells:
		left = " %d cell(s) still use it: %s." % [cells, "now from %s" % ", ".join(doc.symbol_sources(key)) \
				if doc.resolved.symbols.has(key) else "undefined now"]
	message.emit("Removed the map's own '%s'.%s (undo with Ctrl+Z)" % [_show_key(key), left])
	return ""


func open_rename_dialog() -> void:
	if own_state():
		return
	rename_edit.text = ""
	rename_dialog.title = "Rename '%s'" % _show_key(_selected)
	_update_rename()
	PaletteEditor._popup(rename_dialog)
	if rename_edit.is_inside_tree():
		rename_edit.grab_focus()


func _build_rename_dialog() -> void:
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.ok_button_text = "Rename"
	var box := VBoxContainer.new()
	rename_dialog.add_child(box)
	var l := Label.new()
	l.text = "New symbol (its definitions and every cell painted with it follow):"
	box.add_child(l)
	rename_edit = LineEdit.new()
	rename_edit.max_length = 4
	rename_edit.text_changed.connect(func(_t: String) -> void: _update_rename())
	rename_edit.text_submitted.connect(func(_t: String) -> void:
		if not rename_dialog.get_ok_button().disabled:
			rename_dialog.hide()
			rename_selected(rename_edit.text))
	box.add_child(rename_edit)
	_rename_info = Label.new()
	_rename_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rename_info.custom_minimum_size = Vector2(360, 0)
	box.add_child(_rename_info)
	rename_dialog.confirmed.connect(func() -> void: rename_selected(rename_edit.text))
	add_child(rename_dialog)


func _update_rename() -> void:
	var why := own_state()
	if why.is_empty():
		why = doc.check_rename(_selected, rename_edit.text)
	_rename_info.text = why
	rename_dialog.get_ok_button().disabled = not why.is_empty()


func _update_computer_button() -> void:
	var why := computer_state(_selected) if _selected is String else "Select a computer symbol."
	_edit_computer_button.disabled = not why.is_empty()
	var pal := computer_palette(_selected) if _selected is String else ""
	_edit_computer_button.tooltip_text = why if why else ("Edit the selected symbol's computer in palette %s (every map using it changes)" % pal \
			if pal else "Edit the selected symbol's computer (or double-click it)")
	var own := own_state()
	_rename_button.disabled = not own.is_empty()
	_remove_button.disabled = not own.is_empty()
	_rename_button.tooltip_text = own if own else "Give the selected symbol another key: its definitions in the map and every cell painted with it"
	_remove_button.tooltip_text = own if own else "Remove the map's own definitions of the selected symbol (cells keep the key)"


## The palette defining the selected symbol's terrain (else furniture, else
## anything), or "".
func selected_palette() -> String:
	if not _selected is String or _ascii == null:
		return ""
	var info: ResolvedMapgen.SymbolInfo = _ascii.resolved.symbols.get(_selected)
	if info == null:
		return ""
	var bindings: Array = [info.terrain, info.furniture]
	for kind: String in info.extras:
		bindings.append_array(info.extras[kind])
	for b: ResolvedMapgen.Binding in bindings:
		if b and b.from_palette():
			return b.source
	return ""


func _on_selected() -> void:
	if _selecting:
		return
	var item := _tree.get_selected()
	while item and item.get_parent() and item.get_parent().get_metadata(0) is String:
		item = item.get_parent()
	var key: Variant = item.get_metadata(0) if item else null
	_selected = key if key is String else null
	_update_computer_button()
	_show_pieces()
	key_selected.emit(key if key is String else "")


func _rebuild() -> void:
	var expanded := {}
	for key: String in _items:
		if not _items[key].collapsed:
			expanded[key] = true
	_tree.clear()
	_items.clear()
	if _ascii == null:
		return
	var res := _ascii.resolved
	var root := _tree.create_item()
	var counts := {}
	for row in res.cells:
		for k in row:
			counts[k] = counts.get(k, 0) + 1
	var filter := _filter.text.strip_edges().to_lower()

	var used := _tree.create_item(root)
	used.set_text(0, "In use")
	used.set_selectable(0, false)
	used.set_selectable(1, false)
	used.set_selectable(2, false)
	var keys := res.used_keys()
	keys.sort()
	var shown := 0
	for key in keys:
		if _add_symbol(used, key, counts.get(key, 0), filter):
			shown += 1
	used.set_text(1, "%d symbols" % shown)

	if res.fill_binding():
		var fill := _tree.create_item(root)
		fill.set_selectable(0, false)
		fill.set_text(0, "fill_ter")
		fill.set_text(1, res.fill_ter)
		fill.set_tooltip_text(1, "Terrain for cells whose symbol sets none")

	var unused_keys := PackedStringArray()
	for key: String in res.symbols:
		if not counts.has(key):
			unused_keys.append(key)
	if not unused_keys.is_empty():
		unused_keys.sort()
		var unused := _tree.create_item(root)
		unused.set_text(0, "Unused")
		unused.set_selectable(0, false)
		unused.set_selectable(1, false)
		unused.set_selectable(2, false)
		unused.collapsed = filter.is_empty()
		shown = 0
		for key in unused_keys:
			if _add_symbol(unused, key, 0, filter):
				shown += 1
		unused.set_text(1, "%d defined by palettes or the map" % shown)

	for key: String in expanded:
		if _items.has(key):
			_items[key].collapsed = false
	if _selected is String and _items.has(_selected):
		select_key(_selected)
	_update_computer_button()
	_show_pieces()


## Shows the selected symbol's pieces (nothing without a map or symbol).
func _show_pieces() -> void:
	pieces.index = doc.index if doc else null
	pieces.editable = _editable and doc != null
	var key: String = _selected if _selected is String and _ascii else ""
	pieces.show_key(key, _ascii.resolved.symbols.get(key) if key else null)


## Adds a symbol row with one child per definition. Returns false if the
## filter hides it.
func _add_symbol(parent: TreeItem, key: String, count: int, filter: String) -> bool:
	var res := _ascii.resolved
	var info: ResolvedMapgen.SymbolInfo = res.symbols.get(key)
	var lines: Array[PackedStringArray] = []
	var ter := info.terrain if info and info.terrain else null
	if ter:
		lines.append(_binding_line("terrain", ter))
	elif info and info.null_terrain:
		lines.append(PackedStringArray(["terrain", "t_null (keeps fill_ter)", ""]))
	elif res.fill_binding():
		lines.append(_binding_line("terrain", res.fill_binding()))
	if info and info.furniture:
		lines.append(_binding_line("furniture", info.furniture))
	if info:
		for kind: String in info.extras:
			for b: ResolvedMapgen.Binding in info.extras[kind]:
				var text := _short_value(b.value)
				if kind == "computers" and b.value is Dictionary:
					text = Computer.of(b.value).summary()
				lines.append(PackedStringArray([kind, text, b.source_label()]))

	var look := _ascii.look_for(key)
	var title := _title(look, info)
	if filter:
		var hay := (key + " " + title + " " + " ".join(lines.map(
				func(l: PackedStringArray) -> String: return " ".join(l)))).to_lower()
		if not hay.contains(filter):
			return false

	var item := _tree.create_item(parent)
	item.set_metadata(0, key)
	item.set_text(0, "%s  %s" % [_show_key(key), look.ch])
	item.set_custom_color(0, look.colors.fg)
	item.set_custom_bg_color(0, look.colors.bg)
	item.set_text(1, title)
	if look.state in [AsciiMap.State.UNDEFINED, AsciiMap.State.UNKNOWN_ID, AsciiMap.State.NO_TERRAIN]:
		item.set_custom_color(1, Color(1, 0.4, 0.4))
		item.set_tooltip_text(1, _state_text(look.state))
	if count:
		item.set_text(2, str(count))
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
	item.collapsed = true
	for l in lines:
		var child := _tree.create_item(item)
		child.set_metadata(0, key)
		child.set_text(0, l[0])
		child.set_text(1, l[1])
		child.set_text(2, l[2])
		child.set_tooltip_text(1, "%s\n%s" % [l[1], l[2]])
		child.set_tooltip_text(2, l[2])
		child.set_custom_color(0, Color(0.7, 0.7, 0.75))
	_items[key] = item
	return true


func _binding_line(kind: String, b: ResolvedMapgen.Binding) -> PackedStringArray:
	var text := b.id() if b.id() else _short_value(b.value)
	if b.ids.size() > 1:
		text += "  (one of %d: %s)" % [b.ids.size(), ", ".join(b.ids)]
	return PackedStringArray([kind, text, b.source_label()])


func _title(look: AsciiMap.Look, info: ResolvedMapgen.SymbolInfo) -> String:
	var ids := PackedStringArray()
	if look.terrain:
		ids.append(look.terrain.id)
	if look.furniture:
		ids.append(look.furniture.id)
	var title := " + ".join(ids) if not ids.is_empty() else _state_text(look.state)
	if info and not info.extras.is_empty():
		title += "  [%s]" % ", ".join(PackedStringArray(info.extras.keys()))
	return title


static func _state_text(state: AsciiMap.State) -> String:
	match state:
		AsciiMap.State.UNDEFINED: return "undefined symbol"
		AsciiMap.State.UNKNOWN_ID: return "unknown terrain/furniture id"
		AsciiMap.State.NO_TERRAIN: return "no terrain and no fill_ter"
		AsciiMap.State.EMPTY: return "nothing placed"
	return ""


## Shows the space key visibly.
static func _show_key(key: String) -> String:
	match key:
		" ": return "␠"
		"": return "∅"
	return key


static func _short_value(v: Variant) -> String:
	var s: String = v if v is String else JSON.stringify(v)
	return s if s.length() <= MAX_VALUE_TEXT else s.substr(0, MAX_VALUE_TEXT - 1) + "…"

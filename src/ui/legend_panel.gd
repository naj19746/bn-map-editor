class_name LegendPanel
extends VBoxContainer
## Lists the symbols of the open map: how each one looks, its terrain and
## furniture, and where every definition comes from (the map, fill_ter, or
## which palette). Symbols the rows don't use are listed separately.
## Selecting a symbol makes it the brush; "New symbol..." defines another.
## "New computer..." defines a console symbol, and "Edit computer..." (or a
## double-click) edits the selected symbol's computer when the map itself
## defines it.

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

const MAX_VALUE_TEXT := 90

var _filter: LineEdit
var _tree: Tree
var _ascii: AsciiMap
## key -> the symbol's TreeItem.
var _items := {}
var _selecting := false
## The selected symbol, kept across rebuilds; null for none.
var _selected: Variant = null
var _editable := true
var _new_button: Button
var _new_computer_button: Button
var _edit_computer_button: Button


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
	var row := HBoxContainer.new()
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
	_tree = Tree.new()
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
	add_child(_tree)


## Shows [param ascii]'s symbols. [param editable] enables "New symbol...".
func show_map(ascii: AsciiMap, editable := true) -> void:
	if ascii != _ascii:
		_selected = null
	_ascii = ascii
	_new_button.disabled = ascii == null or not editable
	_new_computer_button.disabled = _new_button.disabled
	_editable = editable
	_rebuild()


## Selects [param key]'s entry without emitting key_selected.
func select_key(key: String) -> void:
	_selected = key
	_update_computer_button()
	var item: TreeItem = _items.get(key)
	if item == null:
		return
	_selecting = true
	item.select(0)
	_tree.scroll_to_item(item)
	_selecting = false


## Why [param key]'s computer can't be edited here ("" if it can): it
## places none, a palette defines it, or it's a list of several.
func computer_state(key: String) -> String:
	if _ascii == null or not _editable:
		return "Nothing to edit."
	var info: ResolvedMapgen.SymbolInfo = _ascii.resolved.symbols.get(key)
	if info == null or not info.extras.has("computers"):
		return "'%s' places no computer." % key
	var b: ResolvedMapgen.Binding = info.extras.computers[-1]
	if b.from_palette():
		return "'%s''s computer comes from %s; the palette editor can't edit computers yet." % [key, b.source_label()]
	if not b.value is Dictionary:
		return "'%s' places several computers; edit them as JSON." % key
	return ""


func _update_computer_button() -> void:
	var why := computer_state(_selected) if _selected is String else "Select a computer symbol."
	_edit_computer_button.disabled = not why.is_empty()
	_edit_computer_button.tooltip_text = why if why else "Edit the selected symbol's computer (or double-click it)"


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

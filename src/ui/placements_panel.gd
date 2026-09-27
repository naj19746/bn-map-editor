class_name PlacementsPanel
extends VBoxContainer
## The side drawer's Placements tab: every placement entry of the open map
## (grouped by list), and an inspector for the selected one. Its fields are
## edited as text: ids as typed, the rest as JSON ("[1, 3]" or "1-3" for a
## range). What "chance" means is shown per kind, since it differs (percent,
## one in N, a plain int for place_loot). Entries BN drops or reads oddly
## are listed in red with the reason.

## An entry was selected in the list ("" for none).
signal placement_selected(member: String, index: int)
## "Add" was pressed: the next drag on the map places a new [param member].
signal add_requested(member: String)
## An entry was double-clicked: show it on the map.
signal focus_requested(member: String, index: int)
## Something to tell the user (an edit was refused, ...).
signal message(text: String)

const PROBLEM_COLOR := Color(1, 0.45, 0.45)

var doc: MapDocument
## The selected entry ("" and -1 for none).
var member := ""
var index := -1

var list: Tree
var kind_picker: OptionButton
## key -> the LineEdit editing that field of the selected entry.
var editors := {}

var _filter: LineEdit
var _header: Label
var _fields: GridContainer
var _problems: Label
var _delete_button: Button
var _duplicate_button: Button
var _add_button: Button
## "member#index" -> TreeItem, to select without rebuilding.
var _items := {}
var _selecting := false
var _building := false


func _init() -> void:
	name = "Placements"
	var top := HBoxContainer.new()
	add_child(top)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter lists, ids"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	top.add_child(_filter)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	list = Tree.new()
	list.custom_minimum_size = Vector2(0, 160)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.hide_root = true
	list.columns = 4
	list.set_column_expand(0, false)
	list.set_column_custom_minimum_width(0, 150)
	list.set_column_expand(2, false)
	list.set_column_custom_minimum_width(2, 72)
	list.set_column_expand(3, false)
	list.set_column_custom_minimum_width(3, 72)
	list.item_selected.connect(_on_list_selected)
	list.item_activated.connect(func() -> void:
		var it := list.get_selected()
		if it and it.get_metadata(0) is Array:
			focus_requested.emit(it.get_metadata(0)[0], it.get_metadata(0)[1]))
	list.nothing_selected.connect(func() -> void:
		list.deselect_all()
		_set_selection("", -1, true))
	split.add_child(list)

	var bottom := VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(bottom)
	var bar := HBoxContainer.new()
	bottom.add_child(bar)
	kind_picker = OptionButton.new()
	kind_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m: String in Placement.ADDABLE:
		kind_picker.add_item(m)
	bar.add_child(kind_picker)
	_add_button = _button(bar, "Add", func() -> void:
		add_requested.emit(kind_picker.get_item_text(kind_picker.selected)))
	_add_button.tooltip_text = "Then drag on the map where it goes (Place tool; Esc cancels)"
	_duplicate_button = _button(bar, "Duplicate", duplicate_selected)
	_delete_button = _button(bar, "Delete", delete_selected)

	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_fields = GridContainer.new()
	_fields.columns = 2
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_fields)
	_problems = Label.new()
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.add_theme_color_override("font_color", PROBLEM_COLOR)
	inner.add_child(_problems)
	_update_buttons()


## Shows [param p_doc]'s placements (null for no map).
func show_map(p_doc: MapDocument) -> void:
	if p_doc != doc:
		member = ""
		index = -1
	doc = p_doc
	refresh()


## Selects entry [param p_index] of [param p_member] without emitting
## placement_selected.
func select(p_member: String, p_index: int) -> void:
	_set_selection(p_member, p_index, false)


## Rebuilds after the map changed (an edit, undo, another tab).
func refresh() -> void:
	if doc and member and doc.placement(member, index) == null:
		member = ""
		index = -1
	_rebuild_list()
	_rebuild_inspector()


func delete_selected() -> void:
	if doc and member and doc.placement(member, index):
		var m := member
		var i := index
		# Else the selection would slide onto the next entry of the list.
		_set_selection("", -1, true)
		doc.remove_placement(m, i)


## Adds a copy of the selected entry right after the list's last one and
## selects it.
func duplicate_selected() -> void:
	var p := doc.placement(member, index) if doc and member else null
	if p == null:
		return
	var err := doc.add_placement(member, p.entry, "Duplicate " + p.title())
	if err:
		message.emit(err)
		return
	_set_selection(member, doc.object()[member].size() - 1, true)


## Commits the text of field [param key]'s editor. Returns an error or "".
func commit_field(key: String) -> String:
	var p := doc.placement(member, index) if doc and member else null
	var edit: LineEdit = editors.get(key)
	if p == null or edit == null or _building:
		return ""
	var type := _type_of(key)
	var parsed := parse_text(edit.text, type)
	var err: String = parsed[1]
	if err.is_empty() and type == "xy" and parsed[0] == null:
		err = "%s is required." % key
	if err.is_empty():
		err = doc.set_placement_fields(member, index, {key: parsed[0]})
	if err:
		message.emit(err)
		_problems.text = err
		edit.text = value_text(p.entry.get(key), type)
	return err


# --- Text <-> values ------------------------------------------------------------

## The text shown for [param v] in a field of [param type].
static func value_text(v: Variant, type: String) -> String:
	if v == null:
		return ""
	if v is String and (type == "id" or type == "text"):
		return v
	if v is Array and v.all(func(e: Variant) -> bool: return not (e is Array or e is Dictionary)):
		return "[%s]" % ", ".join(v.map(func(e: Variant) -> String: return BnJson.stringify(e)))
	return BnJson.stringify(v)


## [value, error] for [param text] typed into a field of [param type]; an
## empty text is null (the field is removed). Numbers keep int vs float.
static func parse_text(text: String, type: String) -> Array:
	var t := text.strip_edges()
	if t.is_empty():
		return [null, ""]
	if type == "id" or type == "text":
		if not (t.begins_with("[") or t.begins_with("{")):
			return [t, ""]
	if type == "range" or type == "xy":
		var dash := RegEx.create_from_string("^(-?\\d+)\\s*-\\s*(-?\\d+)$").search(t)
		if dash:
			return [[int(dash.get_string(1)), int(dash.get_string(2))], ""]
	var r := BnJson.parse(t)
	if not r.ok():
		return [null, "\"%s\" isn't valid JSON: %s" % [t, r.error]]
	var v: Variant = r.value
	match type:
		"range", "xy":
			if not Placement.IntRange.parse(v).valid():
				return [null, "Enter an int, [min, max] or min-max."]
		"int":
			if not v is int:
				return [null, "Enter a whole number."]
		"float":
			if not (v is int or v is float):
				return [null, "Enter a number."]
		"bool":
			if not v is bool:
				return [null, "Enter true or false."]
	return [v, ""]


# --- Building ---------------------------------------------------------------------

func _set_selection(p_member: String, p_index: int, notify: bool) -> void:
	var changed := p_member != member or p_index != index
	member = p_member
	index = p_index
	var item: TreeItem = _items.get(_item_key(member, index))
	_selecting = true
	if item:
		item.select(0)
		list.scroll_to_item(item)
	elif member.is_empty():
		list.deselect_all()
	_selecting = false
	if changed:
		_rebuild_inspector()
	if notify:
		placement_selected.emit(member, index)


func _on_list_selected() -> void:
	if _selecting:
		return
	var it := list.get_selected()
	var meta: Variant = it.get_metadata(0) if it else null
	if meta is Array:
		_set_selection(meta[0], meta[1], true)


func _rebuild_list() -> void:
	list.clear()
	_items.clear()
	var root := list.create_item()
	if doc == null:
		_update_buttons()
		return
	var filter := _filter.text.strip_edges().to_lower()
	var groups := {}
	for p in doc.placements():
		var what := p.what()
		if filter and not (p.member + " " + what + " " + p.label()).to_lower().contains(filter):
			continue
		if not groups.has(p.member):
			var g := list.create_item(root)
			g.set_text(0, p.member)
			for c in 4:
				g.set_selectable(c, false)
			groups[p.member] = g
		var it := list.create_item(groups[p.member])
		it.set_metadata(0, [p.member, p.index])
		it.set_text(0, "#%d  %s" % [p.index + 1, p.label()])
		it.set_text(1, what)
		it.set_text(2, _coord_text(p.x))
		it.set_text(3, _coord_text(p.y))
		it.set_tooltip_text(1, what)
		if not p.problems.is_empty():
			for c in 4:
				it.set_custom_color(c, PROBLEM_COLOR)
				it.set_tooltip_text(c, "\n".join(p.problems))
		_items[_item_key(p.member, p.index)] = it
	for m: String in groups:
		groups[m].set_text(1, "%d" % groups[m].get_child_count())
	var sel: TreeItem = _items.get(_item_key(member, index))
	if sel:
		_selecting = true
		sel.select(0)
		_selecting = false
	_update_buttons()


static func _item_key(m: String, i: int) -> String:
	return "%s#%d" % [m, i]


static func _coord_text(r: Placement.IntRange) -> String:
	return r.text() if r.valid() else "?"


func _rebuild_inspector() -> void:
	_building = true
	for c in _fields.get_children():
		_fields.remove_child(c)
		c.queue_free()
	editors.clear()
	var p := doc.placement(member, index) if doc and member else null
	_problems.text = ""
	if p == null:
		_header.text = "Select a placement in the list or on the map (Place tool, P)." if doc else ""
		_building = false
		_update_buttons()
		return
	_header.text = "%s: %s" % [p.title(), _meaning(p)]
	var specs := Placement.field_specs(p.member)
	var keys := specs.map(func(s: Array) -> String: return s[0])
	for spec: Array in specs:
		_add_field(p, spec[0], spec[1], spec[2])
	for key: String in p.entry:
		if not keys.has(key):
			_add_field(p, key, "json", "")
	_problems.text = "\n".join(p.problems)
	_building = false
	_update_buttons()


func _add_field(p: Placement, key: String, type: String, help: String) -> void:
	var label := Label.new()
	label.text = key
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	if not p.entry.has(key):
		label.modulate = Color(1, 1, 1, 0.55)
	_fields.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = value_text(p.entry.get(key), type)
	edit.placeholder_text = help
	edit.tooltip_text = help
	edit.text_submitted.connect(func(_t: String) -> void: commit_field(key))
	edit.focus_exited.connect(func() -> void:
		var cur := doc.placement(member, index) if doc and member else null
		if cur and edit.text != value_text(cur.entry.get(key), type):
			commit_field(key))
	_fields.add_child(edit)
	editors[key] = edit


func _type_of(key: String) -> String:
	for spec: Array in Placement.field_specs(member):
		if spec[0] == key:
			return spec[1]
	return "json"


## One line saying what the entry does and how its chance reads.
static func _meaning(p: Placement) -> String:
	var what := p.what()
	var chance := p.chance_text()
	var parts := PackedStringArray([what if what else "(nothing chosen yet)"])
	match p.chance_kind():
		Placement.Chance.PERCENT: parts.append("chance %s" % chance)
		Placement.Chance.ONE_IN: parts.append("chance one in %s" % chance.trim_prefix("1/"))
	if p.status == Placement.Status.OK and not p.is_set():
		parts.append("in overmap tile (%d, %d)" % [p.anchor_omt.x, p.anchor_omt.y])
	elif p.is_set() and p.status == Placement.Status.OK and p.geometry.omts() != Vector2i.ONE:
		parts.append("runs in every overmap tile")
	return ", ".join(parts)


func _update_buttons() -> void:
	var has := doc != null and member != "" and doc.placement(member, index) != null
	_delete_button.disabled = not has
	_duplicate_button.disabled = not has
	_add_button.disabled = doc == null


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

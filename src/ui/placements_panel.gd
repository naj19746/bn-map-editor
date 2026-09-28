class_name PlacementsPanel
extends VBoxContainer
## The side drawer's Placements tab: every placement entry of the open map
## (grouped by list), and an inspector for the selected one. Its fields are
## edited as text: ids as typed, the rest as JSON ("[1, 3]" or "1-3" for a
## range). What "chance" means is shown per kind, since it differs (percent,
## one in N, a plain int for place_loot). Entries BN drops or reads oddly
## are listed in red with the reason. The fields are a PieceEditor (id
## suggestions, weighted lists for "chunks" and a "monster" list, in-place
## updates). A place_nested entry also shows the chunk it draws. A
## place_computers entry is edited with a ComputerEditor instead of JSON
## fields.

## An entry was selected in the list ("" for none).
signal placement_selected(member: String, index: int)
## "Add" was pressed: the next drag on the map places a new [param member].
signal add_requested(member: String)
## An entry was double-clicked: show it on the map.
signal focus_requested(member: String, index: int)
## Something to tell the user (an edit was refused, ...).
signal message(text: String)
## "Open chunk" was pressed: open that chunk's mapgen.
signal open_chunk_requested(ref: DataIndex.MapgenRef)

const PROBLEM_COLOR := Color(1, 0.45, 0.45)

var doc: MapDocument
## The selected entry ("" and -1 for none).
var member := ""
var index := -1

var list: Tree
var kind_picker: OptionButton
## The selected entry's fields.
var piece: PieceEditor
## key -> the LineEdit editing that field of the selected entry.
var editors: Dictionary:
	get: return piece.editors
## key -> the IdCompleter of an id field's editor (items, monsters, ...).
var completers: Dictionary:
	get: return piece.completers
## key -> the WeightedIdList editing that field (see PieceEditor.LIST_FIELDS).
var lists: Dictionary:
	get: return piece.lists
## Edits a place_computers entry (a copy; committed as field changes).
var computer_editor: ComputerEditor
## What the selected place_computers entry reaches (see set_reach()).
var reach_label: Label

var _filter: LineEdit
var _header: Label
var _problems: Label
var _chunk_box: VBoxContainer
var _chunk_info: Label
var _open_chunk_button: Button
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
	piece = PieceEditor.new(func(fields: Dictionary) -> String:
		var p := doc.placement(member, index) if doc and member else null
		if p == null:
			return "Select a placement first."
		var what := "Edit " + p.title()
		if fields.size() == 1 and piece.lists.has(fields.keys()[0]):
			what = "Edit %s of %s" % [fields.keys()[0], p.title()]
		return doc.set_placement_fields(member, index, fields, what))
	piece.message.connect(func(text: String) -> void:
		message.emit(text)
		_problems.text = text)
	inner.add_child(piece)
	_problems = Label.new()
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.add_theme_color_override("font_color", PROBLEM_COLOR)
	inner.add_child(_problems)
	_build_chunk_picker(inner)
	reach_label = LegendPanel.reach_label_new()
	inner.add_child(reach_label)
	computer_editor = ComputerEditor.new()
	computer_editor.visible = false
	computer_editor.committed.connect(func() -> void:
		var err := commit_computer()
		if err:
			message.emit(err)
			_problems.text = err)
	inner.add_child(computer_editor)
	_update_buttons()


## Shows what [param view] (the selected computer's reach) means; null
## hides it.
func set_reach(view: ConsoleReachView) -> void:
	LegendPanel.show_reach(reach_label, view)


func _build_chunk_picker(parent: Control) -> void:
	_chunk_box = VBoxContainer.new()
	_chunk_box.visible = false
	parent.add_child(_chunk_box)
	_chunk_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	_chunk_box.add_child(row)
	_chunk_info = Label.new()
	_chunk_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chunk_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_chunk_info)
	_open_chunk_button = _button(row, "Open", func() -> void:
		var st := _stamp()
		if st and st.ref:
			open_chunk_requested.emit(st.ref))
	_open_chunk_button.tooltip_text = "Open the chunk drawn for this entry"


## Adds chunk [param id] to the selected place_nested entry's "chunks": a
## plain id at BN's default weight 100, else [id, weight]. Returns an error,
## or "".
func add_chunk(id: String, weight := 100) -> String:
	var p := doc.placement(member, index) if doc and member else null
	if p == null or p.member != "place_nested":
		return "Select a place_nested entry first."
	if id.is_empty():
		return "Enter a nested chunk id."
	if id != "null" and not doc.index.nested.has(id):
		return "There's no nested chunk \"%s\"." % id
	var chunks: Array = p.entry.get("chunks").duplicate(true) if p.entry.get("chunks") is Array else []
	chunks.append(id if weight == 100 else [id, weight])
	return doc.set_placement_fields(member, index, {"chunks": chunks}, "Add chunk %s to %s" % [id, p.title()])


## The selected place_nested entry's chunk as the map draws it, or null.
func _stamp() -> ChunkOverlay.Stamp:
	if doc == null or member != "place_nested":
		return null
	return doc.chunk_overlay().stamp_for(index)


## Shows [param p_doc]'s placements (null for no map).
func show_map(p_doc: MapDocument) -> void:
	if p_doc != doc:
		member = ""
		index = -1
		piece.clear()
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
	return piece.commit_field(key) if not _building else ""


## Commits [param value] as field [param key] (a weighted list). Returns an
## error or "".
func commit_list(key: String, value: Array) -> String:
	return piece.commit_list(key, value) if not _building else ""


## Writes the computer editor's fields into the selected place_computers
## entry (x/y and other fields stay). Returns an error or "".
func commit_computer() -> String:
	var p := doc.placement(member, index) if doc and member else null
	if p == null or p.member != "place_computers" or _building:
		return ""
	var fields := {}
	for key: String in computer_editor.data:
		if key != "x" and key != "y":
			fields[key] = computer_editor.data[key]
	for key: String in p.entry:
		if not computer_editor.data.has(key):
			fields[key] = null
	return doc.set_placement_fields(member, index, fields, "Edit computer of " + p.title())


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
	var p := doc.placement(member, index) if doc and member else null
	_problems.text = ""
	if p == null:
		piece.clear()
		_header.text = "Select a placement in the list or on the map (Place tool, P)." if doc else ""
		_chunk_box.visible = false
		computer_editor.visible = false
		_building = false
		_update_buttons()
		return
	_header.text = "%s: %s" % [p.title(), _meaning(p)]
	var is_computer := p.member == "place_computers"
	piece.index = doc.index
	piece.show_piece(p.member, p.entry, str(p.index), Computer.FIELD_ORDER if is_computer else [])
	computer_editor.visible = is_computer
	if is_computer:
		computer_editor.edit(p.entry.duplicate(true))
	var lines := PackedStringArray()
	for f in doc.findings(false):
		if f.target == Validator.Target.PLACEMENT and f.member == p.member and f.index == p.index:
			lines.append(f.describe())
	_problems.text = "\n".join(lines)
	_show_chunk(p)
	_building = false
	_update_buttons()


func _show_chunk(p: Placement) -> void:
	_chunk_box.visible = p != null and p.member == "place_nested"
	if not _chunk_box.visible:
		return
	var st := _stamp()
	_chunk_info.text = "Draws: " + (st.describe() if st else "nothing (BN drops this entry)")
	_open_chunk_button.disabled = st == null or st.ref == null


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

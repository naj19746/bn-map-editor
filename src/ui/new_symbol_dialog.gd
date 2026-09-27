class_name NewSymbolDialog
extends ConfirmationDialog
## Defines a new symbol in the open map's own "terrain"/"furniture": pick a
## terrain and/or furniture from every known id, and a key (one is
## suggested). Symbols that already place the same ids are pointed out, so
## the user can reuse one instead.

## The symbol was added to the map.
signal symbol_added(key: String)


## A searchable list of terrain or furniture ids.
class IdPicker:
	extends VBoxContainer

	signal changed

	const MAX_SHOWN := 300
	## selected() when the "keep" entry is chosen.
	const KEEP := "\u0001keep"

	var table: Dictionary
	var allow_none := true
	## When set, the list starts with "(keep: <keep_text>)": leave the value
	## as it is (e.g. a distribution the list can't show).
	var keep_text := ""
	var search: LineEdit
	var list: ItemList

	func _init(title: String) -> void:
		var label := Label.new()
		label.text = title
		add_child(label)
		search = LineEdit.new()
		search.placeholder_text = "Search id or name"
		search.clear_button_enabled = true
		search.text_changed.connect(func(_t: String) -> void: refresh())
		add_child(search)
		list = ItemList.new()
		list.custom_minimum_size = Vector2(0, 180)
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_selected.connect(func(_i: int) -> void: changed.emit())
		add_child(list)

	## The chosen id, "" for none (or nothing chosen), KEEP for "(keep)".
	func selected() -> String:
		var items := list.get_selected_items()
		return list.get_item_metadata(items[0]) if not items.is_empty() else ""

	func select_id(id: String) -> void:
		search.text = ""
		refresh()
		if not _select(id) and table.has(id):
			# Not among the first MAX_SHOWN: search for it instead.
			search.text = id
			refresh()
			_select(id)
		if list.get_selected_items().is_empty():
			_select_default()

	func _select(id: String) -> bool:
		list.deselect_all()
		for i in list.item_count:
			if list.get_item_metadata(i) == id:
				list.select(i)
				list.ensure_current_is_visible()
				return true
		return false

	func refresh() -> void:
		var had := not list.get_selected_items().is_empty()
		var keep := selected()
		list.clear()
		if keep_text:
			list.set_item_metadata(list.add_item("(keep: %s)" % keep_text), KEEP)
		if allow_none:
			list.set_item_metadata(list.add_item("(none)"), "")
		var q := search.text.strip_edges().to_lower()
		var ids: Array = table.keys()
		ids.sort()
		var shown := 0
		for id: String in ids:
			var def: DataIndex.TileDef = table[id]
			if def.id != id:
				continue  # an alias
			if q and not id.to_lower().contains(q) and not def.name.to_lower().contains(q):
				continue
			if shown >= MAX_SHOWN:
				break
			shown += 1
			var i := list.add_item("%s  %s   %s" % [def.ascii(), id, def.name])
			list.set_item_metadata(i, id)
		for i in list.item_count:
			if had and list.get_item_metadata(i) == keep:
				list.select(i)
		if list.get_selected_items().is_empty() and not had:
			_select_default()

	## "(keep)" if listed, else "(none)" if listed.
	func _select_default() -> void:
		if list.item_count > 0 and (keep_text or allow_none):
			list.select(0)


var terrain: IdPicker
var furniture: IdPicker
var key_edit: LineEdit
var _info: Label
var _doc: MapDocument
var _key_touched := false


func _init() -> void:
	title = "New symbol"
	ok_button_text = "Add symbol"
	min_size = Vector2i(720, 460)
	var box := VBoxContainer.new()
	add_child(box)
	var note := Label.new()
	note.text = "The symbol is defined in this map's own \"terrain\"/\"furniture\" (palettes are edited in the palette editor)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var pickers := HBoxContainer.new()
	pickers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pickers)
	terrain = IdPicker.new("Terrain")
	furniture = IdPicker.new("Furniture")
	for p: IdPicker in [terrain, furniture]:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.changed.connect(_on_ids_changed)
		pickers.add_child(p)
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = "Symbol:"
	row.add_child(label)
	key_edit = LineEdit.new()
	key_edit.custom_minimum_size = Vector2(60, 0)
	key_edit.max_length = 4
	key_edit.text_changed.connect(func(_t: String) -> void:
		_key_touched = true
		_validate())
	row.add_child(key_edit)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_info)
	confirmed.connect(_on_confirmed)


## Sets the dialog up for [param doc] and shows it.
func open(doc: MapDocument) -> void:
	setup(doc)
	popup_centered()
	terrain.search.grab_focus()


## Like open() without showing the window (for tests).
func setup(doc: MapDocument) -> void:
	_doc = doc
	_key_touched = false
	terrain.table = doc.index.terrain
	furniture.table = doc.index.furniture
	# Terrain is optional when fill_ter (or the map below) supplies it.
	terrain.allow_none = not doc.resolved.fill_ter.is_empty() or doc.resolved.draws_over
	terrain.search.text = ""
	furniture.search.text = ""
	terrain.refresh()
	furniture.refresh()
	_on_ids_changed()


func _on_ids_changed() -> void:
	if _doc == null:
		return
	if not _key_touched:
		key_edit.text = _doc.suggest_key(terrain.selected(), furniture.selected())
	_validate()


func _validate() -> void:
	var ter := terrain.selected()
	var furn := furniture.selected()
	var problem := _doc.check_new_symbol(key_edit.text, ter, furn)
	get_ok_button().disabled = not problem.is_empty()
	var text := problem
	if ter or furn:
		var same := _doc.matching_keys(ter if ter else _doc.resolved.fill_ter, furn)
		if not same.is_empty():
			text += ("  " if text else "") + "Already placed by: %s (their extras, e.g. items, come along)." % \
					", ".join(PackedStringArray(Array(same).map(func(k: String) -> String: return "'%s'" % k)))
	_info.text = text
	_info.modulate = Color(1, 0.6, 0.6) if problem else Color(0.8, 0.8, 0.85)


func _on_confirmed() -> void:
	var key := key_edit.text
	if _doc and _doc.add_symbol(key, terrain.selected(), furniture.selected()).is_empty():
		symbol_added.emit(key)

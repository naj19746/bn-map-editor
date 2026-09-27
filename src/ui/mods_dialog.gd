class_name ModsDialog
extends ConfirmationDialog
## Picks which mods to load on top of core. Dependencies are added when the
## index loads (ModCatalog.load_order), so only the user's picks are kept.

signal mods_chosen(mods: PackedStringArray)

var _tree: Tree
var _show_obsolete: CheckBox
var _catalog: ModCatalog
var _checked := {}


func _init() -> void:
	title = "Mods"
	min_size = Vector2i(460, 520)
	var box := VBoxContainer.new()
	add_child(box)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 140)
	_tree.item_edited.connect(_on_edited)
	box.add_child(_tree)
	_show_obsolete = CheckBox.new()
	_show_obsolete.text = "Show obsolete mods"
	_show_obsolete.toggled.connect(func(_on: bool) -> void: _rebuild())
	box.add_child(_show_obsolete)
	confirmed.connect(_on_confirmed)


func open(catalog: ModCatalog, selected: PackedStringArray) -> void:
	_catalog = catalog
	_checked.clear()
	for id in selected:
		_checked[id] = true
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var mods: Array[ModCatalog.ModInfo] = []
	for id: String in _catalog.mods:
		var m := _catalog.get_mod(id)
		if not m.core and (_show_obsolete.button_pressed or not m.obsolete or _checked.has(id)):
			mods.append(m)
	mods.sort_custom(func(a: ModCatalog.ModInfo, b: ModCatalog.ModInfo) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)
	for m in mods:
		var item := _tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, _checked.has(m.id))
		item.set_text(0, m.name)
		item.set_metadata(0, m.id)
		item.set_text(1, m.id)
		item.set_custom_color(1, Color(0.6, 0.6, 0.65))
		var tip := m.id
		if not m.dependencies.is_empty():
			tip += "\nneeds: " + ", ".join(m.dependencies)
		item.set_tooltip_text(0, tip)


func _on_edited() -> void:
	var item := _tree.get_edited()
	var id: String = item.get_metadata(0)
	if item.is_checked(0):
		_checked[id] = true
	else:
		_checked.erase(id)


func _on_confirmed() -> void:
	# Keep the order they were picked in; it's the load order.
	mods_chosen.emit(PackedStringArray(_checked.keys()))

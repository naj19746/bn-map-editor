class_name NewBuildingDialog
extends ConfirmationDialog
## Creates a city_building placing an open map's overmap tiles at z 0 (its
## other levels are added later with Level > New level above / below), and
## optionally names it in a region's city list: without that, cities never
## spawn it (EditSession.create_building, add_to_city_list).

signal building_created(id: String)

var id_edit: LineEdit
var path_edit: LineEdit
var list_picker: OptionButton
var weight: SpinBox
var _info: Label
var _session: EditSession
var _ref: DataIndex.MapgenRef


func _init() -> void:
	title = "New building"
	ok_button_text = "Create"
	min_size = Vector2i(560, 300)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	id_edit = _field(grid, "city_building id:", LineEdit.new())
	id_edit.text_changed.connect(func(_t: String) -> void: _validate())
	path_edit = _field(grid, "File:", LineEdit.new())
	path_edit.tooltip_text = "Relative to the BN folder; saved into the workspace. An existing file gets it appended."
	path_edit.text_changed.connect(func(_t: String) -> void: _validate())
	list_picker = _field(grid, "City list:", OptionButton.new())
	list_picker.add_item("(none: don't spawn in cities)")
	for l: String in EditSession.CITY_LISTS:
		list_picker.add_item(l)
	list_picker.item_selected.connect(func(_i: int) -> void: _validate())
	weight = _field(grid, "Weight:", SpinBox.new())
	weight.min_value = 1
	weight.max_value = 10000
	weight.value = 100
	weight.tooltip_text = "How often cities pick it against the list's other buildings"
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(520, 0)
	_field(grid, "", _info)
	confirmed.connect(_on_confirmed)


## Starts the dialog for map [param ref], in the map's own file.
func setup(session: EditSession, ref: DataIndex.MapgenRef) -> void:
	_session = session
	_ref = ref
	id_edit.text = ref.title()
	path_edit.text = ref.source.path
	list_picker.select(1)
	_validate()


## [point, "overmap" value] per tile of the map, its top-left at (0, 0, 0),
## placed facing north.
func entries() -> Array:
	var out := []
	for id in _ref.ids:
		var at := _ref.position_of(id)
		out.append([Vector3i(at.x, at.y, 0), id + "_north"])
	return out


func city_list() -> String:
	return "" if list_picker.selected <= 0 else list_picker.get_item_text(list_picker.selected)


func _validate() -> void:
	if _session == null:
		return
	var rel := path_edit.text.strip_edges()
	var problem := _session.check_new_building(rel, id_edit.text.strip_edges(), city_list())
	get_ok_button().disabled = not problem.is_empty()
	var lines := PackedStringArray()
	if problem:
		lines.append(problem)
	else:
		lines.append("Places %s at z 0 (%d tile%s), on \"land\"." % [_ref.title(), _ref.ids.size(),
				"" if _ref.ids.size() == 1 else "s"])
		if city_list():
			lines.append(_session.city_list_note(rel))
		else:
			lines.append("Cities spawn a city_building only if a region's city list names it; this one won't spawn until one does.")
	_info.text = "\n".join(lines)
	_info.modulate = Color(1, 0.6, 0.6) if problem else Color(0.8, 0.8, 0.85)


func _on_confirmed() -> void:
	var id := id_edit.text.strip_edges()
	_session.create_building(path_edit.text.strip_edges(), id, entries(), city_list(), int(weight.value))
	# A city list that couldn't be edited leaves the building made (last_error says why).
	if _session.index.buildings.has(id):
		building_created.emit(id)


func _field(grid: GridContainer, label: String, control: Control) -> Variant:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return control

class_name NewMapDialog
extends ConfirmationDialog
## Creates a new om_terrain mapgen: its id grid (size in overmap tiles),
## fill_ter, palettes and the file it goes in (new, or appended to an
## existing one). Offers to add overmap_terrain entries for new ids, without
## which BN never generates the map.

signal map_created(doc: MapDocument)

var base_edit: LineEdit
var width: SpinBox
var height: SpinBox
var ids_edit: TextEdit
var fill_edit: LineEdit
var palettes_edit: LineEdit
var path_edit: LineEdit
var overmap_check: CheckBox
var _info: Label
var _session: EditSession
## Fields the user typed into stop following the base id.
var _ids_touched := false
var _path_touched := false
var _filling := false


func _init() -> void:
	title = "New map"
	ok_button_text = "Create"
	min_size = Vector2i(560, 480)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	base_edit = _field(grid, "om_terrain id:", LineEdit.new())
	base_edit.placeholder_text = "e.g. my_house"
	base_edit.text_changed.connect(func(_t: String) -> void: _autofill())
	var size_row := HBoxContainer.new()
	width = _spin(size_row)
	var x := Label.new()
	x.text = "x"
	size_row.add_child(x)
	height = _spin(size_row)
	var hint := Label.new()
	hint.text = "overmap tiles (24x24 each)"
	size_row.add_child(hint)
	_field(grid, "Size:", size_row)
	ids_edit = _field(grid, "om_terrain grid:", TextEdit.new())
	ids_edit.custom_minimum_size = Vector2(0, 90)
	ids_edit.tooltip_text = "One line per row of overmap tiles, ids separated by spaces"
	ids_edit.text_changed.connect(func() -> void:
		if not _filling:
			_ids_touched = true
		_validate())
	fill_edit = _field(grid, "fill_ter:", LineEdit.new())
	fill_edit.text = EditSession.DEFAULT_FILL
	fill_edit.text_changed.connect(func(_t: String) -> void: _validate())
	palettes_edit = _field(grid, "Palettes:", LineEdit.new())
	palettes_edit.placeholder_text = "optional, e.g. standard_domestic_palette"
	palettes_edit.text_changed.connect(func(_t: String) -> void: _validate())
	path_edit = _field(grid, "File:", LineEdit.new())
	path_edit.tooltip_text = "Relative to the BN folder; saved into the workspace. An existing file gets the map appended."
	path_edit.text_changed.connect(func(_t: String) -> void:
		if not _filling:
			_path_touched = true
		_validate())
	overmap_check = CheckBox.new()
	overmap_check.text = "Add overmap_terrain entries for ids that have none"
	overmap_check.button_pressed = true
	_field(grid, "", overmap_check)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(520, 0)
	_field(grid, "", _info)
	confirmed.connect(_on_confirmed)


func open(session: EditSession) -> void:
	setup(session)
	popup_centered()
	base_edit.grab_focus()


func setup(session: EditSession) -> void:
	_session = session
	_ids_touched = false
	_path_touched = false
	_autofill()


## The dialog's fields as a spec.
func spec() -> EditSession.NewMapgen:
	var s := EditSession.NewMapgen.new()
	s.rel_path = path_edit.text.strip_edges()
	for line in ids_edit.text.split("\n", false):
		var row := line.strip_edges().split(" ", false)
		if not row.is_empty():
			s.ids.append(row)
	s.fill_ter = fill_edit.text.strip_edges()
	for p in palettes_edit.text.replace(",", " ").split(" ", false):
		s.palettes.append(p)
	s.add_overmap_terrain = overmap_check.button_pressed
	return s


func _autofill() -> void:
	var base := base_edit.text.strip_edges()
	_filling = true
	if not _ids_touched:
		var lines := PackedStringArray()
		for row in EditSession.default_ids(base, int(width.value), int(height.value)):
			lines.append(" ".join(row))
		ids_edit.text = "\n".join(lines) if base else ""
	if not _path_touched:
		path_edit.text = "data/json/mapgen/%s.json" % base if base else ""
	_filling = false
	_validate()


func _validate() -> void:
	if _session == null:
		return
	var s := spec()
	var problem := _session.check_new_mapgen(s)
	get_ok_button().disabled = not problem.is_empty()
	var lines := PackedStringArray()
	if problem:
		lines.append(problem)
	else:
		var f: JsonFile = _session.files.get(s.rel_path)
		lines.append("Adds to %s (%d objects)." % [s.rel_path, f.objects.size()] if f
				else "Creates %s in mod \"%s\"." % [s.rel_path, _session.index.mod_for_path(s.rel_path)])
		for row in s.ids:
			for id in row:
				if not _session.index.om_terrain.get(id, []).is_empty():
					lines.append("\"%s\" already has a mapgen; this adds a variant (picked by weight)." % id)
	_info.text = "\n".join(lines)
	_info.modulate = Color(1, 0.6, 0.6) if problem else Color(0.8, 0.8, 0.85)


func _on_confirmed() -> void:
	var doc := _session.create_mapgen(spec())
	if doc:
		map_created.emit(doc)


func _spin(parent: Control) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 1
	s.max_value = 16
	s.value = 1
	s.value_changed.connect(func(_v: float) -> void: _autofill())
	parent.add_child(s)
	return s


func _field(grid: GridContainer, label: String, control: Control) -> Variant:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return control

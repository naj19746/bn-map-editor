class_name NewMapDialog
extends ConfirmationDialog
## Creates a new om_terrain mapgen: its id grid (size in overmap tiles),
## fill_ter, palettes and the file it goes in (new, or appended to an
## existing one). Offers to add overmap_terrain entries for new ids, without
## which BN never generates the map. Or creates a nested chunk: its
## nested_mapgen_id and mapgensize (1-24 cells each way), palettes and file.
## A new level of a building ([member level]) also goes into the building's
## "overmaps".

signal map_created(doc: MapDocument)

enum Kind { MAP, CHUNK }

var kind_picker: OptionButton
var base_edit: LineEdit
var width: SpinBox
var height: SpinBox
var ids_edit: TextEdit
var fill_edit: LineEdit
## Suggests terrain ids in [member fill_edit].
var fill_completer: IdCompleter
var palettes_edit: LineEdit
var path_edit: LineEdit
var overmap_check: CheckBox
var _info: Label
var _size_hint: Label
var _session: EditSession
## Fields the user typed into stop following the base id.
var _ids_touched := false
var _path_touched := false
var _filling := false
## Set for a new level of a building (see EditSession.NewMapgen.level);
## setup() clears it.
var level: EditSession.LevelTarget
## What new overmap_terrain entries copy ("": EditSession's default).
var overmap_base := ""


func _init() -> void:
	title = "New map"
	ok_button_text = "Create"
	min_size = Vector2i(560, 480)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	kind_picker = _field(grid, "Kind:", OptionButton.new())
	kind_picker.add_item("om_terrain map", Kind.MAP)
	kind_picker.add_item("Nested chunk", Kind.CHUNK)
	kind_picker.item_selected.connect(func(_i: int) -> void: set_kind(kind_picker.selected))
	base_edit = _field(grid, "om_terrain id:", LineEdit.new())
	base_edit.placeholder_text = "e.g. my_house"
	base_edit.text_changed.connect(func(_t: String) -> void: _autofill())
	var size_row := HBoxContainer.new()
	width = _spin(size_row)
	var x := Label.new()
	x.text = "x"
	size_row.add_child(x)
	height = _spin(size_row)
	_size_hint = Label.new()
	_size_hint.text = "overmap tiles (24x24 each)"
	size_row.add_child(_size_hint)
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
	fill_completer = IdCompleter.new(fill_edit, func() -> PackedStringArray:
		return Validator.id_candidates(_session.index, "terrain") if _session else PackedStringArray())
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


func open(session: EditSession, kind := Kind.MAP) -> void:
	setup(session)
	set_kind(kind)
	popup_centered()
	base_edit.grab_focus()


## Switches between a new map and a new chunk.
func set_kind(kind: int) -> void:
	kind_picker.select(kind)
	var chunk := kind == Kind.CHUNK
	title = "New nested chunk" if chunk else "New map"
	_label_of(base_edit).text = "nested_mapgen_id:" if chunk else "om_terrain id:"
	base_edit.placeholder_text = "e.g. my_room_5x5" if chunk else "e.g. my_house"
	_size_hint.text = "cells (mapgensize)" if chunk else "overmap tiles (24x24 each)"
	_filling = true
	for spin in [width, height]:
		spin.max_value = MapgenResolver.OMT_SIZE if chunk else 16
		spin.value = 5 if chunk else 1
	_filling = false
	for c: Control in [ids_edit, fill_edit, overmap_check]:
		c.visible = not chunk
		_label_of(c).visible = not chunk
	_autofill()


## Starts the fields from om_terrain / nested id [param base] and, unless
## empty, file [param rel_path], fill_ter [param fill], [param palettes]
## and the size in tiles [param tiles].
func prefill(base: String, rel_path := "", fill := "", palettes := PackedStringArray(),
		tiles := Vector2i.ZERO) -> void:
	_filling = true
	if tiles.x > 0:
		width.value = tiles.x
		height.value = tiles.y
	if fill:
		fill_edit.text = fill
	if not palettes.is_empty():
		palettes_edit.text = " ".join(palettes)
	_filling = false
	base_edit.text = base
	if rel_path:
		path_edit.text = rel_path
		_path_touched = true
	_autofill()


func is_chunk() -> bool:
	return kind_picker.selected == Kind.CHUNK


func setup(session: EditSession) -> void:
	_session = session
	_ids_touched = false
	_path_touched = false
	level = null
	overmap_base = ""
	_autofill()


## The dialog's fields as a spec.
func spec() -> EditSession.NewMapgen:
	var s := EditSession.NewMapgen.new()
	s.rel_path = path_edit.text.strip_edges()
	if is_chunk():
		s.chunk_size = Vector2i(int(width.value), int(height.value))
		var id := base_edit.text.strip_edges()
		if id:
			s.ids.append(PackedStringArray([id]))
		for p in palettes_edit.text.replace(",", " ").split(" ", false):
			s.palettes.append(p)
		return s
	for line in ids_edit.text.split("\n", false):
		var row := line.strip_edges().split(" ", false)
		if not row.is_empty():
			s.ids.append(row)
	s.fill_ter = fill_edit.text.strip_edges()
	for p in palettes_edit.text.replace(",", " ").split(" ", false):
		s.palettes.append(p)
	s.add_overmap_terrain = overmap_check.button_pressed
	s.level = level
	s.overmap_base = overmap_base
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
		var dir := "data/json/mapgen/nested" if is_chunk() else "data/json/mapgen"
		path_edit.text = "%s/%s.json" % [dir, base] if base else ""
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
		var table := _session.index.nested if s.is_chunk() else _session.index.om_terrain
		for row in s.ids:
			for id in row:
				if not table.get(id, []).is_empty():
					lines.append("\"%s\" already has a mapgen; this adds a variant (picked by weight)." % id)
		if s.is_chunk():
			lines.append("Place it in a map with place_nested (Placements tab) or a \"nested\" symbol mapping.")
		elif s.level:
			lines.append("%s New overmap_terrain entries copy %s." % [_session.level_tiles_note(s.level.building),
					overmap_base if overmap_base else EditSession.OVERMAP_STUB_BASE])
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
	s.value_changed.connect(func(_v: float) -> void:
		if not _filling:
			_autofill())
	parent.add_child(s)
	return s


## The label in front of [param control] in the grid.
func _label_of(control: Control) -> Label:
	return control.get_parent().get_child(control.get_index() - 1)


func _field(grid: GridContainer, label: String, control: Control) -> Variant:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return control

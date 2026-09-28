class_name PieceEditor
extends VBoxContainer
## Edits one mapgen piece as fields: a place_* entry (the Placements
## inspector) or one piece of a symbol's "nested", "items", ... mapping
## (SymbolPieces). Fields are edited as text: ids as typed, the rest as
## JSON ("[1, 3]" or "1-3" for a range); id fields suggest known ids, and
## weighted lists (LIST_FIELDS) get a WeightedIdList above the others.
##
## Edits go through [member apply]; the owner writes them and shows the
## piece again with [method show_piece]. While it's the same piece with the
## same fields, that updates the fields in place (focus and a held SpinBox
## stay); otherwise they're rebuilt.

## Something to tell the user (an edit was refused).
signal message(text: String)

## member -> {field: id kind} of the weighted id lists (a place_monster
## "monster" only when it's written as a list).
const LIST_FIELDS := {
	"place_nested": {"chunks": "chunk", "else_chunks": "chunk"},
	"place_monster": {"monster": "monster"},
}
const ABSENT := Color(1, 1, 1, 0.55)

var index: DataIndex
## Writes changed fields: (fields: Dictionary) -> error or "". A null value
## removes the field.
var apply: Callable
## The piece shown: its kind (a place_* member, for the field list) and a
## copy of its object.
var member := ""
var entry := {}
## Fields never shown (x/y of a mapping piece, a computer's own fields).
var skip: Array = []
## key -> the LineEdit editing that field.
var editors := {}
## key -> the IdCompleter of an id field's editor (items, monsters, ...).
var completers := {}
## key -> the WeightedIdList editing that field (see LIST_FIELDS).
var lists := {}
## key -> the Label naming that field.
var labels := {}

var _grid: GridContainer
## The weighted list fields, each a label over a full-width list.
var _lists_box: VBoxContainer
## What the built fields are for (see _layout()); "" when none are built.
var _layout_key := ""
var _building := false


func _init(p_apply := Callable()) -> void:
	apply = p_apply
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lists_box = VBoxContainer.new()
	add_child(_lists_box)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)


## Shows [param p_entry], a piece of kind [param p_member]. [param tag]
## names which piece it is: another tag rebuilds the fields.
func show_piece(p_member: String, p_entry: Dictionary, tag := "", p_skip: Array = []) -> void:
	_building = true
	member = p_member
	entry = p_entry.duplicate(true)
	skip = p_skip
	var fields := field_list(member, entry, skip)
	var layout := _layout(fields, tag)
	if layout != _layout_key:
		clear()
		for f: Array in fields:
			_add_field(f[0], f[1], f[2])
		_layout_key = layout
	else:
		_update_fields(fields)
	_building = false


## Removes every field.
func clear() -> void:
	for box: Control in [_grid, _lists_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	editors.clear()
	completers.clear()
	lists.clear()
	labels.clear()
	_layout_key = ""


## Commits the text of field [param key]'s editor. Returns an error or "".
func commit_field(key: String) -> String:
	var edit: LineEdit = editors.get(key)
	if edit == null or _building:
		return ""
	var type := _type_of(key)
	var parsed := parse_text(edit.text, type)
	var err: String = parsed[1]
	if err.is_empty() and type == "xy" and parsed[0] == null:
		err = "%s is required." % key
	if err.is_empty():
		err = _apply({key: parsed[0]})
	if err:
		message.emit(err)
		edit.text = value_text(entry.get(key), type)
	return err


## Commits [param value] as field [param key] (a weighted list). An empty
## list removes the field, except "chunks". Returns an error or "".
func commit_list(key: String, value: Array) -> String:
	if _building:
		return ""
	var v: Variant = value if not value.is_empty() or key == "chunks" else null
	var err := _apply({key: v})
	if err:
		message.emit(err)
		if lists.has(key):
			lists[key].set_value(entry.get(key))
	return err


func _apply(fields: Dictionary) -> String:
	if not apply.is_valid():
		return "This can't be edited here."
	return apply.call(fields)


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


## [note, is_problem] shown next to option [param id] of a weighted list of
## [param kind]: a chunk's size (and how many mapgens it has), "unknown".
static func option_note(p_index: DataIndex, kind: String, id: String) -> Array:
	if kind == "chunk":
		if id == "null" or id.is_empty():
			return ["nothing", false]
		var refs: Array = p_index.nested.get(id, [])
		if refs.is_empty():
			return ["unknown", true]
		var ref: DataIndex.MapgenRef = ChunkOverlay.heaviest(refs)
		var extra := ", %d mapgens" % refs.size() if refs.size() > 1 else ""
		return ["%dx%d%s" % [ref.chunk_size.x, ref.chunk_size.y, extra], false]
	return ["", false] if Validator.is_known(p_index, kind, id) else ["unknown", true]


## The fields shown for [param p_entry] of kind [param p_member], as [key,
## type, help]: the kind's fields, then the entry's other keys; none of
## [param p_skip].
static func field_list(p_member: String, p_entry: Dictionary, p_skip: Array = []) -> Array:
	var out := []
	var specs := Placement.field_specs(p_member)
	var keys := specs.map(func(s: Array) -> String: return s[0])
	for spec: Array in specs:
		if not p_skip.has(spec[0]):
			out.append(spec)
	for key: String in p_entry:
		if not keys.has(key) and not p_skip.has(key):
			out.append([key, "json", ""])
	return out


## The id kind of [param key] when it's edited as a weighted list, else "".
static func list_kind(p_member: String, p_entry: Dictionary, key: String) -> String:
	var kind: String = LIST_FIELDS.get(p_member, {}).get(key, "")
	if kind and p_member == "place_monster" and not p_entry.get(key) is Array:
		return ""
	return kind


# --- Building ---------------------------------------------------------------------

## What decides the controls: the piece, and each field with its editor
## (a list, or a text field with its id kind).
func _layout(fields: Array, tag: String) -> String:
	var parts := PackedStringArray([member, tag])
	for f: Array in fields:
		var editor := list_kind(member, entry, f[0])
		if editor:
			editor = "list"
		elif f[1] == "id":
			editor = Validator.field_id_kind(member, f[0], entry)
		parts.append("%s:%s:%s" % [f[0], f[1], editor])
	return "|".join(parts)


## Puts the entry's values into the built fields.
func _update_fields(fields: Array) -> void:
	for f: Array in fields:
		var key: String = f[0]
		labels[key].modulate = Color.WHITE if entry.has(key) else ABSENT
		if lists.has(key):
			lists[key].set_value(entry.get(key))
		elif editors.has(key):
			var text := value_text(entry.get(key), f[1])
			if editors[key].text != text:
				editors[key].text = text


func _add_field(key: String, type: String, help: String) -> void:
	var label := Label.new()
	label.text = key
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	if not entry.has(key):
		label.modulate = ABSENT
	labels[key] = label
	var kind := list_kind(member, entry, key)
	if kind:
		_lists_box.add_child(label)
		_add_list(key, kind)
		return
	_grid.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = value_text(entry.get(key), type)
	edit.placeholder_text = help
	edit.tooltip_text = help
	edit.text_submitted.connect(func(_t: String) -> void: commit_field(key))
	edit.focus_exited.connect(func() -> void:
		if editors.get(key) == edit and edit.text != value_text(entry.get(key), type):
			commit_field(key))
	_grid.add_child(edit)
	editors[key] = edit
	var id_kind := Validator.field_id_kind(member, key, entry) if type == "id" else ""
	if id_kind:
		completers[key] = IdCompleter.new(edit, func() -> PackedStringArray:
			return Validator.id_candidates(index, id_kind) if index else PackedStringArray())


func _add_list(key: String, kind: String) -> void:
	var source := func() -> PackedStringArray:
		if index == null:
			return PackedStringArray()
		var ids := Validator.id_candidates(index, kind)
		if kind == "chunk":
			ids.insert(0, "null")
		return ids
	var describe := func(id: String) -> Array:
		return option_note(index, kind, id) if index else ["", false]
	var hint := "chunk id to add" if kind == "chunk" else "%s id to add" % kind
	var w := WeightedIdList.new(source, describe, hint)
	w.set_value(entry.get(key))
	w.committed.connect(func(v: Array) -> void: commit_list(key, v))
	w.message.connect(func(text: String) -> void: message.emit(text))
	_lists_box.add_child(w)
	lists[key] = w


func _type_of(key: String) -> String:
	for spec: Array in Placement.field_specs(member):
		if spec[0] == key:
			return spec[1]
	return "json"

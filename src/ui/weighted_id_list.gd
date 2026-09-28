class_name WeightedIdList
extends VBoxContainer
## Edits a weighted id list the way BN's load_weighted_list reads it
## (place_nested "chunks" / "else_chunks", a place_monster "monster" list):
## each option is a plain id (weight 100) or an [id, weight] pair. One row
## per option (id with suggestions, a note, weight, up/down/remove), then a
## row to add one. Every change emits [signal committed] with the whole new
## list; the owner writes it and calls [method set_value] back.
##
## Options keep how they were written: a new id keeps the option's form, a
## new weight writes a plain id at 100 and a pair otherwise. An option that
## isn't a string (a monster's {"param": ...}) is shown and typed as JSON.

## The list after an edit (a new Array; empty when the last option went).
signal committed(value: Array)
## Something to tell the user (an edit was refused).
signal message(text: String)

## BN's default weight for a plain id.
const DEFAULT_WEIGHT := 100
const MAX_WEIGHT := 1000000
const PROBLEM_COLOR := Color(1, 0.45, 0.45)
const NOTE_COLOR := Color(0.7, 0.72, 0.78)

## The list as written (a copy).
var value: Array = []
## Returns the ids to suggest (a sorted PackedStringArray).
var source: Callable
## id -> [note, is_problem] shown next to an option; may be invalid.
var describe: Callable
## One Dictionary per option: "id" (LineEdit), "weight" (SpinBox), "note"
## (Label), "up", "down", "remove" (Buttons).
var rows: Array[Dictionary] = []
var add_edit: LineEdit
var add_weight: SpinBox

var _rows_box: VBoxContainer
var _empty_label: Label
## True while set_value fills the controls (their signals are ignored).
var _filling := false


func _init(p_source: Callable, p_describe := Callable(), add_hint := "id to add") -> void:
	source = p_source
	describe = p_describe
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box = VBoxContainer.new()
	add_child(_rows_box)
	_empty_label = Label.new()
	_empty_label.text = "(none)"
	_empty_label.add_theme_color_override("font_color", NOTE_COLOR)
	add_child(_empty_label)
	var row := HBoxContainer.new()
	add_child(row)
	add_edit = LineEdit.new()
	add_edit.placeholder_text = add_hint
	add_edit.tooltip_text = "Type an id (Enter or a suggestion adds it)"
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_edit.text_submitted.connect(func(_t: String) -> void: _on_add())
	row.add_child(add_edit)
	IdCompleter.new(add_edit, source)
	add_weight = _weight_box()
	add_weight.value = DEFAULT_WEIGHT
	row.add_child(add_weight)
	var add := Button.new()
	add.text = "Add"
	add.tooltip_text = "Add this option to the list"
	add.pressed.connect(_on_add)
	row.add_child(add)


# --- Options ------------------------------------------------------------------

## The id of option [param e] (a string, or another value as written).
static func option_id(e: Variant) -> Variant:
	return e[0] if _is_pair(e) else e


## The weight of option [param e] (BN's default for a plain id).
static func option_weight(e: Variant) -> int:
	return int(e[1]) if _is_pair(e) else DEFAULT_WEIGHT


## Option [param e] with id [param id], written as it was.
static func with_id(e: Variant, id: Variant) -> Variant:
	return [id, e[1]] if _is_pair(e) else id


## Option [param e] with weight [param w]: a plain id at 100, else a pair.
static func with_weight(e: Variant, w: int) -> Variant:
	var id: Variant = option_id(e)
	return id if w == DEFAULT_WEIGHT else [id, w]


## A new option: a plain id at 100, else [id, weight].
static func new_option(id: Variant, w: int) -> Variant:
	return id if w == DEFAULT_WEIGHT else [id, w]


## The text shown for an option's id.
static func id_text(id: Variant) -> String:
	return id if id is String else BnJson.stringify(id)


## [id, error] for [param text] typed as an id: a JSON object ("{...") is
## parsed, anything else is the id as typed.
static func parse_id(text: String) -> Array:
	var t := text.strip_edges()
	if t.is_empty():
		return [null, "Enter an id, or remove the option."]
	if t.begins_with("{"):
		var r := BnJson.parse(t)
		if not r.ok():
			return [null, "\"%s\" isn't valid JSON: %s" % [t, r.error]]
		return [r.value, ""]
	return [t, ""]


static func _is_pair(e: Variant) -> bool:
	return e is Array and e.size() == 2 and (e[1] is int or e[1] is float)


# --- Editing --------------------------------------------------------------------

## Shows [param list] (a non-Array shows as empty). Rows are reused, so a
## control being used keeps its focus.
func set_value(list: Variant) -> void:
	value = list.duplicate(true) if list is Array else []
	_filling = true
	while rows.size() > value.size():
		var r: Dictionary = rows.pop_back()
		var box: Control = r.box
		_rows_box.remove_child(box)
		box.queue_free()
	while rows.size() < value.size():
		rows.append(_new_row(rows.size()))
	for i in value.size():
		_fill_row(i)
	_empty_label.visible = value.is_empty()
	_filling = false


## Sets option [param i]'s id from [param text]. Returns an error or "".
func set_id(i: int, text: String) -> String:
	var parsed := parse_id(text)
	if parsed[1]:
		return _refuse(parsed[1], i)
	return _commit(func(l: Array) -> void: l[i] = with_id(l[i], parsed[0]))


func set_weight(i: int, w: int) -> String:
	if w < 0:
		return _refuse("A weight can't be negative (BN drops the option).", i)
	return _commit(func(l: Array) -> void: l[i] = with_weight(l[i], w))


func move(i: int, to: int) -> String:
	if to < 0 or to >= value.size():
		return ""
	return _commit(func(l: Array) -> void:
		var e: Variant = l.pop_at(i)
		l.insert(to, e))


func remove(i: int) -> String:
	return _commit(func(l: Array) -> void: l.remove_at(i))


## Adds an option: [param text] as an id, at weight [param w].
func add(text: String, w := DEFAULT_WEIGHT) -> String:
	var parsed := parse_id(text)
	if parsed[1]:
		message.emit(parsed[1])
		return parsed[1]
	return _commit(func(l: Array) -> void: l.append(new_option(parsed[0], w)))


func _commit(change: Callable) -> String:
	var l := value.duplicate(true)
	change.call(l)
	if l != value:
		committed.emit(l)
	return ""


## Puts row [param i] back to the value and says why.
func _refuse(err: String, i: int) -> String:
	if i >= 0 and i < rows.size():
		set_value(value)
	message.emit(err)
	return err


func _on_add() -> void:
	var text := add_edit.text.strip_edges()
	if text.is_empty():
		return
	var w := int(add_weight.value)
	add_edit.text = ""
	add_weight.value = DEFAULT_WEIGHT
	add(text, w)


# --- Rows -------------------------------------------------------------------------

func _new_row(i: int) -> Dictionary:
	var box := HBoxContainer.new()
	_rows_box.add_child(box)
	var id_e := LineEdit.new()
	id_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_e.custom_minimum_size.x = 120
	box.add_child(id_e)
	IdCompleter.new(id_e, source)
	var note := Label.new()
	note.add_theme_color_override("font_color", NOTE_COLOR)
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(note)
	var w := _weight_box()
	box.add_child(w)
	var r := {"box": box, "id": id_e, "note": note, "weight": w,
			"up": _small_button(box, "↑", "Move up"),
			"down": _small_button(box, "↓", "Move down"),
			"remove": _small_button(box, "✕", "Remove this option")}
	id_e.text_submitted.connect(func(t: String) -> void: set_id(i, t))
	id_e.focus_exited.connect(func() -> void:
		if i < value.size() and id_e.text != id_text(option_id(value[i])):
			set_id(i, id_e.text))
	w.value_changed.connect(func(v: float) -> void:
		if not _filling and i < value.size() and int(v) != option_weight(value[i]):
			set_weight(i, int(v)))
	r.up.pressed.connect(func() -> void: move(i, i - 1))
	r.down.pressed.connect(func() -> void: move(i, i + 1))
	r.remove.pressed.connect(func() -> void: remove(i))
	return r


func _fill_row(i: int) -> void:
	var r := rows[i]
	var e: Variant = value[i]
	var id: Variant = option_id(e)
	var id_e: LineEdit = r.id
	var text := id_text(id)
	if id_e.text != text:
		id_e.text = text
		# Ids in one list tend to share a prefix: a long one shows its end.
		id_e.caret_column = text.length()
	id_e.tooltip_text = text
	var w: SpinBox = r.weight
	w.set_value_no_signal(option_weight(e))
	var note: Label = r.note
	var d: Array = describe.call(id) if describe.is_valid() and id is String else ["", false]
	note.text = d[0]
	note.tooltip_text = d[0]
	note.add_theme_color_override("font_color", PROBLEM_COLOR if d[1] else NOTE_COLOR)
	r.up.disabled = i == 0
	r.down.disabled = i == value.size() - 1


static func _weight_box() -> SpinBox:
	var w := SpinBox.new()
	w.min_value = 0
	w.max_value = MAX_WEIGHT
	w.allow_greater = true
	w.select_all_on_focus = true
	w.tooltip_text = "Weight among the options (BN's default is %d; 0 is never picked)" % DEFAULT_WEIGHT
	return w


static func _small_button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	parent.add_child(b)
	return b

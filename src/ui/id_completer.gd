class_name IdCompleter
extends CanvasLayer
## An autocomplete dropdown under a LineEdit: the ids from [member source]
## matching the typed text (those starting with it first, then those
## containing it; case ignored). Up/Down pick one, Enter or Tab (or a
## click) takes it, Esc closes the list. Taking one sets the edit's text
## and emits its text_changed and text_submitted, as if it was typed and
## Enter pressed.
##
## It's a CanvasLayer child of the edit, so the list draws over everything
## and isn't clipped by a ScrollContainer, and a click on it doesn't take
## the edit's focus (nothing on the layer can be focused). Text that looks
## like JSON ("[..." or "{...") gets no suggestions.

## Suggestions shown at most.
const MAX_SHOWN := 50
## Rows visible before the list scrolls.
const VISIBLE_ROWS := 10
const MIN_WIDTH := 240.0

var edit: LineEdit
## Returns the ids to suggest (a PackedStringArray, sorted). Called once
## each time the edit gains focus, or on the first update after that.
var source: Callable
var list: ItemList

var _ids := PackedStringArray()
var _loaded := false
## True while accept() emits text_changed, so the list stays closed.
var _accepting := false


func _init(p_edit: LineEdit, p_source: Callable) -> void:
	edit = p_edit
	source = p_source
	layer = 100
	list = ItemList.new()
	list.visible = false
	list.focus_mode = Control.FOCUS_NONE
	list.auto_height = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.12, 0.15)
	bg.border_color = Color(0.4, 0.45, 0.55)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(4)
	list.add_theme_stylebox_override("panel", bg)
	list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	list.item_clicked.connect(func(i: int, _at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			accept(i))
	add_child(list)
	edit.add_child(self)
	edit.text_changed.connect(func(_t: String) -> void:
		if not _accepting:
			update())
	edit.focus_entered.connect(func() -> void:
		_loaded = false
		update())
	edit.focus_exited.connect(close)
	edit.gui_input.connect(_on_edit_input)


## The ids matching [param text]: prefix matches first, then the rest
## containing it, each in [param ids]' order; at most [param limit].
static func matches(ids: PackedStringArray, text: String, limit := MAX_SHOWN) -> PackedStringArray:
	var t := text.strip_edges().to_lower()
	var starts := PackedStringArray()
	var contains := PackedStringArray()
	for id in ids:
		var low := id.to_lower()
		if low.begins_with(t):
			starts.append(id)
			if starts.size() >= limit:
				break
		elif contains.size() < limit and low.contains(t):
			contains.append(id)
	starts.append_array(contains)
	return starts.slice(0, limit)


## Fills the list for the edit's text and shows it (or hides it when
## nothing matches, or only the text itself does).
func update() -> void:
	if not _loaded:
		_ids = source.call() if source.is_valid() else PackedStringArray()
		_loaded = true
	list.clear()
	var text := edit.text.strip_edges()
	if text.begins_with("[") or text.begins_with("{"):
		close()
		return
	var found := matches(_ids, text, MAX_SHOWN + 1)
	if found.is_empty() or (found.size() == 1 and found[0] == text):
		close()
		return
	for id in found.slice(0, MAX_SHOWN):
		list.set_item_tooltip(list.add_item(id), id)
	if found.size() > MAX_SHOWN:
		list.set_item_disabled(list.add_item("... more; type to narrow"), true)
	list.visible = true
	_place()


func close() -> void:
	list.visible = false


func is_open() -> bool:
	return list.visible


## Takes suggestion [param i]: sets the edit's text, emits text_changed
## (setting text doesn't) and then text_submitted.
func accept(i: int) -> void:
	if i < 0 or i >= list.item_count or list.is_item_disabled(i):
		return
	var id := list.get_item_text(i)
	close()
	edit.text = id
	edit.caret_column = id.length()
	_accepting = true
	edit.text_changed.emit(id)
	_accepting = false
	edit.text_submitted.emit(id)


func _on_edit_input(event: InputEvent) -> void:
	if not list.visible or not event is InputEventKey or not event.pressed:
		return
	var sel := list.get_selected_items()
	var cur := sel[0] if sel.size() > 0 else -1
	match event.keycode:
		KEY_DOWN, KEY_UP:
			var step := 1 if event.keycode == KEY_DOWN else -1
			var next := clampi(cur + step, 0, list.item_count - 1)
			if cur < 0 and step < 0:
				next = list.item_count - 1
			while list.is_item_disabled(next) and next > 0:
				next -= 1
			list.select(next)
			list.ensure_current_is_visible()
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			if cur < 0:
				if event.keycode != KEY_TAB:
					close()
				return  # Enter submits the text as typed; Tab moves on.
			accept(cur)
		KEY_ESCAPE:
			close()
		_:
			return
	edit.accept_event()


func _process(_delta: float) -> void:
	if list.visible:
		_place()


## Puts the list under the edit, or above it when there's more room there,
## inside the edit's viewport (a dialog's window clips it).
func _place() -> void:
	if not edit.is_inside_tree():
		return
	var rect := edit.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, edit.size)
	var font := list.get_theme_font("font")
	var row := font.get_height(list.get_theme_font_size("font_size")) + list.get_theme_constant("v_separation") + 4
	var rows := mini(list.item_count, VISIBLE_ROWS)
	var size := Vector2(maxf(rect.size.x, MIN_WIDTH), rows * row + 10)
	var screen := edit.get_viewport().get_visible_rect().size
	var pos := Vector2(rect.position.x, rect.end.y)
	var below := screen.y - rect.end.y
	var above := rect.position.y
	if size.y > below:
		# Wherever there's more room, shrunk to fit (a dialog is small).
		size.y = minf(size.y, maxf(below, above))
		if above > below:
			pos.y = rect.position.y - size.y
	pos.x = clampf(pos.x, 0, maxf(0, screen.x - size.x))
	list.position = pos
	list.size = size

class_name MapCanvas
extends Control
## Draws an AsciiMap as a grid of colored characters, with coordinate rulers
## and the 24x24 overmap-tile boundaries. Wheel zooms around the cursor;
## middle or right drag (or space + left drag) pans. A left drag is reported
## as cell_pressed / cell_dragged / cell_released for the drawing tools.

## The cell under the mouse changed; (-1, -1) when it left the map.
signal cell_hovered(cell: Vector2i)
## The left button went down on a cell. [param alt] and [param shift] are
## the modifier keys.
signal cell_pressed(cell: Vector2i, alt: bool, shift: bool)
## The mouse moved to another cell during a left drag (clamped to the map).
signal cell_dragged(cell: Vector2i, shift: bool)
## The left button was released (the cell is clamped to the map).
signal cell_released(cell: Vector2i, shift: bool)

const OMT := MapgenResolver.OMT_SIZE
const RULER := 28.0
const MIN_CELL := 4.0
const MAX_CELL := 64.0
const CANVAS_BG := Color8(24, 24, 28)
const GRID := Color(1, 1, 1, 0.07)
const OMT_LINE := Color(1.0, 0.75, 0.2, 0.8)
const RULER_BG := Color8(40, 40, 46)
const RULER_TEXT := Color8(170, 170, 180)
const HOVER := Color(1, 1, 1, 0.9)
const HIGHLIGHT := Color8(120, 100, 20)
const EMPTY_BG := Color8(34, 34, 40)
const PROBLEM_BG := Color8(150, 0, 40)
const PREVIEW_BG := Color(0.3, 0.6, 1.0, 0.45)

## Line characters drawn as lines, so walls join whatever the font:
## sides as [N, E, S, W].
const LINES := {
	"│": [true, false, true, false], "─": [false, true, false, true],
	"┌": [false, true, true, false], "┐": [false, false, true, true],
	"└": [true, true, false, false], "┘": [true, false, false, true],
	"├": [true, true, true, false], "┤": [true, false, true, true],
	"┬": [false, true, true, true], "┴": [true, true, false, true],
	"┼": [true, true, true, true],
}

var ascii: AsciiMap:
	set(v):
		ascii = v
		queue_redraw()
## Draw each cell's row key instead of the resolved symbol.
var show_keys := false:
	set(v):
		show_keys = v
		queue_redraw()
## Cells whose key is this are highlighted ("" for none).
var highlight_key := "":
	set(v):
		highlight_key = v
		queue_redraw()
## Cells a tool is about to paint, drawn with [member preview_key]'s look.
var preview: Array[Vector2i] = []:
	set(v):
		preview = v
		queue_redraw()
var preview_key := ""
var cell_size := 18.0
## Screen position of cell (0, 0)'s top-left corner.
var origin := Vector2(RULER + 8, RULER + 8)
var hovered := -Vector2i.ONE

var _font: Font
var _panning := false
var _space := false
var _dragging := false
var _drag_cell := -Vector2i.ONE


func _init() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "Consolas",
			"Menlo", "Liberation Mono", "monospace"])
	_font = f


## The cell at a point in this control's coordinates, or (-1, -1).
func cell_at(pos: Vector2) -> Vector2i:
	if ascii == null or pos.x < RULER or pos.y < RULER:
		return -Vector2i.ONE
	var c := Vector2i(((pos - origin) / cell_size).floor())
	if c.x < 0 or c.y < 0 or c.x >= ascii.size.x or c.y >= ascii.size.y:
		return -Vector2i.ONE
	return c


## The cell at a point, clamped to the map (for drags that leave it).
func cell_at_clamped(pos: Vector2) -> Vector2i:
	var c := Vector2i(((pos - origin) / cell_size).floor())
	return c.clamp(Vector2i.ZERO, ascii.size - Vector2i.ONE)


## Fits the whole map in view, capped at a readable size.
func fit() -> void:
	if ascii == null or size.x <= RULER or size.y <= RULER:
		return
	var avail := size - Vector2(RULER, RULER) - Vector2(16, 16)
	cell_size = clampf(floorf(minf(avail.x / ascii.size.x, avail.y / ascii.size.y)), MIN_CELL, 24.0)
	origin = Vector2(RULER + 8, RULER + 8)
	queue_redraw()


func zoom_at(pos: Vector2, factor: float) -> void:
	var new_size := clampf(roundf(cell_size * factor), MIN_CELL, MAX_CELL)
	if new_size == cell_size:
		new_size = clampf(cell_size + signf(factor - 1.0), MIN_CELL, MAX_CELL)
	origin = pos - (pos - origin) * (new_size / cell_size)
	cell_size = new_size
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.15)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / 1.15)
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT] \
				or (mb.button_index == MOUSE_BUTTON_LEFT and _space):
			_panning = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var c := cell_at(mb.position)
				if c.x >= 0:
					_dragging = true
					_drag_cell = c
					cell_pressed.emit(c, mb.alt_pressed, mb.shift_pressed)
			elif _dragging:
				_dragging = false
				cell_released.emit(cell_at_clamped(mb.position), mb.shift_pressed)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			origin += mm.relative
			queue_redraw()
		_set_hovered(cell_at(mm.position))
		if _dragging:
			var c := cell_at_clamped(mm.position)
			if c != _drag_cell:
				_drag_cell = c
				cell_dragged.emit(c, mm.shift_pressed)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_space = k.pressed
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(-Vector2i.ONE)
		_panning = false
	elif what == NOTIFICATION_FOCUS_EXIT and _dragging:
		_dragging = false
		cell_released.emit(_drag_cell, false)


func _set_hovered(c: Vector2i) -> void:
	if c == hovered:
		return
	hovered = c
	queue_redraw()
	cell_hovered.emit(c)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), CANVAS_BG)
	if ascii == null:
		return
	var cs := cell_size
	var w := ascii.size.x
	var h := ascii.size.y
	# Visible cell range.
	var x0 := maxi(0, floori((RULER - origin.x) / cs))
	var y0 := maxi(0, floori((RULER - origin.y) / cs))
	var x1 := mini(w, ceili((size.x - origin.x) / cs))
	var y1 := mini(h, ceili((size.y - origin.y) / cs))
	var font_size := int(cs * 0.8)
	var draw_text := cs >= 7.0
	var ascent := _font.get_ascent(font_size) if draw_text else 0.0
	var descent := _font.get_descent(font_size) if draw_text else 0.0
	var baseline := (cs + ascent - descent) / 2.0

	for y in range(y0, y1):
		var row: PackedStringArray = ascii.resolved.cells[y]
		for x in range(x0, x1):
			var i := y * w + x
			var p := origin + Vector2(x, y) * cs
			var rect := Rect2(p, Vector2(cs, cs))
			var state := ascii.states[i]
			var back: Color = ascii.bg[i]
			if state == AsciiMap.State.EMPTY and back == BnColors.BLACK:
				back = EMPTY_BG
			elif state == AsciiMap.State.UNDEFINED or state == AsciiMap.State.NO_TERRAIN \
					or state == AsciiMap.State.UNKNOWN_ID:
				back = PROBLEM_BG
			if highlight_key and row[x] == highlight_key:
				back = back.lerp(HIGHLIGHT, 0.6)
			if back != BnColors.BLACK:
				draw_rect(rect, back)
			var ch := row[x] if show_keys else ascii.chars[i]
			if not draw_text or ch == " " or ch.is_empty():
				if not draw_text and ch != " " and not ch.is_empty():
					# Too small for text: a dot of the glyph's color.
					draw_rect(rect.grow(-cs * 0.3), ascii.fg[i])
				continue
			var sides: Variant = LINES.get(ch)
			if sides != null:
				_draw_line_glyph(rect, sides, ascii.fg[i])
			else:
				var tw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				draw_string(_font, Vector2(p.x + (cs - tw) / 2.0, p.y + baseline), ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ascii.fg[i])

	_draw_preview(font_size, baseline, draw_text)
	_draw_grid(x0, y0, x1, y1)
	if hovered.x >= 0:
		draw_rect(Rect2(origin + Vector2(hovered) * cs, Vector2(cs, cs)), HOVER, false, 2.0)
	_draw_rulers(x0, y0, x1, y1)


func _draw_preview(font_size: int, baseline: float, draw_text: bool) -> void:
	if preview.is_empty():
		return
	var look := ascii.look_for(preview_key)
	var cs := cell_size
	for c in preview:
		var p := origin + Vector2(c) * cs
		var rect := Rect2(p, Vector2(cs, cs))
		draw_rect(rect, look.colors.bg)
		draw_rect(rect, PREVIEW_BG)
		if draw_text and look.ch != " ":
			var sides: Variant = LINES.get(look.ch)
			if sides != null:
				_draw_line_glyph(rect, sides, look.colors.fg)
			else:
				var tw := _font.get_string_size(look.ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				draw_string(_font, Vector2(p.x + (cs - tw) / 2.0, p.y + baseline), look.ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, look.colors.fg)


func _draw_line_glyph(rect: Rect2, sides: Array, color: Color) -> void:
	var c := rect.get_center()
	var width := maxf(1.0, cell_size / 8.0)
	var ends := [Vector2(c.x, rect.position.y), Vector2(rect.end.x, c.y),
			Vector2(c.x, rect.end.y), Vector2(rect.position.x, c.y)]
	for s in 4:
		if sides[s]:
			draw_line(c, ends[s], color, width)
	draw_rect(Rect2(c - Vector2(width, width) / 2.0, Vector2(width, width)), color)


func _draw_grid(x0: int, y0: int, x1: int, y1: int) -> void:
	var cs := cell_size
	var top := origin.y + y0 * cs
	var bottom := origin.y + y1 * cs
	var left := origin.x + x0 * cs
	var right := origin.x + x1 * cs
	if cs >= 10.0:
		for x in range(x0, x1 + 1):
			if x % OMT != 0:
				draw_line(Vector2(origin.x + x * cs, top), Vector2(origin.x + x * cs, bottom), GRID)
		for y in range(y0, y1 + 1):
			if y % OMT != 0:
				draw_line(Vector2(left, origin.y + y * cs), Vector2(right, origin.y + y * cs), GRID)
	# OMT boundaries, including the map's outer edge.
	for x in range(x0, x1 + 1):
		if x % OMT == 0 or x == ascii.size.x:
			draw_line(Vector2(origin.x + x * cs, top), Vector2(origin.x + x * cs, bottom), OMT_LINE, 1.5)
	for y in range(y0, y1 + 1):
		if y % OMT == 0 or y == ascii.size.y:
			draw_line(Vector2(left, origin.y + y * cs), Vector2(right, origin.y + y * cs), OMT_LINE, 1.5)


func _draw_rulers(x0: int, y0: int, x1: int, y1: int) -> void:
	var cs := cell_size
	draw_rect(Rect2(0, 0, size.x, RULER), RULER_BG)
	draw_rect(Rect2(0, 0, RULER, size.y), RULER_BG)
	var fs := 11
	# Label every cell when there's room, else every 2/4/8/12/24.
	var step := 1
	for s in [1, 2, 4, 8, 12, 24]:
		step = s
		if cs * s >= 22.0:
			break
	for x in range(x0, x1):
		var px := origin.x + x * cs
		if px < RULER:
			continue
		var tick := 8.0 if x % OMT == 0 else 4.0
		draw_line(Vector2(px, RULER - tick), Vector2(px, RULER), OMT_LINE if x % OMT == 0 else RULER_TEXT)
		if x % step == 0:
			var label := str(x)
			var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tx := px + (cs - tw) / 2.0 if step == 1 else px + 2.0
			draw_string(_font, Vector2(tx, RULER - 10),
					label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OMT_LINE if x % OMT == 0 else RULER_TEXT)
	for y in range(y0, y1):
		var py := origin.y + y * cs
		if py < RULER:
			continue
		var tick := 8.0 if y % OMT == 0 else 4.0
		draw_line(Vector2(RULER - tick, py), Vector2(RULER, py), OMT_LINE if y % OMT == 0 else RULER_TEXT)
		if y % step == 0:
			var label := str(y)
			var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ty := py + cs / 2.0 + 4.0 if step == 1 else py + 12.0
			draw_string(_font, Vector2(RULER - 10 - tw, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
					fs, OMT_LINE if y % OMT == 0 else RULER_TEXT)
	draw_rect(Rect2(0, 0, RULER, RULER), RULER_BG)

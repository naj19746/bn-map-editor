class_name MapCanvas
extends Control
## Draws an AsciiMap as a grid of colored characters, with coordinate rulers
## and the 24x24 overmap-tile boundaries, and the map's placements on top:
## a box for a point, a dashed outline for a range, with labels like "I 50%".
## Placements BN drops or reads oddly are drawn in red, where BN puts them.
## The cells a selected problem points at are outlined in magenta.
## Cells whose symbol itself places items, monsters, ... get a corner mark.
## With the Nested layer shown, each placed chunk's footprint is outlined
## (dotted for chunks placed by chunks), and the part reaching past its
## overmap tile is shaded red. With a computer selected, its consoles'
## reach is drawn (see ConsoleReachView): stand cells, the reach outline,
## the doors it changes and other locked doors. Wheel zooms around the
## cursor; middle or right drag (or space + left drag) pans. A left drag is
## reported as cell_pressed / cell_dragged / cell_released for the drawing
## tools; a right click that doesn't move (or Shift+F10, or the Menu key,
## on the hovered cell) as cell_context.
## Around the map, the rest of its building's level (LevelNav.Neighbor) is
## drawn dimmed and read-only, each piece labelled; a tile no mapgen draws
## is hatched. Double-clicking one reports neighbor_activated.
## Under both, a ghost level (the level below or above, LevelNav.ghosts) is
## drawn dimmed where the map is see-through (AsciiMap.see_through: open
## air), and its stairs to this level (and its elevator floor) are marked
## over everything.
## With [member placed], the map itself is drawn as its building places it
## (each tile turned), read-only: placements, chunk footprints, previews and
## the rest are left out, and the cells the signals report are the map's
## own (to_map()).

## The cell under the mouse changed; (-1, -1) when it left the map.
signal cell_hovered(cell: Vector2i)
## The left button went down on a cell. [param alt] and [param shift] are
## the modifier keys.
signal cell_pressed(cell: Vector2i, alt: bool, shift: bool)
## The mouse moved to another cell during a left drag (clamped to the map).
signal cell_dragged(cell: Vector2i, shift: bool)
## The left button was released (the cell is clamped to the map).
signal cell_released(cell: Vector2i, shift: bool)
## A cell menu was asked for on [param cell], at [param at] (this
## control's coordinates).
signal cell_context(cell: Vector2i, at: Vector2)
## The mouse moved onto neighbor [param i] (-1: off every neighbor).
signal neighbor_hovered(i: int)
## Neighbor [param i] was double-clicked.
signal neighbor_activated(i: int)

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
## By Placement.Layer.
const LAYER_COLORS := [Color(1.0, 0.85, 0.3), Color(1.0, 0.45, 0.45), Color(0.4, 0.85, 1.0),
		Color(0.8, 0.55, 1.0), Color(0.5, 1.0, 0.55)]
const PLACEMENT_PROBLEM := Color(1.0, 0.15, 0.25)
const LABEL_BG := Color(0, 0, 0, 0.65)
const OVERHANG := Color(1.0, 0.15, 0.25, 0.22)
const FOCUS := Color(1.0, 0.3, 1.0)
## How far a neighbor's colors fade towards the background.
const NEIGHBOR_DIM := 0.55
const NEIGHBOR_LINE := Color(1.0, 0.75, 0.2, 0.35)
const NEIGHBOR_HOVER := Color(1.0, 0.75, 0.2, 0.9)
const NEIGHBOR_TEXT := Color8(220, 200, 150)
const NEIGHBOR_FLAT := Color(1.0, 0.75, 0.2, 0.08)
## How far a ghost level's colors fade towards the background (when
## dimmed).
const GHOST_DIM := 0.7
const GHOST_STAIRS := Color(0.3, 0.9, 1.0, 0.9)
const GHOST_ELEVATOR := Color(1.0, 0.6, 0.2, 0.9)
## Below this cell size neighbors are flat boxes: a big special's level
## would be hundreds of thousands of cells.
const NEIGHBOR_CELLS_MIN := 7.0
## Console reach: stand cells, the reach outline, doors reached (faded when
## only some stand cells reach them), other locked doors.
const REACH_STAND := Color(0.35, 0.65, 1.0)
const REACH_AREA := Color(0.4, 0.9, 1.0)
const REACH_TARGET := Color(0.45, 1.0, 0.45)
const REACH_OTHER := Color(1.0, 0.3, 0.3)
## Cells a new console could go.
const SPOT := Color(0.45, 1.0, 0.45)
## A right press that moves less than this (pixels) is a click.
const CLICK_SLOP := 4.0

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
## The map's placements (MapDocument.placements()).
var placements: Array[Placement] = []:
	set(v):
		placements = v
		queue_redraw()
## Bit (1 << Placement.Layer) set for each layer drawn.
var layer_mask := (1 << Placement.LAYER_NAMES.size()) - 1:
	set(v):
		layer_mask = v
		queue_redraw()
## The map's nested chunks, for their footprints (null for none).
var chunks: ChunkOverlay:
	set(v):
		chunks = v
		queue_redraw()
## The selected placement ("" for none).
var selected_member := ""
var selected_index := -1
## Where a dragged placement would go, in cells (empty when idle).
var placement_preview := Rect2i():
	set(v):
		placement_preview = v
		queue_redraw()
## Cells a selected problem points at, outlined (empty for none).
var focus := Rect2i():
	set(v):
		focus = v
		queue_redraw()
## The selected computer's reach (null for none).
var reach: ConsoleReachView:
	set(v):
		reach = v
		queue_redraw()
## Cells offered for a new console (empty for none).
var spots: Array[Vector2i] = []:
	set(v):
		spots = v
		queue_redraw()
## The rest of the map's building level, drawn around it (cells relative
## to the map's top-left).
var neighbors: Array[LevelNav.Neighbor] = []:
	set(v):
		neighbors = v
		hovered_neighbor = -1
		queue_redraw()
## The neighbor under the mouse, or -1.
var hovered_neighbor := -1
## The level below or above, drawn under the map and its neighbors.
var ghosts: Array[LevelNav.Neighbor] = []:
	set(v):
		ghosts = v
		queue_redraw()
## Draw the ghost level faded (else at full color).
var ghost_dim := true:
	set(v):
		ghost_dim = v
		queue_redraw()
## True when the ghost is the level above (its stairs lead down here).
var ghost_above := false
## The map as placed (LevelNav.placed, pieces with their ascii), drawn
## instead of [member ascii]; empty: the map as it is.
var placed: Array[LevelNav.Neighbor] = []:
	set(v):
		placed = v
		queue_redraw()
var cell_size := 18.0
## Screen position of cell (0, 0)'s top-left corner.
var origin := Vector2(RULER + 8, RULER + 8)
var hovered := -Vector2i.ONE

var _font: Font
var _panning := false
var _space := false
var _dragging := false
var _drag_cell := -Vector2i.ONE
## Where the right button went down; x < 0 once it moved too far.
var _right_press := -Vector2.ONE


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


## The map's cell drawn at [param c] (a cell_at() cell): [param c] itself
## unless the map is drawn [member placed]; then (-1, -1) where no tile of
## it is drawn.
func to_map(c: Vector2i) -> Vector2i:
	if c.x < 0 or placed.is_empty():
		return c
	for n in placed:
		if n.rect().has_point(c):
			return n.to_ref(c - n.cell)
	return -Vector2i.ONE


## The cell at a point, clamped to the map (for drags that leave it).
func cell_at_clamped(pos: Vector2) -> Vector2i:
	var c := Vector2i(((pos - origin) / cell_size).floor())
	return c.clamp(Vector2i.ZERO, ascii.size - Vector2i.ONE)


## Marks the placement [param member] #[param index] as selected.
func select_placement(member: String, index: int) -> void:
	selected_member = member
	selected_index = index
	queue_redraw()


## Scrolls so [param rect] (cells) is in the middle of the view.
func center_on(rect: Rect2i) -> void:
	var mid := (Vector2(rect.position) + Vector2(rect.size) / 2.0) * cell_size
	origin = (size + Vector2(RULER, RULER)) / 2.0 - mid
	queue_redraw()


## Fits the whole map and its neighbors in view, capped at a readable size.
func fit() -> void:
	if ascii == null or size.x <= RULER or size.y <= RULER:
		return
	var avail := size - Vector2(RULER, RULER) - Vector2(16, 16)
	var whole := bounds()
	var fits := floorf(minf(avail.x / whole.size.x, avail.y / whole.size.y))
	if fits < NEIGHBOR_CELLS_MIN:
		# Too big to show whole: the map alone.
		whole = Rect2i(Vector2i.ZERO, ascii.size)
		fits = floorf(minf(avail.x / whole.size.x, avail.y / whole.size.y))
	cell_size = clampf(fits, MIN_CELL, 24.0)
	origin = Vector2(RULER + 8, RULER + 8) - Vector2(whole.position) * cell_size
	queue_redraw()


## The cells the map and its neighbors cover.
func bounds() -> Rect2i:
	var whole := Rect2i(Vector2i.ZERO, ascii.size if ascii else Vector2i.ONE)
	for n in neighbors:
		whole = whole.merge(n.rect())
	return whole


## The neighbor at a point in this control's coordinates, or -1.
func neighbor_at_point(pos: Vector2) -> int:
	if neighbors.is_empty() or pos.x < RULER or pos.y < RULER:
		return -1
	return LevelNav.neighbor_at(neighbors, Vector2i(((pos - origin) / cell_size).floor()))


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
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_right_press = mb.position
				elif _right_press.x >= 0:
					_right_press = -Vector2.ONE
					var c := to_map(cell_at(mb.position))
					if c.x >= 0:
						cell_context.emit(c, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click and cell_at(mb.position).x < 0:
				var n := neighbor_at_point(mb.position)
				if n >= 0:
					neighbor_activated.emit(n)
			elif mb.pressed:
				var c := cell_at(mb.position)
				if to_map(c).x >= 0:
					_dragging = true
					_drag_cell = c
					cell_pressed.emit(to_map(c), mb.alt_pressed, mb.shift_pressed)
			elif _dragging:
				_dragging = false
				var c := cell_at_clamped(mb.position)
				cell_released.emit(to_map(c) if to_map(c).x >= 0 else to_map(_drag_cell), mb.shift_pressed)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			origin += mm.relative
			queue_redraw()
			if _right_press.x >= 0 and mm.position.distance_to(_right_press) > CLICK_SLOP:
				_right_press = -Vector2.ONE
		_set_hovered(cell_at(mm.position))
		var n := neighbor_at_point(mm.position) if hovered.x < 0 else -1
		if n != hovered_neighbor:
			hovered_neighbor = n
			queue_redraw()
			neighbor_hovered.emit(n)
		if _dragging:
			var c := cell_at_clamped(mm.position)
			if c != _drag_cell and to_map(c).x >= 0:
				_drag_cell = c
				cell_dragged.emit(to_map(c), mm.shift_pressed)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_space = k.pressed
			accept_event()
		elif k.pressed and to_map(hovered).x >= 0 and (k.keycode == KEY_MENU or (k.keycode == KEY_F10 and k.shift_pressed)):
			cell_context.emit(to_map(hovered), origin + (Vector2(hovered) + Vector2(0.5, 0.5)) * cell_size)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(-Vector2i.ONE)
		if hovered_neighbor >= 0:
			hovered_neighbor = -1
			neighbor_hovered.emit(-1)
		_panning = false
	elif what == NOTIFICATION_FOCUS_EXIT and _dragging:
		_dragging = false
		cell_released.emit(to_map(_drag_cell), false)


func _set_hovered(c: Vector2i) -> void:
	if c == hovered:
		return
	hovered = c
	queue_redraw()
	cell_hovered.emit(to_map(c))


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

	for g in ghosts:
		if g.ascii:
			_draw_cells(g.ascii, origin + Vector2(g.cell) * cs, GHOST_DIM if ghost_dim else 0.0,
					font_size, baseline, false)
	var through := not ghosts.is_empty()
	for i in neighbors.size():
		_draw_neighbor(neighbors[i], i == hovered_neighbor, font_size, baseline, through)
	if not placed.is_empty():
		for n in placed:
			if n.ascii:
				_draw_cells(n.ascii, origin + Vector2(n.cell) * cs, 0.0, font_size, baseline, through, true)
		_draw_ghost_stairs()
		_draw_grid(x0, y0, x1, y1)
		if hovered.x >= 0:
			draw_rect(Rect2(origin + Vector2(hovered) * cs, Vector2(cs, cs)), HOVER, false, 2.0)
		_draw_rulers(x0, y0, x1, y1)
		return

	for y in range(y0, y1):
		var row: PackedStringArray = ascii.resolved.cells[y]
		for x in range(x0, x1):
			var i := y * w + x
			var p := origin + Vector2(x, y) * cs
			var rect := Rect2(p, Vector2(cs, cs))
			var state := ascii.states[i]
			var back: Color = ascii.bg[i]
			if through and not show_keys and ascii.see_through[i]:
				# The ghost level shows here: only tint it.
				if highlight_key and row[x] == highlight_key:
					draw_rect(rect, Color(HIGHLIGHT, 0.3))
				if layer_mask and cs >= 6.0 and ascii.look_for(row[x]).layers & layer_mask:
					_draw_mark(rect, ascii.look_for(row[x]).layers & layer_mask)
				continue
			if state == AsciiMap.State.EMPTY and back == BnColors.BLACK:
				back = EMPTY_BG
			elif state == AsciiMap.State.UNDEFINED or state == AsciiMap.State.NO_TERRAIN \
					or state == AsciiMap.State.UNKNOWN_ID:
				back = PROBLEM_BG
			if highlight_key and row[x] == highlight_key:
				back = back.lerp(HIGHLIGHT, 0.6)
			if back != BnColors.BLACK:
				draw_rect(rect, back)
			elif through:
				draw_rect(rect, CANVAS_BG)  # Hides the ghost.
			if layer_mask and cs >= 6.0:
				var marks: int = ascii.look_for(row[x]).layers & layer_mask
				if marks:
					_draw_mark(rect, marks)
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
	_draw_ghost_stairs()
	_draw_grid(x0, y0, x1, y1)
	_draw_reach()
	_draw_spots()
	_draw_placements()
	if focus.has_area():
		var r := Rect2(origin + Vector2(focus.position) * cs, Vector2(focus.size) * cs)
		draw_rect(r.grow(2.0), FOCUS, false, 3.0)
	if hovered.x >= 0:
		draw_rect(Rect2(origin + Vector2(hovered) * cs, Vector2(cs, cs)), HOVER, false, 2.0)
	_draw_rulers(x0, y0, x1, y1)


## A neighbor's cells, faded, with its outline and label; with
## [param through], its see-through cells are left for the ghost level.
func _draw_neighbor(n: LevelNav.Neighbor, is_hovered: bool, font_size: int, baseline: float,
		through := false) -> void:
	var cs := cell_size
	var r := n.rect()
	var box := Rect2(origin + Vector2(r.position) * cs, Vector2(r.size) * cs)
	if not box.intersects(Rect2(Vector2(RULER, RULER), size)):
		return
	var a := n.ascii
	if a and cs < NEIGHBOR_CELLS_MIN:
		draw_rect(box, NEIGHBOR_FLAT)
	elif a:
		_draw_cells(a, box.position, NEIGHBOR_DIM, font_size, baseline, through)
	else:
		# No mapgen draws this tile: hatch it.
		var step := maxf(cs * 3.0, 12.0)
		var d := 0.0
		while d < box.size.x + box.size.y:
			var p0 := box.position + Vector2(minf(d, box.size.x), maxf(0.0, d - box.size.x))
			var p1 := box.position + Vector2(maxf(0.0, d - box.size.y), minf(d, box.size.y))
			draw_line(p0, p1, NEIGHBOR_LINE)
			d += step
	draw_rect(box, NEIGHBOR_HOVER if is_hovered else NEIGHBOR_LINE, false, 2.0 if is_hovered else 1.0)
	if box.size.x < 60.0 and not is_hovered:
		return
	var fs := 12
	var label := n.label()
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while tw > box.size.x - 10.0 and label.length() > 4 and not is_hovered:
		label = label.left(-4) + "…"
		tw = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(box.position + Vector2(2, 2), Vector2(tw + 6, fs + 6)), LABEL_BG)
	draw_string(_font, box.position + Vector2(5, fs + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			NEIGHBOR_TEXT)


## The visible cells of [param a] with its top-left at [param at], colors
## faded [param dim] towards the background; see-through cells skipped
## when [param through]. Nothing below NEIGHBOR_CELLS_MIN unless
## [param small].
func _draw_cells(a: AsciiMap, at: Vector2, dim: float, font_size: int, baseline: float, through: bool,
		small := false) -> void:
	var cs := cell_size
	if cs < NEIGHBOR_CELLS_MIN and not small:
		return
	var x0 := maxi(0, floori((RULER - at.x) / cs))
	var y0 := maxi(0, floori((RULER - at.y) / cs))
	var x1 := mini(a.size.x, ceili((size.x - at.x) / cs))
	var y1 := mini(a.size.y, ceili((size.y - at.y) / cs))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * a.size.x + x
			if through and a.see_through[i]:
				continue
			var rect := Rect2(at + Vector2(x, y) * cs, Vector2(cs, cs))
			var back: Color = a.bg[i]
			if back != BnColors.BLACK:
				draw_rect(rect, back.lerp(CANVAS_BG, dim))
			elif through:
				draw_rect(rect, CANVAS_BG)
			var ch := a.chars[i]
			if ch == " " or ch.is_empty():
				continue
			var fg: Color = a.fg[i].lerp(CANVAS_BG, dim)
			var sides: Variant = LINES.get(ch)
			if sides != null:
				_draw_line_glyph(rect, sides, fg)
			else:
				var tw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				draw_string(_font, Vector2(rect.position.x + (cs - tw) / 2.0, rect.position.y + baseline),
						ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)


## The ghost level's stairs to this level: an outlined cell with a
## triangle pointing the way they lead (up from below, down from above).
## Its elevator floor: a dashed outline.
func _draw_ghost_stairs() -> void:
	var cs := cell_size
	if cs < 4.0:
		return
	for g in ghosts:
		for c in g.elevators:
			var rect := Rect2(origin + Vector2(g.cell + c) * cs, Vector2(cs, cs)).grow(-2.0)
			if not rect.intersects(Rect2(Vector2(RULER, RULER), size)):
				continue
			var d := maxf(2.0, cs / 6.0)
			for side in [[rect.position, rect.position + Vector2(rect.size.x, 0)],
					[rect.position + Vector2(0, rect.size.y), rect.end],
					[rect.position, rect.position + Vector2(0, rect.size.y)],
					[rect.position + Vector2(rect.size.x, 0), rect.end]]:
				draw_dashed_line(side[0], side[1], GHOST_ELEVATOR, 1.5, d)
	for g in ghosts:
		for c in g.stairs:
			var rect := Rect2(origin + Vector2(g.cell + c) * cs, Vector2(cs, cs))
			if not rect.intersects(Rect2(Vector2(RULER, RULER), size)):
				continue
			draw_rect(rect.grow(-1.0), GHOST_STAIRS, false, 2.0)
			var m := rect.position + Vector2(cs, cs) * 0.5
			var h := cs * 0.22
			var tip := -h if not ghost_above else h
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, tip), m + Vector2(-h, -tip), m + Vector2(h, -tip)]),
					GHOST_STAIRS)


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


## The selected computer's reach: stand cells shaded, the reach area
## outlined (an outline, not shading: a radius-25 action covers most of a
## tile), doors it changes boxed (faded when only some stand cells reach
## them), other locked doors crossed out, consoles ringed.
func _draw_reach() -> void:
	if reach == null:
		return
	var cs := cell_size
	var width := maxf(1.5, cs / 9.0)
	for c: Vector2i in reach.stands:
		draw_rect(Rect2(origin + Vector2(c) * cs, Vector2(cs, cs)), Color(REACH_STAND, 0.35))
	if not reach.outline.is_empty():
		var pts := PackedVector2Array()
		pts.resize(reach.outline.size())
		for i in reach.outline.size():
			pts[i] = origin + reach.outline[i] * cs
		draw_multiline(pts, Color(REACH_AREA, 0.85), width)
	for c: Vector2i in reach.targets:
		var r := Rect2(origin + Vector2(c) * cs, Vector2(cs, cs))
		var full: bool = reach.targets[c]
		draw_rect(r, Color(REACH_TARGET, 0.4 if full else 0.15))
		draw_rect(r.grow(-1.0), Color(REACH_TARGET, 1.0 if full else 0.5), false, width * (1.5 if full else 1.0))
	for c: Vector2i in reach.other_locked:
		var r := Rect2(origin + Vector2(c) * cs, Vector2(cs, cs)).grow(-cs * 0.15)
		draw_rect(r, REACH_OTHER, false, width)
		draw_line(r.position, r.end, REACH_OTHER, width)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), REACH_OTHER, width)
	for c in reach.consoles:
		var center := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cs
		draw_arc(center, cs * 0.7, 0, TAU, 24, REACH_AREA, width)


## Cells offered for a new console: shaded with a dotted box.
func _draw_spots() -> void:
	var cs := cell_size
	for c in spots:
		var r := Rect2(origin + Vector2(c) * cs, Vector2(cs, cs))
		draw_rect(r, Color(SPOT, 0.3))
		draw_rect(r.grow(-maxf(1.0, cs * 0.1)), Color(SPOT, 0.8), false, 1.0)


## A corner triangle in the color of the first layer in [param marks]:
## the cell's symbol itself places items, monsters, ...
func _draw_mark(rect: Rect2, marks: int) -> void:
	var layer := 0
	while not marks & (1 << layer):
		layer += 1
	var s := rect.size.x * 0.3
	var tr := Vector2(rect.end.x, rect.position.y)
	draw_colored_polygon(PackedVector2Array([tr, tr - Vector2(s, 0), tr + Vector2(0, s)]), LAYER_COLORS[layer])


func _draw_placements() -> void:
	var cs := cell_size
	# Visible cells, not cut to the map: dropped entries lie outside it.
	var view := Rect2i(Vector2i(((Vector2(RULER, RULER) - origin) / cs).floor()) - Vector2i.ONE,
			Vector2i((size / cs).ceil()) + Vector2i(2, 2))
	var fs := clampi(int(cs * 0.6), 9, 14)
	if chunks and layer_mask & (1 << Placement.Layer.NESTED):
		for st in chunks.stamps:
			if view.intersects(st.footprint):
				_draw_footprint(st, fs)
	var selected: Placement = null
	for p in placements:
		if not layer_mask & (1 << p.layer()):
			continue
		if p.member == selected_member and p.index == selected_index:
			selected = p
			continue
		_draw_placement(p, view, fs, false)
	if selected:
		_draw_placement(selected, view, fs, true)
	if placement_preview.has_area():
		var r := Rect2(origin + Vector2(placement_preview.position) * cs, Vector2(placement_preview.size) * cs)
		draw_rect(r, PREVIEW_BG)
		draw_rect(r, Color.WHITE, false, 2.0)


func _draw_placement(p: Placement, view: Rect2i, fs: int, is_selected: bool) -> void:
	var cs := cell_size
	var ok := p.status == Placement.Status.OK
	var color: Color = LAYER_COLORS[p.layer()] if ok else PLACEMENT_PROBLEM
	var width := 2.5 if is_selected else 1.5
	var label := p.label() if ok else p.label() + " !"
	for cells in p.instances():
		if not view.intersects(cells):
			continue
		var r := Rect2(origin + Vector2(cells.position) * cs, Vector2(cells.size) * cs)
		if is_selected:
			draw_rect(r, Color(color, 0.18))
		if cells.size == Vector2i.ONE:
			draw_rect(r.grow(-maxf(1.0, cs * 0.12)), color, false, width)
		else:
			var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			for k in 4:
				draw_dashed_line(corners[k], corners[(k + 1) % 4], color, width, maxf(3.0, cs * 0.4))
			if is_selected:
				# The resize handle: the bottom-right cell.
				draw_rect(Rect2(r.end - Vector2(cs, cs), Vector2(cs, cs)).grow(-cs * 0.3), color)
		if cs >= 8.0:
			var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var at := r.position + Vector2(2, 1)
			draw_rect(Rect2(at, ts + Vector2(2, 0)), LABEL_BG)
			draw_string(_font, at + Vector2(1, _font.get_ascent(fs)), label, HORIZONTAL_ALIGNMENT_LEFT,
					-1, fs, color)


## A chunk's footprint: solid for the map's own placements, dotted for
## chunks placed by chunks, with the part past its tile shaded.
func _draw_footprint(st: ChunkOverlay.Stamp, fs: int) -> void:
	var cs := cell_size
	var color: Color = LAYER_COLORS[Placement.Layer.NESTED]
	var is_selected := st.depth == 0 and st.member == selected_member and st.index == selected_index \
			and selected_member == "place_nested"
	var r := Rect2(origin + Vector2(st.footprint.position) * cs, Vector2(st.footprint.size) * cs)
	if st.overhangs():
		var inside := st.footprint.intersection(st.tile)
		for part in _outside(st.footprint, inside):
			draw_rect(Rect2(origin + Vector2(part.position) * cs, Vector2(part.size) * cs), OVERHANG)
	if st.depth == 0:
		draw_rect(r.grow(-1.0), Color(color, 0.9 if is_selected else 0.55), false, 2.0 if is_selected else 1.0)
	else:
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			draw_dashed_line(corners[k], corners[(k + 1) % 4], Color(color, 0.4), 1.0, maxf(2.0, cs * 0.2))
		return
	if cs >= 8.0 and st.footprint.size.y >= 2:
		var label := st.label()
		var tint := PLACEMENT_PROBLEM if not st.problems.is_empty() or st.overhangs() else color
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := Vector2(r.position.x + 2, r.end.y - ts.y - 1)
		draw_rect(Rect2(at, ts + Vector2(2, 0)), LABEL_BG)
		draw_string(_font, at + Vector2(1, _font.get_ascent(fs)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)


## [param whole] minus [param inside] (a rect inside it), as up to four rects.
static func _outside(whole: Rect2i, inside: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if not inside.has_area():
		out.append(whole)
		return out
	if inside.position.y > whole.position.y:
		out.append(Rect2i(whole.position.x, whole.position.y, whole.size.x, inside.position.y - whole.position.y))
	if inside.end.y < whole.end.y:
		out.append(Rect2i(whole.position.x, inside.end.y, whole.size.x, whole.end.y - inside.end.y))
	if inside.position.x > whole.position.x:
		out.append(Rect2i(whole.position.x, inside.position.y, inside.position.x - whole.position.x, inside.size.y))
	if inside.end.x < whole.end.x:
		out.append(Rect2i(inside.end.x, inside.position.y, whole.end.x - inside.end.x, inside.size.y))
	return out


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

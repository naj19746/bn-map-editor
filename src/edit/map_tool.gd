class_name MapTool
extends RefCounted
## The drawing tools, driven by press/move/release on map cells. Each press
## to release is one undoable change. Line and Rect show [member preview]
## until release.

## The Pick tool (or Alt+click) chose the symbol at a cell.
signal picked(key: String)

## ERASE paints like PAINT with [method blank_key] instead of the brush.
## PLACE selects and drags placements; main hands its drags to a
## PlacementTool instead.
enum Kind { PAINT, ERASE, LINE, RECT, FILL, PICK, PLACE }

const NAMES := ["Paint", "Erase", "Line", "Rect", "Fill", "Pick", "Place"]

var kind := Kind.PAINT
## The symbol drawn, "" for none.
var key := ""
## Cells Line/Rect will paint on release.
var preview: Array[Vector2i] = []

var _doc: MapDocument
## The symbol the current drag draws: [member key], or the blank when erasing.
var _key := ""
var _start := Vector2i.ZERO
var _last := Vector2i.ZERO


func is_active() -> bool:
	return _doc != null


## The symbol an erased cell gets: " " (or ".", BN's other symbol that may go
## undefined), which leaves fill_ter, the predecessor, or what a nested chunk
## lands on. "" when the map gives both a meaning.
static func blank_key(res: ResolvedMapgen) -> String:
	for k in [" ", "."]:
		if not res.symbols.has(k):
			return k
	return ""


## Starts a drag at [param cell]. [param pick] forces the Pick tool (Alt);
## [param filled] makes Rect fill its inside (Shift). Returns false when
## there's nothing to draw with (no symbol chosen).
func press(doc: MapDocument, cell: Vector2i, pick := false, filled := false) -> bool:
	cancel()
	if kind == Kind.PICK or pick:
		if cell.y < doc.resolved.cells.size() and cell.x < doc.resolved.cells[cell.y].size():
			picked.emit(doc.resolved.cells[cell.y][cell.x])
		return true
	if kind == Kind.PLACE:
		return true
	_key = blank_key(doc.resolved) if kind == Kind.ERASE else key
	if _key.is_empty():
		return false
	match kind:
		Kind.PAINT, Kind.ERASE:
			_doc = doc
			_last = cell
			doc.begin_stroke("Erase" if kind == Kind.ERASE else "Paint '%s'" % _key)
			doc.set_cells([cell], _key)
		Kind.LINE, Kind.RECT:
			_doc = doc
			_start = cell
			_update_preview(cell, filled)
		Kind.FILL:
			doc.paint(Shapes.flood(doc.resolved.cells, cell), _key, "Fill '%s'" % _key)
	return true


func move(cell: Vector2i, filled := false) -> void:
	if _doc == null:
		return
	if _strokes():
		# Join the cells so a fast drag leaves no gaps.
		_doc.set_cells(Shapes.line(_last, cell), _key)
		_last = cell
	else:
		_update_preview(cell, filled)


func release(cell: Vector2i, filled := false) -> void:
	if _doc == null:
		return
	var doc := _doc
	_doc = null
	if _strokes():
		doc.end_stroke()
		return
	_update_preview(cell, filled)
	var shape := preview
	preview = []
	doc.paint(shape, _key, "%s '%s'" % [NAMES[kind], _key])


## Stops a drag: a Paint stroke keeps what it painted, a Line/Rect is dropped.
func cancel() -> void:
	if _doc != null and _strokes():
		_doc.end_stroke()
	_doc = null
	preview = []


## Paint and Erase draw while dragging; the others on release.
func _strokes() -> bool:
	return kind == Kind.PAINT or kind == Kind.ERASE


func _update_preview(cell: Vector2i, filled: bool) -> void:
	preview = Shapes.line(_start, cell) if kind == Kind.LINE else Shapes.rect(_start, cell, filled)

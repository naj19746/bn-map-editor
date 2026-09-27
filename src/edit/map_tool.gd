class_name MapTool
extends RefCounted
## The drawing tools, driven by press/move/release on map cells. Each press
## to release is one undoable change. Line and Rect show [member preview]
## until release.

## The Pick tool (or Alt+click) chose the symbol at a cell.
signal picked(key: String)

## PLACE selects and drags placements; main hands its drags to a
## PlacementTool instead.
enum Kind { PAINT, LINE, RECT, FILL, PICK, PLACE }

const NAMES := ["Paint", "Line", "Rect", "Fill", "Pick", "Place"]

var kind := Kind.PAINT
## The symbol drawn, "" for none.
var key := ""
## Cells Line/Rect will paint on release.
var preview: Array[Vector2i] = []

var _doc: MapDocument
var _start := Vector2i.ZERO
var _last := Vector2i.ZERO


func is_active() -> bool:
	return _doc != null


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
	if key.is_empty():
		return false
	match kind:
		Kind.PAINT:
			_doc = doc
			_last = cell
			doc.begin_stroke("Paint '%s'" % key)
			doc.set_cells([cell], key)
		Kind.LINE, Kind.RECT:
			_doc = doc
			_start = cell
			_update_preview(cell, filled)
		Kind.FILL:
			doc.paint(Shapes.flood(doc.resolved.cells, cell), key, "Fill '%s'" % key)
	return true


func move(cell: Vector2i, filled := false) -> void:
	if _doc == null:
		return
	if kind == Kind.PAINT:
		# Join the cells so a fast drag leaves no gaps.
		_doc.set_cells(Shapes.line(_last, cell), key)
		_last = cell
	else:
		_update_preview(cell, filled)


func release(cell: Vector2i, filled := false) -> void:
	if _doc == null:
		return
	var doc := _doc
	_doc = null
	if kind == Kind.PAINT:
		doc.end_stroke()
		return
	_update_preview(cell, filled)
	var shape := preview
	preview = []
	doc.paint(shape, key, "%s '%s'" % [NAMES[kind], key])


## Stops a drag: a Paint stroke keeps what it painted, a Line/Rect is dropped.
func cancel() -> void:
	if _doc != null and kind == Kind.PAINT:
		_doc.end_stroke()
	_doc = null
	preview = []


func _update_preview(cell: Vector2i, filled: bool) -> void:
	preview = Shapes.line(_start, cell) if kind == Kind.LINE else Shapes.rect(_start, cell, filled)

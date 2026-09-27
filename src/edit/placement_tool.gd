class_name PlacementTool
extends RefCounted
## The Place tool, driven by press/move/release on map cells like MapTool.
## A click selects the smallest visible placement under the cursor (or the
## place_nested entry whose chunk is drawn there) and a drag moves it; dragging the selected one's bottom-right cell (or any of its
## cells with Shift) resizes it; with a kind armed (Add), a drag adds a new
## entry there. Every result stays inside one overmap tile
## (Placement.clamp_move / clamp_span), so no range crosses a tile boundary.
## Each drag is one undoable change of the map.

## The selection changed; [param member] is "" for none.
signal selection_changed(member: String, index: int)
## A drag or an add was refused, e.g. BN would drop the result.
signal failed(message: String)

enum Mode { NONE, MOVE, RESIZE, CREATE }

## The selected placement: its list and position ("" and -1 for none).
var member := ""
var index := -1
## The kind a drag on the map adds ("" for none); cleared once added.
var armed := ""
## Bit (1 << Placement.Layer) set for each layer that can be picked.
var layer_mask := (1 << Placement.LAYER_NAMES.size()) - 1
## Where the dragged placement would go, in map cells (empty when idle).
var preview := Rect2i()
var mode := Mode.NONE

var _doc: MapDocument
var _start := Vector2i.ZERO
var _orig := Rect2i()
var _instance := 0
var _tile := Rect2i()


func is_active() -> bool:
	return _doc != null


func select(p_member: String, p_index: int) -> void:
	if p_member == member and p_index == index:
		return
	member = p_member
	index = p_index
	selection_changed.emit(member, index)


## The selected placement of [param doc], or null.
func selected(doc: MapDocument) -> Placement:
	return doc.placement(member, index) if doc and member else null


func is_visible(p: Placement) -> bool:
	return layer_mask & (1 << p.layer()) != 0


func press(doc: MapDocument, cell: Vector2i, shift := false) -> void:
	cancel()
	_doc = doc
	_start = cell
	var g := _geometry()
	if armed:
		mode = Mode.CREATE
		_tile = g.tile_of(cell)
		preview = Placement.clamp_span(cell, cell, g)
		return
	var sel := selected(doc)
	if sel and is_visible(sel) and _grab(sel, cell, shift):
		return
	for p in doc.placements_at(cell):
		if is_visible(p):
			select(p.member, p.index)
			_grab(p, cell, shift)
			return
	if layer_mask & (1 << Placement.Layer.NESTED):
		for st in doc.chunk_overlay().stamps_at(cell):
			var p := doc.placement(st.member, st.index) if st.depth == 0 else null
			if p:
				select(p.member, p.index)
				_grab(p, cell, false)
				return
	select("", -1)
	_doc = null


func move(cell: Vector2i) -> void:
	if _doc == null:
		return
	var g := _geometry()
	match mode:
		Mode.MOVE:
			preview = Placement.clamp_move(Rect2i(_orig.position + cell - _start, _orig.size), g)
			if _is_set():
				# A "set" entry is in tile coordinates: it stays in its tile.
				var size := preview.size.min(_tile.size)
				preview = Rect2i(preview.position.clamp(_tile.position, _tile.end - size), size)
		Mode.RESIZE:
			preview = _cut(Placement.clamp_span(_orig.position, cell, g))
		Mode.CREATE:
			preview = Placement.clamp_span(_start, cell, g)


func release(cell: Vector2i) -> void:
	if _doc == null:
		return
	move(cell)
	var doc := _doc
	var err := ""
	# A click without a drag changes nothing (even an entry BN reads oddly).
	var dragged := cell != _start
	match mode:
		Mode.MOVE:
			if dragged and preview != _orig:
				err = doc.place_at(member, index, preview, true, _instance)
		Mode.RESIZE:
			if dragged and preview != _orig:
				err = doc.place_at(member, index, preview, false, _instance)
		Mode.CREATE:
			var kind := armed
			err = doc.add_placement(kind, Placement.template(kind, preview))
			if err.is_empty():
				armed = ""
				var list: Array = doc.object()[kind]
				select(kind, list.size() - 1)
	cancel()
	if err:
		failed.emit(err)


## Stops a drag without changing anything.
func cancel() -> void:
	_doc = null
	mode = Mode.NONE
	preview = Rect2i()


## Starts moving (or resizing) [param p] from [param cell]; false if the
## cell isn't on it.
func _grab(p: Placement, cell: Vector2i, shift: bool) -> bool:
	var rects := p.instances()
	for i in rects.size():
		var r := rects[i]
		if r.has_point(cell):
			_instance = i
			_orig = r
			_tile = _geometry().tile_of(r.position)
			var corner := r.end - Vector2i.ONE
			mode = Mode.RESIZE if shift or (cell == corner and r.size != Vector2i.ONE) else Mode.MOVE
			preview = r
			return true
	# A place_nested entry can also be dragged by its chunk.
	var st := _doc.chunk_overlay().stamp_for(p.index) if p.member == "place_nested" else null
	if st and st.footprint.has_point(cell) and not rects.is_empty():
		_instance = 0
		_orig = rects[0]
		_tile = _geometry().tile_of(_orig.position)
		mode = Mode.MOVE
		preview = _orig
		return true
	return false


func _is_set() -> bool:
	return member == "set" and not _geometry().chunk


## A resized "set" entry stays in its tile (clamp_span already keeps others
## in the anchor's tile).
func _cut(r: Rect2i) -> Rect2i:
	return r.intersection(_tile) if _is_set() else r


func _geometry() -> Placement.Geometry:
	return Placement.Geometry.of(_doc.mapgen(), _doc.size())

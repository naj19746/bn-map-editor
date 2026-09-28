class_name AsciiMap
extends RefCounted
## How each cell of a resolved mapgen looks in BN's ASCII view: the
## furniture's symbol and color if there is furniture, else the terrain's.
##
## Terrain with the AUTO_WALL_SYMBOL flag is drawn like map::determine_wall_corner:
## a line joining the orthogonal neighbours whose terrain has the same
## connect group. Cells outside the map count as not connected.
##
## Distributions, params and switches show their first possible id (see
## ResolvedMapgen.Binding.id()). A symbol placing a computer shows t_console,
## as BN puts one there whatever the symbol's terrain.
##
## With an [member overlay], cells a nested chunk writes show what the chunk
## leaves there (ChunkOverlay): its terrain and/or furniture over the map's.

enum State {
	OK,
	## Nothing placed: a nested/update chunk leaves the cell as it was.
	EMPTY,
	## No terrain and nothing to fall back on (no fill_ter).
	NO_TERRAIN,
	## The symbol isn't defined by the map or any of its palettes.
	UNDEFINED,
	## The terrain or furniture id isn't a known type.
	UNKNOWN_ID,
}

const AUTO_WALL := "AUTO_WALL_SYMBOL"
const NO_FLOOR := "NO_FLOOR"

## Connected sides (N=8, E=2, S=1, W=4, as in BN) -> line character.
## A lone neighbour draws a straight line through it, like BN.
const WALL_LINES := {
	15: "┼", 7: "┬", 13: "┤", 5: "┐", 14: "┴", 6: "─", 12: "┘", 4: "─",
	11: "├", 3: "┌", 9: "│", 1: "│", 10: "└", 2: "─", 8: "│",
}

## Line characters after a quarter turn clockwise.
const TURNED_LINES := {
	"│": "─", "─": "│", "┌": "┐", "┐": "┘", "┘": "└", "└": "┌",
	"├": "┬", "┬": "┤", "┤": "┴", "┴": "├",
}

## What a symbol looks like, before wall joining.
class Look:
	var terrain: DataIndex.TileDef
	var furniture: DataIndex.TileDef
	var state := State.OK
	var ch := " "
	var colors: BnColors.Pair
	## True when the terrain shows and joins walls.
	var auto_wall := false
	## Placement.Layer bits for what the symbol's own mappings place
	## (items, monsters, ...), which the canvas marks.
	var layers := 0


var index: DataIndex
var resolved: ResolvedMapgen
var size := Vector2i.ZERO
## 0..3: spring, summer, autumn, winter.
var season := 0
## When false, furniture is hidden and terrain always shows.
var show_furniture := true
## The map's nested chunks, drawn over its cells; null to show the map alone.
## Call refresh() after changing it.
var overlay: ChunkOverlay

## Per cell, row-major (y * size.x + x).
var chars := PackedStringArray()
var fg := PackedColorArray()
var bg := PackedColorArray()
var states := PackedByteArray()
## 1 where the level below shows through: NO_FLOOR terrain (t_open_air)
## with no furniture drawn, or nothing placed.
var see_through := PackedByteArray()

## key -> Look, for the keys in use (and "" for cells with no key).
var looks := {}
## Per cell, the Look drawn there (a key's, or a chunk's over it).
var _cell_looks: Array[Look] = []
## key + terrain + furniture -> Look, for cells a chunk writes.
var _chunk_looks := {}


static func build(p_index: DataIndex, p_resolved: ResolvedMapgen, p_season := 0,
		p_show_furniture := true, p_overlay: ChunkOverlay = null) -> AsciiMap:
	var m := AsciiMap.new()
	m.index = p_index
	m.resolved = p_resolved
	m.season = p_season
	m.show_furniture = p_show_furniture
	m.overlay = p_overlay
	m.refresh()
	return m


## Recomputes every cell, e.g. after changing [member season].
func refresh() -> void:
	size = resolved.size
	looks.clear()
	_chunk_looks.clear()
	if overlay and overlay.size != size:
		overlay = null
	var n := size.x * size.y
	chars.resize(n)
	fg.resize(n)
	bg.resize(n)
	states.resize(n)
	see_through.resize(n)
	_cell_looks.resize(n)
	for y in size.y:
		for x in size.x:
			_set_look(x, y, look_at(x, y))
	_join_walls()


## Recomputes [param points] after their keys changed (and the walls around
## them), without redoing the whole map. The symbols must mean the same.
func update_cells(points: Array[Vector2i]) -> void:
	var rejoin := {}
	for p in points:
		_set_look(p.x, p.y, look_at(p.x, p.y))
		for d: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var q := p + d
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
				rejoin[q] = true
	for q: Vector2i in rejoin:
		chars[q.y * size.x + q.x] = _cell_looks[q.y * size.x + q.x].ch
		_join_wall(q.x, q.y)


## A copy for display only, turned [param turns] quarter turns clockwise, as
## BN turns a map placed with a rotation (point::rotate: east is 1 turn).
## It has the chars, colors and states; [member resolved] stays the
## unturned map's, so don't look cells up by key in it.
func rotated(turns: int) -> AsciiMap:
	turns = posmod(turns, 4)
	var m := AsciiMap.new()
	m.index = index
	m.resolved = resolved
	m.season = season
	m.show_furniture = show_furniture
	m.size = size if turns % 2 == 0 else Vector2i(size.y, size.x)
	var n := size.x * size.y
	m.chars.resize(n)
	m.fg.resize(n)
	m.bg.resize(n)
	m.states.resize(n)
	m.see_through.resize(n)
	for y in size.y:
		for x in size.x:
			var to := Vector2i(x, y)
			match turns:
				1: to = Vector2i(size.y - y - 1, x)
				2: to = Vector2i(size.x - x - 1, size.y - y - 1)
				3: to = Vector2i(y, size.x - x - 1)
			var i := y * size.x + x
			var j := to.y * m.size.x + to.x
			var ch := chars[i]
			for t in turns:
				ch = TURNED_LINES.get(ch, ch)
			m.chars[j] = ch
			m.fg[j] = fg[i]
			m.bg[j] = bg[i]
			m.states[j] = states[i]
			m.see_through[j] = see_through[i]
	return m


func _set_look(x: int, y: int, look: Look) -> void:
	var i := y * size.x + x
	_cell_looks[i] = look
	chars[i] = look.ch
	fg[i] = look.colors.fg
	bg[i] = look.colors.bg
	states[i] = look.state
	see_through[i] = 1 if look.state == State.EMPTY or (look.terrain and look.terrain.has_flag(NO_FLOOR)
			and not (show_furniture and look.furniture)) else 0


func state_at(x: int, y: int) -> State:
	return states[y * size.x + x] as State


func char_at(x: int, y: int) -> String:
	return chars[y * size.x + x]


## Cells whose state is [param state].
func count_state(state: State) -> int:
	return states.count(state)


## One line for the status bar: the position (and overmap tile for a
## multi-tile map), the symbol, and its terrain/furniture with their sources.
func describe_cell(x: int, y: int) -> String:
	var parts := PackedStringArray(["x%d y%d" % [x, y]])
	var omts := resolved.omt_ids
	if not omts.is_empty():
		var omt := Vector2i(x, y) / MapgenResolver.OMT_SIZE
		var local := Vector2i(x, y) - omt * MapgenResolver.OMT_SIZE
		var omt_id := omts[omt.y][omt.x] if omt.y < omts.size() and omt.x < omts[omt.y].size() else "?"
		parts.append("OMT(%d,%d) %s local(%d,%d)" % [omt.x, omt.y, omt_id, local.x, local.y])
	var key := resolved.cells[y][x]
	parts.append("'%s'" % key if key else "(no symbol)")
	var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
	var ter := info.terrain if info and info.terrain else resolved.fill_binding()
	var ids := PackedStringArray()
	if ter:
		ids.append(_describe_binding(ter))
	if info and info.furniture:
		ids.append(_describe_binding(info.furniture))
	if not ids.is_empty():
		parts.append(" + ".join(ids))
	if info and not info.extras.is_empty():
		parts.append("[%s]" % ", ".join(PackedStringArray(info.extras.keys())))
	if info and info.extras.has("computers") and info.extras.computers[-1].value is Dictionary:
		parts.append("computer %s" % Computer.of(info.extras.computers[-1].value).summary())
	var stamp := overlay.stamp_at(Vector2i(x, y)) if overlay else null
	if stamp:
		var i := y * size.x + x
		var drawn := PackedStringArray()
		if overlay.ter[i]:
			drawn.append(overlay.ter[i])
		if overlay.furn[i]:
			drawn.append("no furniture" if overlay.furn[i] == "f_null" else overlay.furn[i])
		parts.append("chunk %s '%s': %s ‹%s›" % [stamp.chunk_id, overlay.chunk_keys[i], " + ".join(drawn), stamp.path])
	match state_at(x, y):
		State.UNDEFINED: parts.append("UNDEFINED SYMBOL")
		State.UNKNOWN_ID: parts.append("UNKNOWN ID")
		State.NO_TERRAIN: parts.append("NO TERRAIN")
		State.EMPTY:
			if ids.is_empty():
				parts.append("nothing placed")
	return "   ".join(parts)


static func _describe_binding(b: ResolvedMapgen.Binding) -> String:
	var id := b.id() if b.id() else "?"
	if b.ids.size() > 1:
		id += " (1 of %d)" % b.ids.size()
	return "%s ‹%s›" % [id, b.source_label()]


## What cell ([param x], [param y]) looks like: its key's Look, or with an
## overlay, what a chunk leaves there.
func look_at(x: int, y: int) -> Look:
	var key := resolved.cells[y][x]
	if overlay == null:
		return look_for(key)
	var i := y * size.x + x
	if overlay.owner[i] < 0:
		return look_for(key)
	var id := "%s\u0001%s\u0001%s" % [key, overlay.ter[i], overlay.furn[i]]
	var look: Look = _chunk_looks.get(id)
	if look == null:
		look = _make_chunk_look(look_for(key), overlay.ter[i], overlay.furn[i])
		_chunk_looks[id] = look
	return look


func look_for(key: String) -> Look:
	var look: Look = looks.get(key)
	if look == null:
		look = _make_look(key)
		looks[key] = look
	return look


func _make_look(key: String) -> Look:
	var look := Look.new()
	var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
	var ter: ResolvedMapgen.Binding = info.terrain if info and info.terrain else resolved.fill_binding()
	var furn: ResolvedMapgen.Binding = info.furniture if info else null
	look.layers = Placement.mapping_layers(info)
	var ter_id := ter.id() if ter else ""
	var furn_id := furn.id() if furn else ""
	if info and info.extras.has("computers"):
		# BN sets t_console and no furniture wherever a computer goes.
		ter_id = Computer.CONSOLE
		furn_id = ""
		ter = null
	look.terrain = index.terrain.get(ter_id)
	if furn_id and furn_id != "f_null":
		look.furniture = index.furniture.get(furn_id)

	if info == null and key != "" and key != " " and key != ".":
		look.state = State.UNDEFINED
	elif (ter and look.terrain == null) or (furn_id and furn_id != "f_null" and look.furniture == null):
		look.state = State.UNKNOWN_ID
	elif ter_id.is_empty():
		look.state = State.EMPTY if resolved.draws_over or not resolved.predecessor_mapgen.is_empty() \
				else State.NO_TERRAIN

	_finish_look(look, key)
	return look


## [param base] (the map's own Look for the cell) with a chunk's terrain
## [param ter] and furniture [param furn] over it ("" keeps the map's,
## "f_null" removes the furniture).
func _make_chunk_look(base: Look, ter: String, furn: String) -> Look:
	var look := Look.new()
	look.layers = base.layers
	look.terrain = index.terrain.get(ter) if ter else base.terrain
	look.furniture = base.furniture
	if furn:
		look.furniture = index.furniture.get(furn) if furn != "f_null" else null
	if (ter and look.terrain == null) or (furn and furn != "f_null" and look.furniture == null):
		look.state = State.UNKNOWN_ID
	elif base.state == State.UNDEFINED or base.state == State.UNKNOWN_ID:
		# The map's own problem is still there.
		look.state = base.state
	elif look.terrain == null:
		look.state = base.state
	_finish_look(look, ter if ter else furn)
	return look


## Sets [param look]'s glyph and colors from its terrain/furniture
## ([param key] is shown when neither is known).
func _finish_look(look: Look, key: String) -> void:
	var shown: DataIndex.TileDef = look.furniture if show_furniture and look.furniture else look.terrain
	if shown == null:
		# Nothing known to draw: show the key itself.
		look.ch = key if key else " "
		look.colors = BnColors.Pair.new(BnColors.GRAY, BnColors.BLACK)
		return
	look.ch = shown.ascii(season)
	var color := shown.color[season] if season < shown.color.size() else ""
	look.colors = BnColors.parse_bg(color) if shown.bgcolor else BnColors.parse(color)
	look.auto_wall = shown == look.terrain and shown.has_flag(AUTO_WALL) \
			and not shown.connect_group.is_empty()


func _join_walls() -> void:
	for y in size.y:
		for x in size.x:
			_join_wall(x, y)


func _join_wall(x: int, y: int) -> void:
	var look := _cell_looks[y * size.x + x]
	if not look.auto_wall:
		return
	var group := look.terrain.connect_group
	var mask := 0
	if _connects(x, y + 1, group):
		mask |= 1
	if _connects(x + 1, y, group):
		mask |= 2
	if _connects(x - 1, y, group):
		mask |= 4
	if _connects(x, y - 1, group):
		mask |= 8
	if mask:
		chars[y * size.x + x] = WALL_LINES[mask]


func _connects(x: int, y: int, group: String) -> bool:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	var t: DataIndex.TileDef = _cell_looks[y * size.x + x].terrain
	return t != null and t.connect_group == group

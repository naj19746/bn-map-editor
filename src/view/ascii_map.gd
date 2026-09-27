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
## ResolvedMapgen.Binding.id()).

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

## Connected sides (N=8, E=2, S=1, W=4, as in BN) -> line character.
## A lone neighbour draws a straight line through it, like BN.
const WALL_LINES := {
	15: "┼", 7: "┬", 13: "┤", 5: "┐", 14: "┴", 6: "─", 12: "┘", 4: "─",
	11: "├", 3: "┌", 9: "│", 1: "│", 10: "└", 2: "─", 8: "│",
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

## Per cell, row-major (y * size.x + x).
var chars := PackedStringArray()
var fg := PackedColorArray()
var bg := PackedColorArray()
var states := PackedByteArray()

## key -> Look, for the keys in use (and "" for cells with no key).
var looks := {}


static func build(p_index: DataIndex, p_resolved: ResolvedMapgen, p_season := 0,
		p_show_furniture := true) -> AsciiMap:
	var m := AsciiMap.new()
	m.index = p_index
	m.resolved = p_resolved
	m.season = p_season
	m.show_furniture = p_show_furniture
	m.refresh()
	return m


## Recomputes every cell, e.g. after changing [member season].
func refresh() -> void:
	size = resolved.size
	looks.clear()
	var n := size.x * size.y
	chars.resize(n)
	fg.resize(n)
	bg.resize(n)
	states.resize(n)
	for y in size.y:
		var row := resolved.cells[y]
		for x in size.x:
			_set_look(x, y, look_for(row[x]))
	_join_walls()


## Recomputes [param points] after their keys changed (and the walls around
## them), without redoing the whole map. The symbols must mean the same.
func update_cells(points: Array[Vector2i]) -> void:
	var rejoin := {}
	for p in points:
		_set_look(p.x, p.y, look_for(resolved.cells[p.y][p.x]))
		for d: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var q := p + d
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
				rejoin[q] = true
	for q: Vector2i in rejoin:
		chars[q.y * size.x + q.x] = looks[resolved.cells[q.y][q.x]].ch
		_join_wall(q.x, q.y)


func _set_look(x: int, y: int, look: Look) -> void:
	var i := y * size.x + x
	chars[i] = look.ch
	fg[i] = look.colors.fg
	bg[i] = look.colors.bg
	states[i] = look.state


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

	var shown: DataIndex.TileDef = look.furniture if show_furniture and look.furniture else look.terrain
	if shown == null:
		# Nothing known to draw: show the key itself.
		look.ch = key if key else " "
		look.colors = BnColors.Pair.new(BnColors.GRAY, BnColors.BLACK)
		return look
	look.ch = shown.ascii(season)
	var color := shown.color[season] if season < shown.color.size() else ""
	look.colors = BnColors.parse_bg(color) if shown.bgcolor else BnColors.parse(color)
	look.auto_wall = shown == look.terrain and shown.has_flag(AUTO_WALL) \
			and not shown.connect_group.is_empty()
	return look


func _join_walls() -> void:
	for y in size.y:
		for x in size.x:
			_join_wall(x, y)


func _join_wall(x: int, y: int) -> void:
	var look: Look = looks[resolved.cells[y][x]]
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
	var t: DataIndex.TileDef = looks[resolved.cells[y][x]].terrain
	return t != null and t.connect_group == group

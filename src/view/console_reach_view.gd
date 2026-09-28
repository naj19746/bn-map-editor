class_name ConsoleReachView
extends RefCounted
## What the canvas shows for a selected computer: for each of its consoles,
## the cells the player can stand on to use it, the area its door actions
## reach from them (cut at each stand cell's overmap tile), the doors they
## change (solid when every stand cell reaches them, faded when only some
## do) and other locked doors in reach that no action opens. Built from
## Validator.console_reach over the rows plus the chunk overlay, so doors a
## "set" or place_terrain entry makes aren't seen (see [member lines]).
##
## Also the "Control with a computer..." helpers: which consoles already
## unlock a door, and where a new console could go to reach it.

## The actions that unlock (or open) a door, and so control it.
const CONTROLS := ["unlock", "unlock_disarm", "unlock_labpass", "open", "open_disarm"]
## The reach of a new door console (Door control: unlock).
const DOOR_RADIUS := 8

## The console cells shown.
var consoles: Array[Vector2i] = []
## cell -> true: where the player can stand to use a console.
var stands := {}
## cell -> true: within reach of a stand cell for some door action.
var area := {}
## The outline of [member area]: pairs of points in cell-corner units
## ((x, y) is cell (x, y)'s top-left corner), for draw_multiline.
var outline := PackedVector2Array()
## Door cell -> true when every stand cell of a console reaching it does,
## false when only some do.
var targets := {}
## cell -> true: other locked doors in reach (see Computer.is_locked_door).
var other_locked := {}
## One line per console for the side panel, then notes.
var lines := PackedStringArray()


## The view of computer [param data] at [param cells] (its consoles) in a
## map of [param size] whose tile_grids() are [param grids].
static func build(p_index: DataIndex, size: Vector2i, grids: Array[PackedStringArray],
		cells: Array[Vector2i], data: Dictionary) -> ConsoleReachView:
	var v := ConsoleReachView.new()
	v.consoles = cells
	var actions := Computer.of(data).door_actions()
	for at in cells:
		var reach := Validator.console_reach(p_index, size, grids, at, data)
		for s in reach.stands:
			v.stands[s] = true
			for action in actions:
				var radius: int = Computer.EFFECTS[action][2]
				if radius <= 0:
					continue
				var box := Computer.reach_rect(s, radius, size)
				for y in range(box.position.y, box.end.y):
					for x in range(box.position.x, box.end.x):
						if Computer.in_reach(s, Vector2i(x, y), radius):
							v.area[Vector2i(x, y)] = true
		for action: String in reach.counts:
			var counts: Dictionary = reach.counts[action]
			for c: Vector2i in counts:
				v.targets[c] = v.targets.get(c, false) or counts[c] == reach.stands.size()
		for c in reach.other_locked:
			v.other_locked[c] = true
		v.lines.append(line(at, reach, actions))
	v.outline = outline_of(v.area)
	if not actions.is_empty() and not cells.is_empty():
		v.lines.append("Doors a \"set\" or place_terrain entry makes aren't shown.")
	return v


## "At (5, 5): unlock reaches 1 door: (5, 11)" for a console at [param at].
static func line(at: Vector2i, reach: Validator.Reach, actions: PackedStringArray) -> String:
	var where := "At (%d, %d): " % [at.x, at.y]
	if reach.stands.is_empty():
		return where + "no cell next to it can be stood on"
	if actions.is_empty():
		return where + "no door actions"
	var parts := PackedStringArray()
	for a in actions:
		if not reach.targets.has(a):
			parts.append("%s works on the whole z-level" % a)
			continue
		var cells: Array = reach.targets[a]
		var shown := cells.slice(0, 4).map(func(c: Vector2i) -> String: return "(%d, %d)" % [c.x, c.y])
		parts.append("%s reaches %d door%s%s" % [a, cells.size(), "" if cells.size() == 1 else "s",
				": " + ", ".join(shown) + (" ..." if cells.size() > 4 else "") if cells.size() else " (nothing)"])
	return where + "; ".join(parts)


## The border of [param cells] (cell -> true) as segment pairs.
static func outline_of(cells: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Vector2i in cells:
		var p := Vector2(c)
		if not cells.has(c + Vector2i.UP):
			out.append_array([p, p + Vector2(1, 0)])
		if not cells.has(c + Vector2i.RIGHT):
			out.append_array([p + Vector2(1, 0), p + Vector2(1, 1)])
		if not cells.has(c + Vector2i.DOWN):
			out.append_array([p + Vector2(0, 1), p + Vector2(1, 1)])
		if not cells.has(c + Vector2i.LEFT):
			out.append_array([p, p + Vector2(0, 1)])
	return out


## The consoles (from Validator.console_cells) with an action in CONTROLS
## that changes [param door]: [console cell, key ("" for a placement)].
static func controllers(p_index: DataIndex, size: Vector2i, grids: Array[PackedStringArray],
		consoles: Dictionary, door: Vector2i) -> Array:
	var out := []
	var cells: Array = consoles.keys()
	cells.sort()
	for at: Vector2i in cells:
		var reach := Validator.console_reach(p_index, size, grids, at, consoles[at][1])
		for action: String in reach.targets:
			if CONTROLS.has(action) and (reach.targets[action] as Array).has(door):
				out.append([at, consoles[at][0]])
				break
	return out


## Where a new door console could go to unlock [param door]: a passable
## cell (not the door, not a console) in the door's overmap tile with a
## passable neighbour within DOOR_RADIUS of the door, in the same tile.
static func console_spots(p_index: DataIndex, size: Vector2i, grids: Array[PackedStringArray],
		door: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var w := size.x
	var ter := grids[0]
	var furn := grids[1]
	var ok := func(c: Vector2i) -> bool:
		return c != door and p_index.passable(ter[c.y * w + c.x], furn[c.y * w + c.x])
	var box := Computer.reach_rect(door, DOOR_RADIUS + 1, size)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := Vector2i(x, y)
			if ter[y * w + x] == Computer.CONSOLE or not ok.call(p):
				continue
			for s in Computer.stand_cells(p, size, ok):
				if Computer.in_reach(s, door, DOOR_RADIUS):
					out.append(p)
					break
	return out

class_name Shapes
extends RefCounted
## Cell sets for the drawing tools.


## The cells on a straight line from [param a] to [param b] (Bresenham).
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var s := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := d.x - d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 > -d.y:
			err -= d.y
			p.x += s.x
		if e2 < d.x:
			err += d.x
			p.y += s.y
	return out


## The cells of the rectangle with corners [param a] and [param b]: its
## outline, or every cell when [param filled].
static func rect(a: Vector2i, b: Vector2i, filled := false) -> Array[Vector2i]:
	var lo := a.min(b)
	var hi := a.max(b)
	var out: Array[Vector2i] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if filled or x == lo.x or x == hi.x or y == lo.y or y == hi.y:
				out.append(Vector2i(x, y))
	return out


## The 4-connected cells from [param start] whose key equals start's.
static func flood(cells: Array[PackedStringArray], start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var h := cells.size()
	if h == 0 or start.y < 0 or start.y >= h or start.x < 0 or start.x >= cells[start.y].size():
		return out
	var key := cells[start.y][start.x]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		out.append(p)
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var q := p + d
			if q.y < 0 or q.y >= h or q.x < 0 or q.x >= cells[q.y].size() or seen.has(q):
				continue
			if cells[q.y][q.x] == key:
				seen[q] = true
				stack.append(q)
	return out

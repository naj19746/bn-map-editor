class_name MapDocument
extends RefCounted
## One mapgen entry opened for editing: paints symbols into its "rows",
## defines new symbols in the map's own "terrain"/"furniture", and keeps an
## undo history. Every change goes straight into the BnJson object in
## [member file], so saving is just writing the file.
##
## Painting only writes symbols that are already defined (the brush is a
## symbol, not an id), and new symbols never go into a palette: a palette is
## shared by other maps (PLAN.MD, "Checked before Stage 3").

## Cells changed (during a stroke, or by undo/redo); the symbols mean the same.
signal cells_changed(cells: Array[Vector2i])
## A change was completed or undone/redone, and [member resolved] is new.
## [param full] is true when symbols may mean something else (a new symbol,
## rows created or removed), so everything must be redrawn; otherwise
## cells_changed already reported every changed cell.
signal changed(full: bool)

## Where a missing object member goes, relative to the others.
const MEMBER_ORDER := ["mapgensize", "fill_ter", "rows", "palettes", "terrain", "furniture"]
## Tried in order when suggesting a key for a new symbol, after the
## symbols of the terrain/furniture themselves.
const KEY_CANDIDATES := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" \
		+ "#%&*+-=:;<>?@^_~!$|/()[]{},'`"


## One undoable edit.
class Change:
	var name := ""
	## Vector2i -> [old key, new key].
	var cells := {}
	## Object member -> [present, value] before and after.
	var before := {}
	var after := {}
	## The map had no "rows"; this change created them.
	var rows_created := false

	func is_empty() -> bool:
		return cells.is_empty() and before.is_empty() and not rows_created


var index: DataIndex
var file: JsonFile
## Position of the mapgen in [member file].
var object_index := 0
var ref: DataIndex.MapgenRef
var resolved: ResolvedMapgen

var _undo: Array[Change] = []
var _redo: Array[Change] = []
var _stroke: Change


## Returns null if objects[[param i]] isn't a mapgen with an "object".
static func open(p_index: DataIndex, p_file: JsonFile, i: int, p_ref: DataIndex.MapgenRef) -> MapDocument:
	if i >= p_file.objects.size() or not p_file.objects[i] is Dictionary \
			or not p_file.objects[i].get("object") is Dictionary:
		return null
	var doc := MapDocument.new()
	doc.index = p_index
	doc.file = p_file
	doc.object_index = i
	doc.ref = p_ref
	doc._resolve()
	return doc


func mapgen() -> Dictionary:
	return file.objects[object_index]


## The mapgen's "object" member.
func object() -> Dictionary:
	return mapgen().object


func size() -> Vector2i:
	return resolved.size


func has_rows() -> bool:
	return object().get("rows") is Array


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Name of the change undo() would revert, or "".
func undo_name() -> String:
	return _undo[-1].name if can_undo() else ""


func redo_name() -> String:
	return _redo[-1].name if can_redo() else ""


# --- Painting ------------------------------------------------------------------

func begin_stroke(name: String) -> void:
	if _stroke != null:
		end_stroke()
	_stroke = Change.new()
	_stroke.name = name


## Sets [param points] to [param key] as part of the current stroke.
func set_cells(points: Array[Vector2i], key: String) -> void:
	if _stroke == null:
		return
	var changed_points: Array[Vector2i] = []
	var rows := {}
	for p in points:
		if p.x < 0 or p.y < 0 or p.x >= resolved.size.x or p.y >= resolved.size.y:
			continue
		if not has_rows():
			_create_rows()
			_stroke.rows_created = true
			changed.emit(true)
		var old := resolved.cells[p.y][p.x]
		if old == key:
			continue
		if _stroke.cells.has(p):
			_stroke.cells[p][1] = key
		else:
			_stroke.cells[p] = [old, key]
		resolved.cells[p.y][p.x] = key
		changed_points.append(p)
		rows[p.y] = true
	if not rows.is_empty():
		_write_rows(rows.keys())
		cells_changed.emit(changed_points)


## Ends the stroke, recording it for undo if it changed anything.
func end_stroke() -> void:
	var c := _stroke
	_stroke = null
	if c == null or c.is_empty():
		return
	_push(c)


## Paints [param points] with [param key] as one undoable change.
func paint(points: Array[Vector2i], key: String, name := "Paint") -> void:
	begin_stroke(name)
	set_cells(points, key)
	end_stroke()


## "rows" filled with spaces: undefined " " leaves fill_ter (or, in a nested
## chunk, what was there), which is what a map without rows does.
func _create_rows() -> void:
	file.touch(object_index)
	var rows := []
	var blank := " ".repeat(resolved.size.x)
	for y in resolved.size.y:
		rows.append(blank)
	_set_member("rows", rows)
	_resolve()


func _write_rows(ys: Array) -> void:
	file.touch(object_index)
	var rows: Array = object().rows
	for y: int in ys:
		var row := resolved.cells[y]
		var text := PackedStringArray()
		for k in row:
			# A padded cell of a too-short row becomes a real column.
			text.append(k if k else " ")
		if y < rows.size():
			rows[y] = "".join(text)


# --- Symbols -------------------------------------------------------------------

## Why [param key] can't be a new symbol for this map, or "".
func check_new_key(key: String) -> String:
	if key.is_empty():
		return "Enter a symbol."
	if CellText.split_row(key).size() != 1 or not CellText.starts_cell(key.unicode_at(0)):
		return "A symbol must be one character wide."
	if _is_wide(key.unicode_at(0)):
		return "Double-width characters can't be used."
	if key == " " or key == ".":
		return "' ' and '.' are left undefined on purpose (keep fill_ter or what's below)."
	var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
	if info != null:
		return "'%s' is already defined by %s." % [key, ", ".join(symbol_sources(key))]
	return ""


## Where [param key]'s definitions come from, e.g. ["map", "palette p"].
func symbol_sources(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
	if info == null:
		return out
	var bindings: Array = [info.terrain, info.furniture]
	for kind: String in info.extras:
		bindings.append_array(info.extras[kind])
	for b: ResolvedMapgen.Binding in bindings:
		if b and not out.has(b.source_label()):
			out.append(b.source_label())
	if out.is_empty():
		out.append("a t_null/f_null entry")
	return out


## A free key for a new symbol: the furniture's or terrain's own symbol if
## free, else the first free one of KEY_CANDIDATES, else any free character.
func suggest_key(terrain_id := "", furniture_id := "") -> String:
	var candidates := PackedStringArray()
	for pair: Array in [[index.furniture, furniture_id], [index.terrain, terrain_id]]:
		var def: DataIndex.TileDef = pair[0].get(pair[1]) if pair[1] else null
		if def and def.ascii().length() == 1:
			candidates.append(def.ascii())
	for i in KEY_CANDIDATES.length():
		candidates.append(KEY_CANDIDATES[i])
	var used := {}
	for k in resolved.used_keys():
		used[k] = true
	for k in candidates:
		if not used.has(k) and check_new_key(k).is_empty():
			return k
	for c in range(0xA1, 0x2FFF):
		var k := char(c)
		if not used.has(k) and check_new_key(k).is_empty():
			return k
	return ""


## Symbols whose terrain (or fill_ter, if it sets none) and furniture are
## exactly these ids (first possible id; "" for none), so the user can reuse
## one instead of adding a new one.
func matching_keys(terrain_id: String, furniture_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in resolved.symbols:
		var info: ResolvedMapgen.SymbolInfo = resolved.symbols[key]
		var ter := info.terrain.id() if info.terrain else resolved.fill_ter
		var furn := info.furniture.id() if info.furniture else ""
		if ter == terrain_id and furn == furniture_id:
			out.append(key)
	out.sort()
	return out


## Why add_symbol([param key], ...) would fail, or "".
func check_new_symbol(key: String, terrain_id: String, furniture_id: String) -> String:
	var problem := check_new_key(key)
	if problem:
		return problem
	if terrain_id.is_empty() and furniture_id.is_empty():
		return "Pick a terrain and/or a furniture."
	if terrain_id and not index.terrain.has(terrain_id):
		return "Unknown terrain \"%s\"." % terrain_id
	if furniture_id and not index.furniture.has(furniture_id):
		return "Unknown furniture \"%s\"." % furniture_id
	if terrain_id.is_empty() and resolved.fill_ter.is_empty() and not resolved.draws_over \
			and resolved.predecessor_mapgen.is_empty():
		return "This map has no fill_ter, so the symbol needs a terrain."
	var obj := object()
	for member in ["terrain", "furniture"]:
		if obj.has(member) and not obj[member] is Dictionary:
			return "The map's \"%s\" isn't an object." % member
	return ""


## Defines [param key] in the map's own "terrain"/"furniture". Returns an
## error, or "" once the symbol is added.
func add_symbol(key: String, terrain_id: String, furniture_id: String) -> String:
	var problem := check_new_symbol(key, terrain_id, furniture_id)
	if problem:
		return problem
	var obj := object()
	var c := Change.new()
	c.name = "New symbol '%s'" % key
	file.touch(object_index)
	for pair: Array in [["terrain", terrain_id], ["furniture", furniture_id]]:
		var member: String = pair[0]
		if pair[1].is_empty():
			continue
		c.before[member] = _snapshot(member)
		var defs: Dictionary = obj.get(member, {})
		defs[key] = pair[1]
		_set_member(member, defs)
		c.after[member] = _snapshot(member)
	_push(c)
	return ""


# --- Undo ----------------------------------------------------------------------

func undo() -> void:
	if not can_undo():
		return
	var c: Change = _undo.pop_back()
	_apply(c, false)
	_redo.append(c)
	changed.emit(_is_full(c))


func redo() -> void:
	if not can_redo():
		return
	var c: Change = _redo.pop_back()
	_apply(c, true)
	_undo.append(c)
	changed.emit(_is_full(c))


func _push(c: Change) -> void:
	_undo.append(c)
	_redo.clear()
	_resolve()
	changed.emit(_is_full(c))


static func _is_full(c: Change) -> bool:
	return c.rows_created or not c.before.is_empty()


func _apply(c: Change, forward: bool) -> void:
	file.touch(object_index)
	if forward and c.rows_created:
		_create_rows()
	var ys := {}
	for p: Vector2i in c.cells:
		resolved.cells[p.y][p.x] = c.cells[p][1 if forward else 0]
		ys[p.y] = true
	if has_rows():
		_write_rows(ys.keys())
	if not forward and c.rows_created:
		object().erase("rows")
	var snaps: Dictionary = c.after if forward else c.before
	for member: String in snaps:
		_restore(member, snaps[member])
	_resolve()
	if not _is_full(c):
		var points: Array[Vector2i] = []
		points.assign(c.cells.keys())
		cells_changed.emit(points)


func _resolve() -> void:
	resolved = MapgenResolver.resolve(index, mapgen())


# --- Object members ------------------------------------------------------------

func _snapshot(member: String) -> Array:
	var obj := object()
	if not obj.has(member):
		return [false, null]
	var v: Variant = obj[member]
	return [true, v.duplicate(true) if v is Dictionary or v is Array else v]


func _restore(member: String, snap: Array) -> void:
	if not snap[0]:
		object().erase(member)
		return
	var v: Variant = snap[1]
	_set_member(member, v.duplicate(true) if v is Dictionary or v is Array else v)


## Sets object()[member], adding a missing member after the ones that come
## before it in MEMBER_ORDER (or first), in place so references stay valid.
func _set_member(member: String, value: Variant) -> void:
	var obj := object()
	if obj.has(member):
		obj[member] = value
		return
	var rank := MEMBER_ORDER.find(member)
	var anchor := ""
	for k: String in obj:
		var r := MEMBER_ORDER.find(k)
		if r >= 0 and r < rank:
			anchor = k
	var items := obj.duplicate()
	obj.clear()
	if anchor.is_empty():
		obj[member] = value
	for k: String in items:
		obj[k] = items[k]
		if k == anchor:
			obj[member] = value


# --- Checks --------------------------------------------------------------------

## The om_terrain ids of this map, flattened.
func om_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var om: Variant = mapgen().get("om_terrain")
	var stack: Array = [om]
	while not stack.is_empty():
		var v: Variant = stack.pop_front()
		if v is String and not out.has(v):
			out.append(v)
		elif v is Array:
			stack.append_array(v)
	return out


## om_terrain ids with no overmap_terrain: BN never generates such a map.
func missing_overmap_terrain() -> PackedStringArray:
	var out := PackedStringArray()
	for id in om_ids():
		if not index.has_overmap_terrain(id):
			out.append(id)
	return out


## The resolver's problems plus the editor's own checks.
func problems() -> PackedStringArray:
	var out := resolved.problems.duplicate()
	for id in missing_overmap_terrain():
		out.append("om_terrain \"%s\" has no overmap_terrain, so BN never generates this map (Edit > Add missing overmap_terrain)" % id)
	return out


## East Asian wide and fullwidth ranges (wcwidth 2).
static func _is_wide(c: int) -> bool:
	return (c >= 0x1100 and c <= 0x115F) or (c >= 0x2E80 and c <= 0xA4CF and c != 0x303F) \
			or (c >= 0xAC00 and c <= 0xD7A3) or (c >= 0xF900 and c <= 0xFAFF) \
			or (c >= 0xFE30 and c <= 0xFE6F) or (c >= 0xFF00 and c <= 0xFF60) \
			or (c >= 0xFFE0 and c <= 0xFFE6) or (c >= 0x20000 and c <= 0x3FFFD)

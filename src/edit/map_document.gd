class_name MapDocument
extends RefCounted
## One mapgen entry opened for editing: paints symbols into its "rows",
## defines new symbols in the map's own "terrain"/"furniture", and keeps an
## undo history. It also adds, moves and edits the coordinate placements
## ("place_items", "set", ...; see Placement). Every change goes straight
## into the BnJson object in [member file], so saving is just writing the file.
##
## Painting only writes symbols that are already defined (the brush is a
## symbol, not an id), and new symbols never go into a palette: a palette is
## shared by other maps (PLAN.MD, "Checked before Stage 3").

## Cells changed (during a stroke, or by undo/redo); the symbols mean the same.
signal cells_changed(cells: Array[Vector2i])
## A change was completed or undone/redone, and [member resolved] is new.
## [param full] is true when symbols may mean something else (a new symbol,
## rows created or removed), so everything must be redrawn; otherwise
## cells_changed already reported every changed cell (none for a placement
## edit, which only changes [method placements]).
signal changed(full: bool)
## Something outside this map that its nested chunks draw from changed (a
## chunk or a palette of one), so chunk_overlay() is new.
signal overlay_changed

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
	## The object's member order before and after, when members changed.
	var order_before := []
	var order_after := []
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
## Where chunk_overlay() reads chunks from; EditSession sets one that sees
## files open for editing.
var objects: MapgenObjects

var _undo: Array[Change] = []
var _redo: Array[Change] = []
var _stroke: Change
var _placements: Array[Placement] = []
## key -> where it's defined, for keys only another option of a palette
## distribution/param defines (BN adds every option, so they're taken too).
var _option_keys := {}
## Built on first use after each change.
var _overlay: ChunkOverlay


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
	var shape := check_key_shape(key)
	if shape:
		return shape
	if key == " " or key == ".":
		return "' ' and '.' are left undefined on purpose (keep fill_ter or what's below)."
	var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
	if info != null:
		return "'%s' is already defined by %s." % [key, ", ".join(symbol_sources(key))]
	if _option_keys.has(key):
		return "'%s' is already defined by %s, another option of a palette choice." % [key, _option_keys[key]]
	return ""


## Why [param key] can't be a symbol at all (in a map or a palette), or "".
static func check_key_shape(key: String) -> String:
	if key.is_empty():
		return "Enter a symbol."
	if CellText.split_row(key).size() != 1 or not CellText.starts_cell(key.unicode_at(0)):
		return "A symbol must be one character wide."
	if _is_wide(key.unicode_at(0)):
		return "Double-width characters can't be used."
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
	c.order_before = obj.keys()
	for pair: Array in [["terrain", terrain_id], ["furniture", furniture_id]]:
		var member: String = pair[0]
		if pair[1].is_empty():
			continue
		c.before[member] = _snapshot(member)
		var defs: Dictionary = obj.get(member, {})
		defs[key] = pair[1]
		_set_member(member, defs)
		c.after[member] = _snapshot(member)
	c.order_after = obj.keys()
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
	if c.rows_created:
		return true
	for member: String in c.before:
		if not Placement.KINDS.has(member):
			return true
	return false


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
	var order := c.order_after if forward else c.order_before
	if not order.is_empty():
		ObjectMembers.reorder(object(), order)
	_resolve()
	if not _is_full(c):
		var points: Array[Vector2i] = []
		points.assign(c.cells.keys())
		cells_changed.emit(points)


func _resolve() -> void:
	resolved = MapgenResolver.resolve(index, mapgen())
	_placements = Placement.read_all(mapgen(), resolved.size)
	_overlay = null
	ref.palettes = DataIndex.palette_options(object())
	ref.chunks = DataIndex.chunk_options(object())
	_option_keys.clear()
	if resolved.choice_options.is_empty():
		return
	for r in MapgenResolver.resolve_variants(index, mapgen()).slice(1):
		for key: String in r.symbols:
			if not resolved.symbols.has(key) and not _option_keys.has(key):
				_option_keys[key] = ", ".join(r.palettes)


## Resolves again after something outside this map changed (a palette), so
## symbols may mean something else.
func refresh() -> void:
	_resolve()
	changed.emit(true)


## True when this map uses palette [param id]: listed, included by a listed
## palette, or any option of a distribution/param.
func uses_palette(id: String) -> bool:
	return index.palette_closure(DataIndex.palette_options(object())).has(id)


# --- Nested chunks -------------------------------------------------------------

## The nested chunks this map places, laid over its cells (see ChunkOverlay).
func chunk_overlay() -> ChunkOverlay:
	if _overlay == null:
		if objects == null:
			objects = MapgenObjects.new(index)
		_overlay = ChunkOverlay.build(index, mapgen(), resolved, objects.object_for)
	return _overlay


## Lays the chunks out again after a chunk or palette they use changed.
func refresh_overlay() -> void:
	_overlay = null
	overlay_changed.emit()


## True when the current overlay draws chunk [param chunk_id], or a chunk
## using palette [param palette_id] (false before it's first built).
func overlay_uses(chunk_id := "", palette_id := "") -> bool:
	if _overlay == null:
		return false
	return (chunk_id and _overlay.drawn_ids.has(chunk_id)) or (palette_id and _overlay.palette_ids.has(palette_id))


## This chunk's nested id, or "" for other maps.
func chunk_id() -> String:
	return ref.ids[0] if ref.kind == DataIndex.MapgenRef.NESTED and not ref.ids.is_empty() else ""


# --- Palettes list -------------------------------------------------------------

## The map's "palettes" entries as written (ids, or distribution objects).
func palette_list() -> Array:
	var v: Variant = object().get("palettes")
	return v if v is Array else []


## Replaces the map's "palettes" (removing the member when empty) as one
## undoable change.
func set_palettes(list: Array, name := "Palettes") -> void:
	if JSON.stringify(list) == JSON.stringify(palette_list()):
		return
	var c := Change.new()
	c.name = name
	file.touch(object_index)
	c.order_before = object().keys()
	c.before["palettes"] = _snapshot("palettes")
	if list.is_empty():
		object().erase("palettes")
	else:
		_set_member("palettes", list.duplicate(true))
	c.after["palettes"] = _snapshot("palettes")
	c.order_after = object().keys()
	_push(c)


## Adds palette [param id] after the others (it wins over them).
func add_palette(id: String) -> void:
	var list := palette_list().duplicate()
	list.append(id)
	set_palettes(list, "Use palette " + id)


func remove_palette(id: String) -> void:
	var list := palette_list().duplicate()
	list.erase(id)
	set_palettes(list, "Stop using palette " + id)


# --- Own symbols ---------------------------------------------------------------

## Keys the map defines itself in its plain "terrain"/"furniture" members.
func own_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for member in ["terrain", "furniture"]:
		var defs: Variant = object().get(member)
		if defs is Dictionary:
			for key: String in defs:
				if not out.has(key):
					out.append(key)
	out.sort()
	return out


## The map's own "terrain" (or "furniture") value for [param key], or null.
func own_value(key: String, member: String) -> Variant:
	var defs: Variant = object().get(member)
	return defs.get(key) if defs is Dictionary else null


## Removes [param key] from the map's own "terrain"/"furniture" (a member
## left empty goes too) as one undoable change.
func remove_own_symbol(key: String, name := "") -> void:
	commit(build_remove_own_symbol(key, name))


## Like remove_own_symbol, but only returns the change (null if there's
## nothing to remove); commit() it, or apply_change() it for a preview.
func build_remove_own_symbol(key: String, name := "") -> Change:
	var c := Change.new()
	c.name = name if name else "Remove '%s' from the map" % key
	file.touch(object_index)
	c.order_before = object().keys()
	for member in ["terrain", "furniture"]:
		var defs: Variant = object().get(member)
		if not (defs is Dictionary and defs.has(key)):
			continue
		c.before[member] = _snapshot(member)
		defs.erase(key)
		if defs.is_empty():
			object().erase(member)
		c.after[member] = _snapshot(member)
	c.order_after = object().keys()
	if c.is_empty():
		return null
	_apply(c, false)
	return c


## Applies [param c] (from a build_* function) and records it for undo.
func commit(c: Change) -> void:
	if c == null:
		return
	_apply(c, true)
	_push(c)


## Puts [param c]'s after (or before) state in place without recording it,
## e.g. to measure an edit before making it.
func apply_change(c: Change, forward: bool) -> void:
	_apply(c, forward)


# --- Placements ----------------------------------------------------------------

## Every placement entry, in member then list order. Rebuilt after each
## change, so look entries up again (by member and index) after an edit.
func placements() -> Array[Placement]:
	return _placements


## The placement at [param member] #[param i], or null.
func placement(member: String, i: int) -> Placement:
	for p in _placements:
		if p.member == member and p.index == i:
			return p
	return null


## Placements whose drawn area holds [param cell], smallest first.
func placements_at(cell: Vector2i) -> Array[Placement]:
	var out: Array[Placement] = []
	for p in _placements:
		for r in p.instances():
			if r.has_point(cell):
				out.append(p)
				break
	out.sort_custom(func(a: Placement, b: Placement) -> bool:
		return a.span().get_area() < b.span().get_area())
	return out


## Why [param entry] can't be list [param member]'s entry #[param i] (the
## end of the list for a new one), or "": BN would drop it or refuse to load.
func check_placement(member: String, i: int, entry: Dictionary) -> String:
	if not Placement.KINDS.has(member):
		return "\"%s\" isn't a placement list." % member
	var p := Placement.read(member, i, entry, Placement.Geometry.of(mapgen(), resolved.size))
	return p.blocking_problem()


## Adds [param entry] to the end of list [param member] (created if
## missing). Returns an error, or "".
func add_placement(member: String, entry: Dictionary, name := "") -> String:
	var list: Variant = object().get(member)
	var problem := check_placement(member, list.size() if list is Array else 0, entry)
	if problem:
		return problem
	if object().has(member) and not list is Array:
		return "The map's \"%s\" isn't a list." % member
	_edit_placements(member, name if name else "Add %s" % member, func(l: Array) -> void:
		l.append(entry.duplicate(true)))
	return ""


func remove_placement(member: String, i: int) -> void:
	var p := placement(member, i)
	if p == null:
		return
	_edit_placements(member, "Delete " + p.title(), func(l: Array) -> void: l.remove_at(i))


## Sets [param fields] (key -> value; null removes the key) of entry
## #[param i] of [param member] as one undoable change, keeping the other
## fields and their order. Returns an error, or "" (also when nothing changed).
func set_placement_fields(member: String, i: int, fields: Dictionary, name := "") -> String:
	var p := placement(member, i)
	if p == null:
		return "%s #%d doesn't exist." % [member, i + 1]
	var e := p.entry.duplicate(true)
	var order := Placement.field_order(member)
	for key: String in fields:
		if fields[key] == null:
			e.erase(key)
		elif e.has(key) or order.has(key):
			ObjectMembers.set_member(e, key, fields[key], order)
		else:
			e[key] = fields[key]
	if BnJson.stringify(e) == BnJson.stringify(p.entry):
		return ""
	# An entry BN already drops can still be edited, as long as it isn't
	# moved somewhere else BN drops it.
	var problem := check_placement(member, i, e)
	if problem and problem != p.blocking_problem():
		return problem
	_edit_placements(member, name if name else "Edit " + p.title(), func(l: Array) -> void: l[i] = e)
	return ""


## Moves or resizes entry #[param i] of [param member] to [param rect] (map
## cells; for a "set" entry, of drawn instance [param instance]).
## [param moved_only] keeps its size and how its ranges are written.
func place_at(member: String, i: int, rect: Rect2i, moved_only: bool, instance := 0) -> String:
	var p := placement(member, i)
	if p == null:
		return "%s #%d doesn't exist." % [member, i + 1]
	return set_placement_fields(member, i, p.values_for(rect, moved_only, instance),
			("Move " if moved_only else "Resize ") + p.title())


## Placement edits that would make BN refuse the map, which saving refuses.
func save_problems() -> PackedStringArray:
	var out := PackedStringArray()
	for p in _placements:
		if p.status == Placement.Status.CROSSES:
			out.append(p.problems[0])
	return out


func _edit_placements(member: String, name: String, edit: Callable) -> void:
	var obj := object()
	var c := Change.new()
	c.name = name
	file.touch(object_index)
	c.order_before = obj.keys()
	c.before[member] = _snapshot(member)
	if not obj.get(member) is Array:
		# A new list goes last, after the map's other members.
		obj[member] = []
	edit.call(obj[member])
	if obj[member].is_empty():
		obj.erase(member)
	c.after[member] = _snapshot(member)
	c.order_after = obj.keys()
	_push(c)


# --- Object members ------------------------------------------------------------

func _snapshot(member: String) -> Array:
	return ObjectMembers.snapshot(object(), member)


func _restore(member: String, snap: Array) -> void:
	ObjectMembers.restore(object(), member, snap, MEMBER_ORDER)


func _set_member(member: String, value: Variant) -> void:
	ObjectMembers.set_member(object(), member, value, MEMBER_ORDER)


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
	for p in _placements:
		out.append_array(p.problems)
	out.append_array(chunk_overlay().problems())
	for id in missing_overmap_terrain():
		out.append("om_terrain \"%s\" has no overmap_terrain, so BN never generates this map (Edit > Add missing overmap_terrain)" % id)
	return out


## East Asian wide and fullwidth ranges (wcwidth 2).
static func _is_wide(c: int) -> bool:
	return (c >= 0x1100 and c <= 0x115F) or (c >= 0x2E80 and c <= 0xA4CF and c != 0x303F) \
			or (c >= 0xAC00 and c <= 0xD7A3) or (c >= 0xF900 and c <= 0xFAFF) \
			or (c >= 0xFE30 and c <= 0xFE6F) or (c >= 0xFF00 and c <= 0xFF60) \
			or (c >= 0xFFE0 and c <= 0xFFE6) or (c >= 0x20000 and c <= 0x3FFFD)

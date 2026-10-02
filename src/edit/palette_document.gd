class_name PaletteDocument
extends RefCounted
## One palette definition opened for editing: the terrain/furniture and
## computers of its keys and its included palettes, with an undo history of
## its own. Every
## change goes straight into the BnJson object in [member file], which is
## also the DataIndex definition's data while the palette is open, so maps
## resolved afterwards see the edit.
##
## Other per-key kinds (items, toilets, nested, ...) are shown but not edited
## here; they stay as written.
##
## A computer edit changes every map using the key: the palette editor
## measures that with PaletteImpact before committing, as for tiles.

## The palette changed (an edit, undo or redo).
signal changed

## Where a missing member goes, relative to the others.
const MEMBER_ORDER := ["type", "id", "parameters", "palettes", "mapping", "terrain", "furniture", "computers",
		"toilets", "vendingmachines", "items", "item", "monsters", "monster", "vehicles", "nested"]
## The members an edit can touch: the includes, "mapping" and every
## MapgenResolver.MAPPING_KINDS kind (a key rename touches them all); each
## change snapshots all of them.
const EDITED := ["palettes", "mapping", "terrain", "furniture", "fields", "npcs", "signs", "vendingmachines",
		"toilets", "gaspumps", "items", "monsters", "vehicles", "item", "artifact", "artifacts", "traps",
		"monster", "rubble", "computers", "sealed_item", "nested", "liquids", "graffiti", "translate", "zones",
		"ter_furn_transforms", "faction_owner_character", "remove_all"]
const TILE_KINDS := ["terrain", "furniture"]


## One undoable edit: the edited members before and after.
class Change:
	var name := ""
	## member -> ObjectMembers snapshot.
	var before := {}
	var after := {}
	## The palette's member order before and after.
	var order_before := []
	var order_after := []
	## Run after the change is undone / redone (and before changed is
	## emitted): e.g. a key rename's repainted maps follow it.
	var on_undo := Callable()
	var on_redo := Callable()


var index: DataIndex
var file: JsonFile
## Position of the palette in [member file].
var object_index := 0
var def: DataIndex.Definition
var id := ""

var _undo: Array[Change] = []
var _redo: Array[Change] = []


## Returns null if objects[[param i]] isn't the palette [param p_def] names.
static func open(p_index: DataIndex, p_file: JsonFile, i: int, p_def: DataIndex.Definition) -> PaletteDocument:
	if i >= p_file.objects.size() or not p_file.objects[i] is Dictionary:
		return null
	var o: Dictionary = p_file.objects[i]
	if o.get("type") != "palette" or str(o.get("id", "")) != p_def.id:
		return null
	var doc := PaletteDocument.new()
	doc.index = p_index
	doc.file = p_file
	doc.object_index = i
	doc.def = p_def
	doc.id = p_def.id
	return doc


func palette() -> Dictionary:
	return file.objects[object_index]


## The definition BN uses for this id, when it isn't this one (a later
## definition, e.g. from a mod, replaces it), else null.
func overridden_by() -> DataIndex.Definition:
	var in_effect := index.palette(id)
	return in_effect if in_effect != def else null


## What each key means, read as if the palette were a map: the palette's own
## definitions have source SOURCE_MAP, included ones their palette's id.
func view() -> ResolvedMapgen:
	return MapgenResolver.resolve(index, {"nested_mapgen_id": id, "object": palette()})


## Keys this palette defines itself, in any kind (sorted).
func own_keys() -> PackedStringArray:
	var out := PackedStringArray()
	var p := palette()
	for kind: String in MapgenResolver.MAPPING_KINDS:
		var defs: Variant = p.get(kind)
		if defs is Dictionary:
			for key: String in defs:
				if not out.has(key):
					out.append(key)
	var mapping: Variant = p.get("mapping")
	if mapping is Dictionary:
		for key: String in mapping:
			if not out.has(key):
				out.append(key)
	out.sort()
	return out


## The palette's own [param kind] ("terrain"/"furniture") value for
## [param key] as written, or null. A plain member entry wins over "mapping",
## as in BN (it's read later).
func tile_value(key: String, kind: String) -> Variant:
	var p := palette()
	var defs: Variant = p.get(kind)
	if defs is Dictionary and defs.has(key):
		return defs[key]
	var mapping: Variant = p.get("mapping")
	if mapping is Dictionary and mapping.get(key) is Dictionary and mapping[key].has(kind):
		return mapping[key][kind]
	return null


## The palette's own computer for [param key] ("computers", else
## "mapping"), the live object; null if it defines none, or a list of
## several (edit those as JSON).
func computer(key: String) -> Variant:
	var member := _computer_member(key)
	var v: Variant = null
	if member == "computers":
		v = palette().computers[key]
	elif member == "mapping":
		v = palette().mapping[key].computers
	return v if v is Dictionary else null


## True when the palette itself mentions a computer for [param key] (of any
## shape).
func has_computer(key: String) -> bool:
	return not _computer_member(key).is_empty()


func _computer_member(key: String) -> String:
	var p := palette()
	if p.get("computers") is Dictionary and p.computers.has(key):
		return "computers"
	var mapping: Variant = p.get("mapping")
	if mapping is Dictionary and mapping.get(key) is Dictionary and mapping[key].has("computers"):
		return "mapping"
	return ""


## Why build_set_computer([param key], ...) can't work, or "".
func check_computer(key: String) -> String:
	var shape := MapDocument.check_key_shape(key)
	if shape:
		return shape
	if has_computer(key) and computer(key) == null:
		return "'%s' places several computers; edit them as JSON." % key
	var p := palette()
	for member: String in ["computers", "terrain", "mapping"]:
		if p.has(member) and not p[member] is Dictionary:
			return "The palette's \"%s\" isn't an object." % member
	return ""


## A change giving [param key] computer [param data] (replaced where it's
## written, else added to "computers"). A new computer on a key the palette
## gives no terrain gets t_console too, so maps using it are valid without
## fill_ter (BN puts a console there anyway). Null when nothing changes or
## check_computer fails.
func build_set_computer(key: String, data: Dictionary, name := "") -> Change:
	if check_computer(key):
		return null
	var label := name if name else ("Edit computer '%s'" % key if has_computer(key) else "New computer '%s'" % key)
	var copy := data.duplicate(true)
	var is_new := not has_computer(key)
	return _build(label, func(p: Dictionary) -> void:
		if _computer_member(key) == "mapping":
			p.mapping[key].computers = copy
		else:
			var defs: Dictionary = p.get("computers", {})
			defs[key] = copy
			ObjectMembers.set_member(p, "computers", defs, MEMBER_ORDER)
		if is_new and tile_value(key, "terrain") == null:
			_set_tile(p, key, "terrain", Computer.CONSOLE))


## The palette's own [param kind] mapping ("nested", "monster", ...) for
## [param key] as written (one piece object or a list of them), or null.
func piece(key: String, kind: String) -> Variant:
	return ObjectMembers.key_value(palette(), key, kind)


## Why build_set_piece([param key], [param kind], ...) can't work, or "".
func check_piece(key: String, kind: String, value: Variant) -> String:
	var shape := MapDocument.check_key_shape(key)
	if shape:
		return shape
	if not (value == null or value is Dictionary or (value is Array and value.all(
			func(e: Variant) -> bool: return e is Dictionary))):
		return "A \"%s\" mapping is an object or a list of objects." % kind
	var p := palette()
	for member: String in [kind, "mapping"]:
		if p.has(member) and not p[member] is Dictionary:
			return "The palette's \"%s\" isn't an object." % member
	return ""


## A change setting the palette's own [param kind] mapping for [param key]
## to [param value] (null removes it). Null when nothing changes or
## check_piece fails.
func build_set_piece(key: String, kind: String, value: Variant, name := "") -> Change:
	if check_piece(key, kind, value):
		return null
	var label := name if name else ("Remove %s of '%s'" % [kind, key] if value == null else "Edit %s of '%s'" % [kind, key])
	return _build(label, func(p: Dictionary) -> void:
		ObjectMembers.set_key_value(p, key, kind, value, MEMBER_ORDER))


## The included palettes as written (ids, or distribution/param objects).
func includes() -> Array:
	var v: Variant = palette().get("palettes")
	return v if v is Array else []


# --- Edits -----------------------------------------------------------------------

## Why [param key] can't be set to these ids, or "". Each of
## [param terrain] and [param furniture] is null (keep), "" (remove), an id,
## or any other mapgen value (a distribution, ...), which is taken as is.
func check_tiles(key: String, terrain: Variant, furniture: Variant) -> String:
	var shape := MapDocument.check_key_shape(key)
	if shape:
		return shape
	for pair: Array in [[terrain, index.terrain, "terrain"], [furniture, index.furniture, "furniture"]]:
		if pair[0] is String and pair[0] != "" and not pair[1].has(pair[0]):
			return "Unknown %s \"%s\"." % [pair[2], pair[0]]
	var p := palette()
	for member: String in TILE_KINDS + ["mapping"]:
		if p.has(member) and not p[member] is Dictionary:
			return "The palette's \"%s\" isn't an object." % member
	return ""


## A change setting [param key]'s terrain and furniture: null keeps one, ""
## removes it, anything else sets it (see check_tiles). An entry is replaced where it's written (the
## plain member, else "mapping"); a new one goes in the plain member.
## Returns null when it would change nothing or check_tiles fails.
func build_set_tiles(key: String, terrain: Variant, furniture: Variant, name := "") -> Change:
	if check_tiles(key, terrain, furniture):
		return null
	var label := name if name else "Set '%s'" % key
	return _build(label, func(p: Dictionary) -> void:
		for pair: Array in [["terrain", terrain], ["furniture", furniture]]:
			if pair[1] != null:
				_set_tile(p, key, pair[0], pair[1]))


## Why [param old] can't be renamed [param new_key], or "": the palette
## must define [param old] itself, and [param new_key] must be free in it
## and its includes (the maps using it are checked by
## PaletteImpact.plan_rename).
func check_rename(old: String, new_key: String) -> String:
	if not own_keys().has(old):
		return "Palette %s doesn't define '%s' itself." % [id, old]
	if old == new_key:
		return "The new key is the same as the old one."
	var shape := MapDocument.check_key_shape(new_key)
	if shape:
		return shape
	if new_key == " " or new_key == ".":
		return "' ' and '.' are left undefined on purpose; pick another key."
	var v := view()
	if v.symbols.has(new_key):
		var info: ResolvedMapgen.SymbolInfo = v.symbols[new_key]
		var from := PackedStringArray()
		for b: ResolvedMapgen.Binding in MapDocument._bindings(info):
			var label := "the palette itself" if b.source == ResolvedMapgen.SOURCE_MAP else b.source_label()
			if not from.has(label):
				from.append(label)
		return "'%s' is already defined by %s." % [new_key, ", ".join(from)]
	for r in MapgenResolver.resolve_variants(index, {"nested_mapgen_id": id, "object": palette()}).slice(1):
		if r.symbols.has(new_key):
			return "'%s' is already defined by %s, an option of an included palette choice." % [
				new_key, ", ".join(r.palettes)]
	return ""


## A change renaming the palette's own key [param old] to [param new_key]
## in every kind and "mapping", each keeping its place. Null when
## check_rename fails.
func build_rename_key(old: String, new_key: String) -> Change:
	if check_rename(old, new_key):
		return null
	return _build("Rename '%s' to '%s'" % [old, new_key], func(p: Dictionary) -> void:
		for member: String in MapgenResolver.MAPPING_KINDS + ["mapping"]:
			var defs: Variant = p.get(member)
			if defs is Dictionary and defs.has(old):
				MapDocument.rename_key_in(defs, old, new_key))


## A change removing [param key]'s terrain and furniture from this palette.
func build_remove_key(key: String) -> Change:
	return build_set_tiles(key, "", "", "Remove '%s'" % key)


## A change replacing the included palettes (the member goes when empty).
func build_set_includes(list: Array, name := "Includes") -> Change:
	var copy := list.duplicate(true)
	return _build(name, func(p: Dictionary) -> void:
		if copy.is_empty():
			p.erase("palettes")
		else:
			ObjectMembers.set_member(p, "palettes", copy, MEMBER_ORDER))


## One change named [param name] made of [param steps]: callables returning
## a Change (or null), each built on the state the ones before it leave.
## Null when nothing changes.
func build_steps(name: String, steps: Array[Callable]) -> Change:
	var done: Array[Change] = []
	for step in steps:
		var c: Change = step.call()
		if c:
			apply(c, true)
			done.append(c)
	for i in range(done.size() - 1, -1, -1):
		apply(done[i], false)
	if done.is_empty():
		return null
	var out := Change.new()
	out.name = name
	out.before = done[0].before
	out.order_before = done[0].order_before
	out.after = done[-1].after
	out.order_after = done[-1].order_after
	if JSON.stringify(out.before) == JSON.stringify(out.after) and out.order_before == out.order_after:
		return null
	return out


## Applies [param c] and records it for undo.
func commit(c: Change) -> void:
	if c == null:
		return
	apply(c, true)
	_undo.append(c)
	_redo.clear()
	changed.emit()


## Puts [param c]'s after (or before) state in place, without touching the
## history or emitting changed (previews use this).
func apply(c: Change, forward: bool) -> void:
	file.touch(object_index)
	var snaps: Dictionary = c.after if forward else c.before
	for member: String in snaps:
		ObjectMembers.restore(palette(), member, snaps[member], MEMBER_ORDER)
	ObjectMembers.reorder(palette(), c.order_after if forward else c.order_before)


func _set_tile(p: Dictionary, key: String, kind: String, value: Variant) -> void:
	var defs: Variant = p.get(kind)
	var mapping: Variant = p.get("mapping")
	var in_mapping: bool = mapping is Dictionary and mapping.get(key) is Dictionary and mapping[key].has(kind)
	if value is String and value.is_empty():
		if defs is Dictionary:
			defs.erase(key)
			if defs.is_empty():
				p.erase(kind)
		if in_mapping:
			mapping[key].erase(kind)
			if mapping[key].is_empty():
				mapping.erase(key)
			if mapping.is_empty():
				p.erase("mapping")
		return
	var copy: Variant = value.duplicate(true) if value is Dictionary or value is Array else value
	if in_mapping and not (defs is Dictionary and defs.has(key)):
		mapping[key][kind] = copy
		return
	if not defs is Dictionary:
		defs = {}
		ObjectMembers.set_member(p, kind, defs, MEMBER_ORDER)
	defs[key] = copy


## Runs [param edit] on the palette to record the after state, then puts the
## before state back. null if nothing changed.
func _build(name: String, edit: Callable) -> Change:
	file.touch(object_index)
	var p := palette()
	var c := Change.new()
	c.name = name
	c.order_before = p.keys()
	for member: String in EDITED:
		c.before[member] = ObjectMembers.snapshot(p, member)
	edit.call(p)
	c.order_after = p.keys()
	for member: String in EDITED:
		c.after[member] = ObjectMembers.snapshot(p, member)
	apply(c, false)
	if JSON.stringify(c.before) == JSON.stringify(c.after) and c.order_before == c.order_after:
		return null
	return c


# --- Undo ----------------------------------------------------------------------

func can_undo() -> bool:
	return not _undo.is_empty()


## The number of steps undo() can take back.
func undo_count() -> int:
	return _undo.size()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_name() -> String:
	return _undo[-1].name if can_undo() else ""


func redo_name() -> String:
	return _redo[-1].name if can_redo() else ""


func undo() -> void:
	if not can_undo():
		return
	var c: Change = _undo.pop_back()
	apply(c, false)
	_redo.append(c)
	if c.on_undo.is_valid():
		c.on_undo.call()
	changed.emit()


func redo() -> void:
	if not can_redo():
		return
	var c: Change = _redo.pop_back()
	apply(c, true)
	_undo.append(c)
	if c.on_redo.is_valid():
		c.on_redo.call()
	changed.emit()

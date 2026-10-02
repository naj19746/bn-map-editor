class_name PaletteImpact
extends RefCounted
## Which maps a palette edit changes: every map using the palette (see
## DataIndex.maps_using) is resolved before and after the edit, and a map
## counts as changed when a symbol its rows use places something else. A
## changed nested chunk also changes every map placing it (directly, through
## a palette's "nested" mapping its rows use, or through another chunk);
## those are named "via" the chunk.
##
## Every palette option of a distribution/param is resolved (BN adds all of
## them), so an edit to the second option counts too. Symbols a map defines
## but never uses don't count. Open maps are read from their live objects
## (unsaved edits included), other maps from their files.


## A map the edit changes, and the symbols in its rows that change (or the
## chunk it places that changes).
class Affected:
	var ref: DataIndex.MapgenRef
	var keys := PackedStringArray()
	## For a map changed through a chunk it places: "chunk_a", or
	## "chunk_b > chunk_a" when chunk_b places chunk_a.
	var via := ""

	## What changes: the symbols, or "via chunk ...".
	func what() -> String:
		return "via chunk " + via if via else " ".join(keys)

	func _to_string() -> String:
		return "%s (%s#%d): %s" % [ref.title(), ref.source.path, ref.source.index, what()]


## What renaming a palette key does (see plan_rename).
class RenamePlan:
	var old := ""
	var new_key := ""
	## The palette's change; null when [member problem] is set.
	var change: PaletteDocument.Change
	## Why the rename can't be made, or "".
	var problem := ""
	## Maps whose rows use the old key and took it from the palette: their
	## cells get the new key (keys: [old]).
	var repainted: Array[Affected] = []
	## Maps that look different afterwards: ones defining the old key
	## themselves that took part of it from the palette (map keys win, so
	## they keep the old key), repainted maps whose new key doesn't mean the
	## same (another palette defines part of the old key), and the maps
	## placing a chunk that changes ("via").
	var changed: Array[Affected] = []


var session: EditSession


func _init(p_session: EditSession) -> void:
	session = p_session


## The maps that [param apply] changes, for an edit to palette
## [param palette_id]. [param apply] makes the edit and [param revert]
## undoes it; both run twice and the edit is left undone.
static func measure(p_session: EditSession, palette_id: String, apply: Callable,
		revert: Callable) -> Array[Affected]:
	var impact := PaletteImpact.new(p_session)
	var index := p_session.index
	var refs := index.maps_using(palette_id)
	# An edit to the includes can add users.
	apply.call()
	for r in index.maps_using(palette_id):
		if not refs.has(r):
			refs.append(r)
	revert.call()
	var before := impact.capture(refs)
	apply.call()
	var after := impact.capture(refs)
	revert.call()
	var out := diff(refs, before, after)
	impact.add_parents(out)
	return out


## What renaming [param doc]'s own key [param old] to [param new_key] does to
## the maps using the palette (open ones as edited). Refused
## (RenamePlan.problem) when the palette or its includes define
## [param new_key] (PaletteDocument.check_rename), or a using map would see
## [param new_key] change meaning: its rows use it, or they use [param old]
## and the map defines [param new_key] (itself or through another palette).
static func plan_rename(p_session: EditSession, doc: PaletteDocument, old: String, new_key: String) -> RenamePlan:
	var plan := RenamePlan.new()
	plan.old = old
	plan.new_key = new_key
	plan.problem = doc.check_rename(old, new_key)
	if plan.problem:
		return plan
	var c := doc.build_rename_key(old, new_key)
	var impact := PaletteImpact.new(p_session)
	var index := p_session.index
	var refs := index.maps_using(doc.id)
	refs.sort_custom(func(a: DataIndex.MapgenRef, b: DataIndex.MapgenRef) -> bool: return a.title() < b.title())
	var conflicts := PackedStringArray()
	# [ref, object, old's signature before] of the maps whose rows use old.
	var using: Array = []
	for ref in refs:
		var o := impact.mapgen_object(ref)
		if not o.get("object") is Dictionary:
			continue
		var variants := MapgenResolver.resolve_variants(index, o)
		var used := variants[0].used_keys()
		var uses_old := used.has(old)
		if used.has(new_key) or (uses_old and variants.any(
				func(r: ResolvedMapgen) -> bool: return r.symbols.has(new_key))):
			conflicts.append(ref.title())
		elif uses_old:
			using.append([ref, o, _signature(variants, old)])
	if not conflicts.is_empty():
		plan.problem = "'%s' already means something in %d map(s) using %s: %s. Pick another key." % [
			new_key, conflicts.size(), doc.id, ", ".join(conflicts.slice(0, 12)) + (" ..." if conflicts.size() > 12 else "")]
		return plan
	doc.apply(c, true)
	for u: Array in using:
		var ref: DataIndex.MapgenRef = u[0]
		var o: Dictionary = u[1]
		var variants := MapgenResolver.resolve_variants(index, o)
		if _signature(variants, old) == u[2]:
			continue
		var a := Affected.new()
		a.ref = ref
		if _defines(o.object, old):
			a.keys = PackedStringArray([old])
			plan.changed.append(a)
			continue
		a.keys = PackedStringArray([old])
		plan.repainted.append(a)
		if _signature(variants, new_key) != u[2]:
			var b := Affected.new()
			b.ref = ref
			b.keys = PackedStringArray([new_key])
			plan.changed.append(b)
	doc.apply(c, false)
	impact.add_parents(plan.changed)
	plan.change = c
	return plan


static func _signature(variants: Array[ResolvedMapgen], key: String) -> String:
	var parts := PackedStringArray()
	for r in variants:
		parts.append(r.key_signature(key))
	return "|".join(parts)


## True when map object [param obj] defines [param key] itself (any kind).
static func _defines(obj: Dictionary, key: String) -> bool:
	for member: String in MapgenResolver.MAPPING_KINDS + ["mapping"]:
		if obj.get(member) is Dictionary and obj[member].has(key):
			return true
	return false


## Appends the maps placing a chunk in [param affected] (and the maps placing
## those, and so on), each once, named via the chunk.
func add_parents(affected: Array[Affected]) -> void:
	var index := session.index
	var seen := {}
	var queue: Array = []
	for a in affected:
		seen[a.ref] = true
		if a.ref.kind == DataIndex.MapgenRef.NESTED:
			queue.append([a.ref.ids[0], a.ref.ids[0]])
	var done := {}
	while not queue.is_empty():
		var next: Array = queue.pop_front()
		var id: String = next[0]
		if done.has(id):
			continue
		done[id] = true
		for ref in index.maps_placing(id):
			if seen.has(ref):
				continue
			var o := mapgen_object(ref)
			if not o.get("object") is Dictionary \
					or not ChunkOverlay.placed_ids(o, MapgenResolver.resolve(index, o)).has(id):
				continue
			seen[ref] = true
			var a := Affected.new()
			a.ref = ref
			a.via = next[1]
			affected.append(a)
			if ref.kind == DataIndex.MapgenRef.NESTED:
				queue.append([ref.ids[0], "%s > %s" % [ref.ids[0], next[1]]])


## For each of [param refs]: key -> what it places (every palette option),
## for the keys its rows use.
func capture(refs: Array[DataIndex.MapgenRef]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ref in refs:
		var o := mapgen_object(ref)
		var sigs := {}
		if o.get("object") is Dictionary:
			var variants := MapgenResolver.resolve_variants(session.index, o)
			for key in variants[0].used_keys():
				var parts := PackedStringArray()
				for r in variants:
					parts.append(r.key_signature(key))
				sigs[key] = "|".join(parts)
		out.append(sigs)
	return out


static func diff(refs: Array[DataIndex.MapgenRef], before: Array[Dictionary],
		after: Array[Dictionary]) -> Array[Affected]:
	var out: Array[Affected] = []
	for i in refs.size():
		var keys := PackedStringArray()
		for key: String in before[i]:
			if after[i].get(key) != before[i][key]:
				keys.append(key)
		for key: String in after[i]:
			if not before[i].has(key) and not keys.has(key):
				keys.append(key)
		if not keys.is_empty():
			keys.sort()
			var a := Affected.new()
			a.ref = refs[i]
			a.keys = keys
			out.append(a)
	return out


## Where the maps using palette [param palette_id] put down the palette's
## computer for [param key]: [[[ref, size, tile grids, console cells], ...]
## for the first [param limit] maps (by title), how many maps in all]. Only
## maps whose rows use the key and take its computer from this palette
## count (not maps defining their own). For the reach each console gets
## (Validator.console_reach) whatever the computer's options become.
static func palette_consoles(p_session: EditSession, palette_id: String, key: String,
		limit := 12) -> Array:
	var index := p_session.index
	var refs := index.maps_using(palette_id)
	refs.sort_custom(func(a: DataIndex.MapgenRef, b: DataIndex.MapgenRef) -> bool: return a.title() < b.title())
	var out := []
	var total := 0
	for ref in refs:
		var o := p_session.objects.object_for(ref)
		var obj: Variant = o.get("object")
		if not obj is Dictionary or not obj.get("rows") is Array \
				or not (obj.rows as Array).any(func(row: Variant) -> bool: return str(row).contains(key)):
			continue
		var r := MapgenResolver.resolve(index, o)
		var info: ResolvedMapgen.SymbolInfo = r.symbols.get(key)
		if info == null or not info.extras.has("computers") or info.extras.computers[-1].source != palette_id:
			continue
		var consoles := Validator.console_cells(r, Placement.read_all(o, r.size))
		var cells: Array[Vector2i] = []
		for at: Vector2i in consoles:
			if consoles[at][0] == key:
				cells.append(at)
		if cells.is_empty():
			continue
		total += 1
		if out.size() >= limit:
			continue
		cells.sort()
		var overlay := ChunkOverlay.build(index, o, r, p_session.objects.object_for)
		out.append([ref, r.size, Validator.tile_grids(r, overlay, consoles), cells])
	return [out, total]


## The mapgen object behind [param ref]: an open map's live object, else
## the object in an open file, else read from disk (each file parsed once).
func mapgen_object(ref: DataIndex.MapgenRef) -> Dictionary:
	return session.objects.object_for(ref)

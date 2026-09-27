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


## The mapgen object behind [param ref]: an open map's live object, else
## the object in an open file, else read from disk (each file parsed once).
func mapgen_object(ref: DataIndex.MapgenRef) -> Dictionary:
	return session.objects.object_for(ref)

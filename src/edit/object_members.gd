class_name ObjectMembers
extends RefCounted
## Snapshots and in-place updates of a JSON object's members, for undo.
## Shared by MapDocument (a mapgen's "object") and PaletteDocument.


## [present, deep copy of the value] for [param member] of [param obj].
static func snapshot(obj: Dictionary, member: String) -> Array:
	if not obj.has(member):
		return [false, null]
	return [true, _copy(obj[member])]


## Puts back what snapshot() recorded.
static func restore(obj: Dictionary, member: String, snap: Array, order: Array) -> void:
	if not snap[0]:
		obj.erase(member)
		return
	set_member(obj, member, _copy(snap[1]), order)


## Sets obj[member], adding a missing member after the ones that come before
## it in [param order] (or first), in place so references stay valid.
static func set_member(obj: Dictionary, member: String, value: Variant, order: Array) -> void:
	if obj.has(member):
		obj[member] = value
		return
	var rank := order.find(member)
	var anchor := ""
	for k: String in obj:
		var r := order.find(k)
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


## Reorders [param obj]'s members in place to follow [param keys] (members
## not listed keep their order, after the listed ones).
static func reorder(obj: Dictionary, keys: Array) -> void:
	if obj.keys() == keys:
		return
	var items := obj.duplicate()
	obj.clear()
	for k: Variant in keys:
		if items.has(k):
			obj[k] = items[k]
	for k: Variant in items:
		if not obj.has(k):
			obj[k] = items[k]


## Where [param obj] (a mapgen object or a palette) defines [param kind]
## for [param key]: [param kind] itself (the plain member), "mapping" (as
## mapping[key][kind]), or "" when it doesn't.
static func key_member(obj: Dictionary, key: String, kind: String) -> String:
	if obj.get(kind) is Dictionary and obj[kind].has(key):
		return kind
	var mapping: Variant = obj.get("mapping")
	if mapping is Dictionary and mapping.get(key) is Dictionary and mapping[key].has(kind):
		return "mapping"
	return ""


## What [param obj] defines as [param kind] for [param key] (the live
## value), or null.
static func key_value(obj: Dictionary, key: String, kind: String) -> Variant:
	match key_member(obj, key, kind):
		"mapping": return obj.mapping[key][kind]
		"": return null
	return obj[kind][key]


## Sets [param obj]'s [param kind] for [param key] to a copy of
## [param value] where it's defined (else in the plain member, added by
## [param order]); null removes it, and a member or mapping entry left
## empty goes too. Returns an error, or "".
static func set_key_value(obj: Dictionary, key: String, kind: String, value: Variant, order: Array) -> String:
	var where := key_member(obj, key, kind)
	if where.is_empty() and obj.has(kind) and not obj[kind] is Dictionary:
		return "\"%s\" isn't an object." % kind
	var copy: Variant = _copy(value)
	if where == "mapping":
		var entry: Dictionary = obj.mapping[key]
		if value == null:
			entry.erase(kind)
			if entry.is_empty():
				obj.mapping.erase(key)
			if obj.mapping.is_empty():
				obj.erase("mapping")
		else:
			entry[kind] = copy
		return ""
	if value == null:
		if where:
			obj[kind].erase(key)
			if obj[kind].is_empty():
				obj.erase(kind)
		return ""
	if not obj.has(kind):
		set_member(obj, kind, {}, order)
	obj[kind][key] = copy
	return ""


static func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if v is Dictionary or v is Array else v

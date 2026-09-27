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


static func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if v is Dictionary or v is Array else v

class_name SymbolPieces
extends VBoxContainer
## A symbol's "nested", "monster", "items", ... mappings
## (Placement.MAPPING_KINDS): the owner's own pieces (the map's, or the palette's in the palette editor)
## are edited with a PieceEditor each, the pieces the symbol gets from
## palettes are listed with where they come from and "Open". BN places
## every piece of a symbol, own and inherited (they're appended, not
## replaced), so adding one here places it as well.
##
## The owner reads and writes through [member get_own] / [member set_own]
## and calls [method show_key] again after a change; while the layout stays
## the same (the same pieces and sources), fields update in place.

## Something to tell the user (an edit was refused).
signal message(text: String)
## "Open" next to an inherited piece: edit [param key] in palette [param id].
signal open_palette_requested(id: String, key: String)

const HINT_COLOR := Color(0.7, 0.72, 0.78)

var index: DataIndex
## (key: String, kind: String) -> the owner's own value, or null.
var get_own: Callable
## (key: String, kind: String, value: Variant) -> error or "" (null
## removes).
var set_own: Callable
## False shows own pieces read-only (a map from a mod, ...).
var editable := true
## The symbol shown ("" for none).
var key := ""
## kind -> Array of PieceEditor, one per own piece.
var editors := {}
## kind -> its "Add ..." Button.
var add_buttons := {}
## kind -> its "Remove" Button (only when there's an own value).
var remove_buttons := {}

var _box: VBoxContainer
var _add_row: HFlowContainer
var _layout := ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	add_child(_box)
	# Eight kinds: they wrap in a narrow drawer.
	_add_row = HFlowContainer.new()
	add_child(_add_row)
	for kind: String in Placement.MAPPING_KINDS:
		var b := Button.new()
		b.text = "Add " + kind
		b.pressed.connect(func() -> void: add_piece(kind))
		_add_row.add_child(b)
		add_buttons[kind] = b


## The pieces of [param v] (a mapping value): one object, a list, or none.
static func pieces_of(v: Variant) -> Array:
	if v is Dictionary:
		return [v]
	if v is Array:
		return v.filter(func(e: Variant) -> bool: return e is Dictionary)
	return []


## Shows symbol [param p_key] ("" for none), whose resolved definitions are
## [param info] (null if the symbol has none).
func show_key(p_key: String, info: ResolvedMapgen.SymbolInfo) -> void:
	key = p_key
	var own := {}
	var inherited := {}
	for kind: String in Placement.MAPPING_KINDS:
		own[kind] = get_own.call(key, kind) if key and get_own.is_valid() else null
		inherited[kind] = []
		if info and info.extras.has(kind):
			for b: ResolvedMapgen.Binding in info.extras[kind]:
				if b.from_palette():
					inherited[kind].append(b)
	# Shown for a symbol with pieces, or one the owner can give pieces to.
	visible = not key.is_empty() and (editable or own.values().any(func(v: Variant) -> bool: return v != null)
			or inherited.values().any(func(l: Array) -> bool: return not l.is_empty()))
	var layout := _layout_of(own, inherited)
	if layout != _layout:
		_build(own, inherited)
		_layout = layout
	else:
		for kind: String in editors:
			var list := pieces_of(own[kind])
			for i in editors[kind].size():
				editors[kind][i].show_piece(Placement.MAPPING_KINDS[kind], list[i], "%s#%d" % [kind, i],
						Placement.mapping_skip(kind))
	for kind: String in add_buttons:
		var b: Button = add_buttons[kind]
		b.disabled = not editable or key.is_empty()
		b.text = ("Add another " if own[kind] != null else "Add ") + kind
		b.tooltip_text = "Give '%s' its own %s piece%s. BN places it as well as any from palettes." % [
				key, kind, " (the mapping becomes a list)" if own[kind] != null else ""]


## Adds an empty piece of [param kind] to the symbol's own mapping: the
## mapping itself, or a list once there's one already. Returns an error or "".
func add_piece(kind: String) -> String:
	if key.is_empty() or not editable:
		return "Select a symbol first."
	var cur: Variant = get_own.call(key, kind)
	var piece := Placement.mapping_template(kind)
	var value: Variant = piece
	if cur is Dictionary:
		value = [cur, piece]
	elif cur is Array:
		value = cur.duplicate(true)
		value.append(piece)
	return _write(kind, value)


## Removes the symbol's own [param kind] mapping (every piece).
func remove_kind(kind: String) -> String:
	return _write(kind, null)


## Removes own piece [param i] of a [param kind] list (the mapping goes
## with the last one).
func remove_piece(kind: String, i: int) -> String:
	var cur: Variant = get_own.call(key, kind)
	if not cur is Array:
		return remove_kind(kind)
	var list: Array = cur.duplicate(true)
	list.remove_at(i)
	return _write(kind, list if not list.is_empty() else null)


## Writes [param fields] into own piece [param i] of [param kind] (null
## removes a field), keeping the mapping's form.
func set_fields(kind: String, i: int, fields: Dictionary) -> String:
	var cur: Variant = get_own.call(key, kind)
	var list := pieces_of(cur).duplicate(true)
	if i < 0 or i >= list.size():
		return "That piece is gone."
	var e: Dictionary = list[i]
	var order := Placement.field_order(Placement.MAPPING_KINDS[kind])
	for f: String in fields:
		if fields[f] == null:
			e.erase(f)
		elif e.has(f) or order.has(f):
			ObjectMembers.set_member(e, f, fields[f], order)
		else:
			e[f] = fields[f]
	return _write(kind, list if cur is Array else e)


func _write(kind: String, value: Variant) -> String:
	var err: String = set_own.call(key, kind, value) if set_own.is_valid() else "This can't be edited here."
	if err:
		message.emit(err)
	return err


func _layout_of(own: Dictionary, inherited: Dictionary) -> String:
	var parts := PackedStringArray([key, str(editable)])
	for kind: String in Placement.MAPPING_KINDS:
		var shape := "-"
		if own[kind] is Dictionary:
			shape = "object"
		elif own[kind] != null:
			shape = "list%d" % pieces_of(own[kind]).size()
		var from := PackedStringArray()
		for b: ResolvedMapgen.Binding in inherited[kind]:
			from.append(b.source_label() + " " + BnJson.stringify(b.value))
		parts.append("%s:%s:%s" % [kind, shape, ",".join(from)])
	return "|".join(parts)


func _build(own: Dictionary, inherited: Dictionary) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	editors.clear()
	remove_buttons.clear()
	for kind: String in Placement.MAPPING_KINDS:
		var list := pieces_of(own[kind])
		if list.is_empty() and own[kind] == null and inherited[kind].is_empty():
			continue
		_box.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		_box.add_child(head)
		var title := Label.new()
		title.text = "'%s' %s" % [LegendPanel._show_key(key), kind]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		if own[kind] != null:
			var rm := Button.new()
			rm.text = "Remove"
			rm.tooltip_text = "Remove this symbol's own %s mapping (pieces from palettes stay)" % kind
			rm.disabled = not editable
			rm.pressed.connect(func() -> void: remove_kind(kind))
			head.add_child(rm)
			remove_buttons[kind] = rm
		for b: ResolvedMapgen.Binding in inherited[kind]:
			_add_inherited(b)
		editors[kind] = []
		for i in list.size():
			if own[kind] is Array:
				var row := HBoxContainer.new()
				_box.add_child(row)
				var l := _hint("piece %d of %d" % [i + 1, list.size()])
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				var del := Button.new()
				del.text = "✕"
				del.tooltip_text = "Remove this piece"
				del.disabled = not editable
				del.pressed.connect(func() -> void: remove_piece(kind, i))
				row.add_child(del)
			var ed := PieceEditor.new(func(fields: Dictionary) -> String:
				return set_fields(kind, i, fields) if editable else "This map can't be edited.")
			ed.index = index
			ed.message.connect(func(text: String) -> void: message.emit(text))
			ed.show_piece(Placement.MAPPING_KINDS[kind], list[i], "%s#%d" % [kind, i], Placement.mapping_skip(kind))
			_box.add_child(ed)
			editors[kind].append(ed)
		if own[kind] != null and list.is_empty():
			_box.add_child(_hint("Own value isn't an object or a list of objects: %s" % LegendPanel._short_value(own[kind])))


func _add_inherited(b: ResolvedMapgen.Binding) -> void:
	var row := HBoxContainer.new()
	_box.add_child(row)
	var l := _hint("%s: %s" % [b.source_label(), LegendPanel._short_value(b.value)])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var open := Button.new()
	open.text = "Open"
	open.tooltip_text = "Edit it in palette %s" % b.source
	var id := b.source
	var k := key
	open.pressed.connect(func() -> void: open_palette_requested.emit(id, k))
	row.add_child(open)


static func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", HINT_COLOR)
	return l

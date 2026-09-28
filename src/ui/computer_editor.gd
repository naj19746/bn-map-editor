class_name ComputerEditor
extends VBoxContainer
## Edits one computer (see Computer): a preset, its name, access-denied
## text, security, mission target, options (name, action picked from a
## grouped list, own security) and failures (checkboxes). Each option says
## what its action does. Edits change [member data] in place, keeping every
## field that isn't edited as it is written.
##
## [signal changed] fires on every edit, keystrokes included (a dialog
## reads [member data] when confirmed); [signal committed] fires once an
## edit is finished (a text field on Enter or leaving it), for hosts that
## apply each edit as an undo step.

signal changed
signal committed

const PROBLEM_COLOR := Color(1, 0.45, 0.45)
const HINT_COLOR := Color(0.7, 0.7, 0.75)
const MAX_SECURITY := 20

var data := {}

var preset_picker: OptionButton
var name_edit: LineEdit
var denied_edit: LineEdit
var security: SpinBox
var target: CheckBox
## One per option: {name: LineEdit, action: OptionButton, security: SpinBox}.
var option_rows: Array[Dictionary] = []
## failure action -> CheckBox
var failure_boxes := {}

var _options_box: VBoxContainer
var _problems: Label
var _building := false
var _shown := false


func _init() -> void:
	name = "ComputerEditor"
	var top := HBoxContainer.new()
	add_child(top)
	top.add_child(_label("Preset:"))
	preset_picker = OptionButton.new()
	preset_picker.add_item("Apply a preset...")
	preset_picker.set_item_metadata(0, "")
	for id: String in Computer.PRESETS:
		preset_picker.add_item(Computer.PRESETS[id][0])
		preset_picker.set_item_metadata(preset_picker.item_count - 1, id)
		preset_picker.set_item_tooltip(preset_picker.item_count - 1, Computer.PRESETS[id][1])
	preset_picker.tooltip_text = "Replaces the security, options and failures (the name stays)"
	preset_picker.item_selected.connect(func(i: int) -> void:
		var id: String = preset_picker.get_item_metadata(i)
		preset_picker.select(0)
		if id:
			apply_preset(id))
	top.add_child(preset_picker)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	grid.add_child(_label("Name"))
	name_edit = _line_edit("The console's title, e.g. \"PolCom OS v1.47 - Supply Room Access\"")
	name_edit.text_changed.connect(func(t: String) -> void: _edit(func() -> void: _c().set_name(t), false))
	grid.add_child(name_edit)
	grid.add_child(_label("Access denied"))
	denied_edit = _line_edit("Shown when logging in fails; empty: BN's default message")
	denied_edit.text_changed.connect(func(t: String) -> void: _edit(func() -> void: _c().set_access_denied(t), false))
	grid.add_child(denied_edit)
	grid.add_child(_label("Security"))
	var sec_row := HBoxContainer.new()
	security = SpinBox.new()
	security.max_value = MAX_SECURITY
	security.tooltip_text = Computer.SECURITY_HINT
	security.value_changed.connect(func(v: float) -> void: _edit(func() -> void: _c().set_security(int(v))))
	sec_row.add_child(security)
	target = CheckBox.new()
	target.text = "Mission target"
	target.tooltip_text = Computer.TARGET_HINT
	target.toggled.connect(func(on: bool) -> void: _edit(func() -> void: _c().set_target(on)))
	sec_row.add_child(target)
	grid.add_child(sec_row)
	var hint := _label(Computer.SECURITY_HINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", HINT_COLOR)
	hint.custom_minimum_size = Vector2(300, 0)
	add_child(hint)

	add_child(HSeparator.new())
	var opt_head := HBoxContainer.new()
	add_child(opt_head)
	var opt_label := _label("Options (the menu the player sees)")
	opt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_head.add_child(opt_label)
	var add := Button.new()
	add.text = "Add option"
	add.tooltip_text = "Adds an \"Unlock doors\" option; pick another action in its list"
	add.pressed.connect(func() -> void: _edit(func() -> void: _c().add_option("Unlock doors", "unlock"), true, true))
	opt_head.add_child(add)
	_options_box = VBoxContainer.new()
	add_child(_options_box)

	add_child(HSeparator.new())
	var fail_label := _label("Failures (one fires at random when a hack fails; none: the console locks for 45 minutes)")
	fail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(fail_label)
	var fails := GridContainer.new()
	fails.columns = 2
	add_child(fails)
	for f: String in Computer.FAILURES:
		var box := CheckBox.new()
		box.text = Computer.FAILURES[f][0]
		box.tooltip_text = "%s: %s" % [f, Computer.FAILURES[f][1]]
		box.toggled.connect(func(on: bool) -> void: _edit(func() -> void: _c().set_failure(f, on)))
		fails.add_child(box)
		failure_boxes[f] = box

	_problems = _label("")
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.add_theme_color_override("font_color", PROBLEM_COLOR)
	add_child(_problems)


## Edits [param p_data] (changed in place; pass a copy to edit on the side).
## The same value again (e.g. after a host applied an edit) keeps the
## controls as they are, so the one in use keeps working.
func edit(p_data: Dictionary) -> void:
	var same := _shown and BnJson.stringify(p_data) == BnJson.stringify(data)
	data = p_data
	_shown = true
	if same:
		_update_problems()
	else:
		_rebuild()


func apply_preset(id: String) -> void:
	_edit(func() -> void: _c().apply_preset(id), true, true)


## Why BN would reject or ignore what's being edited, one per line; "" if
## nothing.
func problems() -> String:
	var lines := PackedStringArray()
	for issue: Array in _c().issues():
		lines.append(issue[1])
	return "\n".join(lines)


func _c() -> Computer:
	return Computer.of(data)


## Runs [param change] on [member data], then tells the host.
## [param done]: the edit is finished (else it's a keystroke).
## [param rebuild]: the option rows changed shape.
func _edit(change: Callable, done := true, rebuild := false) -> void:
	if _building:
		return
	change.call()
	if rebuild:
		_rebuild()
	else:
		_update_problems()
	changed.emit()
	if done:
		committed.emit()


func _rebuild() -> void:
	_building = true
	var c := _c()
	name_edit.text = c.name()
	denied_edit.text = c.access_denied()
	security.value = c.security()
	target.button_pressed = c.target()
	var fails := c.failures()
	for f: String in failure_boxes:
		failure_boxes[f].button_pressed = fails.has(f)
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	option_rows.clear()
	var opts := c.options()
	for i in opts.size():
		_add_option_row(i, opts[i], opts.size())
	if opts.is_empty():
		var none := _label("No options: the console does nothing. Add one, or apply a preset.")
		none.add_theme_color_override("font_color", HINT_COLOR)
		_options_box.add_child(none)
	_update_problems()
	_building = false


func _add_option_row(i: int, o: Dictionary, count: int) -> void:
	var box := VBoxContainer.new()
	_options_box.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_e := _line_edit("What the menu line says")
	name_e.text = Computer._text(o.get("name"))
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_e)
	var action := action_picker(str(o.get("action", "")))
	row.add_child(action)
	var sec := SpinBox.new()
	sec.max_value = MAX_SECURITY
	sec.prefix = "sec"
	sec.value = int(o.get("security", 0)) if Placement.IntRange._is_int(o.get("security", 0)) else 0
	sec.tooltip_text = "The option's own security. " + Computer.OPTION_SECURITY_HINT
	row.add_child(sec)
	var up := _small_button(row, "↑", "Move up", i > 0)
	var down := _small_button(row, "↓", "Move down", i < count - 1)
	var del := _small_button(row, "✕", "Remove this option", true)
	var what := _label(Computer.action_text(str(o.get("action", ""))))
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_color_override("font_color", HINT_COLOR)
	box.add_child(what)

	var set_option := func(done: bool) -> void:
		var act: String = action.get_item_metadata(action.selected)
		what.text = Computer.action_text(act)
		_edit(func() -> void: _c().set_option(i, name_e.text, act, int(sec.value)), done)
	name_e.text_changed.connect(func(_t: String) -> void: set_option.call(false))
	action.item_selected.connect(func(_j: int) -> void: set_option.call(true))
	sec.value_changed.connect(func(_v: float) -> void: set_option.call(true))
	up.pressed.connect(func() -> void: _edit(func() -> void: _c().move_option(i, i - 1), true, true))
	down.pressed.connect(func() -> void: _edit(func() -> void: _c().move_option(i, i + 1), true, true))
	del.pressed.connect(func() -> void: _edit(func() -> void: _c().remove_option(i), true, true))
	option_rows.append({"name": name_e, "action": action, "security": sec})


## An OptionButton of every action, grouped (Doors, Info, Special), with
## [param current] selected (listed first if unknown).
static func action_picker(current: String) -> OptionButton:
	var b := OptionButton.new()
	b.fit_to_longest_item = false
	b.custom_minimum_size = Vector2(190, 0)
	if not Computer.ACTIONS.has(current):
		b.add_item("unknown: %s" % current if current else "(no action)")
		b.set_item_metadata(0, current)
	for g in Computer.GROUP_NAMES.size():
		b.add_separator(Computer.GROUP_NAMES[g])
		for a in Computer.actions_in(g):
			b.add_item(Computer.action_label(a))
			var i := b.item_count - 1
			b.set_item_metadata(i, a)
			b.set_item_tooltip(i, "%s: %s" % [a, Computer.action_text(a)])
	for i in b.item_count:
		if b.get_item_metadata(i) == current and not b.is_item_separator(i):
			b.select(i)
	b.tooltip_text = "What the option does"
	return b


func _update_problems() -> void:
	_problems.text = problems()


func _line_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.tooltip_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_submitted.connect(func(_t: String) -> void: committed.emit())
	e.focus_exited.connect(func() -> void: committed.emit())
	return e


static func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


static func _small_button(parent: Control, text: String, tip: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.disabled = not enabled
	parent.add_child(b)
	return b

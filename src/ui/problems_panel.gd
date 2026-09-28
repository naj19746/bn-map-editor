class_name ProblemsPanel
extends VBoxContainer
## The Problems tab: what BN would say about the current map and the
## palettes it uses (see Validator), errors first, each saying how BN
## reacts. Selecting one shows what it points at: a symbol, a cell, a
## placement, or a palette key in the palette editor.

## A finding was picked in the list.
signal finding_selected(f: Validator.Finding)

## By Validator.Severity.
const COLORS := [Color(1.0, 0.45, 0.45), Color(1.0, 0.8, 0.35), Color(0.65, 0.75, 0.9)]
const NAMES := ["Errors", "Warnings", "Notes"]

var findings: Array[Validator.Finding] = []
var list: Tree
## Show errors / warnings / notes, by Validator.Severity.
var toggles: Array[Button] = []

var _summary: Label
var _footer: Label
var _choices := PackedStringArray()


func _init() -> void:
	name = "Problems"
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	var bar := HBoxContainer.new()
	add_child(bar)
	for s in NAMES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = true
		b.add_theme_color_override("font_pressed_color", COLORS[s])
		b.toggled.connect(func(_on: bool) -> void: _rebuild())
		bar.add_child(b)
		toggles.append(b)
	list = Tree.new()
	list.hide_root = true
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_selected)
	add_child(list)
	_footer = Label.new()
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.modulate = Color(1, 1, 1, 0.6)
	add_child(_footer)
	show_findings([])


## Shows [param p_findings] (sorted, errors first). [param choices] are the
## palette choices the map is drawn with.
func show_findings(p_findings: Array[Validator.Finding], choices := PackedStringArray()) -> void:
	findings = p_findings
	_choices = choices
	var n := Validator.count(findings)
	for s in NAMES.size():
		toggles[s].text = "%s %d" % [NAMES[s], n[s]]
	if n[0] + n[1] + n[2] == 0:
		_summary.text = "Nothing to report: BN would load this map and its palettes without a word."
	else:
		_summary.text = "What BN would say about this map and its palettes. Select one to show it."
	var foot := PackedStringArray([Validator.NOT_CHECKED])
	if not _choices.is_empty():
		foot.append("Drawn with these choices: " + "; ".join(_choices))
	_footer.text = "\n".join(foot)
	_rebuild()


## Picks finding [param i] as if clicked.
func activate(i: int) -> void:
	if i >= 0 and i < findings.size():
		finding_selected.emit(findings[i])


func _rebuild() -> void:
	list.clear()
	var root := list.create_item()
	for i in findings.size():
		var f := findings[i]
		if not toggles[f.severity].button_pressed:
			continue
		var it := list.create_item(root)
		it.set_text(0, f.describe())
		it.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		it.set_custom_color(0, COLORS[f.severity])
		it.set_tooltip_text(0, f.describe())
		it.set_metadata(0, i)


func _on_selected() -> void:
	var it := list.get_selected()
	if it:
		activate(it.get_metadata(0))

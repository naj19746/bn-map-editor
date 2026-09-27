extends Control
## Application root: a read-only ASCII viewer for BN mapgen (Stage 2).
##
## Layout: menu bar and toolbar on top; map tabs with the canvas on the left;
## a side drawer (Browser, Legend) on the right; a status bar at the bottom.
##
## Command line (after "--"): --bn <path> overrides the BN checkout, and
## --open <id> opens a mapgen by om_terrain / nested id once loaded.

## The data finished (re)loading.
signal index_loaded

enum Menu {
	OPEN_BN, MODS, RELOAD, CLOSE_TAB, QUIT,
	SHOW_FURNITURE, SHOW_KEYS, FIT, TOGGLE_DRAWER, FIND,
	SPRING, SUMMER, AUTUMN, WINTER,
}

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]


## One open map tab.
class OpenMap:
	var ref: DataIndex.MapgenRef
	var ascii: AsciiMap
	var canvas: MapCanvas


## False to skip loading on _ready (tests call load_index themselves).
var auto_start := true
var settings: AppSettings
var index: DataIndex
var maps: Array[OpenMap] = []
var show_furniture := true
var show_keys := false
var season := 0

var _file_menu: PopupMenu
var _view_menu: PopupMenu
var _season_menu: PopupMenu
var _furniture_button: Button
var _keys_button: Button
var _tabs: TabBar
var _canvas_area: Control
var _empty_label: Label
var _split: HSplitContainer
var _drawer: TabContainer
var _browser: MapBrowser
var _legend: LegendPanel
var _status: Label
var _problems_button: Button
var _errors_button: Button
var _report: AcceptDialog
var _report_text: TextEdit
var _mods_dialog: ModsDialog
var _bn_dialog: FileDialog
var _bn_override := ""
var _open_on_load := ""


func _ready() -> void:
	settings = AppSettings.load_from()
	_parse_args()
	_build_ui()
	if auto_start:
		_start()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--bn" and i + 1 < args.size():
			_bn_override = args[i + 1]
		elif args[i] == "--open" and i + 1 < args.size():
			_open_on_load = args[i + 1]


func _start() -> void:
	var path := bn_path()
	if path.is_empty():
		_status.text = "Choose your Cataclysm-BN folder (File > Open BN folder)."
		_bn_dialog.popup_centered_ratio(0.6)
		return
	await _load_later(path)
	if _open_on_load:
		open_id(_open_on_load)


## The BN checkout to use: --bn, $BN_PATH, the saved path, or a
## Cataclysm-BN folder next to the project. "" if none holds data/json.
func bn_path() -> String:
	var candidates := [_bn_override, settings.effective_bn_path()]
	if not OS.has_feature("template"):
		candidates.append(ProjectSettings.globalize_path("res://").path_join("../Cataclysm-BN").simplify_path())
	for p: String in candidates:
		if p and is_bn_checkout(p):
			return p
	return ""


static func is_bn_checkout(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path.path_join("data/json"))


## Shows a loading message, lets it draw, then loads.
func _load_later(path: String) -> void:
	_status.text = "Loading %s ..." % path
	await get_tree().process_frame
	await get_tree().process_frame
	load_index(path)


## Loads BN at [param path] with the saved mods, closing any open maps.
func load_index(path: String) -> void:
	_close_all()
	var t := Time.get_ticks_msec()
	index = DataIndex.load_bn(path, settings.mods)
	_browser.set_index(index)
	_status.text = "Loaded %d files from %s (%s) in %d ms. Pick a map in the Browser." % [
		index.file_count, path, ", ".join(index.mods), Time.get_ticks_msec() - t]
	_errors_button.visible = not index.errors.is_empty()
	_errors_button.text = "%d load errors" % index.errors.size()
	_drawer.current_tab = _browser.get_index()
	index_loaded.emit()


## Opens the first mapgen for an om_terrain / nested / update id.
func open_id(id: String) -> OpenMap:
	if index == null:
		return null
	var refs := index.mapgens_for(id)
	if refs.is_empty():
		_status.text = "No mapgen for \"%s\"" % id
		return null
	return open_ref(refs[0])


func open_ref(ref: DataIndex.MapgenRef) -> OpenMap:
	for i in maps.size():
		if maps[i].ref == ref:
			_tabs.current_tab = i
			return maps[i]
	if ref.method != "json":
		_status.text = "%s is a %s mapgen; only json mapgen can be shown." % [ref.title(), ref.method]
		return null
	var obj := index.read_object(ref.source)
	if obj.is_empty():
		_status.text = "Couldn't read %s" % ref.source
		return null
	var m := OpenMap.new()
	m.ref = ref
	m.ascii = AsciiMap.build(index, MapgenResolver.resolve(index, obj), season, show_furniture)
	m.canvas = MapCanvas.new()
	m.canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.canvas.ascii = m.ascii
	m.canvas.show_keys = show_keys
	m.canvas.cell_hovered.connect(_on_cell_hovered.bind(m))
	m.canvas.cell_clicked.connect(_on_cell_clicked.bind(m))
	_canvas_area.add_child(m.canvas)
	maps.append(m)
	var title := ref.title()
	if not ref.grid.is_empty():
		title += " (%dx%d)" % [ref.size_omt().x, ref.size_omt().y]
	_tabs.add_tab(title)
	_tabs.set_tab_tooltip(maps.size() - 1, "%s\n%s #%d" % [", ".join(ref.ids), ref.source.path, ref.source.index])
	_tabs.current_tab = maps.size() - 1
	_on_tab_changed(_tabs.current_tab)
	m.canvas.fit.call_deferred()
	return m


func current_map() -> OpenMap:
	var i := _tabs.current_tab
	return maps[i] if i >= 0 and i < maps.size() else null


func close_tab(i: int) -> void:
	if i < 0 or i >= maps.size():
		return
	maps[i].canvas.queue_free()
	maps.remove_at(i)
	_tabs.remove_tab(i)
	_on_tab_changed(_tabs.current_tab)


func _close_all() -> void:
	while not maps.is_empty():
		close_tab(maps.size() - 1)


func set_show_furniture(on: bool) -> void:
	show_furniture = on
	_furniture_button.set_pressed_no_signal(on)
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_FURNITURE), on)
	_refresh_maps()


func set_show_keys(on: bool) -> void:
	show_keys = on
	_keys_button.set_pressed_no_signal(on)
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_KEYS), on)
	for m in maps:
		m.canvas.show_keys = on


func set_season(s: int) -> void:
	season = s
	for i in SEASONS.size():
		_season_menu.set_item_checked(i, i == s)
	_refresh_maps()


func _refresh_maps() -> void:
	for m in maps:
		m.ascii.season = season
		m.ascii.show_furniture = show_furniture
		m.ascii.refresh()
		m.canvas.queue_redraw()
	var cur := current_map()
	if cur:
		_legend.show_map(cur.ascii)


func _on_tab_changed(i: int) -> void:
	for j in maps.size():
		maps[j].canvas.visible = j == i
	var m := current_map()
	_empty_label.visible = m == null
	_legend.show_map(m.ascii if m else null)
	if m:
		_drawer.current_tab = _legend.get_index()
	var problems := m.ascii.resolved.problems if m else PackedStringArray()
	_problems_button.visible = m != null
	_problems_button.text = "%d problems" % problems.size() if problems.size() else "No problems"
	_problems_button.modulate = Color(1, 0.55, 0.55) if problems.size() else Color(0.7, 1, 0.7)
	if m:
		var r := m.ascii.resolved
		_status.text = "%s   %dx%d   %s   palettes: %s" % [m.ref.source.path, r.size.x, r.size.y,
				MapBrowser.entry_text(m.ref)[1], ", ".join(r.palettes) if r.palettes.size() else "none"]


func _on_cell_hovered(cell: Vector2i, m: OpenMap) -> void:
	if cell.x < 0:
		return
	_status.text = m.ascii.describe_cell(cell.x, cell.y)


func _on_cell_clicked(cell: Vector2i, m: OpenMap) -> void:
	var key := m.ascii.resolved.cells[cell.y][cell.x]
	m.canvas.highlight_key = key
	_drawer.current_tab = _legend.get_index()
	_legend.select_key(key)


func _on_key_selected(key: String) -> void:
	var m := current_map()
	if m:
		m.canvas.highlight_key = key


func _show_report(title: String, lines: PackedStringArray) -> void:
	_report.title = title
	_report_text.text = "\n".join(lines) if lines.size() else "Nothing to report."
	_report.popup_centered_ratio(0.5)


func _on_problems_pressed() -> void:
	var m := current_map()
	if m == null:
		return
	var lines := m.ascii.resolved.problems.duplicate()
	if not m.ascii.resolved.choices.is_empty():
		lines.append("")
		lines.append("Shown with these choices:")
		lines.append_array(m.ascii.resolved.choices)
	_show_report("Problems: " + m.ref.title(), lines)


func _on_menu(id: int) -> void:
	match id:
		Menu.OPEN_BN:
			_bn_dialog.popup_centered_ratio(0.6)
		Menu.MODS:
			if index:
				_mods_dialog.open(index.catalog, settings.mods)
		Menu.RELOAD:
			if index:
				_load_later(index.bn_path)
		Menu.CLOSE_TAB:
			close_tab(_tabs.current_tab)
		Menu.QUIT:
			get_tree().quit()
		Menu.SHOW_FURNITURE:
			set_show_furniture(not show_furniture)
		Menu.SHOW_KEYS:
			set_show_keys(not show_keys)
		Menu.FIT:
			if current_map():
				current_map().canvas.fit()
		Menu.TOGGLE_DRAWER:
			_drawer.visible = not _drawer.visible
		Menu.FIND:
			_drawer.visible = true
			_drawer.current_tab = _browser.get_index()
			_browser.focus_search()
		Menu.SPRING, Menu.SUMMER, Menu.AUTUMN, Menu.WINTER:
			set_season(id - Menu.SPRING)


func _on_bn_chosen(path: String) -> void:
	if not is_bn_checkout(path):
		_status.text = "%s has no data/json; pick the Cataclysm-BN folder." % path
		return
	settings.bn_path = path
	settings.save_to()
	_bn_override = ""
	_load_later(path)


func _on_mods_chosen(mods: PackedStringArray) -> void:
	settings.mods = mods
	settings.save_to()
	_load_later(index.bn_path)


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var menu_bar := MenuBar.new()
	top.add_child(menu_bar)
	_file_menu = _menu(menu_bar, "File", [
		["Open BN folder...", Menu.OPEN_BN, KEY_MASK_CTRL | KEY_O],
		["Mods...", Menu.MODS, KEY_MASK_CTRL | KEY_M],
		["Reload data", Menu.RELOAD, KEY_F5],
		[],
		["Close tab", Menu.CLOSE_TAB, KEY_MASK_CTRL | KEY_W],
		["Quit", Menu.QUIT, KEY_MASK_CTRL | KEY_Q],
	])
	_view_menu = _menu(menu_bar, "View", [
		["Find map...", Menu.FIND, KEY_MASK_CTRL | KEY_P],
		["Fit map to window", Menu.FIT, KEY_MASK_CTRL | KEY_0],
		["Show side panel", Menu.TOGGLE_DRAWER, KEY_F2],
		[],
		["Show furniture", Menu.SHOW_FURNITURE, KEY_MASK_CTRL | KEY_U, true],
		["Show row symbols", Menu.SHOW_KEYS, KEY_MASK_CTRL | KEY_K, true],
	])
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_FURNITURE), true)
	_season_menu = PopupMenu.new()
	_season_menu.name = "Season"
	for i in SEASONS.size():
		_season_menu.add_radio_check_item(SEASONS[i], Menu.SPRING + i)
	_season_menu.set_item_checked(0, true)
	_season_menu.id_pressed.connect(_on_menu)
	_view_menu.add_child(_season_menu)
	_view_menu.add_submenu_node_item("Season", _season_menu)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_label("Show:"))
	_furniture_button = _toggle("Furniture", true, "Draw furniture over terrain (Ctrl+U)", set_show_furniture)
	top.add_child(_furniture_button)
	_keys_button = _toggle("Row symbols", false, "Draw the characters from \"rows\" (Ctrl+K)", set_show_keys)
	top.add_child(_keys_button)
	var fit := Button.new()
	fit.text = "Fit"
	fit.flat = true
	fit.tooltip_text = "Fit the map to the window (Ctrl+0)"
	fit.pressed.connect(_on_menu.bind(Menu.FIT))
	top.add_child(fit)

	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	_split.add_child(left)
	_tabs = TabBar.new()
	_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.tab_close_pressed.connect(close_tab)
	left.add_child(_tabs)
	_canvas_area = Control.new()
	_canvas_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_area.clip_contents = true
	left.add_child(_canvas_area)
	_empty_label = _label("Open a map from the Browser (Ctrl+P to search).")
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_empty_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_canvas_area.add_child(_empty_label)

	_drawer = TabContainer.new()
	_drawer.custom_minimum_size = Vector2(380, 0)
	_split.add_child(_drawer)
	_browser = MapBrowser.new()
	_browser.open_requested.connect(func(ref: DataIndex.MapgenRef) -> void: open_ref(ref))
	_drawer.add_child(_browser)
	_legend = LegendPanel.new()
	_legend.key_selected.connect(_on_key_selected)
	_drawer.add_child(_legend)

	var status_bar := PanelContainer.new()
	root.add_child(status_bar)
	var status_row := HBoxContainer.new()
	status_bar.add_child(status_row)
	_status = _label("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_status)
	_errors_button = Button.new()
	_errors_button.flat = true
	_errors_button.visible = false
	_errors_button.modulate = Color(1, 0.75, 0.4)
	_errors_button.pressed.connect(func() -> void: _show_report("Load errors", index.errors))
	status_row.add_child(_errors_button)
	_problems_button = Button.new()
	_problems_button.flat = true
	_problems_button.visible = false
	_problems_button.pressed.connect(_on_problems_pressed)
	status_row.add_child(_problems_button)

	_report = AcceptDialog.new()
	_report_text = TextEdit.new()
	_report_text.editable = false
	_report_text.custom_minimum_size = Vector2(500, 300)
	_report.add_child(_report_text)
	add_child(_report)
	_mods_dialog = ModsDialog.new()
	_mods_dialog.mods_chosen.connect(_on_mods_chosen)
	add_child(_mods_dialog)
	_bn_dialog = FileDialog.new()
	_bn_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_bn_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_bn_dialog.title = "Choose the Cataclysm-BN folder"
	_bn_dialog.dir_selected.connect(_on_bn_chosen)
	add_child(_bn_dialog)


## Adds a menu. Items are [text, id, shortcut keycode, checkable?]; [] is a separator.
func _menu(bar: MenuBar, title: String, items: Array) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = title
	for it: Array in items:
		if it.is_empty():
			menu.add_separator()
		elif it.size() > 3 and it[3]:
			menu.add_check_item(it[0], it[1], it[2])
		else:
			menu.add_item(it[0], it[1], it[2])
	menu.id_pressed.connect(_on_menu)
	bar.add_child(menu)
	return menu


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _toggle(text: String, on: bool, tip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.tooltip_text = tip
	b.toggled.connect(handler)
	return b

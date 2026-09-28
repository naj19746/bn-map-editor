extends Control
## Application root: the ASCII map editor.
##
## Layout: menu bar and toolbar on top; map tabs with the canvas on the left;
## a side drawer (Browser, Legend, Placements, Problems) on the right; a
## layer bar under the map; a status bar at the bottom, counting the current
## map's errors and warnings (see Validator).
## Maps are edited through an EditSession and saved to the workspace; the
## Palette editor window edits palettes in the same session, and the Sync
## window pushes workspace files into BN.
##
## With a computer selected (the brush symbol places one on the Legend tab,
## a place_computers entry on the Placements tab, or a console finding on
## the Problems tab) the canvas draws its reach. A right click on a cell
## opens a cell menu; "Control with a computer..." on a door locks it (a
## t_door_metal_locked symbol) and, unless a console already unlocks it,
## offers the cells where a Door control console would reach it.
##
## Command line (after "--"): --bn <path> overrides the BN checkout,
## --workspace <path> the workspace folder, and --open <id> opens a mapgen by
## om_terrain / nested id once loaded.

## The data finished (re)loading.
signal index_loaded

enum Menu {
	OPEN_BN, MODS, RELOAD, CLOSE_TAB, QUIT,
	SHOW_FURNITURE, SHOW_KEYS, SHOW_CHUNKS, FIT, TOGGLE_DRAWER, FIND,
	SPRING, SUMMER, AUTUMN, WINTER,
	NEW_MAP, NEW_CHUNK, SAVE, SAVE_ALL, WORKSPACE,
	UNDO, REDO, NEW_SYMBOL, NEW_COMPUTER, ADD_OVERMAP, PALETTES, CHUNK_PARENTS,
	SYNC,
	CELL_PICK, CELL_EDIT_COMPUTER, CELL_DOOR_COMPUTER,
}

## The door terrain computers unlock (Computer.EFFECTS "unlock").
const LOCKED_DOOR := "t_door_metal_locked"
## Findings about a console: selecting one shows its reach.
const CONSOLE_CODES := [Validator.Code.NO_STAND, Validator.Code.NO_DOOR, Validator.Code.DOOR_ELSEWHERE,
		Validator.Code.OTHER_LOCKED, Validator.Code.SHARED_DOOR, Validator.Code.EDGE_CONSOLE]

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
## Tool button hotkeys, by MapTool.Kind.
const TOOL_KEYS := [KEY_B, KEY_L, KEY_R, KEY_F, KEY_I, KEY_P]
const TOOL_TIPS := [
	"Paint: drag to draw with the brush symbol",
	"Line: drag a straight line",
	"Rect: drag a rectangle outline; hold Shift to fill it",
	"Fill: fill the connected area of one symbol",
	"Pick: click a cell to use its symbol as the brush (Alt+click works with any tool)",
	"Place: click a placement to select it, drag to move it, drag its corner (or Shift+drag) to resize",
]


## One open map tab.
class OpenMap:
	var ref: DataIndex.MapgenRef
	var doc: MapDocument
	var ascii: AsciiMap
	var canvas: MapCanvas
	## This map's brush symbol ("" for none); symbols differ per map.
	var brush := ""
	## The selected placement ("" for none).
	var sel_member := ""
	var sel_index := -1
	## The console whose reach the Problems tab shows: [key, place_computers
	## index] (see MapDocument.reach_view), or [].
	var problem_console := []
	## The reach of a chunk's console the Problems tab shows (a finding's
	## Validator.Finding.view), or null.
	var problem_view: ConsoleReachView
	## The door a new console is being placed for; x < 0 when not.
	var console_door := -Vector2i.ONE


## False to skip loading on _ready (tests call load_index themselves).
var auto_start := true
var settings: AppSettings
var index: DataIndex
var session: EditSession
var tool := MapTool.new()
var placement_tool := PlacementTool.new()
var maps: Array[OpenMap] = []
var show_furniture := true
var show_keys := false
## Draw the nested chunks each map places over its cells.
var show_chunks := true
var season := 0
## Placement layers shown (bit 1 << Placement.Layer).
var layer_mask := (1 << Placement.LAYER_NAMES.size()) - 1

var _file_menu: PopupMenu
var _edit_menu: PopupMenu
var _view_menu: PopupMenu
var _season_menu: PopupMenu
var _furniture_button: Button
var _keys_button: Button
var _chunks_button: Button
var _tool_buttons: Array[Button] = []
var _brush_label: Label
var _tabs: TabBar
var _canvas_area: Control
var _empty_label: Label
var _split: HSplitContainer
var _drawer: TabContainer
## The drawer's current tab (TabContainer ignores current_tab outside the
## tree, so tests read this).
var drawer_tab: Control
var _browser: MapBrowser
var _legend: LegendPanel
var _placements_panel: PlacementsPanel
var _problems_panel: ProblemsPanel
## True while a problem selects a placement (the Problems tab stays up).
var _from_problems := false
var _layer_buttons: Array[Button] = []
var _status: Label
var _problems_button: Button
var _errors_button: Button
var _report: AcceptDialog
var _report_text: TextEdit
var _mods_dialog: ModsDialog
var _bn_dialog: FileDialog
var _workspace_dialog: FileDialog
var _new_symbol_dialog: NewSymbolDialog
var _computer_dialog: ComputerDialog
var _new_map_dialog: NewMapDialog
var _sync_dialog: SyncDialog
var _palette_editor: PaletteEditor
var _unsaved_dialog: ConfirmationDialog
var _cell_menu: PopupMenu
## The cell the cell menu was opened on.
var _menu_cell := -Vector2i.ONE
## "Make it a locked metal door?" for "Control with a computer...".
var _door_dialog: ConfirmationDialog
var _pending_door := -Vector2i.ONE
var _unsaved_files := PackedStringArray()
var _after_unsaved := Callable()
var _bn_override := ""
var _workspace_override := ""
var _open_on_load := ""


func _ready() -> void:
	settings = AppSettings.load_from()
	_parse_args()
	_build_ui()
	tool.picked.connect(_on_picked)
	placement_tool.selection_changed.connect(_on_placement_selected)
	placement_tool.failed.connect(func(msg: String) -> void: _status.text = msg)
	if is_inside_tree():
		# Closing the window asks about unsaved changes first.
		get_tree().auto_accept_quit = false
	if auto_start:
		_start()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if i + 1 >= args.size():
			break
		match args[i]:
			"--bn": _bn_override = args[i + 1]
			"--workspace": _workspace_override = args[i + 1]
			"--open": _open_on_load = args[i + 1]


func _start() -> void:
	var path := bn_path()
	if path.is_empty():
		_status.text = "Choose your Cataclysm-BN folder (File > Open BN folder)."
		_bn_dialog.popup_centered_ratio(0.6)
		return
	await _load_later(path)
	if _open_on_load:
		open_id(_open_on_load)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_unsaved(_all_dirty(), get_tree().quit)


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


## The workspace folder: --workspace, the saved one, or the default.
func workspace_root() -> String:
	if _workspace_override:
		return _workspace_override
	return settings.workspace_path if settings.workspace_path else Workspace.default_root()


static func is_bn_checkout(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path.path_join("data/json"))


## Shows a loading message, lets it draw, then loads.
func _load_later(path: String) -> void:
	_status.text = "Loading %s ..." % path
	await get_tree().process_frame
	await get_tree().process_frame
	load_index(path)


## Loads BN at [param path] with the saved mods and the workspace layered on
## top, closing any open maps (unsaved changes are dropped; ask first).
func load_index(path: String) -> void:
	_close_all()
	var t := Time.get_ticks_msec()
	var ws := workspace_root()
	var ws_problem := Workspace.check_root(ws, path)
	index = DataIndex.load_bn(path, settings.mods, null, "" if ws_problem else ws)
	session = EditSession.new(index, Workspace.open(ws, path))
	_palette_editor.setup(session)
	_browser.set_index(index)
	_status.text = "Loaded %d files from %s (%s) in %d ms. Workspace: %s. Pick a map in the Browser." % [
		index.file_count, path, ", ".join(index.mods), Time.get_ticks_msec() - t,
		ws if not ws_problem else "unusable, " + ws_problem]
	var errors := index.errors.duplicate()
	if session.workspace.error:
		errors.append(session.workspace.error)
	_errors_button.visible = not errors.is_empty()
	_errors_button.text = "%d load errors" % errors.size()
	show_drawer_tab(_browser)
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
	var doc := session.open(ref)
	if doc == null:
		_status.text = session.last_error
		return null
	return _add_tab(doc)


func _add_tab(doc: MapDocument) -> OpenMap:
	var m := OpenMap.new()
	m.ref = doc.ref
	m.doc = doc
	m.ascii = AsciiMap.build(index, doc.resolved, season, show_furniture,
			doc.chunk_overlay() if show_chunks else null)
	m.canvas = MapCanvas.new()
	m.canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.canvas.ascii = m.ascii
	m.canvas.chunks = doc.chunk_overlay()
	m.canvas.show_keys = show_keys
	m.canvas.placements = doc.placements()
	m.canvas.layer_mask = layer_mask
	m.canvas.cell_hovered.connect(_on_cell_hovered.bind(m))
	m.canvas.cell_pressed.connect(_on_cell_pressed.bind(m))
	m.canvas.cell_dragged.connect(_on_cell_dragged.bind(m))
	m.canvas.cell_released.connect(_on_cell_released.bind(m))
	m.canvas.cell_context.connect(_on_cell_context.bind(m))
	doc.cells_changed.connect(_on_doc_cells_changed.bind(m))
	doc.changed.connect(_on_doc_changed.bind(m))
	doc.overlay_changed.connect(_on_overlay_changed.bind(m))
	_canvas_area.add_child(m.canvas)
	maps.append(m)
	_tabs.add_tab("")
	_tabs.set_tab_tooltip(maps.size() - 1, "%s\n%s #%d" % [", ".join(m.ref.ids), m.ref.source.path, m.ref.source.index])
	_update_tab_titles()
	_tabs.current_tab = maps.size() - 1
	_on_tab_changed(_tabs.current_tab)
	m.canvas.fit.call_deferred()
	return m


func current_map() -> OpenMap:
	var i := _tabs.current_tab
	return maps[i] if i >= 0 and i < maps.size() else null


## Closes tab [param i]. If it's the last open map of a file with unsaved
## changes, asks first unless [param force].
func close_tab(i: int, force := false) -> void:
	if i < 0 or i >= maps.size():
		return
	var m := maps[i]
	var rel := m.doc.file.rel_path
	# A palette open in the palette editor keeps its file (and its changes) open.
	if not force and session.open_count(rel) == 1 and session.is_dirty(rel):
		_confirm_unsaved(PackedStringArray([rel]), func() -> void: close_tab(maps.find(m), true))
		return
	tool.cancel()
	cancel_console_mode()
	session.close(m.doc)
	m.canvas.queue_free()
	maps.remove_at(i)
	_tabs.remove_tab(i)
	_on_tab_changed(_tabs.current_tab)


func _close_all() -> void:
	while not maps.is_empty():
		close_tab(maps.size() - 1, true)


# --- Editing -------------------------------------------------------------------

## Makes [param key] the brush of the current map, highlights it, and
## selects it in the legend.
func set_brush(key: String) -> void:
	var m := current_map()
	if m == null:
		return
	m.brush = key
	tool.key = key
	m.canvas.highlight_key = key
	_legend.select_key(key)
	_update_brush_label()
	_update_reach(m)


func set_tool(kind: MapTool.Kind) -> void:
	tool.cancel()
	cancel_console_mode()
	placement_tool.cancel()
	if kind != MapTool.Kind.PLACE:
		placement_tool.armed = ""
	tool.kind = kind
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == kind)


func _update_brush_label() -> void:
	var m := current_map()
	if m == null or m.brush.is_empty():
		_brush_label.text = "Brush: none (pick a symbol in the Legend)"
		return
	var look := m.ascii.look_for(m.brush)
	var ids := PackedStringArray()
	if look.terrain:
		ids.append(look.terrain.id)
	if look.furniture:
		ids.append(look.furniture.id)
	_brush_label.text = "Brush: '%s' %s" % [LegendPanel._show_key(m.brush), " + ".join(ids)]


func _on_cell_pressed(cell: Vector2i, alt: bool, shift: bool, m: OpenMap) -> void:
	if m.console_door.x >= 0 and not alt:
		place_door_console(cell)
		return
	if tool.kind == MapTool.Kind.PLACE and not alt:
		placement_tool.press(m.doc, cell, shift)
		m.canvas.placement_preview = placement_tool.preview
		return
	if not tool.press(m.doc, cell, alt, shift):
		_status.text = "Choose a brush first: a symbol in the Legend, or Alt+click a cell."
	m.canvas.preview_key = tool.key
	m.canvas.preview = tool.preview


func _on_cell_dragged(cell: Vector2i, shift: bool, m: OpenMap) -> void:
	if placement_tool.is_active():
		placement_tool.move(cell)
		m.canvas.placement_preview = placement_tool.preview
		return
	tool.move(cell, shift)
	m.canvas.preview = tool.preview


func _on_cell_released(cell: Vector2i, shift: bool, m: OpenMap) -> void:
	if placement_tool.is_active():
		placement_tool.release(cell)
		m.canvas.placement_preview = placement_tool.preview
		return
	tool.release(cell, shift)
	m.canvas.preview = tool.preview


func _on_picked(key: String) -> void:
	set_brush(key)
	var m := current_map()
	if m:
		show_drawer_tab(_legend)
		var info: ResolvedMapgen.SymbolInfo = m.doc.resolved.symbols.get(key)
		if info == null:
			_status.text = "'%s' isn't defined; define it with New symbol to paint it." % key


func _on_doc_cells_changed(cells: Array[Vector2i], m: OpenMap) -> void:
	m.ascii.update_cells(cells)
	m.canvas.queue_redraw()
	_update_reach(m)


## The document was re-resolved. Painted cells were already redrawn
## (cells_changed); a [param full] change redraws every cell.
func _on_doc_changed(full: bool, m: OpenMap) -> void:
	m.ascii.resolved = m.doc.resolved
	m.problem_view = null  # Its finding was made before the change.
	if _update_overlay(m) or full:
		m.ascii.refresh()
	m.canvas.placements = m.doc.placements()
	m.canvas.queue_redraw()
	_update_tab_titles()
	if m == current_map():
		if m.sel_member and m.doc.placement(m.sel_member, m.sel_index) == null:
			placement_tool.select("", -1)
		_placements_panel.refresh()
		_legend.show_map(m.ascii)
		_update_problems()
		_update_brush_label()
	_update_reach(m)


## Gives [param m]'s view the map's current chunk overlay. True when the
## chunks now leave different cells, so every cell must be redrawn.
func _update_overlay(m: OpenMap) -> bool:
	var overlay := m.doc.chunk_overlay()
	m.canvas.chunks = overlay
	var shown := overlay if show_chunks else null
	var same := shown == m.ascii.overlay or (shown != null and shown.same_cells(m.ascii.overlay))
	m.ascii.overlay = shown
	return not same


## A chunk (or a palette of one) this map draws changed elsewhere.
func _on_overlay_changed(m: OpenMap) -> void:
	m.problem_view = null
	if _update_overlay(m):
		m.ascii.refresh()
	m.canvas.queue_redraw()
	_update_reach(m)
	if m == current_map():
		_placements_panel.refresh()
		_update_problems()


## Lists the maps placing the current chunk (directly, through a palette's
## "nested" mapping they use, or through other chunks).
func show_chunk_parents() -> void:
	var m := current_map()
	if m == null:
		return
	var id := m.doc.chunk_id()
	if id.is_empty():
		_status.text = "%s isn't a nested chunk." % m.ref.title()
		return
	var lines := PackedStringArray()
	for a in session.chunk_parents(m.ref):
		lines.append("%s (%s #%d)%s" % [a.ref.title(), a.ref.source.path, a.ref.source.index,
				"" if a.via == id else "  via " + a.via])
	_show_report("Maps placing %s (%d)" % [id, lines.size()], lines)


# --- Computers -----------------------------------------------------------------

## Opens "New computer" for the current map.
func new_computer() -> void:
	var m := current_map()
	if m:
		_computer_dialog.open_new(m.doc)


## Opens the computer of symbol [param key] of the current map: in the
## computer dialog, or in the palette editor when a palette defines it.
func edit_computer(key: String) -> void:
	var m := current_map()
	if m == null:
		return
	var why := _legend.computer_state(key)
	if why:
		_status.text = why
		return
	var pal := _legend.computer_palette(key)
	if pal:
		open_palette_editor(pal)
		why = _palette_editor.edit_computer(key)
		_status.text = why if why else "'%s''s computer is defined in palette %s: editing it changes every map painting '%s' from it." % [
			LegendPanel._show_key(key), pal, LegendPanel._show_key(key)]
		return
	_computer_dialog.open_edit(m.doc, key)


func _on_computer_added(key: String, door_key: String) -> void:
	set_brush(key)
	set_tool(MapTool.Kind.PAINT)
	_status.text = "Paint '%s' where the console goes%s. The Problems tab says if a door option reaches nothing." % [
		LegendPanel._show_key(key),
		", then '%s' for the door (within 8 cells of a cell next to the console, same overmap tile)" % door_key if door_key else ""]


## Shows [param tab] in the side drawer.
func show_drawer_tab(tab: Control) -> void:
	_drawer.current_tab = tab.get_index()
	if drawer_tab != tab:
		drawer_tab = tab
		if current_map():
			_update_reach(current_map())


## Shows the reach of [param m]'s selected computer on its canvas and in
## the drawer tab that selects it (see the class notes).
func _update_reach(m: OpenMap) -> void:
	if m == null or _drawer == null:
		return
	var view: ConsoleReachView = null
	var tab := drawer_tab
	if m == current_map():
		if tab == _legend and m.brush:
			view = m.doc.reach_view(m.brush)
		elif tab == _placements_panel and m.sel_member == "place_computers":
			view = m.doc.reach_view("", m.sel_index)
		elif tab == _problems_panel and m.problem_view:
			view = m.problem_view
		elif tab == _problems_panel and not m.problem_console.is_empty():
			view = m.doc.reach_view(m.problem_console[0], m.problem_console[1])
	m.canvas.reach = view
	if m == current_map():
		_legend.set_reach(view if tab == _legend else null)
		_placements_panel.set_reach(view if tab == _placements_panel else null)


func _on_cell_context(cell: Vector2i, at: Vector2, m: OpenMap) -> void:
	open_cell_menu(cell)
	if is_inside_tree():
		_cell_menu.popup(Rect2i(Vector2i(m.canvas.get_screen_position() + at), Vector2i.ZERO))


## Fills the cell menu for [param cell] of the current map.
func open_cell_menu(cell: Vector2i) -> void:
	var m := current_map()
	if m == null:
		return
	_menu_cell = cell
	_cell_menu.clear()
	var key := m.doc.resolved.cells[cell.y][cell.x]
	_cell_menu.add_item("Use '%s' as the brush" % LegendPanel._show_key(key), Menu.CELL_PICK)
	if m.doc.computer_source(key):
		var why := _legend.computer_state(key)
		_cell_menu.add_item("Edit computer '%s'..." % LegendPanel._show_key(key), Menu.CELL_EDIT_COMPUTER)
		if why:
			var i := _cell_menu.get_item_index(Menu.CELL_EDIT_COMPUTER)
			_cell_menu.set_item_disabled(i, true)
			_cell_menu.set_item_tooltip(i, why)
	_cell_menu.add_item("Control with a computer...", Menu.CELL_DOOR_COMPUTER)
	var problem := door_problem(cell)
	if problem:
		var i := _cell_menu.get_item_index(Menu.CELL_DOOR_COMPUTER)
		_cell_menu.set_item_disabled(i, true)
		_cell_menu.set_item_tooltip(i, problem)
	else:
		_cell_menu.set_item_tooltip(_cell_menu.get_item_index(Menu.CELL_DOOR_COMPUTER),
				"Lock this door (a locked metal door) and place a console that unlocks it")


func _on_cell_menu(id: int) -> void:
	var m := current_map()
	if m == null or _menu_cell.x < 0:
		return
	var key := m.doc.resolved.cells[_menu_cell.y][_menu_cell.x]
	match id:
		Menu.CELL_PICK:
			show_drawer_tab(_legend)
			set_brush(key)
		Menu.CELL_EDIT_COMPUTER:
			set_brush(key)
			edit_computer(key)
		Menu.CELL_DOOR_COMPUTER:
			control_door(_menu_cell)


## Why "Control with a computer..." can't work on [param cell], or "".
func door_problem(cell: Vector2i) -> String:
	var m := current_map()
	var ter := m.doc.terrain_at(cell)
	if not ter.contains("door"):
		return "Not a door (%s)." % (ter if ter else "no terrain")
	var chunk := m.doc.chunk_terrain_source(cell)
	if chunk:
		return "This door comes from chunk %s; open the chunk to change it." % chunk
	return ""


## "Control with a computer..." on door [param cell]: asks to make it a
## locked metal door if it isn't one, then goes on as lock_door().
func control_door(cell: Vector2i) -> void:
	var m := current_map()
	if m == null:
		return
	var problem := door_problem(cell)
	if problem:
		_status.text = problem
		return
	cancel_console_mode()
	var ter := m.doc.terrain_at(cell)
	if ter == LOCKED_DOOR:
		_after_door_locked(cell)
		return
	_pending_door = cell
	var keys := m.doc.matching_keys(LOCKED_DOOR, "")
	var how := "Paint it with '%s'." % LegendPanel._show_key(keys[0]) if keys.size() \
			else "Adds the symbol '%s' for it to the map." % LegendPanel._show_key(m.doc.suggest_key(LOCKED_DOOR))
	_door_dialog.dialog_text = ("This door is %s. A computer only unlocks locked metal doors (%s): " \
			+ "the player can't open them any other way.\n%s") % [ter, LOCKED_DOOR, how]
	if is_inside_tree():
		_door_dialog.popup_centered()


## Makes door [param cell] of the current map a locked metal door (one undo
## step), then looks for a console that unlocks it (see _after_door_locked).
func lock_door(cell: Vector2i) -> void:
	var m := current_map()
	if m == null or cell.x < 0:
		return
	var keys := m.doc.matching_keys(LOCKED_DOOR, "")
	var key := keys[0] if keys.size() else m.doc.suggest_key(LOCKED_DOOR)
	m.doc.begin_group("Lock door at (%d, %d)" % [cell.x, cell.y])
	var err := "" if keys.size() else m.doc.add_symbol(key, LOCKED_DOOR, "")
	if err.is_empty():
		m.doc.paint([cell], key)
	m.doc.end_group()
	if err:
		_status.text = "Can't add a door symbol: " + err
		return
	_after_door_locked(cell)


## A locked metal door at [param cell]: shows the console that already
## unlocks it, or offers the cells where a new one would.
func _after_door_locked(cell: Vector2i) -> void:
	var m := current_map()
	var by := m.doc.door_controllers(cell)
	if not by.is_empty():
		var at: Vector2i = by[0][0]
		var key: String = by[0][1]
		if key:
			show_drawer_tab(_legend)
			set_brush(key)
		else:
			var i: int = m.doc.consoles()[at][3]
			show_drawer_tab(_placements_panel)
			select_placement("place_computers", i)
		_status.text = "The console at (%d, %d) already unlocks the door at (%d, %d)." % [at.x, at.y, cell.x, cell.y]
		return
	var spots := m.doc.console_spots(cell)
	if spots.is_empty():
		_status.text = "No floor cell near the door at (%d, %d) can hold a console that reaches it (within %d of a cell next to the console, same overmap tile)." % [
			cell.x, cell.y, ConsoleReachView.DOOR_RADIUS]
		return
	m.console_door = cell
	m.canvas.spots = spots
	m.canvas.focus = Rect2i(cell, Vector2i.ONE)
	_status.text = "Click a green cell to put a door console there: it unlocks the door at (%d, %d). Esc cancels." % [cell.x, cell.y]


## Puts a Door control console at [param cell] for the door being
## controlled (one undo step): reuses a symbol whose computer unlocks, else
## adds one. Returns an error, or "".
func place_door_console(cell: Vector2i) -> String:
	var m := current_map()
	if m == null or m.console_door.x < 0:
		return "Not placing a console."
	if not m.canvas.spots.has(cell):
		_status.text = "A console there wouldn't reach the door; click a green cell (Esc cancels)."
		return _status.text
	var door := m.console_door
	var key := m.doc.door_console_key()
	var added := key.is_empty()
	m.doc.begin_group("Door console at (%d, %d)" % [cell.x, cell.y])
	var err := ""
	if added:
		key = m.doc.suggest_key(Computer.CONSOLE)
		err = m.doc.add_computer_symbol(key, Computer.preset("door"))
	if err.is_empty():
		m.doc.paint([cell], key)
	m.doc.end_group()
	cancel_console_mode()
	if err:
		_status.text = "Can't add a console symbol: " + err
		return err
	show_drawer_tab(_legend)
	set_brush(key)
	_status.text = "%s console '%s' at (%d, %d); it unlocks the door at (%d, %d). Edit computer... changes what it does." % [
		"Added a Door control" if added else "Placed the", LegendPanel._show_key(key), cell.x, cell.y, door.x, door.y]
	return ""


## Leaves the "place a console" mode, if on.
func cancel_console_mode() -> void:
	for m in maps:
		if m.console_door.x >= 0:
			m.console_door = -Vector2i.ONE
			m.canvas.spots = [] as Array[Vector2i]
			m.canvas.focus = Rect2i()


# --- Placements ----------------------------------------------------------------

## Selects placement [param member] #[param index] of the current map ("" for
## none), on the canvas and in the Placements panel.
func select_placement(member: String, index: int) -> void:
	placement_tool.select(member, index)


func _on_placement_selected(member: String, index: int) -> void:
	var m := current_map()
	if m == null:
		return
	m.sel_member = member
	m.sel_index = index
	m.canvas.select_placement(member, index)
	_update_reach(m)
	_placements_panel.select(member, index)
	var p := m.doc.placement(member, index) if member else null
	if p:
		if not _from_problems:
			show_drawer_tab(_placements_panel)
		_status.text = "%s: %s   %s" % [p.title(), p.label(), p.what()]


## "Add" in the Placements panel: the next drag on the map places it.
func arm_placement(member: String) -> void:
	set_tool(MapTool.Kind.PLACE)
	placement_tool.armed = member
	_status.text = "Drag on the map where the new %s goes (Esc cancels)." % member


func set_layer_visible(layer: int, on: bool) -> void:
	layer_mask = layer_mask | (1 << layer) if on else layer_mask & ~(1 << layer)
	placement_tool.layer_mask = layer_mask
	_layer_buttons[layer].set_pressed_no_signal(on)
	for m in maps:
		m.canvas.layer_mask = layer_mask


func _focus_placement(member: String, index: int) -> void:
	var m := current_map()
	var p := m.doc.placement(member, index) if m else null
	if p:
		select_placement(member, index)
		m.canvas.center_on(p.instances()[0])


func undo() -> void:
	var m := current_map()
	if m and m.doc.can_undo():
		var name := m.doc.undo_name()
		m.doc.undo()
		_status.text = "Undid " + name


func redo() -> void:
	var m := current_map()
	if m and m.doc.can_redo():
		var name := m.doc.redo_name()
		m.doc.redo()
		_status.text = "Redid " + name


## Saves the current map's file to the workspace. Returns an error or "".
func save_current() -> String:
	var m := current_map()
	if m == null:
		return ""
	return _save_files(PackedStringArray([m.doc.file.rel_path]))


func save_all() -> String:
	return _save_files(session.dirty_files())


func _save_files(rels: PackedStringArray) -> String:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	for rel in rels:
		var err := session.save(rel)
		if err:
			errors.append("%s: %s" % [rel, err])
		for n in session.last_notes:
			notes.append("%s: %s" % [rel, n])
	_update_tab_titles()
	_browser.refresh()
	if not errors.is_empty():
		_status.text = "Save failed: " + errors[0]
		_show_report("Save failed", errors)
		return "\n".join(errors)
	_status.text = "Saved %s to %s" % [", ".join(rels), session.workspace.root] if rels.size() \
			else "Nothing to save"
	var fatal := PackedStringArray()
	for rel in rels:
		for d in session.docs_for(rel):
			for f in d.findings(false):
				if f.severity == Validator.Severity.ERROR and f.load_fails:
					fatal.append("%s: %s" % [d.ref.title(), f.text])
	if not fatal.is_empty():
		_status.text += ". BN won't load %s%s (see Problems)" % [fatal[0],
				" and %d more" % (fatal.size() - 1) if fatal.size() > 1 else ""]
	if not notes.is_empty():
		var lines := PackedStringArray(["Saved. These edited objects had text that saving normalized:"])
		lines.append_array(notes)
		_show_report("Saved with changes", lines)
	return ""


## Opens the palette editor at palette [param id], else the current map's
## last palette (the one that wins), else as it was.
func open_palette_editor(id := "") -> void:
	if session == null:
		return
	var m := current_map()
	if id.is_empty() and m and not m.doc.resolved.palettes.is_empty():
		id = m.doc.resolved.palettes[-1]
	_palette_editor.set_map(m.doc if m else null)
	_palette_editor.open(session, id)


## The palette editor changed or saved files (open maps that use an edited
## palette were already redrawn through their documents).
func _on_palette_files_changed() -> void:
	_update_tab_titles()
	_update_problems()
	_browser.refresh()


func add_missing_overmap_terrain() -> void:
	var m := current_map()
	if m == null:
		return
	var added := session.add_missing_overmap_terrain(m.doc)
	_status.text = "Added overmap_terrain for %s to %s (unsaved)" % [", ".join(added), m.doc.file.rel_path] \
			if added.size() else "Every om_terrain id already has an overmap_terrain."
	_update_problems()
	_update_tab_titles()


func _all_dirty() -> PackedStringArray:
	return session.dirty_files() if session else PackedStringArray()


## Runs [param then] once [param rels] are saved or discarded; asks first if
## any of them has unsaved changes.
func _confirm_unsaved(rels: PackedStringArray, then: Callable) -> void:
	var dirty := PackedStringArray()
	for rel in rels:
		if session and session.is_dirty(rel):
			dirty.append(rel)
	if dirty.is_empty():
		then.call()
		return
	_unsaved_files = dirty
	_after_unsaved = then
	_unsaved_dialog.dialog_text = "Unsaved changes in:\n  %s\n\nSave them to the workspace?" % "\n  ".join(dirty)
	_unsaved_dialog.popup_centered()


func _on_unsaved_save() -> void:
	if _save_files(_unsaved_files).is_empty():
		_after_unsaved.call()


func _on_unsaved_action(action: StringName) -> void:
	if action == &"discard":
		_unsaved_dialog.hide()
		_after_unsaved.call()


func _update_tab_titles() -> void:
	for i in maps.size():
		var m := maps[i]
		var title := m.ref.title()
		if not m.ref.grid.is_empty():
			title += " (%dx%d)" % [m.ref.size_omt().x, m.ref.size_omt().y]
		if session.is_dirty(m.doc.file.rel_path):
			title += " *"
		_tabs.set_tab_title(i, title)


## Counts the current map's errors and warnings in the status bar and
## fills the Problems tab.
func _update_problems() -> void:
	var m := current_map()
	var found: Array[Validator.Finding] = m.doc.findings() if m else ([] as Array[Validator.Finding])
	var n := Validator.count(found)
	_problems_button.visible = m != null
	var parts := PackedStringArray()
	if n[0]:
		parts.append("%d error%s" % [n[0], "" if n[0] == 1 else "s"])
	if n[1]:
		parts.append("%d warning%s" % [n[1], "" if n[1] == 1 else "s"])
	if parts.is_empty() and n[2]:
		parts.append("%d note%s" % [n[2], "" if n[2] == 1 else "s"])
	_problems_button.text = ", ".join(parts) if parts.size() else "No problems"
	_problems_button.tooltip_text = "Errors: BN won't load the map or reports it on every load. Warnings: BN " \
			+ "silently skips something. Notes: BN does something odd. Click for the Problems tab."
	_problems_button.modulate = ProblemsPanel.COLORS[0] if n[0] else (ProblemsPanel.COLORS[1] if n[1] else Color(0.7, 1, 0.7))
	_problems_panel.show_findings(found, m.ascii.resolved.choices if m else PackedStringArray())
	if m:
		m.canvas.focus = Rect2i()


## Shows what [param f] points at: its placement, symbol or cell on the map,
## or its palette key in the palette editor.
func show_finding(f: Validator.Finding) -> void:
	var m := current_map()
	_status.text = f.describe()
	if m:
		m.problem_console = []
		m.problem_view = null
		if not f.view.is_empty():
			m.problem_view = ConsoleReachView.build(index, f.view[0], f.view[1], f.view[2], f.view[3])
			m.problem_view.lines.append("The chunk pick this finding is about is laid over the map here; the canvas still draws the usual pick.")
		if f.code in CONSOLE_CODES:
			if f.target == Validator.Target.CELL and f.key:
				m.problem_console = [f.key, -1]
			elif f.target == Validator.Target.PLACEMENT and f.member == "place_computers":
				m.problem_console = ["", f.index]
		_update_reach(m)
	if f.target == Validator.Target.PALETTE_KEY:
		open_palette_editor(f.palette)
		if f.key:
			_palette_editor.select_key(f.key)
		return
	if m == null:
		return
	var focus := Rect2i()
	match f.target:
		Validator.Target.PLACEMENT:
			var p := m.doc.placement(f.member, f.index)
			if p:
				_from_problems = true
				select_placement(f.member, f.index)
				_from_problems = false
				focus = p.instances()[0]
		Validator.Target.SYMBOL:
			m.canvas.highlight_key = f.key
			_legend.select_key(f.key)
			focus = _first_cell(m, f.key)
		Validator.Target.CELL:
			focus = Rect2i(f.cell, Vector2i.ONE)
	m.canvas.focus = focus
	if focus.has_area():
		m.canvas.center_on(focus)


## The first cell (row order) using [param key], or an empty rect.
static func _first_cell(m: OpenMap, key: String) -> Rect2i:
	var cells := m.doc.resolved.cells
	for y in cells.size():
		var x := cells[y].find(key)
		if x >= 0:
			return Rect2i(x, y, 1, 1)
	return Rect2i()


# --- View ----------------------------------------------------------------------

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


func set_show_chunks(on: bool) -> void:
	show_chunks = on
	_chunks_button.set_pressed_no_signal(on)
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_CHUNKS), on)
	_refresh_maps()


func _refresh_maps() -> void:
	for m in maps:
		m.ascii.season = season
		m.ascii.show_furniture = show_furniture
		_update_overlay(m)
		m.ascii.refresh()
		m.canvas.queue_redraw()
	var cur := current_map()
	if cur:
		_legend.show_map(cur.ascii)


func _on_tab_changed(i: int) -> void:
	tool.cancel()
	cancel_console_mode()
	for j in maps.size():
		maps[j].canvas.visible = j == i
	var m := current_map()
	placement_tool.cancel()
	placement_tool.armed = ""
	_palette_editor.set_map(m.doc if m else null)
	_placements_panel.show_map(m.doc if m else null)
	if m:
		placement_tool.select(m.sel_member, m.sel_index)
	_empty_label.visible = m == null
	_legend.show_map(m.ascii if m else null)
	tool.key = m.brush if m else ""
	if m:
		show_drawer_tab(_legend)
		if m.brush:
			_legend.select_key(m.brush)
		var r := m.ascii.resolved
		_status.text = "%s   %dx%d   %s   palettes: %s" % [m.ref.source.path, r.size.x, r.size.y,
				MapBrowser.entry_text(m.ref)[1], ", ".join(r.palettes) if r.palettes.size() else "none"]
		if m.doc.chunk_id():
			_status.text += "   (a nested chunk: Edit > Maps placing this chunk)"
	_update_problems()
	_update_brush_label()
	if m:
		_update_reach(m)


func _on_cell_hovered(cell: Vector2i, m: OpenMap) -> void:
	if cell.x < 0:
		return
	var text := m.ascii.describe_cell(cell.x, cell.y)
	if m.console_door.x >= 0:
		text = ("Click to put the door console here   |   " if m.canvas.spots.has(cell) \
				else "Click a green cell for the console (Esc cancels)   |   ") + text
	var here := PackedStringArray()
	for p in m.doc.placements_at(cell):
		if layer_mask & (1 << p.layer()):
			here.append("%s %s %s" % [p.title(), p.label(), p.what()])
	if layer_mask & (1 << Placement.Layer.NESTED):
		for st in m.doc.chunk_overlay().stamps_at(cell):
			if st.depth == 0:
				here.append("%s: %s" % [st.path, st.describe()])
	if not here.is_empty():
		text += "   |   " + ";  ".join(here)
	_status.text = text


func _on_key_selected(key: String) -> void:
	var m := current_map()
	if m == null:
		return
	if key:
		set_brush(key)
	else:
		m.canvas.highlight_key = ""


func _show_report(title: String, lines: PackedStringArray) -> void:
	_report.title = title
	_report_text.text = "\n".join(lines) if lines.size() else "Nothing to report."
	if is_inside_tree():
		_report.popup_centered_ratio(0.5)


func _on_problems_pressed() -> void:
	_drawer.visible = true
	show_drawer_tab(_problems_panel)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_ESCAPE and current_map() and current_map().console_door.x >= 0:
		cancel_console_mode()
		_status.text = "Cancelled placing a console."
		accept_event()
	elif k.keycode == KEY_ESCAPE and (tool.is_active() or placement_tool.is_active() or placement_tool.armed):
		tool.cancel()
		placement_tool.cancel()
		placement_tool.armed = ""
		if current_map():
			current_map().canvas.preview = tool.preview
			current_map().canvas.placement_preview = placement_tool.preview
		accept_event()
	elif k.keycode == KEY_DELETE and tool.kind == MapTool.Kind.PLACE and current_map():
		_placements_panel.delete_selected()
		accept_event()
	elif k.keycode == KEY_Z and k.ctrl_pressed and k.shift_pressed:
		redo()
		accept_event()


func _on_menu(id: int) -> void:
	match id:
		Menu.OPEN_BN:
			_confirm_unsaved(_all_dirty(), func() -> void: _bn_dialog.popup_centered_ratio(0.6))
		Menu.MODS:
			if index:
				_confirm_unsaved(_all_dirty(), func() -> void: _mods_dialog.open(index.catalog, settings.mods))
		Menu.RELOAD:
			if index:
				_confirm_unsaved(_all_dirty(), func() -> void: _load_later(index.bn_path))
		Menu.WORKSPACE:
			_confirm_unsaved(_all_dirty(), func() -> void:
				_workspace_dialog.current_dir = workspace_root()
				_workspace_dialog.popup_centered_ratio(0.6))
		Menu.NEW_MAP:
			if session:
				_new_map_dialog.open(session)
		Menu.NEW_CHUNK:
			if session:
				_new_map_dialog.open(session, NewMapDialog.Kind.CHUNK)
		Menu.SAVE:
			save_current()
		Menu.SAVE_ALL:
			save_all()
		Menu.CLOSE_TAB:
			close_tab(_tabs.current_tab)
		Menu.QUIT:
			_confirm_unsaved(_all_dirty(), get_tree().quit)
		Menu.UNDO:
			undo()
		Menu.REDO:
			redo()
		Menu.NEW_SYMBOL:
			if current_map():
				_new_symbol_dialog.open(current_map().doc)
		Menu.NEW_COMPUTER:
			new_computer()
		Menu.ADD_OVERMAP:
			add_missing_overmap_terrain()
		Menu.PALETTES:
			open_palette_editor()
		Menu.CHUNK_PARENTS:
			show_chunk_parents()
		Menu.SYNC:
			if session:
				_sync_dialog.open(session)
		Menu.SHOW_FURNITURE:
			set_show_furniture(not show_furniture)
		Menu.SHOW_KEYS:
			set_show_keys(not show_keys)
		Menu.SHOW_CHUNKS:
			set_show_chunks(not show_chunks)
		Menu.FIT:
			if current_map():
				current_map().canvas.fit()
		Menu.TOGGLE_DRAWER:
			_drawer.visible = not _drawer.visible
		Menu.FIND:
			_drawer.visible = true
			show_drawer_tab(_browser)
			_browser.focus_search()
		Menu.SPRING, Menu.SUMMER, Menu.AUTUMN, Menu.WINTER:
			set_season(id - Menu.SPRING)


func _update_edit_menu() -> void:
	var m := current_map()
	var undo_i := _edit_menu.get_item_index(Menu.UNDO)
	var redo_i := _edit_menu.get_item_index(Menu.REDO)
	_edit_menu.set_item_text(undo_i, "Undo " + m.doc.undo_name() if m and m.doc.can_undo() else "Undo")
	_edit_menu.set_item_disabled(undo_i, not (m and m.doc.can_undo()))
	_edit_menu.set_item_text(redo_i, "Redo " + m.doc.redo_name() if m and m.doc.can_redo() else "Redo")
	_edit_menu.set_item_disabled(redo_i, not (m and m.doc.can_redo()))
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(Menu.NEW_SYMBOL), m == null)
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(Menu.NEW_COMPUTER), m == null)
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(Menu.ADD_OVERMAP),
			m == null or m.doc.missing_overmap_terrain().is_empty())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(Menu.CHUNK_PARENTS),
			m == null or m.doc.chunk_id().is_empty())


## The Sync window pushed or discarded files. A push leaves the loaded data
## as it was (BN now has the same content); a discarded copy's content is
## still loaded, so reload when that's safe.
func _on_sync_files_changed(reload_needed: bool) -> void:
	_browser.refresh()
	_update_tab_titles()
	if not reload_needed:
		_status.text = "Pushed into %s. Review and commit there." % index.bn_path
	elif maps.is_empty():
		_load_later(index.bn_path)
	else:
		_status.text = "Discarded a workspace copy. Reload the data (F5) to see BN's version."


func _on_bn_chosen(path: String) -> void:
	if not is_bn_checkout(path):
		_status.text = "%s has no data/json; pick the Cataclysm-BN folder." % path
		return
	settings.bn_path = path
	settings.save_to()
	_bn_override = ""
	_load_later(path)


func _on_workspace_chosen(path: String) -> void:
	var problem := Workspace.check_root(path, index.bn_path if index else "")
	if problem:
		_status.text = "Can't use that workspace: " + problem
		return
	settings.workspace_path = path
	settings.save_to()
	_workspace_override = ""
	if index:
		_load_later(index.bn_path)


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
		["New map...", Menu.NEW_MAP, KEY_MASK_CTRL | KEY_N],
		["New nested chunk...", Menu.NEW_CHUNK, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_N],
		["Save", Menu.SAVE, KEY_MASK_CTRL | KEY_S],
		["Save all", Menu.SAVE_ALL, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S],
		[],
		["Open BN folder...", Menu.OPEN_BN, KEY_MASK_CTRL | KEY_O],
		["Workspace folder...", Menu.WORKSPACE, 0],
		["Mods...", Menu.MODS, KEY_MASK_CTRL | KEY_M],
		["Reload data", Menu.RELOAD, KEY_F5],
		[],
		["Close tab", Menu.CLOSE_TAB, KEY_MASK_CTRL | KEY_W],
		["Quit", Menu.QUIT, KEY_MASK_CTRL | KEY_Q],
	])
	_edit_menu = _menu(menu_bar, "Edit", [
		["Undo", Menu.UNDO, KEY_MASK_CTRL | KEY_Z],
		["Redo", Menu.REDO, KEY_MASK_CTRL | KEY_Y],
		[],
		["New symbol...", Menu.NEW_SYMBOL, KEY_MASK_CTRL | KEY_E],
		["New computer...", Menu.NEW_COMPUTER, 0],
		["Add missing overmap_terrain", Menu.ADD_OVERMAP, 0],
		[],
		["Palette editor...", Menu.PALETTES, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_E],
		["Maps placing this chunk...", Menu.CHUNK_PARENTS, 0],
	])
	_edit_menu.about_to_popup.connect(_update_edit_menu)
	_view_menu = _menu(menu_bar, "View", [
		["Find map...", Menu.FIND, KEY_MASK_CTRL | KEY_P],
		["Fit map to window", Menu.FIT, KEY_MASK_CTRL | KEY_0],
		["Show side panel", Menu.TOGGLE_DRAWER, KEY_F2],
		[],
		["Show furniture", Menu.SHOW_FURNITURE, KEY_MASK_CTRL | KEY_U, true],
		["Show row symbols", Menu.SHOW_KEYS, KEY_MASK_CTRL | KEY_K, true],
		["Show nested chunks", Menu.SHOW_CHUNKS, KEY_MASK_CTRL | KEY_J, true],
	])
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_FURNITURE), true)
	_view_menu.set_item_checked(_view_menu.get_item_index(Menu.SHOW_CHUNKS), true)
	_menu(menu_bar, "Sync", [
		["Sync with BN...", Menu.SYNC, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_P],
	])
	_season_menu = PopupMenu.new()
	_season_menu.name = "Season"
	for i in SEASONS.size():
		_season_menu.add_radio_check_item(SEASONS[i], Menu.SPRING + i)
	_season_menu.set_item_checked(0, true)
	_season_menu.id_pressed.connect(_on_menu)
	_view_menu.add_child(_season_menu)
	_view_menu.add_submenu_node_item("Season", _season_menu)

	top.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for kind in MapTool.NAMES.size():
		var b := Button.new()
		b.text = MapTool.NAMES[kind]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = kind == tool.kind
		b.tooltip_text = "%s (%s)" % [TOOL_TIPS[kind], OS.get_keycode_string(TOOL_KEYS[kind])]
		var key := InputEventKey.new()
		key.keycode = TOOL_KEYS[kind]
		b.shortcut = Shortcut.new()
		b.shortcut.events = [key]
		b.shortcut_in_tooltip = false
		b.pressed.connect(set_tool.bind(kind))
		top.add_child(b)
		_tool_buttons.append(b)
	_brush_label = _label("")
	_brush_label.clip_text = true
	_brush_label.custom_minimum_size = Vector2(160, 0)
	_brush_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_brush_label)
	top.add_child(_label("Show:"))
	_furniture_button = _toggle("Furniture", true, "Draw furniture over terrain (Ctrl+U)", set_show_furniture)
	top.add_child(_furniture_button)
	_keys_button = _toggle("Row symbols", false, "Draw the characters from \"rows\" (Ctrl+K)", set_show_keys)
	top.add_child(_keys_button)
	_chunks_button = _toggle("Chunks", true, "Draw the nested chunks the map places over its cells (Ctrl+J)",
			set_show_chunks)
	top.add_child(_chunks_button)
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
	_empty_label = _label("Open a map from the Browser (Ctrl+P to search), or File > New map.")
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_empty_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_canvas_area.add_child(_empty_label)
	var layer_bar := HBoxContainer.new()
	left.add_child(layer_bar)
	layer_bar.add_child(_label(" Placements:"))
	for layer in Placement.LAYER_NAMES.size():
		var b := _toggle(Placement.LAYER_NAMES[layer], true,
				"Show %s placements (and mark cells whose symbol places them)" % Placement.LAYER_NAMES[layer].to_lower(),
				set_layer_visible.bind(layer))
		b.add_theme_color_override("font_pressed_color", MapCanvas.LAYER_COLORS[layer])
		layer_bar.add_child(b)
		_layer_buttons.append(b)

	_drawer = TabContainer.new()
	_drawer.custom_minimum_size = Vector2(380, 0)
	_drawer.tab_changed.connect(func(_t: int) -> void:
		drawer_tab = _drawer.get_current_tab_control()
		if current_map():
			_update_reach(current_map()))
	_split.add_child(_drawer)
	_browser = MapBrowser.new()
	_browser.open_requested.connect(func(ref: DataIndex.MapgenRef) -> void: open_ref(ref))
	_drawer.add_child(_browser)
	drawer_tab = _browser
	_legend = LegendPanel.new()
	_legend.key_selected.connect(_on_key_selected)
	_legend.new_symbol_requested.connect(_on_menu.bind(Menu.NEW_SYMBOL))
	_legend.palette_requested.connect(open_palette_editor)
	_legend.new_computer_requested.connect(new_computer)
	_legend.edit_computer_requested.connect(edit_computer)
	_drawer.add_child(_legend)
	_placements_panel = PlacementsPanel.new()
	_placements_panel.placement_selected.connect(select_placement)
	_placements_panel.add_requested.connect(arm_placement)
	_placements_panel.focus_requested.connect(_focus_placement)
	_placements_panel.message.connect(func(msg: String) -> void: _status.text = msg)
	_placements_panel.open_chunk_requested.connect(func(ref: DataIndex.MapgenRef) -> void: open_ref(ref))
	_drawer.add_child(_placements_panel)
	_problems_panel = ProblemsPanel.new()
	_problems_panel.finding_selected.connect(show_finding)
	_drawer.add_child(_problems_panel)

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
	_errors_button.pressed.connect(func() -> void:
		var lines := index.errors.duplicate()
		if session.workspace.error:
			lines.append(session.workspace.error)
		_show_report("Load errors", lines))
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
	_bn_dialog = _folder_dialog("Choose the Cataclysm-BN folder", _on_bn_chosen)
	_workspace_dialog = _folder_dialog("Choose the workspace folder (edits are saved here)", _on_workspace_chosen)
	_new_symbol_dialog = NewSymbolDialog.new()
	_new_symbol_dialog.symbol_added.connect(set_brush)
	add_child(_new_symbol_dialog)
	_computer_dialog = ComputerDialog.new()
	_computer_dialog.computer_added.connect(_on_computer_added)
	_computer_dialog.computer_edited.connect(func(key: String) -> void:
		_status.text = "Changed the computer of '%s'." % key)
	add_child(_computer_dialog)
	_new_map_dialog = NewMapDialog.new()
	_new_map_dialog.map_created.connect(func(doc: MapDocument) -> void:
		_add_tab(doc)
		_browser.refresh())
	add_child(_new_map_dialog)
	_palette_editor = PaletteEditor.new()
	_palette_editor.files_changed.connect(_on_palette_files_changed)
	_palette_editor.open_map_requested.connect(func(ref: DataIndex.MapgenRef) -> void: open_ref(ref))
	add_child(_palette_editor)
	_sync_dialog = SyncDialog.new()
	_sync_dialog.files_changed.connect(_on_sync_files_changed)
	add_child(_sync_dialog)
	_cell_menu = PopupMenu.new()
	_cell_menu.id_pressed.connect(_on_cell_menu)
	add_child(_cell_menu)
	_door_dialog = ConfirmationDialog.new()
	_door_dialog.title = "Control with a computer"
	_door_dialog.ok_button_text = "Make it a locked metal door"
	_door_dialog.confirmed.connect(func() -> void: lock_door(_pending_door))
	add_child(_door_dialog)
	_unsaved_dialog = ConfirmationDialog.new()
	_unsaved_dialog.title = "Unsaved changes"
	_unsaved_dialog.ok_button_text = "Save"
	_unsaved_dialog.add_button("Discard", true, "discard")
	_unsaved_dialog.confirmed.connect(_on_unsaved_save)
	_unsaved_dialog.custom_action.connect(_on_unsaved_action)
	add_child(_unsaved_dialog)


func _folder_dialog(title: String, handler: Callable) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.title = title
	d.dir_selected.connect(handler)
	add_child(d)
	return d


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

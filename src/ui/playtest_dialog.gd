class_name PlaytestDialog
extends ConfirmationDialog
## Playtest settings: the game binary, the template world, "Own start
## terrain", "Only my mapgen" (only without the former) and "Check in the game before a playtest" (see Playtest and
## AppSettings). OK writes them into the settings it was opened with and
## emits settings_changed.

signal settings_changed

var binary: LineEdit
var world: OptionButton
var own_terrain: CheckBox
var strong: CheckBox
var no_monsters: CheckBox
var daylight: CheckBox
var reveal: CheckBox
var only_mine: CheckBox
var start_outside: CheckBox
var check_first: CheckBox

var _settings: AppSettings
var _bn := ""
var _found: Label
var _file_dialog: FileDialog
## AppSettings.playtest_world values, by world item index.
var _world_values := PackedStringArray()


func _init() -> void:
	title = "Playtest settings"
	min_size = Vector2i(560, 0)
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(_label("Game binary (empty: find it in the BN folder)"))
	var row := HBoxContainer.new()
	box.add_child(row)
	binary = LineEdit.new()
	binary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binary.text_changed.connect(func(_t: String) -> void: _update_found())
	row.add_child(binary)
	var browse := Button.new()
	browse.text = "Browse..."
	browse.pressed.connect(func() -> void:
		if binary.text:
			_file_dialog.current_path = binary.text
		_file_dialog.popup_centered_ratio(0.6))
	row.add_child(browse)
	_found = _label("")
	_found.modulate = Color(1, 1, 1, 0.6)
	_found.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_found)
	box.add_child(_label("Template world (the playtest world copies its options and mods)"))
	world = OptionButton.new()
	box.add_child(world)
	own_terrain = CheckBox.new()
	own_terrain.text = "Own start terrain: start in the playtest's own copy of the building, always on my map"
	own_terrain.toggled.connect(func(_on: bool) -> void: _update_only_mine())
	box.add_child(own_terrain)
	only_mine = CheckBox.new()
	only_mine.text = "Only my mapgen: disable the other mapgens of the map's ids (without own start terrain)"
	box.add_child(only_mine)
	start_outside = CheckBox.new()
	start_outside.text = "Start outside: on open ground near the building (a start inside removes the monsters in view)"
	box.add_child(start_outside)
	strong = CheckBox.new()
	strong.text = "Strong character: high skills, stat traits, gear and loaded guns"
	box.add_child(strong)
	no_monsters = CheckBox.new()
	no_monsters.text = "No monsters: no monster spawns in the playtest world"
	box.add_child(no_monsters)
	daylight = CheckBox.new()
	daylight.text = "Start in daylight"
	box.add_child(daylight)
	reveal = CheckBox.new()
	reveal.text = "Reveal the building on the overmap"
	box.add_child(reveal)
	check_first = CheckBox.new()
	check_first.text = "Check in the game before a playtest (about 12 s); refuse to start on errors in my files"
	box.add_child(check_first)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Choose the Cataclysm-BN game binary"
	_file_dialog.file_selected.connect(func(path: String) -> void:
		binary.text = path
		_update_found())
	add_child(_file_dialog)
	confirmed.connect(apply)


## Fills the fields from [param settings]; [param user_dir] is BN's data
## folder holding the worlds.
func setup(settings: AppSettings, bn: String, user_dir: String) -> void:
	_settings = settings
	_bn = bn
	binary.text = settings.game_binary
	_update_found()
	world.clear()
	_world_values.clear()
	var fallback := Playtest.default_template_world(user_dir)
	world.add_item("Default (%s)" % (fallback if fallback else "none: BN's default options"))
	_world_values.append("")
	world.add_item("None: BN's default options, no extra mods")
	_world_values.append(AppSettings.NO_WORLD)
	for w in Playtest.worlds(user_dir):
		world.add_item(w)
		_world_values.append(w)
	var at := _world_values.find(settings.playtest_world)
	if at < 0:
		# A saved world that is gone: keep it, marked.
		world.add_item(settings.playtest_world + " (not found)")
		_world_values.append(settings.playtest_world)
		at = _world_values.size() - 1
	world.select(at)
	own_terrain.button_pressed = settings.own_start_terrain
	only_mine.button_pressed = settings.only_my_mapgen
	_update_only_mine()
	start_outside.button_pressed = settings.playtest_start_outside
	check_first.button_pressed = settings.check_before_playtest
	strong.button_pressed = settings.strong_character
	no_monsters.button_pressed = settings.no_monsters
	daylight.button_pressed = settings.start_in_daylight
	reveal.button_pressed = settings.reveal_building


func open(settings: AppSettings, bn: String, user_dir: String) -> void:
	setup(settings, bn, user_dir)
	popup_centered()


## Writes the fields into the settings.
func apply() -> void:
	_settings.game_binary = binary.text.strip_edges()
	_settings.playtest_world = _world_values[world.selected] if world.selected >= 0 else ""
	_settings.own_start_terrain = own_terrain.button_pressed
	_settings.only_my_mapgen = only_mine.button_pressed
	_settings.playtest_start_outside = start_outside.button_pressed
	_settings.check_before_playtest = check_first.button_pressed
	_settings.strong_character = strong.button_pressed
	_settings.no_monsters = no_monsters.button_pressed
	_settings.start_in_daylight = daylight.button_pressed
	_settings.reveal_building = reveal.button_pressed
	settings_changed.emit()


## "Only my mapgen" only matters without own start terrain.
func _update_only_mine() -> void:
	only_mine.disabled = own_terrain.button_pressed


func _update_found() -> void:
	var path := binary.text.strip_edges()
	if path and not FileAccess.file_exists(path):
		var other := Playtest.find_binary(_bn)
		_found.text = "Not found. Without it: " + (other if other else "no game binary found")
	elif path.is_empty():
		var found := Playtest.find_binary(_bn)
		_found.text = "Found: " + found if found else "No game binary found in the BN folder: choose one."
	else:
		_found.text = ""


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

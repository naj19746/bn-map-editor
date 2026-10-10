class_name Playtest
extends RefCounted
## Builds a throwaway copy of BN that starts the player in one map (see
## PLAYTEST.MD), and launches the game on it. No nodes.
##
## Everything goes under one folder (user://playtest by default), rebuilt on
## each build:
## - overlay/: what --basepath points at. BN's top-level folders as symlinks,
##   except the folders leading to a file the playtest replaces or adds,
##   which are real folders of symlinks. It holds every workspace file and
##   every open file with unsaved edits (as compose() writes them), and the
##   bnme_playtest mod: a start location at the map, Play Now's scenario
##   (evacuee) sent there and whitelisted as the only one, and an overmap
##   special that places the map (or its building) in overmap (0, 0). With
##   "own start terrain" the mod also has overmap terrains of its own
##   (bnme_playtest_<id>, copying the building's) and copies of their mapgens
##   (the map alone for its own ids), which only the special places; without
##   it, the other mapgens of the map's ids get "disabled": true ("only my
##   mapgen") in copies of their files.
##   For a map above or below its building's ground floor the player starts
##   on the ground floor under it, and a Lua hook (preload.lua) moves them
##   up or down to the map when the game starts.
## - userdir/: what --userdir points at: the user's BN config files, links to
##   their tilesets, fonts and sound packs, and one empty world, so Play Now
##   picks it without asking.
##
## Nothing is ever written into BN or the workspace: every write checks that
## no folder on its way is a symlink. Removing the old build removes links
## without following them.
##
## A mod whose modinfo "path" leaves its own folder (core's is "../../json")
## gets a real folder: BN joins the path to the folder as text and the
## system resolves ".." after following links, so through a linked folder
## it would read BN's files and miss the overlay's.

const MOD_ID := "bnme_playtest"
const WORLD := "Playtest"
const START_LOCATION := "bnme_playtest"
const SPECIAL := "bnme_playtest_special"
## The overmap terrain the player starts on with Options.start_outside: an
## open grass tile the playtest's special places START_GAP tiles from the
## building.
const START_TILE := "bnme_playtest_start"
## Empty overmap tiles between the building and START_TILE. A new game removes
## every monster with a clear path to the player within 40 tiles
## (game::start_game), and BN's clear_path sees through floors between levels:
## two tiles keep every spot of START_TILE more than 40 tiles from the building.
const START_GAP := 2
## The scenario Play Now uses (scenario::generic).
const SCENARIO := "evacuee"
const MOD_FILE := "playtest.json"
## The prefix of the playtest's own overmap terrain ids ("own start terrain"):
## bnme_playtest_<id> copies <id>.
const OWN_PREFIX := "bnme_playtest_"
## The mod folder holding the copies of the mapgens the own terrain uses, at
## copies/<the original's relative path>.
const MOD_COPIES := "copies"
## The Lua script that moves the player off the ground floor (BN runs a
## mod's preload.lua when its modinfo has "lua_api_version").
const MOD_LUA := "preload.lua"
## BN's LUA_API_VERSION (src/catalua.cpp). Another version only makes BN
## warn on load.
const LUA_API_VERSION := 2
## The profession Play Now gets (the evacuee override's only one).
const PROFESSION := "bnme_playtest"
## INITIAL_TIME when Options.daylight: ten in the morning, light in every season.
const DAYLIGHT_HOUR := 10
## The level the profession gives each of its skills (BN's maximum is 10).
const SKILL_LEVEL := 8
## Skill ids of the strong character (data/json/skills.json).
const STRONG_SKILLS := ["melee", "bashing", "cutting", "stabbing", "dodge", "gun", "rifle", "pistol",
	"shotgun", "throw", "firstaid", "survival", "mechanics", "electronics", "fabrication", "computer",
	"driving"]
## Traits (data/json/mutations): +4 to each stat, and the rest. avatar::create
## gives a profession's "traits" without a points check.
const STRONG_TRAITS := ["STR_UP_4", "DEX_UP_4", "PER_UP_4", "INT_UP_4", "TOUGH", "FASTHEALER", "QUICK",
	"PAINRESIST", "NIGHTVISION", "GOODHEARING"]
## CBMs (data/json/bionics): added by avatar::create without an installation,
## with power full. bio_lockpick opens most locks with no skill (50 J a try).
const STRONG_CBMS := ["bio_armor_head", "bio_armor_torso", "bio_armor_arms", "bio_armor_legs",
	"bio_power_storage_mkII", "bio_power_storage_mkII", "bio_lockpick"]
## Items of the profession's "both" group. Worn in this order: avatar::create
## drops what doesn't fit over what is already worn, so no two share a layer
## and a body part.
const STRONG_ITEMS := ["tank_top", "briefs", "socks", "gloves_tactical", "boots_combat", "armor_riot",
	"tac_fullhelmet", "molle_pack", "tool_belt", "legpouch_large", "ear_plugs", "lighter", "picklocks",
	"crowbar", "hammer", "screwdriver_set", "toolbox", "1st_aid", "water_clean", "mre_beef_box"]
## Item group entries (item_factory.cpp add_entry): "ammo-item" and "charges"
## load a gun's default magazine (or fill a magazine), "count" repeats.
## "container-item" puts the item in another: a flashlight takes a battery
## cell (a magazine) and would spawn empty on its own, as charged_flashlight
## in BN's professions.json does.
## "custom-flags": no_auto_equip keeps it in the pack (it would not fit over
## the helmet), auto_wield wields it.
const STRONG_ENTRIES := [
	{"item": "mask_gas", "custom-flags": ["no_auto_equip"]},
	{"item": "katana", "custom-flags": ["auto_wield"]},
	{"item": "m4a1", "ammo-item": "556", "charges": 30},
	{"item": "stanag30", "ammo-item": "556", "charges": 30, "count": 3},
	{"item": "556", "charges": 90},
	{"item": "glock_19", "ammo-item": "9mm", "charges": 15},
	{"item": "glockmag", "ammo-item": "9mm", "charges": 15, "count": 3},
	{"item": "9mm", "charges": 45},
	{"item": "mossberg_500", "ammo-item": "shot_00", "charges": 6},
	{"item": "shot_00", "charges": 24},
	{"item": "grenade", "count": 5},
	{"item": "light_disposable_cell", "ammo-item": "battery", "charges": 300, "container-item": "flashlight"},
	{"item": "light_disposable_cell", "ammo-item": "battery", "charges": 300},
]
## A game flag (a BN patch) that starts a new game in a world with no saves, as
## Play Now! (Default Scenario) does. Without it the player starts it by hand.
const NEW_GAME_FLAG := "--new-game"
## The game flag that loads the data in test mode and exits.
const CHECK_FLAG := "--check-mods"
## Config files copied from the user's BN config folder: the game's look and
## controls, and no language prompt (a fresh config asks for one).
const CONFIG_FILES := ["options.json", "fonts.json", "keybindings.json"]
## Folders of the user's BN data folder linked into the userdir: tilesets,
## fonts and sound packs installed there.
const USER_LINKS := ["gfx", "font", "sound"]


class Options:
	## The folder everything is built in.
	var root := Playtest.default_root()
	## Give the playtest overmap terrains of its own (OWN_PREFIX + id, copying
	## the map's and its building's), placed only by the playtest's special,
	## with copies of their mapgens: the player always starts in the special,
	## on the playtested map, and nothing is disabled. Off: the map's own ids,
	## which cities place too (only_my_mapgen then matters).
	var own_start_terrain := true
	## Disable the other mapgens of the map's ids (only without
	## own_start_terrain).
	var only_my_mapgen := true
	## Start on START_TILE, outside and away from the building, instead of on
	## its ground floor: a start inside removes the monsters the player could
	## see from there (START_GAP).
	var start_outside := true
	## A world folder whose worldoptions.json and mods.json the playtest
	## world starts from, or "".
	var template_world := ""
	## The user's BN config folder (options.json, ...), or "".
	var bn_config_dir := Playtest.default_config_dir()
	## The user's BN data folder (gfx, font, sound), or "".
	var bn_user_dir := Playtest.default_user_dir()
	## The editor's selected mods, in order.
	var mods := PackedStringArray()
	## The player is the mod's profession: high skills, stat traits, gear,
	## loaded guns and CBMs (ids the selected mods lack are left out, with a
	## warning).
	var strong_character := true
	## SPAWN_DENSITY 0 in the world options: monsters don't spawn.
	var no_monsters := false
	## INITIAL_TIME at DAYLIGHT_HOUR in the world options.
	var daylight := true
	## The Lua hook reveals the special's area on the overmap when the game
	## starts.
	var reveal_building := true


## What build() made, or why it couldn't.
class Build:
	var error := ""
	var warnings := PackedStringArray()
	var basepath := ""
	var userdir := ""
	## The overmap terrain ids the player starts on (START_TILE with
	## Options.start_outside).
	var start_terrain := PackedStringArray()
	## For a map that isn't on its building's ground floor: the ids the Lua
	## hook moves the player to when the game starts, on level move_to_z.
	## Empty otherwise.
	var move_to := PackedStringArray()
	var move_to_z := 0
	## The competing mapgens given "disabled": true, as "rel#index".
	var disabled := PackedStringArray()
	## With Options.own_start_terrain: each overmap terrain id the playtest
	## made -> the id it copies (start_terrain, move_to and the special use
	## them). Empty otherwise.
	var own_terrain := {}
	## The mapgens copied for own_terrain, as "rel#index", in order.
	var copied := PackedStringArray()
	## The data files the overlay replaces or adds (relative, sorted).
	var files := PackedStringArray()
	## The playtest world's mods.json.
	var world_mods := PackedStringArray()
	## Where the game may write its debug.log: the userdir's config folder,
	## and the user's own config folder (XDG builds ignore --userdir there).
	var log_paths := PackedStringArray()
	## Whether launch() passed --new-game: the game starts the playtest itself.
	var new_game := false
	## What the options applied, for the report ("strong character: 17 skills
	## ...", "no monsters", ...).
	var applied := PackedStringArray()
	## The radius (overmap tiles) the Lua hook reveals around the player, and
	## the levels it does that on; 0 when it doesn't reveal.
	var reveal_radius := 0
	var reveal_levels: Array[int] = []

	func ok() -> bool:
		return error.is_empty()

	## The game's command line arguments.
	func args(start_new := false) -> PackedStringArray:
		var out := PackedStringArray(["--basepath", basepath + "/", "--userdir", userdir + "/"])
		if start_new:
			out.append_array([Playtest.NEW_GAME_FLAG, Playtest.WORLD])
		return out

	## The arguments of a data check of the playtest mod (and so of BN core,
	## the map's mod and every workspace file in them).
	func check_args() -> PackedStringArray:
		var out := args()
		out.append_array([Playtest.CHECK_FLAG, Playtest.MOD_ID])
		return out


## supports_new_game's answers by "path@modified time@size".
static var _new_game_cache := {}


static func default_root() -> String:
	return OS.get_user_data_dir().path_join("playtest")


## BN's data folder for the user (saves, tilesets): XDG's, else ~/.cataclysm-bn.
static func default_user_dir() -> String:
	var home := OS.get_environment("HOME")
	var xdg := OS.get_environment("XDG_DATA_HOME")
	var dir := xdg.path_join("cataclysm-bn") if xdg else home.path_join(".local/share/cataclysm-bn")
	if DirAccess.dir_exists_absolute(dir):
		return dir
	dir = home.path_join(".cataclysm-bn")
	return dir if home and DirAccess.dir_exists_absolute(dir) else ""


## BN's config folder for the user: XDG's, else <user dir>/config.
static func default_config_dir() -> String:
	var home := OS.get_environment("HOME")
	var xdg := OS.get_environment("XDG_CONFIG_HOME")
	var dir := xdg.path_join("cataclysm-bn") if xdg else home.path_join(".config/cataclysm-bn")
	if DirAccess.dir_exists_absolute(dir):
		return dir
	var user := default_user_dir()
	return user.path_join("config") if user and DirAccess.dir_exists_absolute(user.path_join("config")) else ""


## The game binary to run: [param saved] when that file exists, else the
## first found of <bn>/cataclysm-bn-tiles, the newest
## <bn>/out/build/*/src/cataclysm-bn-tiles, then the same two for the curses
## build (cataclysm-bn). "" when there's none.
static func find_binary(bn: String, saved := "") -> String:
	if saved and FileAccess.file_exists(saved):
		return saved
	if bn.is_empty():
		return ""
	var exe := ".exe" if OS.get_name() == "Windows" else ""
	for name in ["cataclysm-bn-tiles", "cataclysm-bn"]:
		if FileAccess.file_exists(bn.path_join(name + exe)):
			return bn.path_join(name + exe)
		var newest := ""
		var newest_time := -1
		var builds := bn.path_join("out/build")
		for d in DirAccess.get_directories_at(builds) if DirAccess.dir_exists_absolute(builds) else PackedStringArray():
			var path := builds.path_join(d).path_join("src").path_join(name + exe)
			if FileAccess.file_exists(path) and FileAccess.get_modified_time(path) > newest_time:
				newest = path
				newest_time = FileAccess.get_modified_time(path)
		if newest:
			return newest
	return ""


## The worlds in [param user_dir]'s save folder (folders holding
## worldoptions.json or master.gsav, as BN's worldfactory looks), sorted.
static func worlds(user_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if user_dir.is_empty():
		return out
	var save := user_dir.path_join("save")
	for d in DirAccess.get_directories_at(save):
		var dir := save.path_join(d)
		if FileAccess.file_exists(dir.path_join("worldoptions.json")) or FileAccess.file_exists(dir.path_join("master.gsav")):
			out.append(d)
	out.sort()
	return out


## The template world when none is chosen: Rosier if [param user_dir] has
## it, else the first world, else "".
static func default_template_world(user_dir: String) -> String:
	var found := worlds(user_dir)
	if found.has("Rosier"):
		return "Rosier"
	return found[0] if found.size() else ""


## One error or warning of the game's debug.log.
class LogEntry:
	## "ERROR" or "WARNING".
	var level := ""
	var time := ""
	## The message, without the time and level (it may span lines).
	var text := ""

	func describe() -> String:
		return "%s %s: %s" % [time, level.to_lower(), text]


## The ERROR and WARNING entries of debug.log [param text], in order. An
## entry starts with "HH:MM:SS.mmm LEVEL [CLASS] : " and runs to the next
## one; a backtrace before the message ("(continued from above) ERROR: ")
## is left out.
static func read_log(text: String) -> Array[LogEntry]:
	var out: Array[LogEntry] = []
	var head := RegEx.create_from_string("^(\\d\\d:\\d\\d:\\d\\d\\.\\d+) (\\w*)[^:]*: ?")
	var current: LogEntry = null
	var lines := PackedStringArray()
	for line in text.split("\n") + PackedStringArray(["00:00:00.000 INFO : end"]):
		var m := head.search(line)
		if m == null:
			if current:
				lines.append(line)
			continue
		if current:
			var body := "\n".join(lines).strip_edges()
			var resume := "(continued from above) %s: " % current.level
			var cut := body.find(resume)
			var trace := body.find("(error message will follow backtrace)")
			if cut >= 0 and trace >= 0 and trace < cut:
				body = body.substr(0, trace) + body.substr(cut + resume.length())
			current.text = body.strip_edges()
			out.append(current)
			current = null
		if m.get_string(2) == "ERROR" or m.get_string(2) == "WARNING":
			current = LogEntry.new()
			current.time = m.get_string(1)
			current.level = m.get_string(2)
			lines = PackedStringArray([line.substr(m.get_end())])
	return out


## The debug.log of [param build]'s game, written at or after unix time
## [param since]: the newest of build.log_paths. "" if none.
static func find_log(build: Build, since: int) -> String:
	var best := ""
	var best_time := since - 1
	for path in build.log_paths:
		if FileAccess.file_exists(path) and FileAccess.get_modified_time(path) > best_time:
			best = path
			best_time = FileAccess.get_modified_time(path)
	return best


## What a debug.log entry may name that the user made: the data files the
## playtest replaced or added (b.files), and the ids of the objects in the
## workspace and in unsaved files (ids, om_terrain, nested and update
## mapgen ids), plus the playtest mod's (its own overmap terrains too, with
## their rotations) and the files of the mapgens it copied (the map's and
## its building's; a copy's path in MOD_COPIES holds its original's).
static func log_names(session: EditSession, b: Build) -> PackedStringArray:
	var names := PackedStringArray([MOD_ID, SPECIAL])
	for own: String in b.own_terrain:
		names.append(own)
		for dir: String in DataIndex.DIRECTIONS:
			names.append(own + "_" + dir)
	# The files of the copied mapgens: the map's and its building's levels.
	for c in b.copied:
		if not names.has(c.get_slice("#", 0)):
			names.append(c.get_slice("#", 0))
	var objects := []
	for rel in b.files:
		if rel.begins_with("data/mods/" + MOD_ID + "/"):
			continue
		names.append(rel)
		if session.files.has(rel):
			objects.append_array(session.files[rel].objects)
		else:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(b.basepath.path_join(rel)))
			if parsed is Array:
				objects.append_array(parsed)
			elif parsed is Dictionary:
				objects.append(parsed)
	for o: Variant in objects:
		if not o is Dictionary:
			continue
		for key in ["id", "abstract", "om_terrain", "nested_mapgen_id", "update_mapgen_id"]:
			var v: Variant = o.get(key)
			for id: Variant in (v if v is Array else [v]):
				# om_terrain may be a grid of rows.
				for one: Variant in (id if id is Array else [id]):
					if one is String and one and not names.has(one):
						names.append(one)
	return names


## [param entries] with the playtest's own names put back (copies; the
## entries are left alone): each id of b.own_terrain at the start of a word
## as the id it copies ("bnme_playtest_house_north" -> "house_north"), and a
## copied mapgen's file as its original's path, with a note saying so. Line
## numbers stay the copy's.
static func real_names(entries: Array[LogEntry], b: Build) -> Array[LogEntry]:
	var out: Array[LogEntry] = []
	var copies := "data/mods/%s/%s/" % [MOD_ID, MOD_COPIES]
	var owns: Array = b.own_terrain.keys()
	# Longest first: a longer id may begin with a shorter one.
	owns.sort_custom(func(x: String, y: String) -> bool: return x.length() > y.length())
	for e in entries:
		var text := e.text
		var notes := PackedStringArray()
		for own: String in owns:
			var at := text.find(own)
			while at >= 0:
				if at == 0 or not _word_char(text[at - 1]):
					text = text.substr(0, at) + b.own_terrain[own] + text.substr(at + own.length())
					var note := "%s is the playtest's %s" % [b.own_terrain[own], own]
					if not notes.has(note):
						notes.append(note)
				at = text.find(own, at + 1)
		if text.contains(copies):
			if b.basepath:
				text = text.replace(b.basepath.path_join(copies), "")
			text = text.replace(copies, "")
			notes.append("the file is the playtest's copy of yours (line numbers are the copy's)")
		var c := LogEntry.new()
		c.level = e.level
		c.time = e.time
		c.text = text + ("\n(%s)" % "; ".join(notes) if notes.size() else "")
		out.append(c)
	return out


## The entries of [param entries] that mention one of [param names] (a whole
## id: not inside a longer word).
static func entries_naming(entries: Array[LogEntry], names: PackedStringArray) -> Array[LogEntry]:
	var out: Array[LogEntry] = []
	for e in entries:
		for n in names:
			if _mentions(e.text, n):
				out.append(e)
				break
	return out


static func _mentions(text: String, name: String) -> bool:
	var at := text.find(name)
	while at >= 0:
		var before := text[at - 1] if at > 0 else " "
		var end := at + name.length()
		var after := text[end] if end < text.length() else " "
		if not _word_char(before) and not _word_char(after):
			return true
		at = text.find(name, at + 1)
	return false


static func _word_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")


## Whether [param binary]'s --help lists NEW_GAME_FLAG. Asked once per file
## and modification time.
static func supports_new_game(binary: String) -> bool:
	var size := FileAccess.get_size(binary) if FileAccess.file_exists(binary) else -1
	var key := "%s@%d@%d" % [binary, FileAccess.get_modified_time(binary), size]
	if not _new_game_cache.has(key):
		var out := []
		var flag := RegEx.create_from_string("(?m)^" + NEW_GAME_FLAG + "( |$)")
		_new_game_cache[key] = OS.execute(binary, ["--help"], out) == 0 and flag.search("".join(out)) != null
	return _new_game_cache[key]


## Starts the game on [param build], with NEW_GAME_FLAG when the game has it
## (sets [member Build.new_game]). Returns its process id, or -1.
static func launch(binary: String, build: Build) -> int:
	build.new_game = supports_new_game(binary)
	return OS.create_process(binary, build.args(build.new_game))


## What a data check found.
class CheckResult:
	## Why the check didn't run or didn't get to load the data, or "".
	var error := ""
	var exit_code := 0
	## Seconds it took.
	var seconds := 0.0
	## The game's stdout and stderr.
	var output := ""
	## The debug.log the entries are from, or "".
	var log_path := ""
	## Every error and warning of the check.
	var entries: Array[LogEntry] = []
	## The entries that name the user's files or ids.
	var mine: Array[LogEntry] = []

	## The number of ERROR entries in [member mine].
	func my_errors() -> int:
		return mine.filter(func(e: LogEntry) -> bool: return e.level == "ERROR").size()


## A data check of a build running in the game (CHECK_FLAG): start() it, poll()
## until it returns true, then read result. check() does that blocking. The
## game's debug.log is appended to, so only what the check wrote is read.
class Check:
	var result := CheckResult.new()
	var _build: Build
	var _names := PackedStringArray()
	var _pid := -1
	var _pipes := {}
	var _started := 0
	## Each of the build's log paths -> its size before the check.
	var _sizes := {}

	## Starts [param binary] on [param build]; [param names] are what the log
	## is matched against (Playtest.log_names). False (result.error says why)
	## when it can't start.
	func start(binary: String, build: Build, names: PackedStringArray) -> bool:
		_build = build
		_names = names
		for path in build.log_paths:
			_sizes[path] = FileAccess.get_size(path) if FileAccess.file_exists(path) else 0
		_started = Time.get_ticks_msec()
		_pipes = OS.execute_with_pipe(binary, build.check_args(), false)
		if _pipes.is_empty():
			result.error = "Can't start %s." % binary
			return false
		_pid = _pipes.pid
		return true

	## Whether the game has exited (the result is then complete).
	func poll() -> bool:
		if _pid < 0:
			return true
		if OS.is_process_running(_pid):
			return false
		_finish()
		return true

	## Stops the game, if it still runs.
	func cancel() -> void:
		if _pid >= 0 and OS.is_process_running(_pid):
			OS.kill(_pid)
		_pid = -1
		result.error = "Cancelled."

	func _finish() -> void:
		result.seconds = (Time.get_ticks_msec() - _started) / 1000.0
		result.exit_code = OS.get_process_exit_code(_pid)
		_pid = -1
		var out: FileAccess = _pipes.get("stdio")
		var err: FileAccess = _pipes.get("stderr")
		var text := out.get_as_text() if out else ""
		var errors := err.get_as_text() if err else ""
		result.output = (text + errors).strip_edges()
		# Json errors that stop the load only go to stderr (exit code 0).
		var stop := errors.find("Error loading data:")
		if stop >= 0:
			var e := LogEntry.new()
			e.level = "ERROR"
			e.time = "stderr"
			e.text = errors.substr(stop).strip_edges()
			result.entries.append(e)
		for path in _build.log_paths:
			if not FileAccess.file_exists(path):
				continue
			var bytes := FileAccess.get_file_as_bytes(path)
			var at: int = _sizes.get(path, 0)
			if bytes.size() < at:
				at = 0
			if bytes.size() == at:
				continue
			result.log_path = path
			result.entries.append_array(Playtest.read_log(bytes.slice(at).get_string_from_utf8()))
			break
		result.mine = Playtest.real_names(Playtest.entries_naming(result.entries, _names), _build)
		if not result.output.contains("Checking mod"):
			result.error = "The game didn't get to load the data (exit code %d)." % result.exit_code
			for e in result.entries:
				if e.level == "ERROR":
					result.error += " " + e.text.get_slice("\n", 0)
					break
			if result.entries.is_empty() and result.output:
				result.error += " " + result.output.get_slice("\n", 0)


## Loads the data of [param build] in [param binary] and exits (CHECK_FLAG),
## waiting for it: about 12 s on BN core. A tiles build needs a display to
## start, but opens no window. [param names] as in Check.start.
static func check(binary: String, build: Build, names: PackedStringArray) -> CheckResult:
	var c := Check.new()
	if c.start(binary, build, names):
		while not c.poll():
			OS.delay_msec(50)
	return c.result


## Builds a playtest of [param ref] (an om_terrain mapgen) with the open
## files and workspace of [param session].
static func build(session: EditSession, ref: DataIndex.MapgenRef, options: Options) -> Build:
	var b := Build.new()
	var index := session.index
	var root := options.root.simplify_path()
	b.error = _check_target(index, ref)
	if not b.error:
		b.error = _check_root(root, [index.bn_path, session.workspace.root])
	if b.error:
		return b
	var overlay := root.path_join("overlay")
	b.basepath = overlay
	b.userdir = root.path_join("userdir")
	for dir in [overlay, b.userdir]:
		b.error = _remove_tree(dir)
		if b.error:
			return b
	b.error = _make_overlay(index.bn_path, overlay)
	if b.error:
		return b

	# rel -> text of every data file the overlay replaces or adds.
	var texts := {}
	var ws_files := PackedStringArray()
	if DirAccess.dir_exists_absolute(session.workspace.root):
		WorkspaceSync._collect(session.workspace.root, "", ws_files)
	for rel in ws_files:
		if rel.begins_with("data/"):
			texts[rel] = session.files[rel].compose() if session.files.has(rel) \
					else FileAccess.get_file_as_string(session.workspace.path(rel))
	for rel: String in session.files:
		if session.files[rel].is_dirty():
			texts[rel] = session.files[rel].compose()
	# Own start terrain needs an overmap_terrain to copy for each of the
	# map's ids (a LINEAR terrain's pieces have none of their own).
	var own := options.own_start_terrain
	for id in ref.ids if own else PackedStringArray():
		if not index.overmap_terrain.has(id):
			own = false
			b.warnings.append("no overmap_terrain is named %s (a piece of a LINEAR terrain?): the playtest uses the map's own ids" % id)
			break
	if options.only_my_mapgen and not own:
		b.error = _disable_competitors(session, ref, texts, b)
		if b.error:
			return b
	var mod_dir := "data/mods/" + MOD_ID
	var special := _special(session, ref, b)
	if special.is_empty():
		return b
	var own_oters := []
	if own:
		own_oters = _own_terrain(session, ref, texts, special, b)
		if b.error:
			return b
	var start_objects := _start_outside(special, b) if options.start_outside else []
	var reveal_note := _reveal_area(special, options, b)

	# The mods the world must list: the map's and every replaced or added
	# file's, which BN only reads when the world has them. A mod only the
	# workspace has isn't in the index's catalog, so its modinfo (as written
	# to the overlay) is read here.
	var catalog := ModCatalog.new()
	catalog.bn_path = index.catalog.bn_path
	catalog.mods = index.catalog.mods.duplicate()
	var ws_mods := {}
	for rel: String in texts:
		if rel.begins_with("data/mods/") and rel.get_file() == "modinfo.json":
			for id in catalog.add_modinfo(overlay.path_join(rel), texts[rel]):
				ws_mods[id] = rel.get_base_dir()
	var added := {}
	var sources := PackedStringArray([ref.source.path])
	sources.append_array(PackedStringArray(texts.keys()))
	# The copied mapgens' palettes and chunks are in their files' mods.
	for c in b.copied:
		sources.append(c.get_slice("#", 0))
	for rel in sources:
		var mod := _mod_of(index, catalog, rel, ws_mods)
		if not mod.is_empty() and not catalog.get_mod(mod).core and not added.has(mod):
			added[mod] = rel

	texts[mod_dir.path_join("modinfo.json")] = BnJson.stringify([
		_modinfo(catalog, _mod_of(index, catalog, ref.source.path, ws_mods),
				b.move_to.size() > 0 or b.reveal_radius > 0)])
	var scenario := {"type": "scenario", "id": SCENARIO, "copy-from": SCENARIO, "start_name": "Playtest",
			"allowed_locs": [START_LOCATION], "flags": []}
	var profession: Array = []
	if options.strong_character:
		profession.append(_profession(index, b))
		scenario["professions"] = [PROFESSION]
	if reveal_note:
		b.applied.append(reveal_note)
	var start_location := {"type": "start_location", "id": START_LOCATION, "name": "Playtest: " + ref.title(),
			"terrain": Array(b.start_terrain)}
	if options.start_outside:
		start_location["flags"] = ["ALLOW_OUTSIDE"]
	texts[mod_dir.path_join(MOD_FILE)] = BnJson.stringify([
		start_location,
		scenario,
		# Only evacuee can be picked: the main menu's plain "Play Now!" (and
		# Random Character) picks a random scenario.
		{"type": "SCENARIO_BLACKLIST", "subtype": "whitelist", "scenarios": [SCENARIO]},
	] + profession + own_oters + [special] + start_objects)

	for info: ModCatalog.ModInfo in index.catalog.mods.values():
		var folder := info.info_file.get_base_dir()
		if info.path != folder and not info.path.begins_with(folder + "/"):
			b.error = _materialize(index.bn_path, overlay, index.relative_path(folder))
			if b.error:
				return b
	if b.move_to.size() or b.reveal_radius > 0:
		texts[mod_dir.path_join(MOD_LUA)] = _lua(b.move_to, b.move_to_z, b.reveal_radius, b.reveal_levels)
	var rels := texts.keys()
	rels.sort()
	for rel: String in rels:
		var text: String = texts[rel]
		if rel.ends_with(".json"):
			var formatted := JsonFormatter.format(text)
			if not formatted.ok():
				b.error = "%s: %s" % [rel, formatted.error]
				return b
			text = formatted.text
		b.error = _write(index.bn_path, overlay, rel, text)
		if b.error:
			return b
		b.files.append(rel)

	b.error = _make_userdir(catalog, options, b, added)
	b.log_paths.append(b.userdir.path_join("config/debug.log"))
	if options.bn_config_dir:
		b.log_paths.append(options.bn_config_dir.path_join("debug.log"))
	return b


static func _check_target(index: DataIndex, ref: DataIndex.MapgenRef) -> String:
	if ref == null or ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		return "only an om_terrain map can be playtested (a chunk only appears inside one)"
	if ref.disabled:
		return "%s is disabled (\"disabled\": true or a weight of 0), so BN never uses it" % ref.title()
	for id in ref.ids:
		if not index.has_overmap_terrain(id):
			return "no overmap_terrain defines %s, so BN can't place it" % id
	return ""


## Why [param root] can't hold a playtest, or "".
static func _check_root(root: String, keep_out: Array) -> String:
	if root.is_empty() or root == "/":
		return "no playtest folder set"
	for other: String in keep_out:
		var o := other.simplify_path()
		if o and (root == o or root.begins_with(o + "/") or o.begins_with(root + "/")):
			return "the playtest folder can't be inside %s or contain it: %s" % [o, root]
	return ""


## overlay/ with a link to each of BN's top-level entries.
static func _make_overlay(bn: String, overlay: String) -> String:
	var err := DirAccess.make_dir_recursive_absolute(overlay)
	if err != OK:
		return "can't create %s: %s" % [overlay, error_string(err)]
	return _link_children(bn, overlay)


## Links every entry of [param from] (but hidden ones) into [param to].
static func _link_children(from: String, to: String) -> String:
	var dir := DirAccess.open(to)
	if dir == null:
		return "can't open " + to
	var names := DirAccess.get_directories_at(from) + DirAccess.get_files_at(from)
	for n in names:
		if n.begins_with("."):
			continue
		var err := dir.create_link(from.path_join(n), to.path_join(n))
		if err != OK:
			return "can't link %s: %s" % [to.path_join(n), error_string(err)]
	return ""


## Makes overlay folder [param rel] and every folder above it real: a linked
## folder becomes a real one holding links to the BN folder's entries; a
## folder BN doesn't have is created empty.
static func _materialize(bn: String, overlay: String, rel: String) -> String:
	var at := ""
	var dir := DirAccess.open(overlay)
	for part in rel.split("/", false):
		at = at.path_join(part) if at else part
		var path := overlay.path_join(at)
		if dir.is_link(path):
			var err := DirAccess.remove_absolute(path)
			if err == OK:
				err = DirAccess.make_dir_absolute(path)
			if err != OK:
				return "can't replace the link %s: %s" % [path, error_string(err)]
			var problem := _link_children(bn.path_join(at), path)
			if problem:
				return problem
		elif not DirAccess.dir_exists_absolute(path):
			var err := DirAccess.make_dir_absolute(path)
			if err != OK:
				return "can't create %s: %s" % [path, error_string(err)]
	return ""


## Writes overlay file [param rel], replacing a link there.
static func _write(bn: String, overlay: String, rel: String, text: String) -> String:
	var problem := _materialize(bn, overlay, rel.get_base_dir())
	if problem:
		return problem
	var path := overlay.path_join(rel)
	problem = _check_real(overlay, rel.get_base_dir())
	if problem:
		return problem
	if DirAccess.open(overlay).is_link(path):
		DirAccess.remove_absolute(path)
	return _store(path, text)


## Refuses a write below a linked folder, which would land in BN.
static func _check_real(root: String, rel_dir: String) -> String:
	var dir := DirAccess.open(root)
	var at := root
	for part in rel_dir.split("/", false):
		at = at.path_join(part)
		if dir.is_link(at):
			return "refusing to write through the link " + at
	return ""


static func _store(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "can't write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	f.store_string(text)
	f.close()
	return ""


## Deletes [param path] and everything under it, removing links without
## following them.
static func _remove_tree(path: String) -> String:
	if not DirAccess.dir_exists_absolute(path):
		return ""
	var dir := DirAccess.open(path)
	if dir == null:
		return "can't open " + path
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		var sub := path.path_join(d)
		if dir.is_link(sub):
			DirAccess.remove_absolute(sub)
		else:
			var problem := _remove_tree(sub)
			if problem:
				return problem
	var err := DirAccess.remove_absolute(path)
	return "" if err == OK else "can't remove %s: %s" % [path, error_string(err)]


## Adds "disabled": true to every other enabled mapgen of [param ref]'s ids,
## in [param texts] (taking each file's text from there, the open file or
## disk).
static func _disable_competitors(session: EditSession, ref: DataIndex.MapgenRef, texts: Dictionary,
		b: Build) -> String:
	var index := session.index
	# rel -> object indexes
	var by_file := {}
	for id in ref.ids:
		var oter := _object(session, index.overmap_terrain.get(id))
		if DataIndex.BUILTIN_MAPGENS.has(id) or oter.get("mapgen") is Array:
			b.warnings.append("BN's built-in mapgen for %s can still be picked" % id)
		for r: DataIndex.MapgenRef in index.om_terrain.get(id, []):
			if r == ref or r.disabled:
				continue
			if not by_file.has(r.source.path):
				by_file[r.source.path] = []
			if not by_file[r.source.path].has(r.source.index):
				by_file[r.source.path].append(r.source.index)
	for rel: String in by_file:
		var text: String
		if texts.has(rel):
			text = texts[rel]
		elif session.files.has(rel):
			text = session.files[rel].compose()
		else:
			text = FileAccess.get_file_as_string(index.file_path(rel))
		var err := []
		var f := JsonFile.from_bytes(text.to_utf8_buffer(), rel, err)
		if f == null:
			return err[0]
		var at: Array = by_file[rel]
		at.sort()
		for i: int in at:
			if i >= f.objects.size() or not f.objects[i] is Dictionary:
				return "%s has no object #%d any more" % [rel, i]
			f.touch(i)
			f.objects[i]["disabled"] = true
			b.disabled.append("%s#%d" % [rel, i])
		texts[rel] = f.compose()
	return ""


## The object at [param src] as the session sees it (open files live, others
## read with BnJson, so ints stay ints), or {}.
static func _object(session: EditSession, src: DataIndex.Source) -> Dictionary:
	if src == null or src.path.is_empty():
		return {}
	var objects: Variant
	if session.files.has(src.path):
		objects = session.files[src.path].objects
	else:
		var parsed := BnJson.parse(FileAccess.get_file_as_string(session.index.file_path(src.path)))
		objects = parsed.value if parsed.ok() else []
		if objects is Dictionary:
			objects = [objects]
	if objects is Array and src.index < objects.size() and objects[src.index] is Dictionary:
		return objects[src.index]
	return {}


## The mod whose folder holds [param rel], among every mod of the catalog
## (loaded or not; a workspace-only one is in [param ws_mods], id -> its
## folder). The longest folder wins. "" if none.
static func _mod_of(index: DataIndex, catalog: ModCatalog, rel: String, ws_mods: Dictionary) -> String:
	var best := ""
	var best_len := -1
	for id: String in catalog.mods:
		var dir: String = ws_mods[id] if ws_mods.has(id) else index.relative_path(catalog.get_mod(id).path)
		if rel.begins_with(dir + "/") and dir.length() > best_len:
			best = id
			best_len = dir.length()
	return best


static func _modinfo(catalog: ModCatalog, mod: String, lua: bool) -> Dictionary:
	var deps := ["bn"]
	if mod and not deps.has(mod) and not catalog.get_mod(mod).core:
		deps.append(mod)
	var info := {"type": "MOD_INFO", "id": MOD_ID, "name": "BN Map Editor playtest",
		"description": "Starts a new game in the map being playtested. Made by BN Map Editor; rebuilt on every playtest.",
		"category": "content", "dependencies": deps}
	if lua:
		info["lua_api_version"] = LUA_API_VERSION
	return info


## The mod's preload.lua. When a new game starts:
## - with [param ids]: moves the player from the ground floor to the closest
##   tile of [param ids] on level [param z] (overmapbuffer.find_closest from
##   the tile above or below them, so the building they start in), then onto
##   the stairs leading back towards the ground (GOES_DOWN above it, GOES_UP
##   below), else the closest flat floor without furniture. A failure goes to
##   debug.log naming the mod, so the editor shows it.
## - with [param radius] > 0: reveals that radius around the player's tile
##   (after the move) on each of [param levels] (overmapbuffer.reveal).
static func _lua(ids: PackedStringArray, z: int, radius := 0, levels: Array[int] = []) -> String:
	var out := "-- Made by BN Map Editor; rebuilt on every playtest.\n"
	var calls := PackedStringArray()
	if not ids.is_empty():
		var quoted := PackedStringArray()
		for id in ids:
			quoted.append(BnJson.encode_string(id))
		out += _LUA_MOVE % [", ".join(quoted), z, "GOES_DOWN" if z > 0 else "GOES_UP", MOD_ID]
		calls.append("move_player()")
	if radius > 0:
		var zs := PackedStringArray()
		for level in levels:
			zs.append(str(level))
		out += _LUA_REVEAL % [", ".join(zs), radius]
		calls.append("reveal_building()")
	out += "\ngame.add_hook(\"on_game_started\", function()\n"
	for call in calls:
		out += "  %s\n" % call
	return out + "end)\n"


const _LUA_MOVE := """-- Start locations work on the ground floor, so the game starts the player on
-- the ground and this moves them to the playtested level.

local targets = { %s }
local level = %d
local stairs = "%s"
local omt_size = 24

local function spot_rank(map, p)
  if map:has_ter_flag_at(stairs, p) then return 0 end
  if map:has_ter_flag_at("FLAT", p) and map:get_furn_at(p):str_id():is_null() then return 1 end
  return nil
end

local function move_player()
  local avatar = gapi.get_avatar()
  local here = gapi.bub_to_abs(avatar:get_pos_ms()):to_omt()
  local params = OmtFindParams.new()
  for _, id in ipairs(targets) do
    params:add_type(id, OtMatchType.TYPE)
  end
  params:set_search_layers(level, level)
  local dest = overmapbuffer.find_closest(TripointAbsOmt.new(here.x, here.y, level), params)
  local names = table.concat(targets, ", ")
  if dest == nil then
    gdebug.log_error("%s: no " .. names .. " found on level " .. level .. ", the player stays on the ground floor")
    gapi.add_msg("Playtest: no " .. names .. " found on level " .. level .. ".")
    return
  end
  gapi.place_player_overmap_at(dest)

  local map = gapi.get_map()
  local from = avatar:get_pos_ms()
  local corner = map:abs_to_bub(TripointAbsMs.new(dest.x * omt_size, dest.y * omt_size, dest.z))
  local best, best_rank, best_dist = nil, nil, nil
  for dy = 0, omt_size - 1 do
    for dx = 0, omt_size - 1 do
      local p = TripointBubMs.new(corner.x + dx, corner.y + dy, corner.z)
      local rank = spot_rank(map, p)
      if rank ~= nil then
        local dist = (p.x - from.x) * (p.x - from.x) + (p.y - from.y) * (p.y - from.y)
        if best == nil or rank < best_rank or (rank == best_rank and dist < best_dist) then
          best, best_rank, best_dist = p, rank, dist
        end
      end
    end
  end
  if best ~= nil then
    gapi.place_player_local_at(best)
  end
  gapi.add_msg("Playtest: moved to " .. names .. " on level " .. level .. ".")
end
"""

const _LUA_REVEAL := """
-- Shows the building on the overmap: the radius covers the special from any
-- of its tiles, and the player starts on one.
local reveal_levels = { %s }
local reveal_radius = %d

local function reveal_building()
  local here = gapi.bub_to_abs(gapi.get_avatar():get_pos_ms()):to_omt()
  for _, z in ipairs(reveal_levels) do
    overmapbuffer.reveal(TripointAbsOmt.new(here.x, here.y, z), reveal_radius)
  end
end
"""


## The profession Play Now gets with Options.strong_character: STRONG_SKILLS
## at SKILL_LEVEL, STRONG_TRAITS, STRONG_CBMS and the gear, with points 0 (so
## avatar::randomize spends nothing on it). An id the loaded mods lack or
## blacklist is left out with a warning in [param b]; so is a gun's ammo (the
## gun stays, unloaded). Adds to b.applied.
static func _profession(index: DataIndex, b: Build) -> Dictionary:
	# kind -> the ids left out; blacklisted items apart.
	var missing := {}
	var blacklisted := PackedStringArray()
	var known := func(kind: String, id: String) -> bool:
		if not index.has_id(kind, id):
			if not missing.has(kind):
				missing[kind] = PackedStringArray()
			if not missing[kind].has(id):
				missing[kind].append(id)
			return false
		if kind == "item" and index.item_blacklist.has(id):
			if not blacklisted.has(id):
				blacklisted.append(id)
			return false
		return true
	var skills := []
	for id: String in STRONG_SKILLS:
		if known.call("skill", id):
			skills.append({"name": id, "level": SKILL_LEVEL})
	var traits := []
	for id: String in STRONG_TRAITS:
		if known.call("mutation", id):
			traits.append(id)
	var cbms := []
	for id: String in STRONG_CBMS:
		if known.call("bionic", id):
			cbms.append(id)
	var items := []
	for id: String in STRONG_ITEMS:
		if known.call("item", id):
			items.append(id)
	var entries := []
	for e: Dictionary in STRONG_ENTRIES:
		if not known.call("item", e.item):
			continue
		if e.has("container-item") and not known.call("item", e["container-item"]):
			continue
		var entry := e.duplicate(true)
		if entry.has("ammo-item") and not known.call("item", entry["ammo-item"]):
			entry.erase("ammo-item")
			entry.erase("charges")
		entries.append(entry)
	for kind: String in missing:
		b.warnings.append("the strong character's %s %s aren't in the selected mods: left out" % [
			"traits" if kind == "mutation" else kind + "s", ", ".join(missing[kind])])
	if blacklisted.size():
		b.warnings.append("the strong character's items %s are blacklisted by the selected mods: left out" % ", ".join(blacklisted))
	var group := {"items": items}
	if not entries.is_empty():
		group["entries"] = entries
	b.applied.append("strong character (%d skills at %d, %d traits, %d CBMs, %d items)" % [
		skills.size(), SKILL_LEVEL, traits.size(), cbms.size(), items.size() + entries.size()])
	return {"type": "profession", "id": PROFESSION, "name": "Playtest character",
		"description": "A strong character for trying out a map. Made by BN Map Editor; rebuilt on every playtest.",
		"points": 0, "skills": skills, "traits": traits, "CBMs": cbms, "items": {"both": group}}


## Sets b.reveal_radius and b.reveal_levels from [param special]'s overmaps
## when Options.reveal_building: the radius reaches its farthest tile from any
## other (with one tile of margin), on each of its levels. Returns what it
## did for b.applied, "" if nothing.
static func _reveal_area(special: Dictionary, options: Options, b: Build) -> String:
	b.reveal_radius = 0
	b.reveal_levels.clear()
	if not options.reveal_building:
		return ''

	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for o: Variant in special.get("overmaps", []):
		var point: Variant = o.get("point") if o is Dictionary else null
		if not point is Array or point.size() < 3:
			continue
		low = Vector2i(mini(low.x, int(point[0])), mini(low.y, int(point[1])))
		high = Vector2i(maxi(high.x, int(point[0])), maxi(high.y, int(point[1])))
		if not b.reveal_levels.has(int(point[2])):
			b.reveal_levels.append(int(point[2]))
	if b.reveal_levels.is_empty():
		return ""
	b.reveal_levels.sort()
	b.reveal_radius = maxi(high.x - low.x, high.y - low.y) + 1
	return "the building revealed on the overmap (radius %d, level%s %s)" % [
		b.reveal_radius, "" if b.reveal_levels.size() == 1 else "s",
		", ".join(b.reveal_levels.map(str))]


## The playtest world's worldoptions.json: [param template] (the template
## world's text, "" for none) with the options' overrides, else it unchanged
## ("[]" for none). Values are strings, as BN writes them. Adds to
## b.applied; a template that can't be read is used as written, with a
## warning in [param b].
static func _world_options(template: String, options: Options, b: Build) -> String:
	var wanted := {}
	if options.daylight:
		wanted["INITIAL_TIME"] = str(DAYLIGHT_HOUR)
	if options.no_monsters:
		wanted["SPAWN_DENSITY"] = "0.00"
	var listed: Array = []
	if template:
		var parsed := BnJson.parse(template)
		if parsed.ok() and parsed.value is Array:
			listed = parsed.value
		else:
			b.warnings.append("the template world's worldoptions.json can't be read: used as it is")
			return template
	# At least one city (PLAYTEST.MD risk 4); BN's own default is 8.
	for o: Variant in listed:
		if o is Dictionary and o.get("name") == "CITY_SIZE" and str(o.get("value", "0")).to_int() < 1:
			wanted["CITY_SIZE"] = "1"
	if wanted.is_empty():
		return template if template else "[]"
	for name: String in wanted:
		var found := false
		for o: Variant in listed:
			if o is Dictionary and o.get("name") == name:
				o["value"] = wanted[name]
				found = true
		if not found:
			listed.append({"name": name, "value": wanted[name]})
	if wanted.has("INITIAL_TIME"):
		b.applied.append("start in daylight (INITIAL_TIME %s)" % wanted["INITIAL_TIME"])
	if wanted.has("SPAWN_DENSITY"):
		b.applied.append("no monsters (SPAWN_DENSITY 0)")
	if wanted.has("CITY_SIZE"):
		b.applied.append("CITY_SIZE raised to 1")
	var formatted := JsonFormatter.format(BnJson.stringify(listed))
	return formatted.text if formatted.ok() else template if template else "[]"


## The overmap special placing [param ref]: a copy of its building's
## "overmaps" when a (fixed) building places it, else the map alone. Sets
## b.start_terrain. Returns {} with b.error set when it can't be made.
static func _special(session: EditSession, ref: DataIndex.MapgenRef, b: Build) -> Dictionary:
	var index := session.index
	var special := {"type": "overmap_special", "id": SPECIAL}
	var building: DataIndex.Building = null
	var mutable := false
	for id in ref.ids:
		for t in index.buildings_using(id):
			var bld: DataIndex.Building = index.buildings.get(t.building)
			if bld == null:
				continue
			if bld.mutable:
				mutable = true
			elif building == null and bld.overmaps_source:
				building = bld
	if building:
		var own := _object(session, building.source)
		var from := _object(session, building.overmaps_source)
		special["overmaps"] = from.get("overmaps", []).duplicate(true)
		for key in ["locations", "connections", "rotate"]:
			var v: Variant = own.get(key, from.get(key))
			if v != null:
				special[key] = v.duplicate(true) if v is Array or v is Dictionary else v
		# The map's tiles on its level nearest the ground, and the ground
		# tiles under them: the start. Off the ground the Lua hook moves
		# the player up or down.
		var z := _level_of(building, ref)
		var under: Array[Vector2i] = []
		for t in building.level(z):
			if ref.ids.has(t.oter):
				under.append(Vector2i(t.point.x, t.point.y))
				if z != 0 and not b.move_to.has(t.oter):
					b.move_to.append(t.oter)
		b.move_to_z = z
		for t in building.level(0):
			if t.oter and under.has(Vector2i(t.point.x, t.point.y)) and not b.start_terrain.has(t.oter):
				b.start_terrain.append(t.oter)
		if b.start_terrain.is_empty():
			for t in building.level(0):
				if t.oter and not b.start_terrain.has(t.oter):
					b.start_terrain.append(t.oter)
		if b.start_terrain.is_empty():
			b.error = "%s has no tile on the ground floor (z 0) to start on" % building.id
			return {}
	else:
		if mutable:
			b.warnings.append("%s is placed by a mutable special's rules: the playtest places the map alone" % ref.title())
		var overmaps := []
		var size := ref.size_omt()
		for y in size.y:
			for x in size.x:
				var id: String = ref.grid[y][x] if not ref.grid.is_empty() else ref.ids[0]
				var suffix := "_north" if _rotates(session, id, 0) else ""
				overmaps.append({"point": [x, y, 0], "overmap": id + suffix})
				if not b.start_terrain.has(id):
					b.start_terrain.append(id)
		special["overmaps"] = overmaps
	if not special.has("locations"):
		special["locations"] = ["land"]
	special["occurrences"] = [1, 1]
	# Placed first, and only, in the overmap the start location searches first.
	special["flags"] = ["GLOBALLY_UNIQUE"]
	special["absolute_spawn_loc"] = {"x": 0, "y": 0}
	return special


## Adds START_TILE to [param special] (Options.start_outside): on the ground,
## START_GAP tiles south of everything the special places, so the gap holds
## no tile of it. Makes it b.start_terrain. Returns its overmap_terrain and its
## mapgen (grass).
static func _start_outside(special: Dictionary, b: Build) -> Array:
	var low_x := 0
	var high_y := 0
	var first := true
	for o: Variant in special.overmaps:
		var point: Variant = o.get("point") if o is Dictionary else null
		if point is Array and point.size() >= 3:
			low_x = int(point[0]) if first else mini(low_x, int(point[0]))
			high_y = int(point[1]) if first else maxi(high_y, int(point[1]))
			first = false
	special.overmaps.append({"point": [low_x, high_y + START_GAP + 1, 0], "overmap": START_TILE})
	b.start_terrain = PackedStringArray([START_TILE])
	var rows := []
	for y in 24:
		rows.append(".".repeat(24))
	return [
		{"type": "overmap_terrain", "id": START_TILE, "name": "playtest start", "sym": "*",
			"color": "light_green", "see_cost": 2, "flags": ["NO_ROTATE"]},
		{"type": "mapgen", "method": "json", "om_terrain": [START_TILE],
			"object": {"fill_ter": "t_grass", "rows": rows}},
	]


## Gives the playtest overmap terrains of its own (Options.own_start_terrain):
## OWN_PREFIX + id, copy-from id (so flags, NO_ROTATE and looks are kept),
## for every tile of [param special] that has an enabled JSON mapgen, and
## copies of those mapgens (as the session has them, from [param texts]
## first) in [param texts] under MOD_COPIES, with om_terrain renamed. The
## map's own ids get only [param ref]; the other tiles every enabled mapgen of
## theirs that doesn't also make one of the map's ids. A list mapgen is copied
## only for the ids the special needs, a grid whole. A tile without such a
## mapgen (a C++ or Lua one, a LINEAR piece) keeps its id: an overmap terrain
## without a mapgen is a load error in BN. Renames the special's overmaps,
## b.start_terrain and b.move_to, and fills b.own_terrain and b.copied.
## Returns the overmap_terrain objects, or [] with b.error set.
static func _own_terrain(session: EditSession, ref: DataIndex.MapgenRef, texts: Dictionary,
		special: Dictionary, b: Build) -> Array:
	var index := session.index
	var tiles := PackedStringArray()
	for e: Variant in special.get("overmaps", []):
		var id := _tile_oter(index, str(e.get("overmap", ""))) if e is Dictionary else ""
		if id and not tiles.has(id):
			tiles.append(id)
	# The mapgens to copy, in order, and the ids each is copied for.
	var order: Array[DataIndex.MapgenRef] = []
	var picks := {}
	for id in tiles:
		var refs: Array = [ref] if ref.ids.has(id) else index.om_terrain.get(id, [])
		for r: DataIndex.MapgenRef in refs:
			if r.disabled or r.kind != DataIndex.MapgenRef.OM_TERRAIN:
				continue
			if r != ref and Array(r.ids).any(func(x: String) -> bool: return ref.ids.has(x)):
				continue
			if not picks.has(r):
				picks[r] = PackedStringArray()
				order.append(r)
			if not picks[r].has(id):
				picks[r].append(id)
	# real id -> the playtest's
	var made := {}
	for r in order:
		for id in r.ids if r.grid.size() else picks[r]:
			if index.overmap_terrain.has(id) and not made.has(id):
				made[id] = OWN_PREFIX + id
	var cache := {}
	var by_file := {}
	var files := PackedStringArray()
	for r in order:
		var o := _source_object(session, texts, r.source, cache)
		if o.is_empty() or not o.has("om_terrain"):
			b.error = "%s has no mapgen #%d any more" % [r.source.path, r.source.index]
			return []
		var copy: Dictionary = o.duplicate(true)
		var om: Variant = copy.om_terrain
		if r.grid.size() and om is Array:
			var rows := []
			for row: Variant in om:
				rows.append((row as Array).map(func(id: Variant) -> Variant: return made.get(id, id)))
			copy.om_terrain = rows
		elif om is Array:
			var ids := []
			for id: Variant in om:
				if picks[r].has(id):
					ids.append(made[id])
			copy.om_terrain = ids
		else:
			copy.om_terrain = made.get(om, om)
		var rel := MOD_COPIES.path_join(r.source.path.replace("mod_interactions", "mod-interactions"))
		if not by_file.has(rel):
			by_file[rel] = []
			files.append(rel)
		by_file[rel].append(copy)
		b.copied.append("%s#%d" % [r.source.path, r.source.index])
	for rel in files:
		texts[("data/mods/" + MOD_ID).path_join(rel)] = BnJson.stringify(by_file[rel])

	for e: Variant in special.get("overmaps", []):
		if not e is Dictionary:
			continue
		var name := str(e.get("overmap", ""))
		var id := _tile_oter(index, name)
		if made.has(id):
			e.overmap = made[id] + name.substr(id.length())
	for i in b.start_terrain.size():
		var id := b.start_terrain[i]
		if made.has(id):
			b.start_terrain[i] = made[id]
		else:
			b.warnings.append("the playtest can't copy %s (no JSON mapgen of its own): the start may be any %s in the first overmap" % [id, id])
	for i in b.move_to.size():
		b.move_to[i] = made.get(b.move_to[i], b.move_to[i])
	var oters := []
	for id: String in made:
		b.own_terrain[made[id]] = id
		oters.append({"type": "overmap_terrain", "id": made[id], "copy-from": id})
	return oters


## The overmap terrain id of special entry [param name] ("house_north" ->
## "house"), or "" when no overmap_terrain is named so (a LINEAR piece).
static func _tile_oter(index: DataIndex, name: String) -> String:
	if index.overmap_terrain.has(name):
		return name
	for dir: String in DataIndex.DIRECTIONS:
		var base := name.trim_suffix("_" + dir)
		if base != name and index.overmap_terrain.has(base):
			return base
	return ""


## The object at [param src] as the playtest writes its file: from
## [param texts] when it replaces the file, else as _object reads it. Files
## are parsed once, into [param cache].
static func _source_object(session: EditSession, texts: Dictionary, src: DataIndex.Source,
		cache: Dictionary) -> Dictionary:
	if not texts.has(src.path):
		return _object(session, src)
	if not cache.has(src.path):
		var parsed := BnJson.parse(texts[src.path])
		var objects: Variant = parsed.value if parsed.ok() else []
		cache[src.path] = [objects] if objects is Dictionary else objects if objects is Array else []
	var objects: Array = cache[src.path]
	if src.index < objects.size() and objects[src.index] is Dictionary:
		return objects[src.index]
	return {}


## The level of [param building] holding [param ref]'s ids that is nearest
## the ground (0 when one is on it).
static func _level_of(building: DataIndex.Building, ref: DataIndex.MapgenRef) -> int:
	var best := 0
	var found := false
	for t in building.tiles:
		if t.placed and ref.ids.has(t.oter) and (not found or absi(t.point.z) < absi(best)):
			best = t.point.z
			found = true
	return best


## True when overmap terrain [param id] rotates (no NO_ROTATE or LINEAR flag
## on it or what it copies from), so a special names it with a direction.
static func _rotates(session: EditSession, id: String, depth: int) -> bool:
	var src: DataIndex.Source = session.index.overmap_terrain.get(id)
	var o := _object(session, src)
	var flags: Variant = o.get("flags", [])
	if flags is Array and (flags.has("NO_ROTATE") or flags.has("LINEAR")):
		return false
	var base: Variant = o.get("copy-from")
	if base is String and base != id and session.index.overmap_terrain.has(base) and depth < 16:
		return _rotates(session, base, depth + 1)
	return true


## userdir/: config copies, links to the user's tilesets and the like, and
## the empty playtest world.
## [param added]: the mods the map or a file needs that the editor and the
## template don't list (mod id -> the file that needs it), listed after them.
static func _make_userdir(catalog: ModCatalog, options: Options, b: Build, added: Dictionary) -> String:
	var config := b.userdir.path_join("config")
	var world := b.userdir.path_join("save").path_join(WORLD)
	for dir in [config, world]:
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return "can't create %s: %s" % [dir, error_string(err)]
	if options.bn_config_dir:
		for name: String in CONFIG_FILES:
			var from := options.bn_config_dir.path_join(name)
			if FileAccess.file_exists(from):
				var err := DirAccess.copy_absolute(from, config.path_join(name))
				if err != OK:
					return "can't copy %s: %s" % [from, error_string(err)]
	if options.bn_user_dir:
		var dir := DirAccess.open(b.userdir)
		for name: String in USER_LINKS:
			var from := options.bn_user_dir.path_join(name)
			if DirAccess.dir_exists_absolute(from):
				dir.create_link(from, b.userdir.path_join(name))

	var template := options.template_world
	if template and not DirAccess.dir_exists_absolute(template):
		b.warnings.append("template world %s not found" % template)
		template = ""
	var template_options := ""
	if template and FileAccess.file_exists(template.path_join("worldoptions.json")):
		template_options = FileAccess.get_file_as_string(template.path_join("worldoptions.json"))
	var problem := _store(world.path_join("worldoptions.json"), _world_options(template_options, options, b))
	if problem:
		return problem

	var wanted := options.mods.duplicate()
	if template:
		var listed: Variant = JSON.parse_string(FileAccess.get_file_as_string(template.path_join("mods.json")))
		if not listed is Array:
			listed = []
		for id: Variant in listed:
			if not id is String:
				continue
			if catalog.has(id):
				wanted.append(id)
			else:
				b.warnings.append("the template world's mod %s isn't in BN's data/mods: left out" % id)
	for id: String in added:
		if not wanted.has(id):
			wanted.append(id)
			b.warnings.append("added %s: %s is in it" % [id, added[id]])
	var known := PackedStringArray()
	for id in wanted:
		if catalog.has(id):
			known.append(id)
		else:
			b.warnings.append("mod %s not found: left out" % id)
	var order := catalog.load_order(known)
	b.warnings.append_array(order.errors)
	for id in order.mods:
		if catalog.has(id) and id != MOD_ID:
			b.world_mods.append(id)
	b.world_mods.append(MOD_ID)
	var formatted := JsonFormatter.format(BnJson.stringify(Array(b.world_mods)))
	return _store(world.path_join("mods.json"), formatted.text if formatted.ok() else "")

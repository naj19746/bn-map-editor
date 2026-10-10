class_name AppSettings
extends RefCounted
## Editor settings, stored with ConfigFile (user://settings.cfg by default).
## The BN_PATH environment variable overrides the stored BN path without
## replacing it; see effective_bn_path().

const DEFAULT_FILE := "user://settings.cfg"
## playtest_world for "no template world" (a name no folder can have).
const NO_WORLD := "/"

var bn_path := ""
## Selected mods (besides core), in the order the user picked them.
var mods := PackedStringArray()
var workspace_path := ""
## The ghost level drawn under a building's map: -1 the level below, 1 the
## level above, 0 none.
var ghost := -1
## Draw the ghost level faded.
var ghost_dim := true
## The game binary a playtest runs ("": find one, Playtest.find_binary).
var game_binary := ""
## The world a playtest world copies its options and mods from: a world
## name, "" for the default (Playtest.default_template_world), NO_WORLD for
## none.
var playtest_world := ""
## Give a playtest overmap terrains of its own, which only its special places
## (Playtest.Options.own_start_terrain).
var own_start_terrain := true
## Disable the other mapgens of a playtested map's ids (without
## own_start_terrain).
var only_my_mapgen := true
## A playtest starts outside, away from the building
## (Playtest.Options.start_outside).
var playtest_start_outside := true
## Load the data in the game (Playtest.check) before a playtest and refuse to
## start it on errors naming the user's files. It takes ~12 s, so off.
var check_before_playtest := false
## The playtest character is strong (Playtest.Options.strong_character).
var strong_character := true
## No monsters spawn in a playtest (Options.no_monsters).
var no_monsters := false
## A playtest starts by day (Options.daylight).
var start_in_daylight := true
## A playtest shows the building on the overmap (Options.reveal_building).
var reveal_building := true


static func load_from(file := DEFAULT_FILE) -> AppSettings:
	var s := AppSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(file) == OK:
		s.bn_path = str(cfg.get_value("bn", "path", ""))
		s.mods = PackedStringArray(cfg.get_value("bn", "mods", PackedStringArray()))
		s.workspace_path = str(cfg.get_value("workspace", "path", ""))
		s.ghost = clampi(int(cfg.get_value("view", "ghost", -1)), -1, 1)
		s.ghost_dim = bool(cfg.get_value("view", "ghost_dim", true))
		s.game_binary = str(cfg.get_value("playtest", "binary", ""))
		s.playtest_world = str(cfg.get_value("playtest", "world", ""))
		s.own_start_terrain = bool(cfg.get_value("playtest", "own_terrain", true))
		s.only_my_mapgen = bool(cfg.get_value("playtest", "only_my_mapgen", true))
		s.playtest_start_outside = bool(cfg.get_value("playtest", "start_outside", true))
		s.check_before_playtest = bool(cfg.get_value("playtest", "check_before", false))
		s.strong_character = bool(cfg.get_value("playtest", "strong_character", true))
		s.no_monsters = bool(cfg.get_value("playtest", "no_monsters", false))
		s.start_in_daylight = bool(cfg.get_value("playtest", "daylight", true))
		s.reveal_building = bool(cfg.get_value("playtest", "reveal_building", true))
	return s


## $BN_PATH if set, else the stored path.
func effective_bn_path() -> String:
	var env := OS.get_environment("BN_PATH")
	return env if not env.is_empty() else bn_path


func save_to(file := DEFAULT_FILE) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("bn", "path", bn_path)
	cfg.set_value("bn", "mods", mods)
	cfg.set_value("workspace", "path", workspace_path)
	cfg.set_value("view", "ghost", ghost)
	cfg.set_value("view", "ghost_dim", ghost_dim)
	cfg.set_value("playtest", "binary", game_binary)
	cfg.set_value("playtest", "world", playtest_world)
	cfg.set_value("playtest", "own_terrain", own_start_terrain)
	cfg.set_value("playtest", "only_my_mapgen", only_my_mapgen)
	cfg.set_value("playtest", "start_outside", playtest_start_outside)
	cfg.set_value("playtest", "check_before", check_before_playtest)
	cfg.set_value("playtest", "strong_character", strong_character)
	cfg.set_value("playtest", "no_monsters", no_monsters)
	cfg.set_value("playtest", "daylight", start_in_daylight)
	cfg.set_value("playtest", "reveal_building", reveal_building)
	return cfg.save(file)

class_name AppSettings
extends RefCounted
## Editor settings, stored with ConfigFile (user://settings.cfg by default).
## The BN_PATH environment variable overrides the stored BN path without
## replacing it; see effective_bn_path().

const DEFAULT_FILE := "user://settings.cfg"

var bn_path := ""
## Selected mods (besides core), in the order the user picked them.
var mods := PackedStringArray()
var workspace_path := ""


static func load_from(file := DEFAULT_FILE) -> AppSettings:
	var s := AppSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(file) == OK:
		s.bn_path = str(cfg.get_value("bn", "path", ""))
		s.mods = PackedStringArray(cfg.get_value("bn", "mods", PackedStringArray()))
		s.workspace_path = str(cfg.get_value("workspace", "path", ""))
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
	return cfg.save(file)

extends "res://tests/support/test_case.gd"


func test_save_and_load() -> void:
	var file := OS.get_temp_dir().path_join("bnme_settings_%d.cfg" % OS.get_process_id())
	var s := AppSettings.new()
	s.bn_path = "/somewhere/Cataclysm-BN"
	s.mods = PackedStringArray(["mod_b", "mod_a"])
	s.workspace_path = "/somewhere/workspace"
	check_eq(s.save_to(file), OK)
	var back := AppSettings.load_from(file)
	check_eq(back.bn_path, s.bn_path)
	check_eq(back.mods, s.mods)
	check_eq(back.workspace_path, s.workspace_path)
	DirAccess.remove_absolute(file)
	check_eq(AppSettings.load_from(file).mods, PackedStringArray(), "a missing file gives defaults")

extends "res://tests/support/test_case.gd"
## Stage 0 acceptance: every BN mapgen, palette and mod JSON file survives
## BnJson.parse -> BnJson.stringify -> json_formatter byte-for-byte.

const BnEnv := preload("res://tests/support/bn_env.gd")
const DIRS := ["data/json/mapgen", "data/json/mapgen_palettes", "data/mods"]
const MAX_REPORTED := 20


func test_bn_files_round_trip() -> void:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return

	var files := PackedStringArray()
	for dir: String in DIRS:
		files.append_array(BnEnv.json_files(bn.path_join(dir)))
	check(files.size() > 1000, "expected >1000 files, found %d" % files.size())

	var bad := 0
	var parse_ms := 0
	for path in files:
		var original := FileAccess.get_file_as_bytes(path)
		var t := Time.get_ticks_msec()
		var parsed := BnJson.parse_bytes(original)
		parse_ms += Time.get_ticks_msec() - t
		var problem := ""
		if not parsed.ok():
			problem = "parse error line %d: %s" % [parsed.error_line, parsed.error]
		elif not parsed.warnings.is_empty():
			problem = "lossy: " + ", ".join(parsed.warnings)
		else:
			var formatted := JsonFormatter.format(BnJson.stringify(parsed.value))
			if not formatted.ok():
				problem = formatted.error
			elif formatted.text.to_utf8_buffer() != original:
				problem = "output differs"
		if problem:
			bad += 1
			if bad <= MAX_REPORTED:
				failures.append("%s: %s" % [path.trim_prefix(bn + "/"), problem])
	check_eq(bad, 0, "files failing the round trip (of %d)" % files.size())
	print("     %d files, parse total %d ms" % [files.size(), parse_ms])

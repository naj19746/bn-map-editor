extends SceneTree
## Headless test runner:
##   godot --headless --path . -s tests/run_tests.gd [-- FILTER...]
## Runs test_* methods in tests/test_*.gd. A FILTER keeps tests whose
## "file::method" contains it. Exits 1 if any test fails.

const TESTS_DIR := "res://tests"


## Turns engine/script errors raised during a test into failures; otherwise a
## runtime error just aborts the method and the test would look like a pass.
class ErrorCatcher:
	extends Logger

	var errors := PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var e := errors
		errors = PackedStringArray()
		_mutex.unlock()
		return e


func _initialize() -> void:
	if not FileAccess.file_exists("res://.godot/global_script_class_cache.cfg"):
		printerr("No class_name cache; run `godot --headless --path . --import` first (tools/run_tests.sh does).")
		quit(1)
		return
	var filters := OS.get_cmdline_user_args()
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)

	var passed := 0
	var failed := 0
	var skipped := 0
	for file in _test_files():
		catcher.take()
		var script: GDScript = load(TESTS_DIR.path_join(file))
		var load_errors := catcher.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			failed += 1
			print("FAIL %s: failed to load" % file)
			for e in load_errors:
				print("     " + e)
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			var id := "%s::%s" % [file.get_basename(), name]
			if not name.begins_with("test_") or not _matches(id, filters):
				continue
			var test: RefCounted = script.new()
			catcher.take()
			var start := Time.get_ticks_msec()
			test.call(name)
			var ms := Time.get_ticks_msec() - start
			var problems: PackedStringArray = test.failures + catcher.take()
			if not problems.is_empty():
				failed += 1
				print("FAIL %s (%d ms)" % [id, ms])
				for p in problems:
					print("     " + p)
			elif test.skip_reason:
				skipped += 1
				print("SKIP %s: %s" % [id, test.skip_reason])
			else:
				passed += 1
				print("ok   %s (%d ms)" % [id, ms])

	OS.remove_logger(catcher)
	print("\n%d passed, %d failed, %d skipped" % [passed, failed, skipped])
	quit(1 if failed > 0 else 0)


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(TESTS_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	return files


func _matches(id: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if id.contains(f):
			return true
	return false

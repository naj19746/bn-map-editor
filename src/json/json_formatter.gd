class_name JsonFormatter
extends RefCounted
## Runs BN's json_formatter (tools/format in a BN checkout) over JSON text.
##
## OS.execute can't write to a child's stdin, so this uses the formatter's
## in-place file mode on a temp file: exit 0 = unchanged, 1 = reformatted (or
## "Failed to open"), anything else = crash, e.g. an abort on invalid JSON.


class Result:
	var text := ""
	## Empty on success.
	var error := ""

	func ok() -> bool:
		return error.is_empty()


static var _temp_counter := 0

var executable: String


func _init(p_executable := default_executable()) -> void:
	executable = p_executable


## Where tools/build_json_formatter.sh puts the binary.
static func default_executable() -> String:
	var name := "json_formatter.exe" if OS.get_name() == "Windows" else "json_formatter"
	return ProjectSettings.globalize_path("res://build").path_join(name)


func is_available() -> bool:
	return FileAccess.file_exists(executable)


func format(json_text: String) -> Result:
	var result := Result.new()
	if not is_available():
		result.error = "json_formatter not found at %s (run tools/build_json_formatter.sh)" % executable
		return result
	_temp_counter += 1
	var tmp := OS.get_temp_dir().path_join("bnme_fmt_%d_%d.json" % [OS.get_process_id(), _temp_counter])
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		result.error = "can't write temp file %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
		return result
	f.store_string(json_text)
	f.close()

	var output: Array = []
	var code := OS.execute(executable, [tmp], output, true)
	var out_text := "".join(PackedStringArray(output)).strip_edges()
	if code != 0 and (code != 1 or out_text.contains("Failed to open")):
		result.error = "json_formatter failed (exit %d): %s" % [code, out_text]
	else:
		result.text = FileAccess.get_file_as_string(tmp)
	DirAccess.remove_absolute(tmp)
	return result

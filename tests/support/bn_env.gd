extends RefCounted
## Locates the BN checkout for tests that need real data.
## Tests only read from it; anything written goes to a temp dir.


## $BN_PATH, else ../Cataclysm-BN next to this project. "" if neither exists.
static func bn_path() -> String:
	var path := OS.get_environment("BN_PATH")
	if path.is_empty():
		path = ProjectSettings.globalize_path("res://").path_join("../Cataclysm-BN").simplify_path()
	return path if DirAccess.dir_exists_absolute(path.path_join("data/json")) else ""


## All *.json files under [param dir], recursively, sorted.
static func json_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	_collect(dir, out)
	out.sort()
	return out


static func _collect(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)

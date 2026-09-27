class_name MapgenObjects
extends RefCounted
## Finds the mapgen object behind a MapgenRef, for display: from a file open
## for editing (live, unsaved edits included) when [member live] has it,
## else from the file on disk, parsed with Godot's JSON once and kept.
## Numbers from disk are floats; fine for resolving and drawing.

var index: DataIndex
## (rel path) -> the file's objects (Array), or null when it isn't open.
var live := Callable()

## rel path -> Array of parsed objects.
var _files := {}


func _init(p_index: DataIndex, p_live := Callable()) -> void:
	index = p_index
	live = p_live


## The top-level object [param src] points at, or {} if it's gone.
func object_at(src: DataIndex.Source) -> Dictionary:
	var objects: Variant = live.call(src.path) if live.is_valid() else null
	if objects == null:
		if not _files.has(src.path):
			var json := JSON.new()
			var ok := json.parse(FileAccess.get_file_as_string(index.file_path(src.path))) == OK
			_files[src.path] = ([json.data] if json.data is Dictionary else json.data) if ok else []
		objects = _files[src.path]
	if objects is Array and src.index < objects.size() and objects[src.index] is Dictionary:
		return objects[src.index]
	return {}


func object_for(ref: DataIndex.MapgenRef) -> Dictionary:
	return object_at(ref.source)


## Drops the cached copy of [param rel] (all files when ""), e.g. after it
## was saved and the file on disk changed.
func forget(rel := "") -> void:
	if rel.is_empty():
		_files.clear()
	else:
		_files.erase(rel)

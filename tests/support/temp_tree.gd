extends RefCounted
## Builds a throwaway folder tree for tests, e.g. a fake BN checkout.

static var _counter := 0


## Writes [param files] (relative path -> String, or a value to JSON-encode)
## under a new temp folder and returns its absolute path.
static func make(files: Dictionary) -> String:
	_counter += 1
	var root := OS.get_temp_dir().path_join("bnme_tree_%d_%d" % [OS.get_process_id(), _counter])
	remove(root)
	for rel: String in files:
		var path := root.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var content: Variant = files[rel]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(content if content is String else JSON.stringify(content, " "))
		f.close()
	return root


## Deletes [param root] recursively. Only touches the temp folder.
static func remove(root: String) -> void:
	if not root.begins_with(OS.get_temp_dir()) or not DirAccess.dir_exists_absolute(root):
		return
	for f in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(root.path_join(f))
	for d in DirAccess.get_directories_at(root):
		remove(root.path_join(d))
	DirAccess.remove_absolute(root)

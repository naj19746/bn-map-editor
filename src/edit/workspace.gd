class_name Workspace
extends RefCounted
## The folder edits are saved to. It mirrors BN's relative paths
## (<root>/data/json/mapgen/house.json) and is layered over the BN checkout
## by DataIndex. The editor never writes into BN itself.
##
## <root>/manifest.json records, per file, what it was copied from:
##   {"files": {"data/json/mapgen/house.json": {"base_sha256": "...", "base_commit": "..."},
##              "data/json/mapgen/mine.json": {"new": true}}}
## WorkspaceSync compares BN's current file against base_sha256 and pushes.

const MANIFEST := "manifest.json"

var root := ""
var bn_path := ""
## rel path -> {"base_sha256", "base_commit"} or {"new": true}.
var files := {}
## Set when manifest.json exists but can't be read.
var error := ""


static func open(p_root: String, p_bn_path: String) -> Workspace:
	var ws := Workspace.new()
	ws.root = p_root.simplify_path()
	ws.bn_path = p_bn_path.simplify_path()
	var path := ws.root.path_join(MANIFEST)
	if FileAccess.file_exists(path):
		var parsed := BnJson.parse(FileAccess.get_file_as_string(path))
		if parsed.ok() and parsed.value is Dictionary and parsed.value.get("files") is Dictionary:
			ws.files = parsed.value.files
		else:
			ws.error = "can't read %s: %s" % [path, parsed.error if not parsed.ok() else "no \"files\""]
	return ws


## The workspace default: a folder in the editor's user data.
static func default_root() -> String:
	return OS.get_user_data_dir().path_join("workspace")


## Why [param p_root] can't be a workspace for [param p_bn_path], or "".
static func check_root(p_root: String, p_bn_path: String) -> String:
	var r := p_root.simplify_path()
	var bn := p_bn_path.simplify_path()
	if r.is_empty():
		return "no workspace folder set"
	if r == bn or r.begins_with(bn + "/") or bn.begins_with(r + "/"):
		return "the workspace can't be inside the BN checkout or contain it: %s" % r
	return ""


func path(rel: String) -> String:
	return root.path_join(rel)


func has_file(rel: String) -> bool:
	return FileAccess.file_exists(path(rel))


## Writes [param text] to [param rel]. The first time a file is written, the
## manifest records its base: [param base_sha256] of the BN file it was read
## from, or "new" when "" (the file isn't from BN). Returns an error or "".
func write_file(rel: String, text: String, base_sha256: String) -> String:
	var problem := check_root(root, bn_path)
	if problem:
		return problem
	if rel.is_absolute_path() or rel.contains(".."):
		return "not a relative path: " + rel
	var target := path(rel)
	var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if err != OK:
		return "can't create %s: %s" % [target.get_base_dir(), error_string(err)]
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return "can't write %s: %s" % [target, error_string(FileAccess.get_open_error())]
	f.store_string(text)
	f.close()
	if not files.has(rel):
		if base_sha256:
			files[rel] = {"base_sha256": base_sha256, "base_commit": bn_commit(bn_path)}
		else:
			files[rel] = {"new": true}
		return save_manifest()
	return ""


func save_manifest() -> String:
	var keys: Array = files.keys()
	keys.sort()
	var sorted := {}
	for k: String in keys:
		sorted[k] = files[k]
	var text := BnJson.stringify({"files": sorted})
	var fmt := JsonFormatter.new()
	if fmt.is_available():
		var r := fmt.format(text)
		if r.ok():
			text = r.text
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(path(MANIFEST), FileAccess.WRITE)
	if f == null:
		return "can't write %s: %s" % [path(MANIFEST), error_string(FileAccess.get_open_error())]
	f.store_string(text)
	f.close()
	return ""


## The commit checked out in [param repo], read from .git without running
## git; "" if it can't be worked out.
static func bn_commit(repo: String) -> String:
	var git := repo.path_join(".git")
	if FileAccess.file_exists(git):
		# A worktree or submodule: ".git" is a file pointing at the git dir.
		var line := FileAccess.get_file_as_string(git).strip_edges()
		if not line.begins_with("gitdir:"):
			return ""
		git = line.trim_prefix("gitdir:").strip_edges()
		if git.is_relative_path():
			git = repo.path_join(git).simplify_path()
	if not DirAccess.dir_exists_absolute(git):
		return ""
	var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
	if not head.begins_with("ref:"):
		return head
	var ref := head.trim_prefix("ref:").strip_edges()
	# Refs live in the common dir for worktrees.
	var common := git
	if FileAccess.file_exists(git.path_join("commondir")):
		common = git.path_join(FileAccess.get_file_as_string(git.path_join("commondir")).strip_edges()).simplify_path()
	for dir in [git, common]:
		if FileAccess.file_exists(dir.path_join(ref)):
			return FileAccess.get_file_as_string(dir.path_join(ref)).strip_edges()
	if FileAccess.file_exists(common.path_join("packed-refs")):
		for l in FileAccess.get_file_as_string(common.path_join("packed-refs")).split("\n"):
			if l.ends_with(" " + ref):
				return l.get_slice(" ", 0)
	return ""

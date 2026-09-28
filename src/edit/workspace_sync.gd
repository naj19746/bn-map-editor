class_name WorkspaceSync
extends RefCounted
## Compares workspace files with the BN checkout and pushes them into it.
##
## This is the only code that writes into BN, and only for a push the user
## asked for. It never runs git. After a successful push the workspace copy
## and its manifest entry are deleted, so BN is the source again and nothing
## goes stale (decided 2026-09-27, see PLAN.MD).
##
## A push is safe when BN's file still matches the base recorded in the
## manifest (or, for a new file, BN still has none). Anything else is a
## conflict, which is pushed only with overwrite.

enum State {
	## BN has no file there: push creates it.
	NEW,
	## BN still matches the base: push replaces it.
	MODIFIED,
	## The workspace file is byte-identical to BN's: push just drops the copy.
	SAME,
	## Conflict: BN's file changed since the base was recorded.
	CHANGED_IN_BN,
	## Conflict: BN's file was deleted or renamed since the base.
	DELETED_IN_BN,
	## Conflict: the file was new, but BN has a file at that path now.
	ADDED_IN_BN,
	## Conflict: a workspace file the manifest doesn't know, where BN has a
	## file too, so there is no base to check against.
	UNTRACKED,
	## The manifest lists a file the workspace no longer has.
	MISSING,
}

const STATE_TEXT := {
	State.NEW: "new",
	State.MODIFIED: "modified",
	State.SAME: "same as BN",
	State.CHANGED_IN_BN: "conflict: BN changed since the base",
	State.DELETED_IN_BN: "conflict: deleted from BN since the base",
	State.ADDED_IN_BN: "conflict: BN has a file there now",
	State.UNTRACKED: "conflict: not in the manifest, BN has this file",
	State.MISSING: "missing from the workspace",
}

## Where push writes before renaming over the target.
const TEMP_SUFFIX := ".bnme-tmp"


## One object that differs between the workspace file and BN's.
class ObjectChange:
	## "added" (push adds it), "changed" or "removed" (push removes it).
	var kind := ""
	## e.g. "mapgen house_01", "mapgen house_01 (2nd)", "speech #12".
	var label := ""

	func _init(p_kind: String, p_label: String) -> void:
		kind = p_kind
		label = p_label

	func _to_string() -> String:
		return "%s %s" % [kind, label]


class FileStatus:
	var rel := ""
	var state := State.MODIFIED
	## The manifest entry, {} if untracked.
	var entry := {}
	## What push would do to BN's objects. Empty when SAME or MISSING, or when
	## a side doesn't parse (see summary_error).
	var changes: Array[ObjectChange] = []
	var summary_error := ""
	## Objects in the workspace file that push leaves as they are.
	var unchanged := 0

	func is_conflict() -> bool:
		return state in [State.CHANGED_IN_BN, State.DELETED_IN_BN, State.ADDED_IN_BN, State.UNTRACKED]

	func can_push() -> bool:
		return state != State.MISSING

	func text() -> String:
		return WorkspaceSync.STATE_TEXT[state]

	## "2 changed, 1 added" or the reason there is no summary.
	func summary_text() -> String:
		if summary_error:
			return summary_error
		var counts := {}
		for c in changes:
			counts[c.kind] = counts.get(c.kind, 0) + 1
		var parts := PackedStringArray()
		for kind in ["changed", "added", "removed"]:
			if counts.has(kind):
				parts.append("%d %s" % [counts[kind], kind])
		return ", ".join(parts) if parts.size() else "no object changes"


var workspace: Workspace


func _init(p_workspace: Workspace) -> void:
	workspace = p_workspace


## The status of every workspace file and manifest entry, sorted by path.
func scan() -> Array[FileStatus]:
	var rels := {}
	for rel: String in workspace.files:
		rels[rel] = true
	for rel in workspace_files():
		rels[rel] = true
	var sorted := rels.keys()
	sorted.sort()
	var out: Array[FileStatus] = []
	for rel: String in sorted:
		out.append(status(rel))
	return out


## Every .json file in the workspace (relative paths), except the manifest.
func workspace_files() -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(workspace.root):
		_collect(workspace.root, "", out)
	return out


static func _collect(dir: String, rel: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json") and not (rel.is_empty() and f == Workspace.MANIFEST):
			out.append(rel.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d), rel.path_join(d), out)


func status(rel: String) -> FileStatus:
	var s := FileStatus.new()
	s.rel = rel
	s.entry = workspace.files.get(rel, {})
	var ws_path := workspace.path(rel)
	var bn_file := workspace.bn_path.path_join(rel)
	var in_bn := FileAccess.file_exists(bn_file)
	if not FileAccess.file_exists(ws_path):
		s.state = State.MISSING
		return s
	var ws_bytes := FileAccess.get_file_as_bytes(ws_path)
	var bn_bytes := FileAccess.get_file_as_bytes(bn_file) if in_bn else PackedByteArray()
	if in_bn and ws_bytes == bn_bytes:
		s.state = State.SAME
		return s
	if s.entry.is_empty():
		s.state = State.UNTRACKED if in_bn else State.NEW
	elif s.entry.get("new", false):
		s.state = State.ADDED_IN_BN if in_bn else State.NEW
	elif not in_bn:
		s.state = State.DELETED_IN_BN
	elif FileAccess.get_sha256(bn_file) != s.entry.get("base_sha256", ""):
		s.state = State.CHANGED_IN_BN
	else:
		s.state = State.MODIFIED
	_summarize(s, bn_bytes, ws_bytes)
	return s


## Fills in what push would change: [param before] is BN's file (empty if
## none), [param after] the workspace file.
static func _summarize(s: FileStatus, before: PackedByteArray, after: PackedByteArray) -> void:
	var old := _keyed_objects(before, "BN's file") if before.size() else {}
	if old.has("error"):
		s.summary_error = old.error
		return
	var cur := _keyed_objects(after, "the workspace file")
	if cur.has("error"):
		s.summary_error = cur.error
		return
	for key: String in cur:
		if not old.has(key):
			s.changes.append(ObjectChange.new("added", cur[key].label))
		elif old[key].text != cur[key].text:
			s.changes.append(ObjectChange.new("changed", cur[key].label))
		else:
			s.unchanged += 1
	for key: String in old:
		if not cur.has(key):
			s.changes.append(ObjectChange.new("removed", old[key].label))


## A file's top-level objects as pair key -> {"label", "text"}, or
## {"error": ...}. The key is type + id (om_terrain, nested_mapgen_id, ...)
## plus its occurrence among objects with the same key, since one om_terrain
## often has several weighted mapgens: the 2nd "house_01" pairs with the 2nd.
## Objects with no id are keyed by type and occurrence, labelled by position.
## "text" is the object's bytes; both files come out of json_formatter, so an
## unchanged object has the same text.
static func _keyed_objects(bytes: PackedByteArray, what: String) -> Dictionary:
	var parsed := BnJson.parse_bytes(bytes)
	if not parsed.ok():
		return {"error": "%s doesn't parse (line %d: %s)" % [what, parsed.error_line, parsed.error]}
	var objects: Array = parsed.value if parsed.value is Array else [parsed.value]
	var spans: Array[Vector2i] = parsed.spans if parsed.value is Array else [Vector2i(0, bytes.size())]
	var out := {}
	var seen := {}
	for i in objects.size():
		var o: Variant = objects[i]
		var type := str(o.get("type", "?")) if o is Dictionary else type_string(typeof(o))
		var id := object_id(o)
		var base := type + " " + id if id else type
		var n: int = seen.get(base, 0) + 1
		seen[base] = n
		var label := base if id else "%s #%d" % [type, i + 1]
		if id and n > 1:
			label += " (%s)" % ordinal(n)
		out["%s\n%d" % [base, n]] = {"label": label, "text": bytes.slice(spans[i].x, spans[i].y)}
	return out


## What identifies [param o] in a summary: its id, abstract, om_terrain,
## nested_mapgen_id, update_mapgen_id or name (monstergroup); "" if none.
static func object_id(o: Variant) -> String:
	if not o is Dictionary:
		return ""
	for member in ["id", "abstract", "om_terrain", "nested_mapgen_id", "update_mapgen_id", "name"]:
		if o.has(member):
			var v: Variant = o[member]
			if v is String:
				return v
			if v is Array:
				var ids := PackedStringArray()
				_flatten(v, ids)
				if ids.size() > 0:
					return ", ".join(ids) if ids.size() <= 3 else "%s ... %s (%d)" % [ids[0], ids[-1], ids.size()]
			# "name" is a translation object on most types: not an id.
	return ""


static func _flatten(v: Variant, out: PackedStringArray) -> void:
	if v is Array:
		for x: Variant in v:
			_flatten(x, out)
	elif v is String:
		out.append(v)


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


## Why [param rel] can't be a path to write into BN, or "". The manifest is
## a plain file, so its paths aren't trusted.
static func check_rel(rel: String) -> String:
	if rel.is_empty() or rel.is_absolute_path() or rel.contains("\\") or rel.contains(":"):
		return "not a relative path: " + rel
	for part in rel.split("/"):
		if part in ["", ".", ".."]:
			return "not a plain relative path: " + rel
	return ""


## Copies [param rel] from the workspace into BN, then deletes the workspace
## copy and its manifest entry. A conflict is only pushed with [param
## overwrite]. The status is checked again here, so a stale sync window
## can't overwrite a change it didn't show. Returns an error or "".
func push(rel: String, overwrite := false) -> String:
	var problem := check_rel(rel)
	if problem:
		return problem
	problem = Workspace.check_root(workspace.root, workspace.bn_path)
	if problem:
		return problem
	var s := status(rel)
	if s.state == State.MISSING:
		return "%s isn't in the workspace" % rel
	if s.is_conflict() and not overwrite:
		return "%s: %s" % [rel, s.text()]
	if s.state != State.SAME:
		var err := _write_bn(rel, FileAccess.get_file_as_bytes(workspace.path(rel)))
		if err:
			return err
	return remove_copy(rel)


## Writes [param bytes] to BN's [param rel] through a temp file and a rename,
## so a failed write never leaves half a file.
func _write_bn(rel: String, bytes: PackedByteArray) -> String:
	var target := workspace.bn_path.path_join(rel)
	var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if err != OK:
		return "can't create %s: %s" % [target.get_base_dir(), error_string(err)]
	var tmp := target + TEMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "can't write %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_buffer(bytes)
	f.close()
	err = DirAccess.rename_absolute(tmp, target)
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return "can't replace %s: %s" % [target, error_string(err)]
	if FileAccess.get_file_as_bytes(target) != bytes:
		return "%s doesn't read back as written" % target
	return ""


## Deletes the workspace copy of [param rel] and its manifest entry, so BN's
## file is used again (after a push, or to throw the edits away). Returns an
## error or "".
func remove_copy(rel: String) -> String:
	var problem := check_rel(rel)
	if problem:
		return problem
	var path := workspace.path(rel)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return "can't delete %s: %s" % [path, error_string(err)]
		_remove_empty_dirs(path.get_base_dir())
	return workspace.set_entry(rel, null)


## Deletes [param dir] and its parents while they are empty, up to the
## workspace root.
func _remove_empty_dirs(dir: String) -> void:
	var root := workspace.root.simplify_path()
	dir = dir.simplify_path()
	while dir.begins_with(root + "/") and DirAccess.get_files_at(dir).is_empty() \
			and DirAccess.get_directories_at(dir).is_empty():
		if DirAccess.remove_absolute(dir) != OK:
			return
		dir = dir.get_base_dir()

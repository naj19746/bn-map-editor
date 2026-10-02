class_name JsonFile
extends RefCounted
## A BN JSON file opened for editing: its top-level objects as BnJson values.
##
## compose() writes each top-level object that still matches the original
## back as its original text, and re-encodes only the ones that changed. The
## formatter keeps string escapes as written, so this keeps untouched objects
## byte-identical even in files BnJson can't reproduce (\u escapes, duplicate
## keys; see BnJson.ParseResult.warnings).
##
## Callers must call touch(i) before changing object i. remove(i) takes an
## object out (every later one moves down an index) and insert() puts it
## back, original text included.

## Relative to the BN checkout / workspace, e.g. "data/json/mapgen/house.json".
var rel_path := ""
## The top-level objects. A file holding one bare object has one entry.
var objects: Array = []
## True when the file is one bare object rather than an array.
var single_object := false
## sha256 of the BN file this was read from; "" if it was read from the
## workspace or is new.
var base_sha256 := ""
## True when it was read from the workspace (or has been saved there).
var in_workspace := false
## True for a file created in the editor and not saved yet.
var is_new := false
## The file this was read from or last written to (absolute), and the
## sha256 of its bytes then ("" when there was no file: a new one). Saving
## refuses when that file no longer matches (see EditSession.save).
var disk_path := ""
var disk_sha256 := ""
var warnings := PackedStringArray()

var _raw := PackedByteArray()
var _spans: Array[Vector2i] = []
var _warning_offsets := PackedInt64Array()
## index -> BnJson.stringify of the object as read, captured by touch().
var _pristine := {}
## index -> BnJson.stringify as last saved, for is_dirty().
var _saved := {}
var _saved_count := 0


## A top-level object remove() took out, with what insert() needs to put it
## back as it was.
class Removed:
	var index := 0
	var object: Variant
	## Its original text's span, or (-1, -1) for an object added since the
	## file was read.
	var span := Vector2i(-1, -1)
	var pristine: Variant = null
	var saved: Variant = null
	var single_object := false


## Reads [param abs_path]. Returns null and sets [param error_out][0] on failure.
static func load_file(abs_path: String, rel: String, error_out: Array = []) -> JsonFile:
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes.is_empty() and not FileAccess.file_exists(abs_path):
		error_out.append("can't read " + abs_path)
		return null
	var parsed := BnJson.parse_bytes(bytes)
	if not parsed.ok():
		error_out.append("%s:%d: %s" % [rel, parsed.error_line, parsed.error])
		return null
	var f := JsonFile.new()
	f.rel_path = rel
	f._raw = bytes
	f.warnings = parsed.warnings
	f._warning_offsets = parsed.warning_offsets
	if parsed.value is Array:
		f.objects = parsed.value
		f._spans = parsed.spans
	else:
		f.objects = [parsed.value]
		f.single_object = true
		f._spans = [Vector2i(0, bytes.size())]
	f._saved_count = f.objects.size()
	f.disk_path = abs_path
	f.disk_sha256 = sha256_of(bytes)
	return f


static func sha256_of(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## The sha256 of the file at [param path], or "" if there is none.
static func sha256_at(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


## True when the file this was read from (or last written to) isn't as it
## was then: another program (e.g. the editor next to the MCP server) wrote,
## deleted or created it.
func changed_on_disk() -> bool:
	return not disk_path.is_empty() and sha256_at(disk_path) != disk_sha256


## A file that doesn't exist yet.
static func create(rel: String) -> JsonFile:
	var f := JsonFile.new()
	f.rel_path = rel
	f.is_new = true
	return f


## A new file goes to [param abs_path], where nothing may appear before it
## is saved.
static func create_at(rel: String, abs_path: String) -> JsonFile:
	var f := create(rel)
	f.disk_path = abs_path
	return f


## Call before changing objects[i].
func touch(i: int) -> void:
	if not _pristine.has(i) and i < _spans.size():
		var s := BnJson.stringify(objects[i])
		_pristine[i] = s
		_saved[i] = s


## Appends a new object; returns its index.
func append(o: Dictionary) -> int:
	# A bare object becomes the first element of an array.
	single_object = false
	objects.append(o)
	return objects.size() - 1


## Takes objects[[param i]] out; the later objects move down one index.
func remove(i: int) -> Removed:
	var r := Removed.new()
	r.index = i
	r.object = objects[i]
	r.single_object = single_object
	if i < _spans.size():
		r.span = _spans[i]
		_spans.remove_at(i)
	r.pristine = _pristine.get(i)
	r.saved = _saved.get(i)
	objects.remove_at(i)
	single_object = false
	_pristine = _shift_keys(_pristine, i, -1)
	_saved = _shift_keys(_saved, i, -1)
	return r


## Puts back what remove() took out, at the same index (the later objects
## move up one). An original object is written back as its original text
## again. Undo removals last first: an original can only go back while the
## originals before it are in place.
func insert(r: Removed) -> void:
	var i := r.index
	objects.insert(i, r.object)
	if r.span.x >= 0:
		_spans.insert(i, r.span)
	_pristine = _shift_keys(_pristine, i, 1)
	_saved = _shift_keys(_saved, i, 1)
	if r.pristine != null:
		_pristine[i] = r.pristine
	if r.saved != null:
		_saved[i] = r.saved
	single_object = r.single_object and objects.size() == 1


## [param d] (index -> value) with the entries for [param i] and after
## moved by [param delta]; a removal (-1) drops entry [param i].
static func _shift_keys(d: Dictionary, i: int, delta: int) -> Dictionary:
	var out := {}
	for k: int in d:
		if k < i:
			out[k] = d[k]
		elif k > i or delta > 0:
			out[k + delta] = d[k]
	return out


## Unsaved changes: an object changed since the last save, or objects added.
func is_dirty() -> bool:
	if objects.size() != _saved_count or is_new:
		return true
	for i: int in _pristine:
		if BnJson.stringify(objects[i]) != _saved[i]:
			return true
	for i in range(_spans.size(), objects.size()):
		if not _saved.has(i) or BnJson.stringify(objects[i]) != _saved[i]:
			return true
	return false


## True when objects[i] will be written back as its original text.
func is_original(i: int) -> bool:
	return i < _spans.size() and (not _pristine.has(i) or BnJson.stringify(objects[i]) == _pristine[i])


## Compact JSON for the formatter.
func compose() -> String:
	var out := PackedByteArray()
	if not single_object:
		out.append(0x5b)
	for i in objects.size():
		if i > 0:
			out.append(0x2c)
		if is_original(i):
			out.append_array(_raw.slice(_spans[i].x, _spans[i].y))
		else:
			out.append_array(BnJson.stringify(objects[i]).to_utf8_buffer())
	if not single_object:
		out.append(0x5d)
	return out.get_string_from_utf8()


## Warnings inside objects that will be re-encoded: what saving normalizes.
func lossy_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for w in warnings.size():
		var at := _warning_offsets[w]
		for i in _spans.size():
			if at >= _spans[i].x and at < _spans[i].y and not is_original(i):
				out.append(warnings[w])
	return out


## Records the current state as saved to [param abs_path], whose bytes now
## hash to [param sha256].
func mark_saved(abs_path := "", sha256 := "") -> void:
	if abs_path:
		disk_path = abs_path
		disk_sha256 = sha256
	in_workspace = true
	is_new = false
	_saved_count = objects.size()
	for i: int in _pristine:
		_saved[i] = BnJson.stringify(objects[i])
	for i in range(_spans.size(), objects.size()):
		_saved[i] = BnJson.stringify(objects[i])


## The saved file was pushed into BN (and the workspace copy deleted):
## [param sha256] is BN's file at [param bn_file] now, the base for the
## next save.
func mark_pushed(sha256: String, bn_file := "") -> void:
	in_workspace = false
	base_sha256 = sha256
	if bn_file:
		disk_path = bn_file
		disk_sha256 = sha256

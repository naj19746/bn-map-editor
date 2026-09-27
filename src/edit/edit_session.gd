class_name EditSession
extends RefCounted
## The files and maps open for editing, and saving them to the workspace.
##
## Maps from the same file share one JsonFile, so saving one keeps the
## others' edits. Files are read from the workspace copy if there is one,
## else from BN, and always saved to the workspace through json_formatter.

## Where a stub overmap_terrain copies from: an abstract city building in core.
const OVERMAP_STUB_BASE := "generic_city_building"
const DEFAULT_FILL := "t_grass"

var index: DataIndex
var workspace: Workspace
var formatter: JsonFormatter
## rel path -> JsonFile, for files with open maps.
var files := {}
var docs: Array[MapDocument] = []
## Set when open(), create_mapgen() or save() fail.
var last_error := ""
## What the last save re-encoded that wasn't canonical (see JsonFile).
var last_notes := PackedStringArray()

## rel path -> Array of MapgenRef / overmap_terrain ids added to the index
## but not saved yet, taken out again if the file is discarded.
var _new_refs := {}
var _new_overmap := {}


func _init(p_index: DataIndex, p_workspace: Workspace, p_formatter: JsonFormatter = null) -> void:
	index = p_index
	workspace = p_workspace
	formatter = p_formatter if p_formatter else JsonFormatter.new()


## The file at [param rel], read on first use. null (see last_error) if it
## can't be read or parsed.
func get_file(rel: String) -> JsonFile:
	if files.has(rel):
		return files[rel]
	var abs_path := index.file_path(rel)
	var err := []
	var f := JsonFile.load_file(abs_path, rel, err)
	if f == null:
		last_error = err[0]
		return null
	f.in_workspace = index.in_workspace(rel)
	if not f.in_workspace:
		f.base_sha256 = FileAccess.get_sha256(abs_path)
	files[rel] = f
	return f


## Opens [param ref] for editing, or returns its open document.
func open(ref: DataIndex.MapgenRef) -> MapDocument:
	for d in docs:
		if d.ref == ref:
			return d
	if ref.method != "json":
		last_error = "%s is a %s mapgen; only json mapgen can be edited." % [ref.title(), ref.method]
		return null
	var had_file := files.has(ref.source.path)
	var f := get_file(ref.source.path)
	if f == null:
		return null
	var doc := MapDocument.open(index, f, ref.source.index, ref) if _is_entry(f, ref) else null
	if doc == null:
		last_error = "%s #%d is no longer the mapgen for %s; reload the data (F5)." % [
			ref.source.path, ref.source.index, ref.title()]
		if not had_file:
			files.erase(ref.source.path)
		return null
	docs.append(doc)
	return doc


## True when the file's object at ref's index is still that mapgen.
static func _is_entry(f: JsonFile, ref: DataIndex.MapgenRef) -> bool:
	var i := ref.source.index
	if i >= f.objects.size() or not f.objects[i] is Dictionary:
		return false
	var o: Dictionary = f.objects[i]
	for member in ["om_terrain", "nested_mapgen_id", "update_mapgen_id"]:
		if o.has(member):
			return JSON.stringify(o[member]).contains(JSON.stringify(ref.ids[0]))
	return false


func docs_for(rel: String) -> Array[MapDocument]:
	var out: Array[MapDocument] = []
	for d in docs:
		if d.file.rel_path == rel:
			out.append(d)
	return out


func is_dirty(rel: String) -> bool:
	return files.has(rel) and files[rel].is_dirty()


func dirty_files() -> PackedStringArray:
	var out := PackedStringArray()
	for rel: String in files:
		if files[rel].is_dirty():
			out.append(rel)
	return out


## Writes [param rel] to the workspace. Returns an error, or "".
func save(rel: String) -> String:
	last_notes = PackedStringArray()
	var f: JsonFile = files.get(rel)
	if f == null:
		return _fail("%s isn't open" % rel)
	if not formatter.is_available():
		return _fail("can't save without json_formatter: %s isn't built (run tools/build_json_formatter.sh)" % formatter.executable)
	var formatted := formatter.format(f.compose())
	if not formatted.ok():
		return _fail(formatted.error)
	var err := workspace.write_file(rel, formatted.text, f.base_sha256)
	if err:
		return _fail(err)
	last_notes = f.lossy_warnings()
	f.mark_saved()
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	return ""


## Saves every file with changes. Returns the errors.
func save_all() -> PackedStringArray:
	var errors := PackedStringArray()
	for rel in dirty_files():
		var err := save(rel)
		if err:
			errors.append("%s: %s" % [rel, err])
	return errors


## Closes [param doc]. When it's the last open map of its file, the file is
## dropped too, and with it any unsaved changes: ask first (is_dirty).
func close(doc: MapDocument) -> void:
	docs.erase(doc)
	var rel := doc.file.rel_path
	if not docs_for(rel).is_empty():
		return
	for ref: DataIndex.MapgenRef in _new_refs.get(rel, []):
		index.remove_mapgen(ref)
	for id: String in _new_overmap.get(rel, []):
		index.overmap_terrain.erase(id)
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	files.erase(rel)


# --- New mapgen ----------------------------------------------------------------

## A new om_terrain mapgen. [param ids] is the om_terrain grid by row (one
## id for a 1x1 map); rows start blank so fill_ter shows everywhere.
class NewMapgen:
	var rel_path := ""
	var ids: Array[PackedStringArray] = []
	var fill_ter := EditSession.DEFAULT_FILL
	var palettes := PackedStringArray()
	## Also add overmap_terrain entries for ids that have none.
	var add_overmap_terrain := true


## The default om_terrain grid for [param base]: the id itself for 1x1,
## else base_<column>_<row> counted from 1.
static func default_ids(base: String, w: int, h: int) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for y in h:
		var row := PackedStringArray()
		for x in w:
			row.append(base if w == 1 and h == 1 else "%s_%d_%d" % [base, x + 1, y + 1])
		out.append(row)
	return out


## Why [param spec] can't be created, or "".
func check_new_mapgen(spec: NewMapgen) -> String:
	var rel := spec.rel_path
	if not rel.ends_with(".json") or rel.is_absolute_path() or rel.contains("..") or rel.contains("\\"):
		return "The file must be a relative .json path, e.g. data/json/mapgen/my_map.json."
	if index.mod_for_path(rel).is_empty():
		return "%s isn't inside a loaded mod's data folder, so BN wouldn't load it." % rel
	if spec.ids.is_empty() or spec.ids[0].is_empty():
		return "Enter at least one om_terrain id."
	var seen := {}
	for row in spec.ids:
		if row.size() != spec.ids[0].size():
			return "Every row of the om_terrain grid needs the same number of ids."
		for id in row:
			if id.is_empty() or id.contains(" ") or id.contains("\""):
				return "\"%s\" isn't a valid id." % id
			if seen.has(id):
				return "\"%s\" appears twice in the grid." % id
			seen[id] = true
	if not index.terrain.has(spec.fill_ter):
		return "Unknown fill_ter terrain \"%s\"." % spec.fill_ter
	for p in spec.palettes:
		if index.palette(p) == null:
			return "Unknown palette \"%s\"." % p
	if files.has(rel) or index.in_workspace(rel) or FileAccess.file_exists(index.bn_path.path_join(rel)):
		var f := get_file(rel)
		if f == null:
			return "Can't add to %s: %s" % [rel, last_error]
	return ""


## Adds the mapgen described by [param spec] (to its file, created if new)
## and opens it. null (see last_error) if check_new_mapgen fails.
func create_mapgen(spec: NewMapgen) -> MapDocument:
	var problem := check_new_mapgen(spec)
	if problem:
		_fail(problem)
		return null
	var rel := spec.rel_path
	var f := get_file(rel) if files.has(rel) or index.in_workspace(rel) \
			or FileAccess.file_exists(index.bn_path.path_join(rel)) else null
	if f == null:
		f = JsonFile.create(rel)
		files[rel] = f
	var w := spec.ids[0].size()
	var h := spec.ids.size()
	var om: Variant = spec.ids[0][0]
	if w > 1 or h > 1:
		om = []
		for row in spec.ids:
			om.append(Array(row))
	var obj := {"fill_ter": spec.fill_ter}
	var rows := []
	for y in h * MapgenResolver.OMT_SIZE:
		rows.append(" ".repeat(w * MapgenResolver.OMT_SIZE))
	obj["rows"] = rows
	if not spec.palettes.is_empty():
		obj["palettes"] = Array(spec.palettes)
	var mapgen := {"type": "mapgen", "method": "json", "om_terrain": om, "object": obj}
	var i := f.append(mapgen)
	var ref := index.add_mapgen(mapgen, DataIndex.Source.new(index.mod_for_path(rel), rel, i))
	_remember(_new_refs, rel, ref)
	var doc := MapDocument.open(index, f, i, ref)
	docs.append(doc)
	if spec.add_overmap_terrain:
		add_missing_overmap_terrain(doc)
	return doc


## Appends a minimal overmap_terrain for [param doc]'s om_terrain ids that
## have none, next to the map in its file. Returns the ids added.
func add_missing_overmap_terrain(doc: MapDocument) -> PackedStringArray:
	var missing := doc.missing_overmap_terrain()
	if missing.is_empty():
		return missing
	var rel := doc.file.rel_path
	var i := doc.file.append(overmap_stub(missing))
	var src := DataIndex.Source.new(index.mod_for_path(rel), rel, i)
	for id in missing:
		index.overmap_terrain[id] = src
		_remember(_new_overmap, rel, id)
	return missing


## A minimal overmap_terrain for [param ids]: a city building named after
## the first id. Rotatable, so BN adds the _north/_east/... variants itself.
static func overmap_stub(ids: PackedStringArray) -> Dictionary:
	return {
		"type": "overmap_terrain",
		"id": ids[0] if ids.size() == 1 else Array(ids),
		"copy-from": OVERMAP_STUB_BASE,
		"name": ids[0].replace("_", " "),
		"color": "light_gray",
	}


func _remember(table: Dictionary, rel: String, value: Variant) -> void:
	if not table.has(rel):
		table[rel] = []
	table[rel].append(value)


func _fail(msg: String) -> String:
	last_error = msg
	return msg

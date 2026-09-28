class_name EditSession
extends RefCounted
## The files and maps open for editing, and saving them to the workspace.
##
## Maps and palettes from the same file share one JsonFile, so saving one
## keeps the others' edits. Files are read from the workspace copy if there
## is one, else from BN, and always saved to the workspace through
## json_formatter.
##
## An open palette's DataIndex definition points at the live object, so
## every map resolved afterwards sees its edits; open maps that use it are
## refreshed when it changes. Discarding a file puts the index back as the
## file on disk has it.
##
## Open maps draw the nested chunks they place (MapDocument.chunk_overlay),
## read through [member objects], so an edited chunk or palette shows up in
## every open map drawing it: those are told to lay their chunks out again.

## Where a stub overmap_terrain copies from: an abstract city building in core.
const OVERMAP_STUB_BASE := "generic_city_building"
const DEFAULT_FILL := "t_grass"

var index: DataIndex
var workspace: Workspace
var formatter: JsonFormatter
## rel path -> JsonFile, for files with open maps.
var files := {}
var docs: Array[MapDocument] = []
var palette_docs: Array[PaletteDocument] = []
## Mapgen objects for drawing chunks: open files live, others from disk.
var objects: MapgenObjects
## Set when open(), create_mapgen() or save() fail.
var last_error := ""
## What the last save re-encoded that wasn't canonical (see JsonFile).
var last_notes := PackedStringArray()

## rel path -> Array of MapgenRef / overmap_terrain ids added to the index
## but not saved yet, taken out again if the file is discarded.
var _new_refs := {}
var _new_overmap := {}
var _new_palettes := {}


func _init(p_index: DataIndex, p_workspace: Workspace, p_formatter: JsonFormatter = null) -> void:
	index = p_index
	workspace = p_workspace
	formatter = p_formatter if p_formatter else JsonFormatter.new()
	objects = MapgenObjects.new(index, _live_objects)


## The objects of open file [param rel], or null.
func _live_objects(rel: String) -> Variant:
	return files[rel].objects if files.has(rel) else null


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
	_add_doc(doc)
	return doc


func _add_doc(doc: MapDocument) -> void:
	doc.objects = objects
	# Bound to the chunk id, not the document: that would be a reference cycle.
	doc.changed.connect(_on_map_changed.bind(doc.chunk_id()))
	docs.append(doc)


## A map changed; if it's a chunk, the maps drawing it lay their chunks out
## again.
func _on_map_changed(_full: bool, chunk_id: String) -> void:
	if chunk_id.is_empty():
		return
	for d in docs:
		if d.overlay_uses(chunk_id):
			d.refresh_overlay()


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


## Opens the palette definition [param def] for editing, or returns its open
## document.
func open_palette(def: DataIndex.Definition) -> PaletteDocument:
	for d in palette_docs:
		if d.def == def:
			return d
	if def.source.path.is_empty():
		last_error = "palette %s has no file" % def.id
		return null
	var had_file := files.has(def.source.path)
	var f := get_file(def.source.path)
	if f == null:
		return null
	var doc := PaletteDocument.open(index, f, def.source.index, def)
	if doc == null:
		last_error = "%s #%d is no longer palette %s; reload the data (F5)." % [
			def.source.path, def.source.index, def.id]
		if not had_file:
			files.erase(def.source.path)
		return null
	def.data = doc.palette()
	# Bound to the id, not the document: that would be a reference cycle.
	doc.changed.connect(_on_palette_changed.bind(doc.id))
	palette_docs.append(doc)
	return doc


## Closes [param doc]; like close(), the file goes with its last document.
func close_palette(doc: PaletteDocument) -> void:
	palette_docs.erase(doc)
	doc.changed.disconnect(_on_palette_changed)
	_release_file(doc.file.rel_path)


## The open palette document for [param def], or null.
func palette_doc_for(def: DataIndex.Definition) -> PaletteDocument:
	for d in palette_docs:
		if d.def == def:
			return d
	return null


## The maps [param c] (an uncommitted change of [param doc]) would change.
func impact_of(doc: PaletteDocument, c: PaletteDocument.Change) -> Array[PaletteImpact.Affected]:
	if c == null:
		return [] as Array[PaletteImpact.Affected]
	return PaletteImpact.measure(self, doc.id, doc.apply.bind(c, true), doc.apply.bind(c, false))


## Why [param map_doc]'s own symbol [param key] can't move into
## [param pal_doc], or "".
func check_move_symbol(map_doc: MapDocument, pal_doc: PaletteDocument, key: String) -> String:
	if not map_doc.own_keys().has(key):
		return "'%s' isn't defined in the map's own terrain/furniture." % key
	if pal_doc.overridden_by():
		return "Palette %s is replaced by the definition in %s, so the map wouldn't see it." % [
			pal_doc.id, pal_doc.overridden_by().source]
	if not map_doc.resolved.palettes.has(pal_doc.id):
		return "The map doesn't use palette %s." % pal_doc.id
	for options in map_doc.resolved.choice_options:
		if options.has(pal_doc.id):
			return "The map only uses palette %s as one option of a choice." % pal_doc.id
	var ter: Variant = map_doc.own_value(key, "terrain")
	var furn: Variant = map_doc.own_value(key, "furniture")
	return pal_doc.check_tiles(key, ter if ter is String else null, furn if furn is String else null)


## The two changes moving [param key]: [palette change or null, map change].
func _move_changes(map_doc: MapDocument, pal_doc: PaletteDocument, key: String) -> Array:
	var name := "Move '%s' from %s to %s" % [key, map_doc.ref.title(), pal_doc.id]
	# Only the kinds the map defines move; the palette keeps its others,
	# which the map may already get from it.
	var pc := pal_doc.build_set_tiles(key, map_doc.own_value(key, "terrain"),
			map_doc.own_value(key, "furniture"), name)
	return [pc, map_doc.build_remove_own_symbol(key, name)]


## The maps moving [param key] would change (ideally none: the moved map
## should look the same).
func move_symbol_impact(map_doc: MapDocument, pal_doc: PaletteDocument, key: String) -> Array[PaletteImpact.Affected]:
	var cs := _move_changes(map_doc, pal_doc, key)
	var apply := func() -> void:
		if cs[0]:
			pal_doc.apply(cs[0], true)
		if cs[1]:
			map_doc.apply_change(cs[1], true)
	var revert := func() -> void:
		if cs[1]:
			map_doc.apply_change(cs[1], false)
		if cs[0]:
			pal_doc.apply(cs[0], false)
	return PaletteImpact.measure(self, pal_doc.id, apply, revert)


## Moves [param map_doc]'s own terrain/furniture for [param key] into
## [param pal_doc]: one undo step in the palette and one in the map.
## Returns an error, or "".
func move_symbol(map_doc: MapDocument, pal_doc: PaletteDocument, key: String) -> String:
	var problem := check_move_symbol(map_doc, pal_doc, key)
	if problem:
		return problem
	var cs := _move_changes(map_doc, pal_doc, key)
	pal_doc.commit(cs[0])
	map_doc.commit(cs[1])
	return ""


## The maps placing chunk [param ref]'s id: directly, through a palette's
## "nested" mapping their rows use, or through other chunks (then "via" says
## which, e.g. "chunk_b > chunk_a").
func chunk_parents(ref: DataIndex.MapgenRef) -> Array[PaletteImpact.Affected]:
	var chunk := PaletteImpact.Affected.new()
	chunk.ref = ref
	var list: Array[PaletteImpact.Affected] = [chunk]
	PaletteImpact.new(self).add_parents(list)
	return list.slice(1)


func _on_palette_changed(id: String) -> void:
	for d in docs:
		if d.uses_palette(id):
			d.refresh()
		elif d.overlay_uses("", id):
			d.refresh_overlay()


func docs_for(rel: String) -> Array[MapDocument]:
	var out: Array[MapDocument] = []
	for d in docs:
		if d.file.rel_path == rel:
			out.append(d)
	return out


## Open maps plus open palettes of file [param rel].
func open_count(rel: String) -> int:
	var n := docs_for(rel).size()
	for d in palette_docs:
		if d.file.rel_path == rel:
			n += 1
	return n


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
	for d in docs_for(rel):
		var blocked := d.save_problems()
		if not blocked.is_empty():
			return _fail("%s: %s" % [d.ref.title(), blocked[0]])
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
	objects.forget(rel)
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	_new_palettes.erase(rel)
	return ""


## [param rel] was pushed into BN and its workspace copy deleted. An open
## copy now counts as read from BN, so its next save records BN's new file
## as the base instead of marking the file new.
func mark_pushed(rel: String) -> void:
	if files.has(rel):
		files[rel].mark_pushed(FileAccess.get_sha256(workspace.bn_path.path_join(rel)))


## Saves every file with changes. Returns the errors.
func save_all() -> PackedStringArray:
	var errors := PackedStringArray()
	for rel in dirty_files():
		var err := save(rel)
		if err:
			errors.append("%s: %s" % [rel, err])
	return errors


## Closes [param doc]. When it's the last open map or palette of its file,
## the file is dropped too, and with it any unsaved changes: ask first
## (is_dirty).
func close(doc: MapDocument) -> void:
	docs.erase(doc)
	doc.changed.disconnect(_on_map_changed)
	_release_file(doc.file.rel_path)


## Drops file [param rel] once nothing has it open. Unsaved changes are
## thrown away, and the index is put back as the file on disk has it.
func _release_file(rel: String) -> void:
	if open_count(rel) > 0 or not files.has(rel):
		return
	var dirty: bool = files[rel].is_dirty()
	for ref: DataIndex.MapgenRef in _new_refs.get(rel, []):
		index.remove_mapgen(ref)
	for id: String in _new_overmap.get(rel, []):
		index.overmap_terrain.erase(id)
	for def: DataIndex.Definition in _new_palettes.get(rel, []):
		index.remove_palette(def)
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	_new_palettes.erase(rel)
	files.erase(rel)
	objects.forget(rel)
	if dirty:
		_reindex_from_disk(rel)
		# Chunks or palettes from the file are back as on disk.
		for d in docs:
			d.refresh_overlay()


## Palette data and maps' palette and chunk lists of [param rel] as the file
## on disk has them (the editor changed them in place).
func _reindex_from_disk(rel: String) -> void:
	var json := JSON.new()
	var path := index.file_path(rel)
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var parsed: Variant = json.data
	var on_disk: Array = [parsed] if parsed is Dictionary else (parsed if parsed is Array else [])
	for id: String in index.palettes:
		for def: DataIndex.Definition in index.palettes[id]:
			if def.source.path == rel and def.source.index < on_disk.size() and on_disk[def.source.index] is Dictionary:
				def.data = on_disk[def.source.index]
	for ref in index.mapgens:
		if ref.source.path == rel and ref.source.index < on_disk.size() and on_disk[ref.source.index] is Dictionary:
			var obj: Variant = on_disk[ref.source.index].get("object")
			ref.palettes = DataIndex.palette_options(obj) if obj is Dictionary else PackedStringArray()
			ref.chunks = DataIndex.chunk_options(obj) if obj is Dictionary else PackedStringArray()


# --- New palette ---------------------------------------------------------------

## Where a new palette [param id] goes by default: core's mapgen_palettes
## folder, or that folder in the mod of [param near_rel] (e.g. the open map).
func default_palette_path(id: String, near_rel := "") -> String:
	var mod := index.mod_for_path(near_rel) if near_rel else ""
	var dir := "data/json/mapgen_palettes"
	if mod and not index.catalog.get_mod(mod).core:
		dir = index.relative_path(index.catalog.get_mod(mod).path).path_join("mapgen_palettes")
	return dir.path_join((id if id else "new_palette") + ".json")


## Why a palette [param id] can't be created in [param rel], or "".
func check_new_palette(rel: String, id: String) -> String:
	var path_problem := _check_new_path(rel)
	if path_problem:
		return path_problem
	if id.is_empty() or id.contains(" ") or id.contains("\"") or id.contains("\\"):
		return "\"%s\" isn't a valid palette id." % id
	var existing := index.palette(id)
	if existing:
		return "Palette %s already exists (%s); a second definition would replace it." % [id, existing.source]
	if _file_exists(rel):
		var f := get_file(rel)
		if f == null:
			return "Can't add to %s: %s" % [rel, last_error]
	return ""


## Adds an empty palette [param id] to [param rel] (created if new) and
## opens it. null (see last_error) if check_new_palette fails.
func create_palette(rel: String, id: String) -> PaletteDocument:
	var problem := check_new_palette(rel, id)
	if problem:
		_fail(problem)
		return null
	var f := get_file(rel) if _file_exists(rel) else null
	if f == null:
		f = JsonFile.create(rel)
		files[rel] = f
	var o := {"type": "palette", "id": id}
	var i := f.append(o)
	var def := index.add_palette(o, DataIndex.Source.new(index.mod_for_path(rel), rel, i))
	_remember(_new_palettes, rel, def)
	return open_palette(def)


## True when [param rel] exists: open, in the workspace, or in BN.
func _file_exists(rel: String) -> bool:
	return files.has(rel) or index.in_workspace(rel) or FileAccess.file_exists(index.bn_path.path_join(rel))


## Why a new object can't go into [param rel], or "".
func _check_new_path(rel: String) -> String:
	if not rel.ends_with(".json") or rel.is_absolute_path() or rel.contains("..") or rel.contains("\\"):
		return "The file must be a relative .json path, e.g. data/json/mapgen/my_map.json."
	if index.mod_for_path(rel).is_empty():
		return "%s isn't inside a loaded mod's data folder, so BN wouldn't load it." % rel
	return ""


# --- New mapgen ----------------------------------------------------------------

## A new om_terrain mapgen or nested chunk. [param ids] is the om_terrain
## grid by row (one id for a 1x1 map), or the chunk's nested_mapgen_id alone.
## Rows start blank: fill_ter shows everywhere, and a chunk leaves every cell
## as it finds it.
class NewMapgen:
	var rel_path := ""
	var ids: Array[PackedStringArray] = []
	var fill_ter := EditSession.DEFAULT_FILL
	var palettes := PackedStringArray()
	## Also add overmap_terrain entries for ids that have none.
	var add_overmap_terrain := true
	## Set for a nested chunk: its mapgensize, 1-24 cells each way. A chunk
	## gets no fill_ter (BN ignores it there) and no overmap_terrain.
	var chunk_size := Vector2i.ZERO

	func is_chunk() -> bool:
		return chunk_size != Vector2i.ZERO


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
	var path_problem := _check_new_path(rel)
	if path_problem:
		return path_problem
	if spec.ids.is_empty() or spec.ids[0].is_empty():
		return "Enter the nested_mapgen_id." if spec.is_chunk() else "Enter at least one om_terrain id."
	if spec.is_chunk():
		if spec.ids.size() != 1 or spec.ids[0].size() != 1:
			return "A chunk has one nested_mapgen_id."
		if spec.chunk_size.x < 1 or spec.chunk_size.y < 1 or spec.chunk_size.x > MapgenResolver.OMT_SIZE \
				or spec.chunk_size.y > MapgenResolver.OMT_SIZE:
			return "A chunk's mapgensize is 1-24 cells each way."
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
	if not spec.is_chunk() and not index.terrain.has(spec.fill_ter):
		return "Unknown fill_ter terrain \"%s\"." % spec.fill_ter
	for p in spec.palettes:
		if index.palette(p) == null:
			return "Unknown palette \"%s\"." % p
	if _file_exists(rel):
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
	var f := get_file(rel) if _file_exists(rel) else null
	if f == null:
		f = JsonFile.create(rel)
		files[rel] = f
	var mapgen := _new_mapgen_object(spec)
	var i := f.append(mapgen)
	var ref := index.add_mapgen(mapgen, DataIndex.Source.new(index.mod_for_path(rel), rel, i))
	_remember(_new_refs, rel, ref)
	var doc := MapDocument.open(index, f, i, ref)
	_add_doc(doc)
	if spec.add_overmap_terrain and not spec.is_chunk():
		add_missing_overmap_terrain(doc)
	return doc


static func _new_mapgen_object(spec: NewMapgen) -> Dictionary:
	var cells := spec.chunk_size
	var obj := {}
	if spec.is_chunk():
		obj["mapgensize"] = [cells.x, cells.y]
	else:
		cells = Vector2i(spec.ids[0].size(), spec.ids.size()) * MapgenResolver.OMT_SIZE
		obj["fill_ter"] = spec.fill_ter
	var rows := []
	for y in cells.y:
		rows.append(" ".repeat(cells.x))
	obj["rows"] = rows
	if not spec.palettes.is_empty():
		obj["palettes"] = Array(spec.palettes)
	var mapgen := {"type": "mapgen", "method": "json"}
	if spec.is_chunk():
		mapgen["nested_mapgen_id"] = spec.ids[0][0]
	elif spec.ids.size() == 1 and spec.ids[0].size() == 1:
		mapgen["om_terrain"] = spec.ids[0][0]
	else:
		mapgen["om_terrain"] = spec.ids.map(func(row: PackedStringArray) -> Array: return Array(row))
	mapgen["object"] = obj
	return mapgen


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
	for d in docs:
		d.forget_findings()
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

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
## A map's stair and elevator findings read the other levels of its
## buildings, so when a map changes, every other open map sharing a
## building with it forgets its findings (MapDocument.levels_changed).
##
## Files other programs change (the MCP server next to the editor) are
## noticed by external_changes(): the open files, and the workspace's
## manifest and the files it lists, against what was read or saved.
##
## Taking an object out of a file (a deleted palette, an undone
## overmap_terrain stub) moves every later object down one index: the
## index's Sources (DataIndex.shift_sources) and the open documents follow
## (_remove_object / _insert_object).

## A map changed (a stroke's cells, or a completed edit), or the chunks it
## draws did: views drawing it elsewhere (neighbours, ghosts) redraw it.
signal map_edited(ref: DataIndex.MapgenRef)

## Where a stub overmap_terrain copies from: an abstract city building in core.
const OVERMAP_STUB_BASE := "generic_city_building"
## Stub bases for a new roof and basement (core's house levels copy these).
const ROOF_STUB_BASE := "generic_city_house_roof"
const BASEMENT_STUB_BASE := "generic_city_house_basement"
## The city lists of a region_settings "city" object that name buildings
## (regional_settings.cpp load_building_types).
const CITY_LISTS := DataIndex.CITY_LISTS
const REGION_SETTINGS_FILE := "data/json/regional_map_settings.json"
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
## rel path -> Array of DataIndex.Building the editor created there.
var _new_buildings := {}
## rel path -> Array of DeletedPalette, oldest first, until the file is
## saved or discarded.
var _deleted := {}
## rel path of a map file -> the building files a new level of it edited,
## released with it (see add_level_tiles).
var _linked := {}
## Absolute path -> sha256 ("" when missing) of the workspace's manifest and
## the files it lists, as this session last saw or wrote them (see
## external_changes).
var _stamps := {}
## Absolute path -> [modified time, size, sha256]: a file's hash, taken
## again only when its time or size moved (or it was written in the last
## couple of seconds, which a time in whole seconds can't tell apart).
var _hashes := {}


## A palette delete_palette() took out of its file, and where it was.
class DeletedPalette:
	var def: DataIndex.Definition
	var rel := ""
	var removed: JsonFile.Removed
	## Its place among the definitions of its id (load order).
	var position := 0
	## It was created in this session and not saved.
	var was_new := false
	## The undo steps the definition of its id in effect afterwards had
	## then (0 when it had no document): more now are edits made after
	## the deletion, which undo takes back first.
	var edits_before := 0


func _init(p_index: DataIndex, p_workspace: Workspace, p_formatter: JsonFormatter = null) -> void:
	index = p_index
	workspace = p_workspace
	formatter = p_formatter if p_formatter else JsonFormatter.new()
	objects = MapgenObjects.new(index, _live_objects)
	accept_external()


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
		f.base_sha256 = f.disk_sha256
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
	# Bound to the chunk id and ref, not the document: that would be a
	# reference cycle.
	doc.changed.connect(_on_map_changed.bind(doc.chunk_id(), doc.ref))
	doc.cells_changed.connect(_on_map_cells.bind(doc.ref))
	docs.append(doc)


## A map changed; if it's a chunk, the maps drawing it lay their chunks out
## again. The maps sharing a building with any of them forget their
## findings.
func _on_map_changed(_full: bool, chunk_id: String, ref: DataIndex.MapgenRef) -> void:
	var edited: Array[DataIndex.MapgenRef] = [ref]
	if chunk_id:
		for d in docs:
			if d.overlay_uses(chunk_id):
				d.refresh_overlay()
				edited.append(d.ref)
	for r in edited:
		_notify_levels(r)
		map_edited.emit(r)


## Cells painted during a stroke (the stroke's end also emits changed).
func _on_map_cells(_cells: Array[Vector2i], ref: DataIndex.MapgenRef) -> void:
	map_edited.emit(ref)


## Tells every other open map placed by a building that places [param ref]
## that one of its levels changed.
func _notify_levels(ref: DataIndex.MapgenRef) -> void:
	var ids := {}
	for p in BuildingLevels.places(index, ref):
		ids[p.building.id] = true
	if ids.is_empty():
		return
	for d in docs:
		if d.ref != ref and BuildingLevels.places(index, d.ref).any(
				func(p: BuildingLevels.Place) -> bool: return ids.has(p.building.id)):
			d.other_level_changed()


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
	var stale := check_on_disk(rel)
	if stale:
		return _fail(stale)
	var formatted := formatter.format(f.compose())
	if not formatted.ok():
		return _fail(formatted.error)
	var err := workspace.write_file(rel, formatted.text, f.base_sha256)
	if err:
		return _fail(err)
	last_notes = f.lossy_warnings()
	f.mark_saved(workspace.path(rel), JsonFile.sha256_at(workspace.path(rel)))
	# The session's own writes aren't changes by others.
	_stamps[workspace.path(rel)] = f.disk_sha256
	_stamps[workspace.path(Workspace.MANIFEST)] = _sha(workspace.path(Workspace.MANIFEST))
	objects.forget(rel)
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	_new_palettes.erase(rel)
	_deleted.erase(rel)
	return ""


## Why saving open file [param rel] would overwrite something it didn't
## read, or "": the file it was read from changed (or went) since, or a
## workspace copy appeared over a file read from BN. Only another program
## does that, e.g. the editor and the MCP server on one workspace.
func check_on_disk(rel: String) -> String:
	var f: JsonFile = files.get(rel)
	if f == null:
		return ""
	var target := workspace.path(rel)
	if f.changed_on_disk() or (f.disk_path != target and FileAccess.file_exists(target)):
		return "%s changed on disk since it was read (saved by another editor or MCP server?); " % rel \
				+ "reload the data to see it (unsaved edits to it are lost)"
	return ""


## Open files whose file on disk changed since they were read (see
## check_on_disk).
func changed_on_disk() -> PackedStringArray:
	var out := PackedStringArray()
	for rel: String in files:
		if check_on_disk(rel):
			out.append(rel)
	return out


## Files another program changed since this session read or wrote them
## (relative paths; "manifest.json" for the workspace manifest): an open
## file whose file on disk changed (check_on_disk), and the workspace's
## manifest and the files it lists (one created, changed or deleted). The
## editor reloads when it finds some (or asks, with unsaved edits); the
## MCP server does before a tool call. accept_external() forgets them.
func external_changes() -> PackedStringArray:
	var out := PackedStringArray()
	for rel: String in files:
		var f: JsonFile = files[rel]
		var target := workspace.path(rel)
		if (f.disk_path and _sha(f.disk_path) != _stamps.get(f.disk_path, f.disk_sha256)) \
				or (f.disk_path != target and _stamps.get(target, "") != _sha(target)):
			out.append(rel)
	var manifest := workspace.path(Workspace.MANIFEST)
	if _stamps.get(manifest, "") != _sha(manifest):
		out.append(Workspace.MANIFEST)
		workspace.reload_manifest()
	for rel: String in workspace.files:
		var path := workspace.path(rel)
		if not out.has(rel) and _stamps.get(path, "") != _sha(path):
			out.append(rel)
	for path: String in _stamps:
		var rel := path.trim_prefix(workspace.root + "/")
		if rel != path and rel != Workspace.MANIFEST and not out.has(rel) and not workspace.files.has(rel) \
				and _stamps[path] != _sha(path):
			out.append(rel)
	return out


## Takes the files on disk as they are now as seen (see external_changes):
## after loading, and after the user chose to keep their edits over them.
func accept_external() -> void:
	_stamps.clear()
	if workspace == null or workspace.root.is_empty():
		return
	workspace.reload_manifest()
	_stamps[workspace.path(Workspace.MANIFEST)] = _sha(workspace.path(Workspace.MANIFEST))
	for rel: String in workspace.files:
		_stamps[workspace.path(rel)] = _sha(workspace.path(rel))
	for rel: String in files:
		_stamps[workspace.path(rel)] = _sha(workspace.path(rel))
		if files[rel].disk_path:
			_stamps[files[rel].disk_path] = _sha(files[rel].disk_path)


## The sha256 of the file at [param path] ("" if there is none), hashed
## again only when it may have changed (see _hashes).
func _sha(path: String) -> String:
	if not FileAccess.file_exists(path):
		_hashes.erase(path)
		return ""
	var t := FileAccess.get_modified_time(path)
	var size := FileAccess.get_size(path)
	var known: Array = _hashes.get(path, [])
	if not known.is_empty() and known[0] == t and known[1] == size \
			and int(Time.get_unix_time_from_system()) - t > 2:
		return known[2]
	var sha := FileAccess.get_sha256(path)
	_hashes[path] = [t, size, sha]
	return sha


## [param rel] was pushed into BN and its workspace copy deleted. An open
## copy now counts as read from BN, so its next save records BN's new file
## as the base instead of marking the file new.
func mark_pushed(rel: String) -> void:
	if files.has(rel):
		var bn_file := workspace.bn_path.path_join(rel)
		files[rel].mark_pushed(FileAccess.get_sha256(bn_file), bn_file)


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
	doc.cells_changed.disconnect(_on_map_cells)
	_release_file(doc.file.rel_path)


## Closes every map and palette of file [param rel], dropping its unsaved
## changes (see _release_file). Returns the titles closed.
func discard(rel: String) -> PackedStringArray:
	var closed := PackedStringArray()
	for d in docs_for(rel):
		closed.append(d.ref.title())
		close(d)
	for d in palette_docs.duplicate():
		if d.file.rel_path == rel:
			closed.append("palette " + d.id)
			close_palette(d)
	# A file read without a document (a palette shown, not edited).
	_release_file(rel)
	return closed


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
	for b: DataIndex.Building in _new_buildings.get(rel, []):
		index.remove_building(b)
	_new_refs.erase(rel)
	_new_overmap.erase(rel)
	_new_palettes.erase(rel)
	_new_buildings.erase(rel)
	# Deleted palettes are back (last first), and the objects after them at
	# their indexes on disk.
	var deleted: Array = _deleted.get(rel, [])
	for k in range(deleted.size() - 1, -1, -1):
		var d: DeletedPalette = deleted[k]
		if not d.was_new:
			index.shift_sources(rel, d.removed.index, 1)
			index.insert_palette(d.def, d.position)
	_deleted.erase(rel)
	files.erase(rel)
	objects.forget(rel)
	if dirty:
		_reindex_from_disk(rel)
		# Palettes from the file are back as on disk: the maps using them
		# resolve again. Chunks from it too: the maps placing them lay them
		# out again.
		var palettes := PackedStringArray()
		for id: String in index.palettes:
			for def: DataIndex.Definition in index.palettes[id]:
				if def.source.path == rel and not palettes.has(id):
					palettes.append(id)
		for d in docs:
			if Array(palettes).any(func(id: String) -> bool: return d.uses_palette(id)):
				d.refresh()
			d.refresh_overlay()
	for other: String in _linked.get(rel, []):
		_release_file(other)
	_linked.erase(rel)


## Palette data, maps' palette and chunk lists and buildings' tiles of
## [param rel] as the file on disk has them (the editor changed them in
## place).
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
	var seen := {}
	for id: String in index.buildings:
		var src: DataIndex.Source = index.buildings[id].overmaps_source
		if src and src.path == rel and not seen.has(src.index):
			seen[src.index] = true
			var o: Variant = on_disk[src.index] if src.index < on_disk.size() else null
			index.set_building_overmaps(src, o.get("overmaps") if o is Dictionary else null)
	for ref in index.mapgens:
		if ref.source.path == rel and ref.source.index < on_disk.size() and on_disk[ref.source.index] is Dictionary:
			var obj: Variant = on_disk[ref.source.index].get("object")
			ref.palettes = DataIndex.palette_options(obj) if obj is Dictionary else PackedStringArray()
			ref.chunks = DataIndex.chunk_options(obj) if obj is Dictionary else PackedStringArray()
	# An overmap_terrain the editor took out (an undone stub, saved before):
	# the ids the index lost are back (the last definition, as loading does).
	var lost := {}
	for i in on_disk.size():
		var o: Variant = on_disk[i]
		if o is Dictionary and o.get("type") == "overmap_terrain":
			var src := DataIndex.Source.new(index.mod_for_path(rel), rel, i)
			for id in DataIndex._tags(o.get("id", [])):
				if lost.has(id) or not index.overmap_terrain.has(id):
					lost[id] = src
	index.overmap_terrain.merge(lost, true)


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
		f = JsonFile.create_at(rel, workspace.path(rel))
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
	## "" for none (every cell then needs a terrain).
	var fill_ter := EditSession.DEFAULT_FILL
	var palettes := PackedStringArray()
	## Also add overmap_terrain entries for ids that have none.
	var add_overmap_terrain := true
	## Set for a nested chunk: its mapgensize, 1-24 cells each way. A chunk
	## gets no fill_ter (BN ignores it there) and no overmap_terrain.
	var chunk_size := Vector2i.ZERO
	## What new overmap_terrain entries copy from ("": OVERMAP_STUB_BASE).
	var overmap_base := ""
	## Set for a new level of a building: its tiles are added to the
	## building's "overmaps" (see add_level_tiles).
	var level: LevelTarget

	func is_chunk() -> bool:
		return chunk_size != Vector2i.ZERO


## Where a new map goes in a building: its top-left tile at [member origin]
## of building [member building], the others to the east and south, each
## placed with rotation [member dir].
class LevelTarget:
	var building := ""
	var origin := Vector3i.ZERO
	var dir := "north"

	## [point, "overmap" value] per tile of the om_terrain grid [param ids].
	func entries(ids: Array[PackedStringArray]) -> Array:
		var out := []
		for y in ids.size():
			for x in ids[y].size():
				out.append([origin + Vector3i(x, y, 0), ids[y][x] + ("_" + dir if dir else "")])
		return out


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
	if not spec.is_chunk() and spec.fill_ter and not index.terrain.has(spec.fill_ter):
		return "Unknown fill_ter terrain \"%s\"." % spec.fill_ter
	for p in spec.palettes:
		if index.palette(p) == null:
			return "Unknown palette \"%s\"." % p
	if spec.level and not spec.is_chunk():
		var level_problem := check_level_tiles(spec.level.building, spec.level.entries(spec.ids))
		if level_problem:
			return level_problem
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
		f = JsonFile.create_at(rel, workspace.path(rel))
		files[rel] = f
	var mapgen := _new_mapgen_object(spec)
	var i := f.append(mapgen)
	var ref := index.add_mapgen(mapgen, DataIndex.Source.new(index.mod_for_path(rel), rel, i))
	_remember(_new_refs, rel, ref)
	var doc := MapDocument.open(index, f, i, ref)
	_add_doc(doc)
	if spec.add_overmap_terrain and not spec.is_chunk():
		add_missing_overmap_terrain(doc, spec.overmap_base)
	if spec.level and not spec.is_chunk():
		var err := add_level_tiles(spec.level.building, spec.level.entries(spec.ids))
		if err:
			_fail(err)
		else:
			var b_rel: String = index.buildings[spec.level.building].overmaps_source.path
			if b_rel != rel:
				_remember(_linked, rel, b_rel)
	return doc


static func _new_mapgen_object(spec: NewMapgen) -> Dictionary:
	var cells := spec.chunk_size
	var obj := {}
	if spec.is_chunk():
		obj["mapgensize"] = [cells.x, cells.y]
	else:
		cells = Vector2i(spec.ids[0].size(), spec.ids.size()) * MapgenResolver.OMT_SIZE
		if spec.fill_ter:
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
## have none, next to the map in its file, copying [param base] ("":
## OVERMAP_STUB_BASE), as an undo step of the map (undoing it takes the
## stub out of the file again). Returns the ids added.
func add_missing_overmap_terrain(doc: MapDocument, base := "") -> PackedStringArray:
	var missing := doc.missing_overmap_terrain()
	if missing.is_empty():
		return missing
	var rel := doc.file.rel_path
	var stub := overmap_stub(missing, base)
	var c := MapDocument.Change.new()
	c.name = "Add overmap_terrain " + ", ".join(missing)
	# Bound to the path, the stub and a state shared by undo and redo, not
	# the document (a reference cycle).
	var state := {"removed": null, "unsaved": true}
	c.file_undo = _remove_stub.bind(rel, stub, missing, state)
	c.file_redo = _append_stub.bind(rel, stub, missing, state)
	_append_stub(rel, stub, missing, state)
	doc.record(c)
	return missing


## Appends [param stub] (an overmap_terrain for [param ids]) to open file
## [param rel] and indexes it; a redo puts back what _remove_stub took out
## (its saved state too). [param state]: "removed", the JsonFile.Removed of
## the last undo; "unsaved", the stub isn't in the file on disk (discard
## takes its ids out of the index). Returns "".
func _append_stub(rel: String, stub: Dictionary, ids: PackedStringArray, state: Dictionary) -> String:
	var f: JsonFile = files.get(rel)
	if f == null:
		return "%s isn't open any more." % rel
	var removed: JsonFile.Removed = state.removed
	var i := f.objects.size()
	if removed and removed.index == i:
		_insert_object(rel, removed)
	else:
		f.append(stub)
	state.removed = null
	var src := DataIndex.Source.new(index.mod_for_path(rel), rel, i)
	for id in ids:
		index.overmap_terrain[id] = src
		if state.unsaved:
			_remember(_new_overmap, rel, id)
	_forget_all_findings()
	return ""


## Takes [param stub] out of [param rel] again, when nothing was added to
## the file after it (nor deleted from after it: that must come back
## first). Returns why it can't, or "".
func _remove_stub(rel: String, stub: Dictionary, ids: PackedStringArray, state: Dictionary) -> String:
	var f: JsonFile = files.get(rel)
	var i := -1
	if f:
		for k in f.objects.size():
			if is_same(f.objects[k], stub):
				i = k
	if i < 0:
		return "The overmap_terrain for %s is no longer in %s." % [", ".join(ids), rel]
	if i != f.objects.size() - 1:
		return "Can't undo adding the overmap_terrain for %s: something was added to %s after it (a new map, level or palette); undo or discard that first." % [
			", ".join(ids), rel]
	for d: DeletedPalette in _deleted.get(rel, []):
		if d.removed.index > i:
			return "Can't undo adding the overmap_terrain for %s: palette %s was deleted from %s after it; undo that first." % [
				", ".join(ids), d.def.id, rel]
	state.unsaved = _new_overmap.has(rel) and _new_overmap[rel].has(ids[0])
	state.removed = _remove_object(rel, i)
	for id in ids:
		index.overmap_terrain.erase(id)
		if _new_overmap.has(rel):
			_new_overmap[rel].erase(id)
	_forget_all_findings()
	return ""


func _forget_all_findings() -> void:
	for d in docs:
		d.forget_findings()


# --- Taking objects out --------------------------------------------------------

## Takes object [param i] out of open file [param rel]: the index's Sources
## and the open documents after it move down one. The caller takes the
## object's own entries out of the index.
func _remove_object(rel: String, i: int) -> JsonFile.Removed:
	var f: JsonFile = files[rel]
	var r := f.remove(i)
	index.shift_sources(rel, i, -1)
	_shift_documents(rel, i, -1)
	objects.forget(rel)
	return r


## Puts back what _remove_object() took out; the caller indexes it again.
func _insert_object(rel: String, r: JsonFile.Removed) -> void:
	index.shift_sources(rel, r.index, 1)
	_shift_documents(rel, r.index, 1)
	files[rel].insert(r)
	objects.forget(rel)


func _shift_documents(rel: String, at: int, delta: int) -> void:
	for d in docs:
		if d.file.rel_path == rel and (d.object_index > at or (delta > 0 and d.object_index == at)):
			d.object_index += delta
	for d in palette_docs:
		if d.file.rel_path == rel and (d.object_index > at or (delta > 0 and d.object_index == at)):
			d.object_index += delta


# --- Deleting a palette --------------------------------------------------------

## What uses palette [param id]: [maps (by title), palettes including it].
func palette_users(id: String) -> Array:
	var maps := index.maps_using(id)
	maps.sort_custom(func(a: DataIndex.MapgenRef, b: DataIndex.MapgenRef) -> bool: return a.title() < b.title())
	var including := PackedStringArray()
	for pid: String in index.palettes:
		var p := index.palette(pid)
		if pid != id and p and DataIndex.palette_options(p.data).has(id):
			including.append(pid)
	including.sort()
	return [maps, including]


## Why [param def] can't be deleted, or "". A palette something loaded
## uses can't be (unless another definition of its id stays in effect).
func check_delete_palette(def: DataIndex.Definition) -> String:
	if def.source.path.is_empty():
		return "Palette %s has no file." % def.id
	var defs: Array = index.palettes.get(def.id, [])
	if not defs.has(def):
		return "Palette %s (%s) isn't loaded." % [def.id, def.source]
	if index.palette(def.id) == def:
		var users := palette_users(def.id)
		var maps: Array = users[0]
		var including: PackedStringArray = users[1]
		if not maps.is_empty() or not including.is_empty():
			var names := PackedStringArray()
			for ref: DataIndex.MapgenRef in maps.slice(0, 12):
				names.append(ref.title())
			if maps.size() > 12:
				names.append("%d more" % (maps.size() - 12))
			var parts := PackedStringArray()
			if not maps.is_empty():
				parts.append("%d map(s) (%s)" % [maps.size(), ", ".join(names)])
			if not including.is_empty():
				parts.append("palette(s) including it: %s" % ", ".join(including))
			var also := " and the definition it replaces would take over" if defs.size() > 1 else ""
			return "Palette %s is used by %s%s; stop using it first." % [def.id, "; ".join(parts), also]
	var f := get_file(def.source.path)
	if f == null:
		return "Can't open %s: %s" % [def.source.path, last_error]
	if not _is_palette_at(f, def):
		return "%s #%d is no longer palette %s; reload the data (F5)." % [def.source.path, def.source.index, def.id]
	return ""


static func _is_palette_at(f: JsonFile, def: DataIndex.Definition) -> bool:
	var i := def.source.index
	return i < f.objects.size() and f.objects[i] is Dictionary and f.objects[i].get("type") == "palette" \
			and str(f.objects[i].get("id", "")) == def.id


## Takes palette [param def] out of its file (unsaved; the objects after it
## move down one) and out of the index. An open document of it closes, but
## the file stays open, with the deletion as an unsaved change until it is
## saved or discarded. restore_palette() puts it back until then. Returns
## an error, or "".
func delete_palette(def: DataIndex.Definition) -> String:
	var problem := check_delete_palette(def)
	if problem:
		return _fail(problem)
	var rel := def.source.path
	var doc := palette_doc_for(def)
	if doc:
		# Not close_palette(): that would drop the file, deletion and all.
		palette_docs.erase(doc)
		doc.changed.disconnect(_on_palette_changed)
	var d := DeletedPalette.new()
	d.def = def
	d.rel = rel
	d.position = index.palettes[def.id].find(def)
	d.was_new = _new_palettes.has(rel) and _new_palettes[rel].has(def)
	if d.was_new:
		_new_palettes[rel].erase(def)
	index.remove_palette(def)
	var now := index.palette(def.id)
	var now_doc := palette_doc_for(now) if now else null
	d.edits_before = now_doc.undo_count() if now_doc else 0
	d.removed = _remove_object(rel, def.source.index)
	_remember(_deleted, rel, d)
	_forget_all_findings()
	return ""


## The palette with id [param id] that restore_palette() would put back,
## or null.
func deleted_palette(id: String) -> DeletedPalette:
	for rel: String in _deleted:
		for d: DeletedPalette in _deleted[rel]:
			if d.def.id == id:
				return d
	return null


## The palettes deleted and not saved yet, oldest first per file.
func deleted_palettes() -> Array[DeletedPalette]:
	var out: Array[DeletedPalette] = []
	for rel: String in _deleted:
		out.append_array(_deleted[rel])
	return out


## Puts the deleted palette [param id] back where it was (an undo of
## delete_palette). Only the file's last deletion can go back first.
## Returns an error, or "".
func restore_palette(id: String) -> String:
	var d := deleted_palette(id)
	if d == null:
		return _fail("No deleted palette %s to restore (only until its file is saved)." % id)
	var list: Array = _deleted[d.rel]
	if list[-1] != d:
		return _fail("Restore palette %s first (deleted from %s after %s)." % [list[-1].def.id, d.rel, id])
	if d.removed.index > files[d.rel].objects.size():
		return _fail("Can't restore palette %s: %s has fewer objects than when it was deleted (#%d); redo what took them out first." % [
			id, d.rel, d.removed.index])
	list.pop_back()
	if list.is_empty():
		_deleted.erase(d.rel)
	_insert_object(d.rel, d.removed)
	d.def.source.index = d.removed.index
	index.insert_palette(d.def, d.position)
	if d.was_new:
		_remember(_new_palettes, d.rel, d.def)
	_forget_all_findings()
	return ""


# --- Renaming a palette key ----------------------------------------------------

## Renames palette key [param plan].old to .new_key as
## PaletteImpact.plan_rename worked out: one undo step in the palette, and
## one in each repainted map (opened for it). Undoing the palette's step
## undoes the maps' too while it is still their last. Refused, changing
## nothing, when a map to repaint can't be opened (a lua mapgen, an
## unreadable file). Returns an error, or "".
func rename_palette_key(doc: PaletteDocument, plan: PaletteImpact.RenamePlan) -> String:
	if plan.problem:
		return _fail(plan.problem)
	var name := "%s (palette %s)" % [plan.change.name, doc.id]
	var refs: Array[DataIndex.MapgenRef] = []
	for a in plan.repainted:
		refs.append(a.ref)
	# Every map opens before anything changes: one that can't would keep
	# the old key with the palette no longer defining it.
	var opened: Array[MapDocument] = []
	var failed := PackedStringArray()
	for ref in refs:
		var was_open := docs.any(func(d: MapDocument) -> bool: return d.ref == ref)
		var md := open(ref)
		if md == null:
			failed.append("%s: %s" % [ref.title(), last_error])
		elif not was_open:
			opened.append(md)
	if not failed.is_empty():
		for md in opened:
			close(md)
		return _fail("Not renamed: these maps using the key can't be repainted: " + "; ".join(failed))
	plan.change.on_undo = _follow_palette.bind(refs, name, true)
	plan.change.on_redo = _follow_palette.bind(refs, name, false)
	doc.commit(plan.change)
	for ref in refs:
		var md := open(ref)
		var points: Array[Vector2i] = []
		for y in md.resolved.cells.size():
			var row := md.resolved.cells[y]
			for x in row.size():
				if row[x] == plan.old:
					points.append(Vector2i(x, y))
		md.paint(points, plan.new_key, name)
	return ""


## The palette step [param name] was undone ([param back]) or redone: the
## open maps of [param refs] whose last step (or last undone step) it is
## follow.
func _follow_palette(refs: Array[DataIndex.MapgenRef], name: String, back: bool) -> void:
	for d in docs.duplicate():
		if not refs.has(d.ref):
			continue
		if back and d.undo_name() == name:
			d.undo()
		elif not back and d.redo_name() == name:
			d.redo()


## A minimal overmap_terrain for [param ids]: a city building named after
## the first id, copying [param base] ("": OVERMAP_STUB_BASE). Rotatable,
## so BN adds the _north/_east/... variants itself.
static func overmap_stub(ids: PackedStringArray, base := "") -> Dictionary:
	return {
		"type": "overmap_terrain",
		"id": ids[0] if ids.size() == 1 else Array(ids),
		"copy-from": base if base else OVERMAP_STUB_BASE,
		"name": ids[0].replace("_", " "),
		"color": "light_gray",
	}


# --- Building levels -----------------------------------------------------------

## What a new level's overmap_terrain copies: the copy-from of the
## overmap_terrain at another level of [param building]'s point
## ([param at], z ignored) on the same side of the ground (nearest first),
## else core's generic by z: a roof ([param roof]) the house roof, below
## ground the house basement, else OVERMAP_STUB_BASE.
func level_stub_base(building: String, at: Vector3i, roof := false) -> String:
	var b: DataIndex.Building = index.buildings.get(building)
	var best := ""
	var best_d := 0
	if b:
		for t in b.tiles:
			if not t.placed or t.point.x != at.x or t.point.y != at.y or t.point.z == at.z:
				continue
			if signi(t.point.z) != signi(at.z) or not index.overmap_terrain.has(t.oter):
				continue
			var base: Variant = index.read_object(index.overmap_terrain[t.oter]).get("copy-from")
			var d := absi(t.point.z - at.z)
			if base is String and base and (best.is_empty() or d < best_d):
				best = base
				best_d = d
	if best:
		return best
	if roof:
		return ROOF_STUB_BASE
	return BASEMENT_STUB_BASE if at.z < 0 else OVERMAP_STUB_BASE


## Why [param entries] ([point, "overmap" value] pairs) can't be added to
## building [param id]'s "overmaps", or "".
func check_level_tiles(id: String, entries: Array) -> String:
	var b: DataIndex.Building = index.buildings.get(id)
	if b == null:
		return "Unknown building %s." % id
	if b.mutable:
		return "%s is a mutable special (placed by rules, no fixed points); add levels to it by hand." % id
	var src := b.overmaps_source
	if src == null:
		return "%s has no \"overmaps\" list to add to." % id
	for e: Array in entries:
		var t := b.at(e[0])
		if t:
			return "%s already has %s at %s." % [id, t.oter, e[0]]
	var f := get_file(src.path)
	if f == null:
		return "Can't open %s: %s" % [src.path, last_error]
	var o: Variant = f.objects[src.index] if src.index < f.objects.size() else null
	if not (o is Dictionary and o.get("overmaps") is Array):
		return "%s #%d no longer has the \"overmaps\" list of %s." % [src.path, src.index, id]
	return ""


## Where add_level_tiles() writes for building [param id], as a sentence
## ("" if it can't).
func level_tiles_note(id: String) -> String:
	var b: DataIndex.Building = index.buildings.get(id)
	if b == null or b.overmaps_source == null:
		return ""
	var src := b.overmaps_source
	var text := "Adds the new tiles to the \"overmaps\" of %s in %s" % [id, src.path]
	if src.path != b.source.path or src.index != b.source.index:
		var o := index.read_object(src)
		text += " (the definition of %s it copies them from)" % str(o.get("id", "?"))
	var sharing := PackedStringArray()
	for other: String in index.buildings:
		var ob: DataIndex.Building = index.buildings[other]
		if other != id and ob.overmaps_source and ob.overmaps_source.path == src.path \
				and ob.overmaps_source.index == src.index:
			sharing.append(other)
	if not sharing.is_empty():
		text += "; %s get%s them too" % [", ".join(sharing), "s" if sharing.size() == 1 else ""]
	return text + "."


## Adds [param entries] ([point, "overmap" value] pairs) to building
## [param id]'s "overmaps", in the definition that supplies the list (its
## own, or the one it copies from; see level_tiles_note), and indexes them.
## A new entry copies "locations" from an entry at the same x, y if one has
## it. Not undoable: discarding the building's file takes it back. Returns
## an error, or "".
func add_level_tiles(id: String, entries: Array) -> String:
	var problem := check_level_tiles(id, entries)
	if problem:
		return _fail(problem)
	var src: DataIndex.Source = index.buildings[id].overmaps_source
	var f := get_file(src.path)
	f.touch(src.index)
	var list: Array = f.objects[src.index].overmaps
	for e: Array in entries:
		var p: Vector3i = e[0]
		var entry := {"point": [p.x, p.y, p.z], "overmap": e[1]}
		for other: Variant in list:
			if other is Dictionary and other.has("locations") and other.get("point") is Array \
					and other.point.size() == 3 and int(other.point[0]) == p.x and int(other.point[1]) == p.y:
				entry["locations"] = other.locations.duplicate(true)
				break
		list.append(entry)
	index.set_building_overmaps(src, list)
	for d in docs:
		d.forget_findings()
	return ""


## Adds a city_building [param id] to [param rel] (created if new) placing
## [param entries] ([point, "overmap" value] pairs), on "land" like core's.
## With [param city_list] (one of CITY_LISTS), also names it in that list
## with [param weight] (see add_to_city_list). Returns an error, or "".
func create_building(rel: String, id: String, entries: Array, city_list := "", weight := 100) -> String:
	last_error = ""
	var problem := check_new_building(rel, id, city_list)
	if problem:
		return _fail(problem)
	var f := get_file(rel) if _file_exists(rel) else null
	if f == null:
		f = JsonFile.create_at(rel, workspace.path(rel))
		files[rel] = f
	var overmaps := []
	for e: Array in entries:
		overmaps.append({"point": [e[0].x, e[0].y, e[0].z], "overmap": e[1]})
	var o := {"type": "city_building", "id": id, "locations": ["land"], "overmaps": overmaps}
	var i := f.append(o)
	var b := index.add_building(o, DataIndex.Source.new(index.mod_for_path(rel), rel, i))
	_remember(_new_buildings, rel, b)
	if city_list:
		return add_to_city_list(rel, id, city_list, weight)
	return ""


## Why a city_building [param id] can't be created in [param rel] (and put
## in [param city_list]), or "".
func check_new_building(rel: String, id: String, city_list := "") -> String:
	var path_problem := _check_new_path(rel)
	if path_problem:
		return path_problem
	if id.is_empty() or id.contains(" ") or id.contains("\""):
		return "\"%s\" isn't a valid building id." % id
	if index.buildings.has(id):
		return "%s already exists (%s); a second definition would replace it." % [id, index.buildings[id].source]
	if city_list and not CITY_LISTS.has(city_list):
		return "Unknown city list \"%s\" (one of %s)." % [city_list, ", ".join(CITY_LISTS)]
	if _file_exists(rel) and get_file(rel) == null:
		return "Can't add to %s: %s" % [rel, last_error]
	return ""


## Where add_to_city_list() names a building of [param rel], as a sentence.
func city_list_note(rel: String) -> String:
	if index.catalog.get_mod(index.mod_for_path(rel)).core:
		return "Adds it to the \"default\" region's city list in %s (a region_overlay in core may load before the regions it changes)." % REGION_SETTINGS_FILE
	return "Adds a region_overlay naming it for every region, next to it in %s." % rel


## Names building [param id] (defined in [param rel]) in city list
## [param list] with [param weight], so cities spawn it: in a mod, a
## region_overlay for "all" regions appended to [param rel] (BN applies
## overlays as it loads them, after core's regions); in core, the region
## settings of REGION_SETTINGS_FILE (every region_settings there with a
## "city"). Returns an error, or "".
func add_to_city_list(rel: String, id: String, list: String, weight: int) -> String:
	if index.catalog.get_mod(index.mod_for_path(rel)).core:
		var f := get_file(REGION_SETTINGS_FILE)
		if f == null:
			return _fail("Can't open %s: %s" % [REGION_SETTINGS_FILE, last_error])
		var done := 0
		for i in f.objects.size():
			var o: Variant = f.objects[i]
			if o is Dictionary and o.get("type") == "region_settings" and o.get("city") is Dictionary:
				f.touch(i)
				if not o.city.get(list) is Dictionary:
					o.city[list] = {}
				o.city[list][id] = weight
				done += 1
		if done == 0:
			return _fail("%s has no region_settings with a \"city\" object." % REGION_SETTINGS_FILE)
		_remember(_linked, rel, REGION_SETTINGS_FILE)
		return ""
	var f := get_file(rel)
	f.append({"type": "region_overlay", "regions": ["all"], "city": {list: {id: weight}}})
	return ""


## The files a new level or building made from map file [param rel]
## edited (its building's, the region settings), which go with it.
func linked_files(rel: String) -> PackedStringArray:
	return PackedStringArray(_linked.get(rel, []))


func _remember(table: Dictionary, rel: String, value: Variant) -> void:
	if not table.has(rel):
		table[rel] = []
	table[rel].append(value)


func _fail(msg: String) -> String:
	last_error = msg
	return msg

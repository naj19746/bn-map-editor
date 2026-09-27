class_name DataIndex
extends RefCounted
## Read-only index of a BN checkout plus selected mods: terrain, furniture,
## palettes, item groups, monster groups and mapgen entries, each with the
## file it came from.
##
## Loads like BN: mods in load order, each mod's *.json files in BFS order
## (a folder's files sorted, then its subfolders sorted), skipping
## "mod_interactions", whose <mod id> subfolders load in a second pass for the
## active mods. Objects are indexed by their "type", not by folder.
##
## Files are read with Godot's JSON (numbers become floats), which is fine for
## an index. Anything that gets saved must be re-read with BnJson.

const TYPE_TERRAIN := "terrain"
const TYPE_FURNITURE := "furniture"


## Where an object came from.
class Source:
	var mod := ""
	## Relative to the BN checkout, e.g. "data/json/mapgen/house.json".
	## Empty for ids built into BN (t_null, f_null).
	var path := ""
	## Index of the object in the file's top-level array (0 for a lone object).
	var index := 0

	func _init(p_mod := "", p_path := "", p_index := 0) -> void:
		mod = p_mod
		path = p_path
		index = p_index

	func _to_string() -> String:
		return "%s#%d (%s)" % [path, index, mod]


## A terrain or furniture type, with copy-from already applied.
class TileDef:
	var id := ""
	var name := ""
	## Four seasonal symbols (spring, summer, autumn, winter): one ASCII
	## character, or "LINE_XOXO" / "LINE_OXOX".
	var symbol := PackedStringArray()
	## Four seasonal BN color names, e.g. "light_gray" or "i_red".
	var color := PackedStringArray()
	## True when the colors came from "bgcolor" rather than "color".
	var bgcolor := false
	var looks_like := ""
	var copy_from := ""
	## Flag names, with copy-from's "extend"/"delete" applied.
	var flags := PackedStringArray()
	## The "connects_to" group ("WALL", "CHAINFENCE", ...) or "". Not
	## inherited: BN recomputes it on every load, and for terrain the WALL and
	## CONNECT_TO_WALL flags imply "WALL".
	var connect_group := ""
	var source: Source

	func copy() -> TileDef:
		var t := TileDef.new()
		t.id = id
		t.name = name
		t.symbol = symbol.duplicate()
		t.color = color.duplicate()
		t.bgcolor = bgcolor
		t.looks_like = looks_like
		t.copy_from = copy_from
		t.flags = flags.duplicate()
		t.connect_group = connect_group
		t.source = source
		return t

	## The symbol as one character: LINE_XOXO (a vertical wall line) is "│",
	## LINE_OXOX (horizontal) is "─". BN connects these to their neighbours;
	## that's left to the renderer.
	func ascii(season := 0) -> String:
		var s := symbol[season] if season < symbol.size() else ""
		match s:
			"LINE_XOXO": return "│"
			"LINE_OXOX": return "─"
		return s

	func has_flag(flag: String) -> bool:
		return flags.has(flag)


## One definition of a palette, item group or monster group.
class Definition:
	var id := ""
	var source: Source
	## The parsed JSON object. Only kept for palettes.
	var data: Dictionary


## A mapgen entry: one object in a file, which may serve several ids.
class MapgenRef:
	const OM_TERRAIN := "om_terrain"
	const NESTED := "nested_mapgen_id"
	const UPDATE := "update_mapgen_id"

	## One of OM_TERRAIN, NESTED, UPDATE.
	var kind := ""
	var source: Source
	## "json" or "lua".
	var method := ""
	## Every id this entry registers.
	var ids := PackedStringArray()
	## For a multi-tile om_terrain (a nested list), the ids by row; otherwise
	## empty (a plain list reuses the same 1x1 map for each id).
	var grid: Array[PackedStringArray] = []
	var weight := 1000
	## A nested/update chunk's "mapgensize" in cells, else (0, 0).
	var chunk_size := Vector2i.ZERO

	## The id to show for this entry: the first id, top-left for a grid.
	func title() -> String:
		return ids[0] if not ids.is_empty() else "?"

	## Size in overmap tiles; (1, 1) unless this is a multi-tile building.
	func size_omt() -> Vector2i:
		if grid.is_empty():
			return Vector2i.ONE
		return Vector2i(grid[0].size(), grid.size())

	## Position of [param id] in the grid, (0, 0) for a 1x1 map, or (-1, -1).
	func position_of(id: String) -> Vector2i:
		if grid.is_empty():
			return Vector2i.ZERO if ids.has(id) else -Vector2i.ONE
		for y in grid.size():
			var x := grid[y].find(id)
			if x >= 0:
				return Vector2i(x, y)
		return -Vector2i.ONE


var bn_path := ""
var catalog: ModCatalog
## Mods in load order.
var mods := PackedStringArray()
## id -> TileDef. Aliases map to the same TileDef.
var terrain := {}
var furniture := {}
## id -> Array[Definition], in load order; the last one is in effect.
var palettes := {}
var item_groups := {}
var monster_groups := {}
## id -> Array[MapgenRef], in load order.
var om_terrain := {}
var nested := {}
var update := {}
var mapgens: Array[MapgenRef] = []
## Load problems: unparsable files, unresolved copy-from, bad mod selection.
var errors := PackedStringArray()
var file_count := 0

var _abstracts := {TYPE_TERRAIN: {}, TYPE_FURNITURE: {}}
## [kind, object, Source] triples waiting for their copy-from base.
var _deferred: Array = []


## Loads the core mod plus [param selected] mods (in load order, with their
## dependencies). Check [member errors] afterwards.
static func load_bn(p_bn_path: String, selected := PackedStringArray(),
		p_catalog: ModCatalog = null) -> DataIndex:
	var index := DataIndex.new()
	index.bn_path = p_bn_path.simplify_path()
	index.catalog = p_catalog if p_catalog else ModCatalog.scan(index.bn_path)
	index.errors.append_array(index.catalog.errors)
	var order := index.catalog.load_order(selected)
	index.errors.append_array(order.errors)
	index.mods = order.mods
	index._load_all()
	return index


func _load_all() -> void:
	_add_builtin(TYPE_TERRAIN, "t_null")
	_add_builtin(TYPE_FURNITURE, "f_null")
	for mod in mods:
		for file in data_files(catalog.get_mod(mod).path):
			_load_file(mod, file)
	for mod in mods:
		var interactions := catalog.get_mod(mod).path.path_join("mod_interactions")
		if not DirAccess.dir_exists_absolute(interactions):
			continue
		for other in mods:
			var dir := interactions.path_join(other)
			if DirAccess.dir_exists_absolute(dir):
				for file in data_files(dir, false):
					_load_file(mod, file)
	_finish_deferred()


## The *.json files under [param dir] in BN's load order. With
## [param skip_interactions], folders named "mod_interactions" are left out.
static func data_files(dir: String, skip_interactions := true) -> PackedStringArray:
	var out := PackedStringArray()
	var queue := PackedStringArray([dir])
	var head := 0
	while head < queue.size():
		var d := queue[head]
		head += 1
		var files := DirAccess.get_files_at(d)
		files.sort()
		for f in files:
			if f.ends_with(".json"):
				out.append(d.path_join(f))
		var subdirs := DirAccess.get_directories_at(d)
		subdirs.sort()
		for s in subdirs:
			if not (skip_interactions and s == "mod_interactions"):
				queue.append(d.path_join(s))
	return out


## BN defines the null ids in code (blank symbol, white): "no terrain/furniture".
func _add_builtin(kind: String, id: String) -> void:
	var def := TileDef.new()
	def.id = id
	def.name = "nothing"
	def.symbol = PackedStringArray([" ", " ", " ", " "])
	def.color = PackedStringArray(["white", "white", "white", "white"])
	def.source = Source.new("", "", -1)
	(terrain if kind == TYPE_TERRAIN else furniture)[id] = def


func _load_file(mod: String, file: String) -> void:
	file_count += 1
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK:
		errors.append("%s:%d: %s" % [relative_path(file), json.get_error_line(), json.get_error_message()])
		return
	var objects: Variant = json.data
	if objects is Dictionary:
		objects = [objects]
	if not objects is Array:
		return
	var rel := relative_path(file)
	for i in objects.size():
		var o: Variant = objects[i]
		if o is Dictionary:
			_add_object(o, Source.new(mod, rel, i))


func relative_path(file: String) -> String:
	return file.trim_prefix(bn_path + "/")


func _add_object(o: Dictionary, src: Source) -> void:
	match o.get("type"):
		TYPE_TERRAIN, TYPE_FURNITURE:
			if not _load_tile(o.type, o, src):
				_deferred.append([o.type, o, src])
		"palette":
			_add_definition(palettes, str(o.get("id", "")), src, o)
		"item_group":
			_add_definition(item_groups, str(o.get("id", "")), src)
		"monstergroup":
			_add_definition(monster_groups, str(o.get("name", o.get("id", ""))), src)
		"mapgen":
			_add_mapgen(o, src)


func _add_definition(table: Dictionary, id: String, src: Source, data := {}) -> void:
	if id.is_empty():
		return
	var d := Definition.new()
	d.id = id
	d.source = src
	d.data = data
	if not table.has(id):
		table[id] = []
	table[id].append(d)


## Mirrors generic_factory::load: copy-from takes a copy of whatever is loaded
## under that id (or abstract) right now; if nothing is, the object waits.
func _load_tile(kind: String, o: Dictionary, src: Source) -> bool:
	var table: Dictionary = terrain if kind == TYPE_TERRAIN else furniture
	var abstracts: Dictionary = _abstracts[kind]
	var def: TileDef
	var copy_from: Variant = o.get("copy-from")
	if copy_from is String:
		var base: TileDef = table.get(copy_from, abstracts.get(copy_from))
		if base == null:
			return false
		def = base.copy()
		def.copy_from = copy_from
		if def.looks_like.is_empty():
			def.looks_like = copy_from
	else:
		def = TileDef.new()
		def.symbol = PackedStringArray(["", "", "", ""])
		def.color = PackedStringArray(["", "", "", ""])
	def.source = src
	_apply_tile_fields(def, o)
	_apply_flags(kind, def, o)

	if o.get("abstract") is String:
		abstracts[o.abstract] = def
		return true
	var ids: Variant = o.get("id")
	if ids is String:
		ids = [ids]
	if not ids is Array:
		return true
	var first := true
	for id: Variant in ids:
		var d := def if first else def.copy()
		first = false
		d.id = str(id)
		table[d.id] = d
		if ids.size() == 1:
			var alias: Variant = o.get("alias")
			if alias is String:
				alias = [alias]
			if alias is Array:
				for a: Variant in alias:
					table[str(a)] = d
	return true


static func _apply_tile_fields(def: TileDef, o: Dictionary) -> void:
	var name: Variant = o.get("name")
	if name is Dictionary:
		name = name.get("str", name.get("str_sp", ""))
	if name is String:
		def.name = name
	if o.get("looks_like") is String:
		def.looks_like = o.looks_like
	if o.has("symbol"):
		def.symbol = _seasons(o.symbol)
	# BN allows only one of the two; either replaces an inherited one.
	if o.has("color"):
		def.color = _seasons(o.color)
		def.bgcolor = false
	elif o.has("bgcolor"):
		def.color = _seasons(o.bgcolor)
		def.bgcolor = true


## Like BN's assign() for a set: "flags" replaces, else "extend"/"delete"
## modify the inherited flags. Then the connect group is worked out afresh.
static func _apply_flags(kind: String, def: TileDef, o: Dictionary) -> void:
	if o.has("flags"):
		def.flags = _tags(o.flags)
	else:
		var add: Variant = o.get("extend")
		if add is Dictionary and add.has("flags"):
			for f in _tags(add.flags):
				if not def.flags.has(f):
					def.flags.append(f)
		var del: Variant = o.get("delete")
		if del is Dictionary and del.has("flags"):
			for f in _tags(del.flags):
				def.flags.erase(f)
	def.connect_group = ""
	if kind == TYPE_TERRAIN and (def.flags.has("WALL") or def.flags.has("CONNECT_TO_WALL")):
		def.connect_group = "WALL"
	if o.get("connects_to") is String:
		def.connect_group = o.connects_to


## A string or a list of strings.
static func _tags(v: Variant) -> PackedStringArray:
	if v is Array:
		return PackedStringArray(v.map(func(e: Variant) -> String: return str(e)))
	return PackedStringArray([str(v)])


## A string, or a list of 1 or 4 strings, as four seasonal values.
static func _seasons(v: Variant) -> PackedStringArray:
	if v is Array and v.size() == 4:
		return PackedStringArray([str(v[0]), str(v[1]), str(v[2]), str(v[3])])
	if v is Array and v.size() > 0:
		v = v[0]
	var s := str(v)
	return PackedStringArray([s, s, s, s])


## BN retries deferred objects until a pass makes no progress.
func _finish_deferred() -> void:
	var progress := true
	while progress and not _deferred.is_empty():
		progress = false
		var waiting := _deferred
		_deferred = []
		for entry: Array in waiting:
			if _load_tile(entry[0], entry[1], entry[2]):
				progress = true
			else:
				_deferred.append(entry)
	for entry: Array in _deferred:
		var o: Dictionary = entry[1]
		errors.append("%s %s: copy-from \"%s\" not found (%s)" % [
			entry[0], o.get("id", o.get("abstract", "?")), o.get("copy-from"), entry[2]])
	_deferred = []


func _add_mapgen(o: Dictionary, src: Source) -> void:
	var ref := MapgenRef.new()
	ref.source = src
	ref.method = str(o.get("method", "json"))
	var w: Variant = o.get("weight")
	if w is float or w is int:
		ref.weight = int(w)
	var table: Dictionary
	if o.has("om_terrain"):
		ref.kind = MapgenRef.OM_TERRAIN
		table = om_terrain
		var om: Variant = o.om_terrain
		if om is String:
			ref.ids.append(om)
		elif om is Array and not om.is_empty() and om[0] is Array:
			for row: Variant in om:
				var ids := PackedStringArray(row)
				ref.grid.append(ids)
				ref.ids.append_array(ids)
		elif om is Array:
			ref.ids = PackedStringArray(om)
	elif o.has("nested_mapgen_id"):
		ref.kind = MapgenRef.NESTED
		table = nested
		ref.ids.append(str(o.nested_mapgen_id))
		ref.chunk_size = _mapgensize(o)
	elif o.has("update_mapgen_id"):
		ref.kind = MapgenRef.UPDATE
		table = update
		ref.ids.append(str(o.update_mapgen_id))
		ref.chunk_size = _mapgensize(o)
	else:
		errors.append("mapgen without om_terrain, nested_mapgen_id or update_mapgen_id (%s)" % src)
		return
	mapgens.append(ref)
	var seen := {}
	for id in ref.ids:
		if seen.has(id):
			continue
		seen[id] = true
		if not table.has(id):
			table[id] = []
		table[id].append(ref)


## "mapgensize", defaulting to one overmap tile like BN.
static func _mapgensize(o: Dictionary) -> Vector2i:
	var obj: Variant = o.get("object")
	var ms: Variant = obj.get("mapgensize") if obj is Dictionary else null
	if ms is Array and ms.size() == 2:
		return Vector2i(int(ms[0]), int(ms[1]))
	return Vector2i(24, 24)


## The palette definition in effect for [param id], or null.
func palette(id: String) -> Definition:
	var defs: Array = palettes.get(id, [])
	return defs[-1] if not defs.is_empty() else null


## Every mapgen entry for an om_terrain id, nested id or update id.
func mapgens_for(id: String) -> Array[MapgenRef]:
	var out: Array[MapgenRef] = []
	for table: Dictionary in [om_terrain, nested, update]:
		out.append_array(table.get(id, []))
	return out


## Reads the mapgen object behind [param ref] (with Godot's JSON, so numbers
## are floats; fine for viewing). Returns {} if the file can't be read.
func read_object(src: Source) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(bn_path.path_join(src.path))) != OK:
		return {}
	var objects: Variant = json.data
	if objects is Dictionary:
		objects = [objects]
	if objects is Array and src.index < objects.size() and objects[src.index] is Dictionary:
		return objects[src.index]
	return {}

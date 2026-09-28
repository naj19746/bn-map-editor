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
##
## With a workspace, its files are layered over BN's: a workspace file at the
## same relative path replaces the BN file, and new workspace files load in
## their place in BFS order. [member Source.path] stays relative either way;
## file_path() says where the file actually is.

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
	## Terrain: "move_cost" (0 is impassable). Furniture: "move_cost_mod"
	## (-1 is impassable).
	var move_cost := 0
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
		t.move_cost = move_cost
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
	## The palettes the map lists itself, every option of a distribution or
	## param included (not the ones those palettes include).
	var palettes := PackedStringArray()
	## The nested chunk ids the map places itself (place_nested "chunks" and
	## "else_chunks", and its own "nested" symbol mappings), not the ones its
	## palettes' mappings place.
	var chunks := PackedStringArray()
	## An om_terrain mapgen with "weight" <= 0 or "disabled": true, which BN
	## never loads (load_mapgen_function). Chunks and update mapgens load
	## whatever their weight.
	var disabled := false

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


## om_terrain ids ending in one of these belong to the LINEAR overmap_terrain
## without the suffix (BN's om_lines::mapgen_suffixes).
const LINEAR_SUFFIXES := ["_straight", "_curved", "_end", "_tee", "_four_way"]

## Other object types whose ids mapgen refers to: JSON "type" -> the kind
## they're indexed under in [member ids]. Every item type is an "item".
const ID_TYPES := {
	"MONSTER": "monster", "vehicle": "vehicle", "vehicle_group": "vehicle_group", "trap": "trap",
	"field_type": "field_type", "npc": "npc", "overmap_connection": "overmap_connection",
	"ter_furn_transform": "ter_furn_transform",
	"AMMO": "item", "GUN": "item", "ARMOR": "item", "PET_ARMOR": "item", "TOOL": "item",
	"TOOLMOD": "item", "TOOL_ARMOR": "item", "BOOK": "item", "COMESTIBLE": "item",
	"CONTAINER": "item", "ENGINE": "item", "WHEEL": "item", "FUEL": "item", "GUNMOD": "item",
	"MAGAZINE": "item", "BATTERY": "item", "GENERIC": "item", "BIONIC_ITEM": "item",
}
## Types loaded through BN's generic_factory, which also registers "alias" ids.
const ALIAS_TYPES := ["MONSTER", "vehicle_group", "trap", "field_type", "overmap_connection",
	"ter_furn_transform"]
## Lua files of a mod that can register hooks.
const LUA_FILES := ["preload.lua", "finalize.lua", "main.lua"]

var bn_path := ""
## Folder layered over [member bn_path], or "".
var workspace_path := ""
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
## overmap_terrain id -> Source of its last definition. Abstracts aren't ids.
var overmap_terrain := {}
## Kind (a value of ID_TYPES) -> {id: Source of its last definition}.
var ids := {}
## om_terrain mapgen ids something other than an overmap_terrain uses: map
## extras with generator_method "mapgen", and ids a Lua
## "on_make_mapgen_factory_list" hook adds (id -> where).
var mapgen_users := {}
## Load problems: unparsable files, unresolved copy-from, bad mod selection.
var errors := PackedStringArray()
var file_count := 0

var _abstracts := {TYPE_TERRAIN: {}, TYPE_FURNITURE: {}}
## [kind, object, Source] triples waiting for their copy-from base.
var _deferred: Array = []


## Loads the core mod plus [param selected] mods (in load order, with their
## dependencies), with [param p_workspace] (if any) layered on top. Check
## [member errors] afterwards.
static func load_bn(p_bn_path: String, selected := PackedStringArray(),
		p_catalog: ModCatalog = null, p_workspace := "") -> DataIndex:
	var index := DataIndex.new()
	index.bn_path = p_bn_path.simplify_path()
	index.workspace_path = p_workspace.simplify_path() if p_workspace else ""
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
		var dir := catalog.get_mod(mod).path
		for file in data_files(dir, true, _overlay(dir)):
			_load_file(mod, file)
		for lua in LUA_FILES:
			_scan_lua(mod, dir.path_join(lua))
	for mod in mods:
		var interactions := catalog.get_mod(mod).path.path_join("mod_interactions")
		for other in mods:
			var dir := interactions.path_join(other)
			for file in data_files(dir, false, _overlay(dir)):
				_load_file(mod, file)
	_finish_deferred()


## The workspace folder mirroring [param dir] (a folder in the BN checkout).
func _overlay(dir: String) -> String:
	if workspace_path.is_empty():
		return ""
	return workspace_path.path_join(relative_path(dir))


## The *.json files under [param dir] in BN's load order. With
## [param skip_interactions], folders named "mod_interactions" are left out.
## With [param overlay], files and folders there are merged in, and an
## overlay file replaces the one at the same relative path.
static func data_files(dir: String, skip_interactions := true, overlay := "") -> PackedStringArray:
	var out := PackedStringArray()
	# Relative folders, "" for dir itself.
	var queue := PackedStringArray([""])
	var head := 0
	while head < queue.size():
		var rel := queue[head]
		head += 1
		var d := dir.path_join(rel) if rel else dir
		var o := (overlay.path_join(rel) if rel else overlay) if overlay else ""
		for f in _union(_list(d, false), _list(o, false)):
			if f.ends_with(".json"):
				out.append(o.path_join(f) if o and FileAccess.file_exists(o.path_join(f)) else d.path_join(f))
		for s in _union(_list(d, true), _list(o, true)):
			if not (skip_interactions and s == "mod_interactions"):
				queue.append(rel.path_join(s) if rel else s)
	return out


## Files or folders in [param dir]; none if it doesn't exist (DirAccess would
## log an error).
static func _list(dir: String, folders: bool) -> PackedStringArray:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	return DirAccess.get_directories_at(dir) if folders else DirAccess.get_files_at(dir)


## Sorted, without duplicates.
static func _union(a: PackedStringArray, b: PackedStringArray) -> PackedStringArray:
	var out := a.duplicate()
	for s in b:
		if not out.has(s):
			out.append(s)
	out.sort()
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


## [param file] relative to the BN checkout (or the workspace, for a
## workspace file).
func relative_path(file: String) -> String:
	if workspace_path and file.begins_with(workspace_path + "/"):
		return file.trim_prefix(workspace_path + "/")
	return file.trim_prefix(bn_path + "/")


## Where the file at BN-relative [param rel] is read from: the workspace copy
## if there is one, else the BN checkout.
func file_path(rel: String) -> String:
	if in_workspace(rel):
		return workspace_path.path_join(rel)
	return bn_path.path_join(rel)


## True when the workspace has a file at [param rel].
func in_workspace(rel: String) -> bool:
	return not workspace_path.is_empty() and FileAccess.file_exists(workspace_path.path_join(rel))


## The loaded mod whose data folder holds [param rel], or "" (a file there
## wouldn't load in BN). The innermost folder wins, since a mod's folder can
## sit inside another's.
func mod_for_path(rel: String) -> String:
	var best := ""
	var best_len := -1
	for mod in mods:
		var dir := relative_path(catalog.get_mod(mod).path)
		if rel.begins_with(dir + "/") and dir.length() > best_len and not _in_interactions(rel, dir):
			best = mod
			best_len = dir.length()
	return best


## True when [param rel] is in a "mod_interactions" folder that doesn't load:
## only <dir>/mod_interactions/<loaded mod>/... does.
func _in_interactions(rel: String, dir: String) -> bool:
	var parts := rel.substr(dir.length() + 1).split("/")
	var i := parts.find("mod_interactions")
	return i >= 0 and (i != 0 or parts.size() < 3 or not mods.has(parts[1]))


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
			add_mapgen(o, src)
		"overmap_terrain":
			for id in _tags(o.get("id", [])):
				overmap_terrain[id] = src
		"map_extra":
			var gen: Variant = o.get("generator", o)
			if gen is Dictionary and gen.get("generator_method") == "mapgen" and gen.get("generator_id") is String:
				mapgen_users[gen.generator_id] = "map_extra %s" % o.get("id", "?")
		var type:
			var kind: String = ID_TYPES.get(type, "") if type is String else ""
			if kind:
				_add_ids(kind, type, o, src)


func _add_ids(kind: String, type: String, o: Dictionary, src: Source) -> void:
	if not ids.has(kind):
		ids[kind] = {}
	var table: Dictionary = ids[kind]
	if o.has("id"):
		for id in _tags(o.id):
			table[id] = src
	if ALIAS_TYPES.has(type) and o.has("alias"):
		for id in _tags(o.alias):
			table[id] = src


## True when an object of [param kind] (a value of ID_TYPES) has [param id].
func has_id(kind: String, id: String) -> bool:
	return ids.get(kind, {}).has(id)


## True when a player can stand on terrain [param ter_id] with furniture
## [param furn_id] ("" or "f_null" for none). Unknown ids count as
## impassable.
func passable(ter_id: String, furn_id := "") -> bool:
	var t: TileDef = terrain.get(ter_id)
	if t == null or t.move_cost <= 0:
		return false
	if furn_id.is_empty() or furn_id == "f_null":
		return true
	var f: TileDef = furniture.get(furn_id)
	return f != null and f.move_cost >= 0


## Records the string ids a Lua "on_make_mapgen_factory_list" hook in
## [param file] adds: every quoted string inside the hook's function.
func _scan_lua(mod: String, file: String) -> void:
	if not FileAccess.file_exists(file):
		return
	var text := FileAccess.get_file_as_string(file)
	var hook := "\"on_make_mapgen_factory_list\""
	var strings := RegEx.create_from_string("\"([^\"\\\\]+)\"")
	var at := text.find(hook)
	while at >= 0:
		var start := text.find("function", at)
		var stop := text.find("end)", start) if start >= 0 else -1
		if stop < 0:
			break
		for m in strings.search_all(text.substr(start, stop - start)):
			mapgen_users[m.get_string(1)] = "Lua hook in %s (%s)" % [relative_path(file), mod]
		at = text.find(hook, stop)


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
	for key in ["move_cost", "move_cost_mod"]:
		if o.get(key) is float or o.get(key) is int:
			def.move_cost = int(o[key])
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


## Indexes the mapgen object [param o] (also used for mapgens the editor
## creates). Returns its entry, or null if it has no id.
func add_mapgen(o: Dictionary, src: Source) -> MapgenRef:
	var ref := MapgenRef.new()
	ref.source = src
	ref.method = str(o.get("method", "json"))
	var w: Variant = o.get("weight")
	if w is float or w is int:
		ref.weight = int(w)
	ref.disabled = o.has("om_terrain") and (ref.weight <= 0 or o.get("disabled") == true)
	var obj: Variant = o.get("object")
	if obj is Dictionary:
		ref.palettes = palette_options(obj)
		ref.chunks = chunk_options(obj)
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
		return null
	mapgens.append(ref)
	var seen := {}
	for id in ref.ids:
		if seen.has(id):
			continue
		seen[id] = true
		if not table.has(id):
			table[id] = []
		table[id].append(ref)
	return ref


## Undoes add_mapgen, e.g. when a new, unsaved mapgen is discarded.
func remove_mapgen(ref: MapgenRef) -> void:
	mapgens.erase(ref)
	for table: Dictionary in [om_terrain, nested, update]:
		for id in ref.ids:
			var refs: Array = table.get(id, [])
			refs.erase(ref)
			if refs.is_empty():
				table.erase(id)


## True when an overmap_terrain gives [param om_id] a place on the overmap:
## defined under that id, or a LINEAR terrain's id plus one of its suffixes.
func has_overmap_terrain(om_id: String) -> bool:
	if overmap_terrain.has(om_id):
		return true
	for suffix: String in LINEAR_SUFFIXES:
		if om_id.ends_with(suffix) and overmap_terrain.has(om_id.trim_suffix(suffix)):
			return true
	return false


## True when BN counts om_terrain mapgen id [param om_id] as used
## (mapgen_factory::get_usages): an overmap_terrain, a map extra or a Lua
## hook uses it, or it is "null", which BN drops without a word.
func mapgen_id_used(om_id: String) -> bool:
	return om_id == "null" or has_overmap_terrain(om_id) or mapgen_users.has(om_id)


## "mapgensize", defaulting to one overmap tile like BN.
static func _mapgensize(o: Dictionary) -> Vector2i:
	var obj: Variant = o.get("object")
	var ms: Variant = obj.get("mapgensize") if obj is Dictionary else null
	if ms is Array and ms.size() == 2:
		return Vector2i(int(ms[0]), int(ms[1]))
	return Vector2i(24, 24)


## Every palette [param data]'s "palettes" can add (a map's "object" or a
## palette): each id, and every option of a distribution or param, since BN
## adds all of them (mapgen_palette::add). Parameter defaults come from
## [param data]'s own "parameters".
static func palette_options(data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var params: Variant = data.get("parameters")
	var list: Variant = data.get("palettes")
	if not list is Array:
		return out
	for v: Variant in list:
		for id in MapgenResolver.possible_ids(v, "", params if params is Dictionary else {}):
			if not out.has(id):
				out.append(id)
	return out


## [param ids] and every palette they include, directly or not (every
## option), from the definitions in effect.
func palette_closure(ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var queue := ids.duplicate()
	while not queue.is_empty():
		var id: String = queue[0]
		queue.remove_at(0)
		if out.has(id):
			continue
		out.append(id)
		var def := palette(id)
		if def:
			queue.append_array(palette_options(def.data))
	return out


## Mapgen entries whose palettes include [param id] directly, through an
## included palette, or as any option of a distribution/param.
func maps_using(id: String) -> Array[MapgenRef]:
	# Palettes that reach id: id itself, then whatever includes one of them.
	var reaching := {id: true}
	var grew := true
	while grew:
		grew = false
		for pid: String in palettes:
			if reaching.has(pid) or palette(pid) == null:
				continue
			for inc in palette_options(palette(pid).data):
				if reaching.has(inc):
					reaching[pid] = true
					grew = true
					break
	var out: Array[MapgenRef] = []
	for ref in mapgens:
		for p in ref.palettes:
			if reaching.has(p):
				out.append(ref)
				break
	return out


## Every nested chunk id [param data] (a map's "object" or a palette) can
## place itself: its place_nested entries' "chunks" and "else_chunks", and its
## "nested" symbol mappings (also inside "mapping"). "null" and "" place
## nothing and are left out.
static func chunk_options(data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var pieces: Array = []
	var list: Variant = data.get("place_nested")
	if list is Array:
		pieces.append_array(list)
	for v in nested_mappings(data):
		pieces.append_array(v if v is Array else [v])
	for piece: Variant in pieces:
		if not piece is Dictionary:
			continue
		for member in ["chunks", "else_chunks"]:
			for option in weighted_ids(piece.get(member)):
				if option[0] and option[0] != "null" and not out.has(option[0]):
					out.append(option[0])
	return out


## The values of [param data]'s "nested" symbol mappings (each an object or
## a list of them), "mapping" entries first as BN reads them.
static func nested_mappings(data: Dictionary) -> Array:
	var out := []
	var mapping: Variant = data.get("mapping")
	if mapping is Dictionary:
		for key: String in mapping:
			if mapping[key] is Dictionary and mapping[key].has("nested"):
				out.append(mapping[key].nested)
	var nested: Variant = data.get("nested")
	if nested is Dictionary:
		out.append_array(nested.values())
	return out


## A weighted list as BN's load_weighted_list reads it: plain ids (weight
## 100) or [id, weight] pairs, as [[id, weight], ...]. Anything else is left
## out.
static func weighted_ids(list: Variant) -> Array:
	var out := []
	if not list is Array:
		return out
	for e: Variant in list:
		if e is String:
			out.append([e, 100])
		elif e is Array and e.size() == 2 and e[0] is String and (e[1] is int or e[1] is float):
			out.append([e[0], int(e[1])])
	return out


## Mapgen entries that place chunk [param id] themselves, or may through a
## "nested" mapping of a palette they use (directly, by include, or as any
## option). The palette case is a superset: the map may not use the symbol.
func maps_placing(id: String) -> Array[MapgenRef]:
	var direct := {}
	for pid: String in palettes:
		var def := palette(pid)
		if def and chunk_options(def.data).has(id):
			direct[pid] = true
	var reaching := {}
	if not direct.is_empty():
		for pid: String in palettes:
			for p in palette_closure(PackedStringArray([pid])):
				if direct.has(p):
					reaching[pid] = true
					break
	var out: Array[MapgenRef] = []
	for ref in mapgens:
		if ref.chunks.has(id):
			out.append(ref)
			continue
		for p in ref.palettes:
			if reaching.has(p):
				out.append(ref)
				break
	return out


## Adds a palette definition (one the editor creates) after the loaded ones.
func add_palette(o: Dictionary, src: Source) -> Definition:
	_add_definition(palettes, str(o.get("id", "")), src, o)
	return palette(str(o.get("id", "")))


## Undoes add_palette.
func remove_palette(def: Definition) -> void:
	var defs: Array = palettes.get(def.id, [])
	defs.erase(def)
	if defs.is_empty():
		palettes.erase(def.id)


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
	if json.parse(FileAccess.get_file_as_string(file_path(src.path))) != OK:
		return {}
	var objects: Variant = json.data
	if objects is Dictionary:
		objects = [objects]
	if objects is Array and src.index < objects.size() and objects[src.index] is Dictionary:
		return objects[src.index]
	return {}

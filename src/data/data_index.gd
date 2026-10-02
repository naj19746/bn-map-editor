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
	## "examine_action" when it is a name ("elevator", "controls_gate", ...).
	var examine_action := ""
	## Terrain: "roof", what the level above gets over it when built on
	## (set for a building's floors, walls, doors and windows).
	var roof := ""
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
		t.examine_action = examine_action
		t.roof = roof
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


## A city_building or overmap_special (BN loads both as overmap specials):
## which overmap terrains it places where, floors included.
class Building:
	var id := ""
	## "city_building" or "overmap_special".
	var type := ""
	## The definition in effect (the last one loaded).
	var source: Source
	## A "subtype": "mutable" special: placed by rules, so its tiles have no
	## fixed point (BuildingTile.placed is false).
	var mutable := false
	## Every tile, in the order the definition lists them.
	var tiles: Array[BuildingTile] = []
	## The definition whose "overmaps" list is in effect (the building's own,
	## or the one it copies from); null when none has one.
	var overmaps_source: Source

	## The z-levels that have a tile, lowest first.
	func levels() -> PackedInt32Array:
		var out := PackedInt32Array()
		for t in tiles:
			if t.placed and not out.has(t.point.z):
				out.append(t.point.z)
		out.sort()
		return out

	## The tiles on level [param z].
	func level(z: int) -> Array[BuildingTile]:
		var out: Array[BuildingTile] = []
		for t in tiles:
			if t.placed and t.point.z == z:
				out.append(t)
		return out

	## The tile at [param p], or null (the last one wins, as in BN).
	func at(p: Vector3i) -> BuildingTile:
		for i in range(tiles.size() - 1, -1, -1):
			if tiles[i].placed and tiles[i].point == p:
				return tiles[i]
		return null


## One "overmaps" entry of a Building.
class BuildingTile:
	## The Building's id (not the object: that would be a reference cycle).
	var building := ""
	var point := Vector3i.ZERO
	## False for a mutable special's overmaps, which have no fixed point.
	var placed := true
	## The overmap terrain type, rotation suffix stripped: the id its
	## om_terrain mapgen is registered under ("" when the entry names none).
	var oter := ""
	## The rotation it is placed with ("north", "east", "south", "west"), or
	## "" for a terrain named without one (it doesn't rotate).
	var dir := ""


## The city lists of a region_settings / region_overlay "city" object that
## name buildings (regional_settings.cpp load_building_types).
const CITY_LISTS := ["houses", "urban_houses", "shops", "urban_shops", "parks", "finales"]

## Overmap terrain ids BN draws with a C++ function when no JSON mapgen does
## (mapgen_functions.cpp get_mapgen_cfunction, registered per id).
const BUILTIN_MAPGENS := ["null", "test", "crater", "field", "forest", "forest_trail_straight",
	"forest_trail_curved", "forest_trail_end", "forest_trail_tee", "forest_trail_four_way", "hive",
	"road_straight", "road_curved", "road_end", "road_tee", "road_four_way", "highway",
	"railroad_straight", "railroad_curved", "railroad_end", "railroad_tee", "railroad_four_way",
	"railroad_bridge", "river_center", "river_curved_not", "river_straight", "river_curved",
	"river_shore", "parking_lot", "cavern", "open_air", "rift", "hellmouth", "empty_rock", "rock",
	"subway_straight", "subway_curved", "subway_end", "subway_tee", "subway_four_way",
	"sewer_straight", "sewer_curved", "sewer_end", "sewer_tee", "sewer_four_way", "tutorial",
	"lake_shore", "pd_border"]
## Overmap terrain id prefixes BN draws in code when nothing else does
## (mapgen.cpp draw_map's fallback).
const FALLBACK_PREFIXES := ["office", "temple", "mine"]

## Rotation suffixes of overmap terrain ids (BN's om_direction names).
const DIRECTIONS := ["north", "east", "south", "west"]

## om_terrain ids ending in one of these belong to the LINEAR overmap_terrain
## without the suffix (BN's om_lines::mapgen_suffixes).
const LINEAR_SUFFIXES := ["_straight", "_curved", "_end", "_tee", "_four_way"]
## The overmap terrain ids of a LINEAR terrain are its id plus one of these
## (om_lines::all), e.g. road_ew.
const LINE_SUFFIXES := ["_isolated", "_end_south", "_end_west", "_ne", "_end_north", "_ns", "_es", "_nes",
	"_end_east", "_wn", "_ew", "_new", "_sw", "_nsw", "_esw", "_nesw"]

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
## city_building / overmap_special id -> Building (copy-from applied).
var buildings := {}
## Overmap terrain type (as BuildingTile.oter) -> Array[BuildingTile]: the
## buildings that place it, in building load order.
var building_tiles := {}
## Building id -> the city lists naming it, e.g. "houses of region default"
## (region_settings and region_overlay objects).
var city_listed := {}
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
## Building id -> Array of [object, Source], in load order; resolved once
## everything (overmap_terrain included) has loaded.
var _building_defs := {}
## overmap_terrain id -> whether its definition has a "mapgen" list or is
## LINEAR (see has_mapgen_for), read on first use.
var _oter_draws := {}


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
	_finish_buildings()


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
		"city_building", "overmap_special":
			var id := str(o.get("id", ""))
			if id:
				if not _building_defs.has(id):
					_building_defs[id] = []
				_building_defs[id].append([o, src])
		"region_settings", "region_overlay":
			_add_city_lists(o)
		"map_extra":
			var gen: Variant = o.get("generator", o)
			if gen is Dictionary and gen.get("generator_method") == "mapgen" and gen.get("generator_id") is String:
				mapgen_users[gen.generator_id] = "map_extra %s" % o.get("id", "?")
		var type:
			var kind: String = ID_TYPES.get(type, "") if type is String else ""
			if kind:
				_add_ids(kind, type, o, src)


## Records the buildings [param o]'s "city" lists name (see city_listed).
func _add_city_lists(o: Dictionary) -> void:
	var city: Variant = o.get("city")
	if not city is Dictionary:
		return
	var region := str(o.get("id", "")) if o.type == "region_settings" else "overlay for %s" % ", ".join(
			_tags(o.get("regions", [])))
	for list: String in CITY_LISTS:
		var names: Variant = city.get(list)
		if not names is Dictionary:
			continue
		for id: String in names:
			if not city_listed.has(id):
				city_listed[id] = PackedStringArray()
			city_listed[id].append("%s of %s" % [list, region])


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
	if o.has("examine_action"):
		def.examine_action = o.examine_action if o.examine_action is String else ""
	if o.has("roof"):
		def.roof = o.roof if o.roof is String else ""
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


## Builds [member buildings] and [member building_tiles] from the loaded
## definitions. A copy-from without its own "overmaps" keeps its base's (the
## previous definition when it copies its own id, as mods overriding a
## special's flags do).
func _finish_buildings() -> void:
	for id: String in _building_defs:
		var defs: Array = _building_defs[id]
		var got := _building_data(id, defs.size() - 1, 0)
		var b := Building.new()
		b.id = id
		b.type = str(defs[-1][0].get("type"))
		b.source = defs[-1][1]
		b.mutable = got[0] == "mutable"
		b.overmaps_source = got[2]
		buildings[id] = b
		_set_tiles(b, got[1])
	_building_defs = {}


## Puts [param b]'s tiles (and their building_tiles entries) as
## [param overmaps] (an "overmaps" value) lists them.
func _set_tiles(b: Building, overmaps: Variant) -> void:
	for t in b.tiles:
		if building_tiles.has(t.oter):
			building_tiles[t.oter].erase(t)
			if building_tiles[t.oter].is_empty():
				building_tiles.erase(t.oter)
	b.tiles.clear()
	if b.mutable and overmaps is Dictionary:
		for key: String in overmaps:
			var e: Variant = overmaps[key]
			if e is Dictionary and e.get("overmap") is String:
				b.tiles.append(_building_tile(b.id, e.overmap, Vector3i.ZERO, false))
	elif not b.mutable and overmaps is Array:
		for e: Variant in overmaps:
			if not e is Dictionary or not e.get("overmap") is String:
				continue
			var p: Variant = e.get("point")
			if p is Array and p.size() == 3 and p.all(func(v: Variant) -> bool: return v is float or v is int):
				b.tiles.append(_building_tile(b.id, e.overmap, Vector3i(int(p[0]), int(p[1]), int(p[2]))))
	for t in b.tiles:
		if t.oter:
			if not building_tiles.has(t.oter):
				building_tiles[t.oter] = []
			building_tiles[t.oter].append(t)


## Reads the tiles again for every building whose "overmaps" come from
## the definition at [param src], now [param overmaps] (e.g. edited, or back
## as on disk). Returns the buildings changed.
func set_building_overmaps(src: Source, overmaps: Variant) -> Array[Building]:
	var out: Array[Building] = []
	for id: String in buildings:
		var b: Building = buildings[id]
		var from := b.overmaps_source
		if from and from.path == src.path and from.index == src.index:
			_set_tiles(b, overmaps)
			out.append(b)
	return out


## Adds a building the editor created from [param o] (its own "overmaps",
## no copy-from), defined at [param src].
func add_building(o: Dictionary, src: Source) -> Building:
	var b := Building.new()
	b.id = str(o.get("id", ""))
	b.type = str(o.get("type", ""))
	b.source = src
	b.mutable = o.get("subtype") == "mutable"
	b.overmaps_source = src
	buildings[b.id] = b
	_set_tiles(b, o.get("overmaps"))
	return b


## Takes out a building add_building() added.
func remove_building(b: Building) -> void:
	_set_tiles(b, null)
	buildings.erase(b.id)


## [subtype, overmaps, Source of the definition giving the overmaps] of
## definition [param k] of building [param id], following copy-from for what
## it doesn't say itself.
func _building_data(id: String, k: int, depth: int) -> Array:
	var o: Dictionary = _building_defs[id][k][0]
	var subtype: Variant = o.get("subtype")
	var overmaps: Variant = o.get("overmaps")
	var from_src: Source = _building_defs[id][k][1] if overmaps != null else null
	var base := str(o.get("copy-from", ""))
	if (subtype == null or overmaps == null) and base and depth < 32:
		var from: Array = []
		if base == id and k > 0:
			from = _building_data(id, k - 1, depth + 1)
		elif base != id and _building_defs.has(base):
			from = _building_data(base, _building_defs[base].size() - 1, depth + 1)
		if not from.is_empty():
			if subtype == null:
				subtype = from[0]
			if overmaps == null:
				overmaps = from[1]
				from_src = from[2]
	return [subtype if subtype is String else "fixed", overmaps, from_src]


func _building_tile(building: String, oter_id: String, point: Vector3i, placed := true) -> BuildingTile:
	var t := BuildingTile.new()
	t.building = building
	t.point = point
	t.placed = placed
	t.oter = oter_id
	for dir: String in DIRECTIONS:
		if oter_id.ends_with("_" + dir) and not overmap_terrain.has(oter_id):
			t.oter = oter_id.trim_suffix("_" + dir)
			t.dir = dir
			break
	return t


## The building tiles that place overmap terrain [param oter_id] (with or
## without a rotation suffix).
func buildings_using(oter_id: String) -> Array[BuildingTile]:
	var out: Array[BuildingTile] = []
	out.assign(building_tiles.get(oter_id, building_tiles.get(
			_building_tile("", oter_id, Vector3i.ZERO).oter, [])))
	return out


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


## True when BN has something to draw overmap terrain type [param oter]
## (a BuildingTile.oter) with: an enabled om_terrain mapgen, a C++ function
## (BUILTIN_MAPGENS, or a "mapgen" list in its overmap_terrain), a Lua
## generator, or draw_map's fallback by prefix. A LINEAR terrain counts
## (its mapgens are per suffix). Without one BN shows an error when it
## generates the tile and fills it with t_floor.
func has_mapgen_for(oter: String) -> bool:
	for r: MapgenRef in om_terrain.get(oter, []):
		if not r.disabled:
			return true
	if BUILTIN_MAPGENS.has(oter) or mapgen_users.has(oter):
		return true
	for prefix: String in FALLBACK_PREFIXES:
		if oter.begins_with(prefix):
			return true
	if not overmap_terrain.has(oter):
		# A LINEAR terrain's id plus a suffix, or no terrain at all.
		return is_overmap_terrain_id(oter)
	if not _oter_draws.has(oter):
		var o := read_object(overmap_terrain[oter])
		_oter_draws[oter] = o.get("mapgen") is Array or _tags(o.get("flags", [])).has("LINEAR")
	return _oter_draws[oter]


## True when [param oter] names an overmap terrain: a defined id, or a
## LINEAR terrain's id plus one of LINE_SUFFIXES (a building placing a
## piece of road).
func is_overmap_terrain_id(oter: String) -> bool:
	if overmap_terrain.has(oter):
		return true
	for suffix: String in LINE_SUFFIXES:
		if oter.ends_with(suffix) and overmap_terrain.has(oter.trim_suffix(suffix)):
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


## Puts back a definition remove_palette() took out, at [param position]
## in its id's load order.
func insert_palette(def: Definition, position: int) -> void:
	if not palettes.has(def.id):
		palettes[def.id] = []
	var defs: Array = palettes[def.id]
	defs.insert(clampi(position, 0, defs.size()), def)


## Moves the objects of file [param rel] at index [param at] and after by
## [param delta]: -1 after the object at [param at] was taken out of the
## file (its own Source, if still indexed, is left alone), +1 before one is
## put back there. Every Source the index holds moves once, however many
## entries share it.
func shift_sources(rel: String, at: int, delta: int) -> void:
	var seen := {}
	var all: Array = []
	for table: Dictionary in [terrain, furniture]:
		for id: String in table:
			all.append(table[id].source)
	for table: Dictionary in [palettes, item_groups, monster_groups]:
		for id: String in table:
			for d: Definition in table[id]:
				all.append(d.source)
	for ref in mapgens:
		all.append(ref.source)
	all.append_array(overmap_terrain.values())
	for id: String in buildings:
		all.append(buildings[id].source)
		all.append(buildings[id].overmaps_source)
	for kind: String in ids:
		all.append_array(ids[kind].values())
	for src: Source in all:
		if src == null or src.path != rel or seen.has(src):
			continue
		seen[src] = true
		if src.index > at or (delta > 0 and src.index == at):
			src.index += delta


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

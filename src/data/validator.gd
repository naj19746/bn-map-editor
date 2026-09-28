class_name Validator
extends RefCounted
## Checks a mapgen or a palette the way BN does when it loads them, and says
## how BN reacts to each finding (mapgen.cpp; PLAN.MD, "Checked after
## Stage 6"):
## - ERROR: BN won't load the map (a JsonError while setting it up), or it
##   reports the problem on every load (a debugmsg from its consistency
##   checks; the game goes on). [member Finding.load_fails] says which.
## - WARNING: BN silently drops or skips something.
## - NOTE: BN does something odd but defined.
##
## Where BN looks: a palette is checked on its own, every key. A map is
## checked for the keys its rows use (its pieces are built per used cell),
## its place_* lists and "set". So an unknown id in a palette is one finding
## on the palette, not one per map using it: validate_map() leaves palette
## definitions to validate_palette(). For keys a map defines but its rows
## don't use, BN still converts plain terrain/furniture/trap/field ids when it
## reads the map (reported), but checks nothing else: those are notes.
##
## Kinds of ids checked: terrain, furniture, traps, fields, items, item
## groups, monsters, monster groups, vehicles (groups and prototypes), npc
## templates, ter_furn_transforms, gas pump fuel, nested chunks, neighbors
## overmap terrain types and connections, palettes. NOT_CHECKED lists what
## BN checks and this doesn't.

enum Severity { ERROR, WARNING, NOTE }
## What a finding points at.
enum Target {
	NONE,
	## A symbol ([member Finding.key]) of the map.
	SYMBOL,
	## A cell ([member Finding.cell]) of the map.
	CELL,
	## Placement [member Finding.member] #[member Finding.index].
	PLACEMENT,
	## A key of palette [member Finding.palette] ("" key: the palette itself).
	PALETTE_KEY,
}

## What a finding is about, for counting and tests.
enum Code {
	MALFORMED, ROWS, NO_TERRAIN, UNDEFINED_SYMBOL, UNKNOWN_ID, UNKNOWN_PALETTE, UNDEFINED_PARAMETER,
	CROSSES, LOOT_GROUP_ITEM, NO_MONSTER, SET_OPERATION, DEPRECATED_SET, BAD_FUEL, NOT_USED,
	CHUNK_LOOP, ROTATION, COMPUTER,
	DROPPED, DROPPED_SET, ITEMS_CHANCE, COMPUTER_IGNORED, NO_OPTIONS, NO_STAND, NO_DOOR,
	DISABLED, SPANS_BACK, OUTSIDE_CHUNK, CHUNK_ROTATION, OVERHANG, CONDITIONAL, UNUSED_KEY_ID,
	DOOR_ELSEWHERE, OTHER_LOCKED, SHARED_DOOR, EDGE_CONSOLE, CHUNK_CONSOLE, CONSOLE_OVERHANG,
	STAIRS, STAIRS_OFFSET, STAIRS_NO_TILE, ELEVATOR, ELEVATOR_OFFSET, ELEVATOR_ON,
	CITY_LIST, BAD_TERRAIN, DUPLICATE_POINT, NO_MAPGEN,
}

const NOT_CHECKED := "Not checked yet: sign and graffiti snippets, zone types and factions, mapgen " \
		+ "flags, parameter scopes and types, the PLANT rule for furniture outside sealed_item, " \
		+ "paint on NO_PAINT terrain, joins; for computers, doors from \"set\"/place_terrain or on other " \
		+ "z-levels."

## Kinds of ids, as [label, the id meaning "nothing"].
const ID_KINDS := {
	"terrain": ["terrain", "t_null"],
	"furniture": ["furniture", "f_null"],
	"trap": ["trap", "tr_null"],
	"field_type": ["field type", "fd_null"],
	"npc": ["npc template", "null"],
	"item": ["item", "null"],
	"item_group": ["item group", ""],
	"group_or_item": ["item group or item", ""],
	"fuel": ["gas pump fuel", "null"],
	"monster": ["monster", "mon_null"],
	"monster_group": ["monster group", "GROUP_NULL"],
	"vehicle_group": ["vehicle group or vehicle", "null"],
	"ter_furn_transform": ["ter_furn_transform", "null"],
	"chunk": ["nested chunk", "null"],
	"oter_type": ["overmap terrain type", ""],
	"overmap_connection": ["overmap connection", ""],
}
## Ids BN converts to an int id as soon as it reads a plain string, which
## reports an unknown one whether the symbol is used or not.
const CONVERTED := ["terrain", "furniture", "trap", "field_type"]
## Gas pumps take only these (jmapgen_gaspump::check).
const FUELS := ["null", "gasoline", "diesel", "jp8", "avgas"]
const OMT_CELLS := MapgenResolver.OMT_SIZE

## Per mapping kind (and the place_* list using the same piece): the fields
## holding ids, as [field, id kind]. Terrain, furniture and traps are
## handled apart (a plain value, or a list of alternatives).
const PIECE_FIELDS := {
	"fields": [["field", "field_type"]],
	"npcs": [["class", "npc"]],
	"vendingmachines": [["item_group", "item_group"]],
	"gaspumps": [["fuel", "fuel"]],
	"items": [["item", "group_or_item"]],
	"monsters": [["monster", "monster_group"]],
	"vehicles": [["vehicle", "vehicle_group"]],
	"item": [["item", "item"]],
	"monster": [["group", "monster_group"]],
	"rubble": [["rubble_type", "furniture"], ["floor_type", "terrain"]],
	"sealed_item": [["furniture", "furniture"]],
	"liquids": [["liquid", "item"]],
	"translate": [["from", "terrain"], ["to", "terrain"]],
	"ter_furn_transforms": [["transform", "ter_furn_transform"]],
}
## place_* list -> the mapping kind whose piece it holds.
const MEMBER_PIECES := {
	"place_item": "item", "add": "item", "place_fields": "fields", "place_npcs": "npcs",
	"place_vendingmachines": "vendingmachines", "place_liquids": "liquids",
	"place_gaspumps": "gaspumps", "place_items": "items", "place_monsters": "monsters",
	"place_vehicles": "vehicles", "place_traps": "traps", "place_furniture": "furniture",
	"place_terrain": "terrain", "place_monster": "monster", "place_rubble": "rubble",
	"place_nested": "nested", "translate_ter": "translate", "place_computers": "computers",
	"place_ter_furn_transforms": "ter_furn_transforms",
}
## The wrapper member of the alternatives kinds, as a place_* entry names it.
const TILE_WRAPPERS := {"terrain": "ter", "furniture": "furn", "traps": "trap"}
## "set" operations and the id kind their "id" names ("" for none).
const SET_OPERATIONS := {"terrain": "terrain", "furniture": "furniture", "trap": "trap",
	"radiation": "", "bash": ""}


## One thing BN would complain about or do oddly.
class Finding:
	var severity := Severity.ERROR
	## For an ERROR: true when BN won't load the map at all, false when it
	## reports the problem on every load.
	var load_fails := false
	var code := Code.MALFORMED
	var text := ""
	var target := Target.NONE
	var key := ""
	var cell := -Vector2i.ONE
	var member := ""
	var index := -1
	var palette := ""
	## For a console of a chunk the map places: what the canvas shows when
	## the finding is selected, as ConsoleReachView.build's arguments after
	## the index ([size, grids, cells, computer]); else empty.
	var view: Array = []
	## For a finding about a building (validate_building): its id.
	var building := ""
	## For a stair or elevator finding: the other levels' mapgens it is
	## about (DataIndex.MapgenRef), so a client can open them.
	var levels: Array = []

	## "error", "warning" or "note".
	func severity_name() -> String:
		return ["error", "warning", "note"][severity]

	## How BN reacts, e.g. "BN won't load this map".
	func reaction() -> String:
		match severity:
			Severity.ERROR:
				if load_fails:
					return "BN won't load this " + ("palette" if palette else "map")
				return "BN reports this on every load"
			Severity.WARNING:
				if code in [Code.NO_OPTIONS, Code.NO_STAND, Code.NO_DOOR, Code.CHUNK_CONSOLE]:
					return "it does nothing in game"
				if code == Code.CONSOLE_OVERHANG:
					return "BN crashes if that tile isn't generated yet"
				if code == Code.STAIRS:
					return "the stairs lead nowhere"
				if code == Code.ELEVATOR:
					return "the elevator goes nowhere"
				if code == Code.NO_MAPGEN:
					return "BN shows an error when it generates the tile, and fills it with floor"
				return "BN silently skips it"
		return "works, but oddly"

	## One line: "error: <text> (BN won't load this map)".
	func describe() -> String:
		var where := "palette %s: " % palette if palette and target == Target.PALETTE_KEY \
				else "building %s: " % building if building else ""
		return "%s: %s%s (%s)" % [severity_name(), where, text, reaction()]


var index: DataIndex
var findings: Array[Finding] = []
## What the findings are added with, set per check.
var _target := Target.NONE
var _key := ""
var _member := ""
var _index := -1
var _cell := -Vector2i.ONE
var _palette := ""
var _params := {}
## Chunk id -> whether it (or a chunk it places) may put down a console.
var _console_chunks := {}
## Chunk console findings made so far (text -> true).
var _console_texts := {}


## Every finding for map [param mapgen] (a whole mapgen object) of
## [param ref], resolved as [param resolved], with [param placements] and
## its chunk [param overlay] (null to skip the chunk checks). Palettes it
## uses are left to validate_palette(). With [param stairs], its stairs are
## paired with the levels above and below in every building placing it
## (see _check_stairs), and its elevator controls with the building's other
## levels (_check_elevators); share one Stairs between maps to look each
## other level up once.
static func validate_map(p_index: DataIndex, ref: DataIndex.MapgenRef, mapgen: Dictionary,
		resolved: ResolvedMapgen, placements: Array[Placement], overlay: ChunkOverlay,
		stairs: Stairs = null) -> Array[Finding]:
	var v := Validator.new()
	v.index = p_index
	v._check_map(ref, mapgen, resolved, placements, overlay)
	if stairs and ref and not ref.disabled and ref.kind == DataIndex.MapgenRef.OM_TERRAIN \
			and mapgen.get("object") is Dictionary:
		var grid := stairs.grid_of(mapgen, resolved, overlay)
		v._check_stairs(ref, grid, stairs)
		v._check_elevators(ref, grid, stairs, resolved, placements)
	return v.findings


## Every finding for palette [param id] as defined by [param data]: each of
## its own keys (not its includes', which are checked on their own).
static func validate_palette(p_index: DataIndex, id: String, data: Dictionary) -> Array[Finding]:
	var v := Validator.new()
	v.index = p_index
	v._palette = id
	v._check_palette(data)
	return v.findings


## Findings of every palette [param ids] uses (itself and what it includes,
## every option), each palette once.
static func validate_palettes(p_index: DataIndex, ids: PackedStringArray) -> Array[Finding]:
	var out: Array[Finding] = []
	for id in p_index.palette_closure(ids):
		var def := p_index.palette(id)
		if def:
			out.append_array(validate_palette(p_index, id, def.data))
	return out


## Every finding for building [param b] (a city_building or
## overmap_special), as overmap_special::check and the city generator see
## it: a city_building no region's city list names (NOTE); for a fixed
## special, an "overmaps" terrain that doesn't exist and a point listed
## twice (ERROR, reported on load), and a tile nothing draws (WARNING; see
## DataIndex.has_mapgen_for). Not checked: "locations", connections, a
## rotating terrain named without its rotation.
static func validate_building(p_index: DataIndex, b: DataIndex.Building) -> Array[Finding]:
	var v := Validator.new()
	v.index = p_index
	v._check_building(b)
	for f in v.findings:
		f.building = b.id
	return v.findings


## [param list] with the errors first, then warnings, then notes (stable).
static func sorted(list: Array[Finding]) -> Array[Finding]:
	var out: Array[Finding] = []
	for s in [Severity.ERROR, Severity.WARNING, Severity.NOTE]:
		for f in list:
			if f.severity == s:
				out.append(f)
	return out


## [errors, warnings, notes] in [param list].
static func count(list: Array[Finding]) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	for f in list:
		out[f.severity] += 1
	return out


# --- Buildings -----------------------------------------------------------------

func _check_building(b: DataIndex.Building) -> void:
	if b.type == "city_building" and not index.city_listed.has(b.id):
		_add(Severity.NOTE, Code.CITY_LIST, "no region's city list (%s) names it, so cities don't place it; it spawns only if something else does (a mod's overmap rules, a Lua hook, another special)" % ", ".join(DataIndex.CITY_LISTS))
	if b.mutable:
		return
	var points := {}
	var oters := {}
	for t in b.tiles:
		if points.has(t.point):
			if points[t.point] == 1:
				_error(false, Code.DUPLICATE_POINT, "point (%d, %d, %d) is listed more than once in \"overmaps\"; the last one is used" % [
						t.point.x, t.point.y, t.point.z])
			points[t.point] += 1
			continue
		points[t.point] = 1
		if t.oter.is_empty() or oters.has(t.oter):
			continue
		oters[t.oter] = true
		var named := t.oter + ("_" + t.dir if t.dir else "")
		if not index.is_overmap_terrain_id(t.oter) and not index.is_overmap_terrain_id(named):
			_error(false, Code.BAD_TERRAIN, "\"overmaps\" names terrain \"%s\" (at (%d, %d, %d)), which no overmap_terrain defines" % [
					named, t.point.x, t.point.y, t.point.z])
		elif not index.has_mapgen_for(t.oter):
			_add(Severity.WARNING, Code.NO_MAPGEN, "no mapgen draws %s (at (%d, %d, %d))" % [t.oter, t.point.x,
					t.point.y, t.point.z])


# --- Maps ----------------------------------------------------------------------

func _check_map(ref: DataIndex.MapgenRef, mapgen: Dictionary, resolved: ResolvedMapgen,
		placements: Array[Placement], overlay: ChunkOverlay) -> void:
	if ref and ref.disabled:
		_add(Severity.NOTE, Code.DISABLED, "\"weight\" is %d%s, so BN never loads this map and checks nothing in it" % [
			ref.weight, " and \"disabled\" is true" if mapgen.get("disabled") == true else ""])
		return
	var obj: Variant = mapgen.get("object")
	var chunk := mapgen.has("nested_mapgen_id") or mapgen.has("update_mapgen_id")
	if mapgen.has("nested_mapgen_id") and not (obj is Dictionary and obj.get("mapgensize") is Array):
		_error(true, Code.MALFORMED, "a nested chunk needs \"mapgensize\"")
	_resolver_issues(resolved)
	if not obj is Dictionary:
		return
	_params = resolved.parameters
	_check_own_symbols(obj, resolved)
	_check_placements(placements)
	if obj.has("set"):
		_check_sets(obj.set, placements)
	if chunk and mapgen.has("nested_mapgen_id"):
		_check_chunk_rotation(obj)
	if overlay:
		_check_overlay(overlay)
	if not mapgen.has("update_mapgen_id"):
		_check_consoles(obj, resolved, placements, overlay, chunk)
		if overlay:
			_check_chunk_consoles(mapgen, resolved, placements, overlay)
	if ref and ref.kind == DataIndex.MapgenRef.OM_TERRAIN and ref.method == "json":
		_to(Target.NONE)
		for id in ref.ids:
			if not index.mapgen_id_used(id):
				_error(false, Code.NOT_USED, "om_terrain \"%s\" has no overmap_terrain (\"Mapgen %s is not used by anything!\"; Edit > Add missing overmap_terrain)" % [id, id])


func _resolver_issues(resolved: ResolvedMapgen) -> void:
	for issue: Array in resolved.issues:
		var key: String = issue[1]
		if key:
			_to(Target.SYMBOL, key)
		else:
			_to(Target.NONE)
		match issue[0]:
			ResolvedMapgen.Issue.OBJECT, ResolvedMapgen.Issue.ROWS:
				_error(true, Code.ROWS, issue[2])
			ResolvedMapgen.Issue.NO_TERRAIN:
				_error(true, Code.NO_TERRAIN, issue[2])
			ResolvedMapgen.Issue.UNDEFINED:
				_error(false, Code.UNDEFINED_SYMBOL, issue[2])
			ResolvedMapgen.Issue.PALETTE:
				_error(false, Code.UNKNOWN_PALETTE, issue[2])
			ResolvedMapgen.Issue.FILL_TER:
				_error(false, Code.UNKNOWN_ID, issue[2])
			# IDS: checked per definition below (the palette's own are the palette's).


## The map's own symbol definitions: used keys like BN, unused ones as notes
## (plain converted ids still as errors).
func _check_own_symbols(obj: Dictionary, resolved: ResolvedMapgen) -> void:
	var used := {}
	for key in resolved.used_keys():
		used[key] = true
	for piece in own_pieces(obj):
		_to(Target.SYMBOL, piece[0])
		_check_piece(piece[1], piece[2], used.has(piece[0]))


## Every piece [param data] (a map's "object" or a palette) defines itself,
## as [key, mapping kind, value], "mapping" entries first per kind as BN
## reads them.
static func own_pieces(data: Dictionary) -> Array:
	var out := []
	var mapping: Variant = data.get("mapping")
	for kind: String in MapgenResolver.MAPPING_KINDS:
		if mapping is Dictionary:
			for key: String in mapping:
				if mapping[key] is Dictionary and mapping[key].has(kind):
					out.append([key, kind, mapping[key][kind]])
		var defs: Variant = data.get(kind)
		if defs is Dictionary:
			for key: String in defs:
				out.append([key, kind, defs[key]])
	return out


func _check_placements(placements: Array[Placement]) -> void:
	for p in placements:
		_to(Target.PLACEMENT, "", p.member, p.index)
		for issue: Array in p.issues:
			match issue[0]:
				Placement.Issue.MALFORMED:
					_error(true, Code.MALFORMED, issue[1])
				Placement.Issue.CROSSES:
					_error(true, Code.CROSSES, issue[1])
				Placement.Issue.LOOT_GROUP_ITEM:
					_error(true, Code.LOOT_GROUP_ITEM, issue[1])
				Placement.Issue.NO_MONSTER:
					_error(true, Code.NO_MONSTER, issue[1])
				Placement.Issue.DROPPED:
					_add(Severity.WARNING, Code.DROPPED_SET if p.is_set() else Code.DROPPED, issue[1])
				Placement.Issue.ITEMS_CHANCE:
					_add(Severity.WARNING, Code.ITEMS_CHANCE, issue[1])
				Placement.Issue.SPANS_BACK:
					_add(Severity.NOTE, Code.SPANS_BACK, issue[1])
				Placement.Issue.OUTSIDE_CHUNK:
					_add(Severity.NOTE, Code.OUTSIDE_CHUNK, issue[1])
		# BN builds a piece only for an entry it keeps.
		if p.status == Placement.Status.DROPPED or p.status == Placement.Status.CROSSES or p.is_set():
			continue
		if p.member == "place_loot":
			_check_loot(p.title(), p.entry)
		elif MEMBER_PIECES.has(p.member):
			var kind: String = MEMBER_PIECES[p.member]
			var value: Variant = p.entry
			if TILE_WRAPPERS.has(kind):
				value = p.entry.get(TILE_WRAPPERS[kind])
			_check_piece(kind, value, true, p.title() + ": ")


## place_loot reads its group or item when the map loads: an unknown one
## makes BN refuse the map (set_mapgen_defer).
func _check_loot(title: String, e: Dictionary) -> void:
	if e.get("group") is String and e.group and not index.item_groups.has(e.group):
		_error(true, Code.UNKNOWN_ID, "%s: unknown item group \"%s\"%s" % [title, e.group, _mods_note()])
	if e.get("item") is String and e.item and not index.has_id("item", e.item):
		_error(true, Code.UNKNOWN_ID, "%s: unknown item \"%s\"%s" % [title, e.item, _mods_note()])


## "set" entries: BN reads each kept one's operation and id when the map
## loads; a bad one makes it refuse the map.
func _check_sets(list: Variant, placements: Array[Placement]) -> void:
	if not list is Array:
		return
	var kept := {}
	for p in placements:
		if p.is_set() and p.status != Placement.Status.DROPPED:
			kept[p.index] = true
	for i in list.size():
		var e: Variant = list[i]
		if not e is Dictionary:
			continue
		_to(Target.PLACEMENT, "", "set", i)
		var op := ""
		for form in ["point", "set", "line", "square"]:
			if e.get(form) is String:
				op = e[form]
				if form == "set":
					_error(false, Code.DEPRECATED_SET, "set #%d: {\"set\": ...} is deprecated, use \"point\"" % (i + 1))
				break
		if op.is_empty():
			_error(true, Code.SET_OPERATION, "set #%d needs \"point\", \"line\" or \"square\"" % (i + 1))
			continue
		if not SET_OPERATIONS.has(op):
			_error(true, Code.SET_OPERATION, "set #%d: \"%s\" isn't terrain, furniture, trap, radiation or bash" % [i + 1, op])
			continue
		var kind: String = SET_OPERATIONS[op]
		if kind.is_empty() or not kept.has(i):
			continue
		var id: Variant = e.get("id")
		if not id is String:
			_error(true, Code.MALFORMED, "set #%d needs an \"id\"" % (i + 1))
		elif not _known(kind, id):
			_error(true, Code.UNKNOWN_ID, "set #%d: unknown %s \"%s\"%s" % [i + 1, ID_KINDS[kind][0], id, _mods_note()])


## A chunk's own "rotation" is never used: only the placing entry's turns it.
func _check_chunk_rotation(obj: Dictionary) -> void:
	if not obj.has("rotation"):
		return
	var r := Placement.IntRange.parse(obj.rotation)
	if r.valid() and r.first == 0 and r.second == 0:
		return
	_to(Target.NONE)
	_add(Severity.NOTE, Code.CHUNK_ROTATION, "the chunk's own \"rotation\" %s does nothing: BN turns a chunk only by the placing entry's \"rotation\"" % JSON.stringify(obj.rotation))


func _check_overlay(overlay: ChunkOverlay) -> void:
	var seen := {}
	for s in overlay.stamps:
		var top := s
		while top.parent >= 0:
			top = overlay.stamps[top.parent]
		_to_stamp(top)
		for issue: Array in s.issues:
			if issue[0] == ChunkOverlay.Issue.LOOP or issue[0] == ChunkOverlay.Issue.TOO_DEEP:
				var text := "%s: %s" % [s.path, issue[1]]
				if not seen.has(text):
					seen[text] = true
					_error(false, Code.CHUNK_LOOP, text + " (BN would recurse forever generating it)")
		if s.depth == 0 and s.overhangs():
			_add(Severity.NOTE, Code.OVERHANG, "%s: chunk %s reaches past its overmap tile; BN doesn't clip it (whether the overhang survives in game is unverified)" % [
				s.path, s.chunk_id])


# --- Consoles ------------------------------------------------------------------

## Whether each console's door options reach anything: the player stands
## next to the console, and BN changes matching terrain within the action's
## radius, in the stand cell's overmap tile only (see Computer.EFFECTS).
## Terrain comes from the rows and the chunk overlay; doors a "set" or
## place_terrain entry makes aren't seen, so a door those name only makes
## a note. In a chunk ([param in_chunk]) the player may stand in the map
## placing it, so a console on its edge with no stand cell inside is a note.
func _check_consoles(obj: Dictionary, resolved: ResolvedMapgen, placements: Array[Placement],
		overlay: ChunkOverlay, in_chunk := false) -> void:
	var consoles := console_cells(resolved, placements)
	if consoles.is_empty():
		return
	var grids := tile_grids(resolved, overlay, consoles)
	var terrain: PackedStringArray = grids[0]
	var elsewhere := JSON.stringify([obj.get("set"), obj.get("place_terrain"), obj.get("translate_ter")])
	## door cell -> {console cell: true}
	var reached := {}
	for at: Vector2i in consoles:
		var data: Dictionary = consoles[at][1]
		var where := "'%s' at (%d, %d)" % [consoles[at][0], at.x, at.y] if consoles[at][0] \
				else "%s at (%d, %d)" % [consoles[at][2], at.x, at.y]
		if consoles[at][0]:
			_to(Target.CELL, consoles[at][0])
			_cell_target(at)
		else:
			_to(Target.PLACEMENT, "", "place_computers", consoles[at][3])
		var reach := console_reach(index, resolved.size, grids, at, data)
		if reach.stands.is_empty() and in_chunk and _on_edge(at, resolved.size):
			_add(Severity.NOTE, Code.EDGE_CONSOLE, "%s: no cell next to the console inside the chunk can be stood on; the player has to stand in the map placing it (judged there)" % where)
			continue
		if reach.stands.is_empty():
			_add(Severity.WARNING, Code.NO_STAND, "%s: no cell next to the console can be stood on, so nobody can use it" % where)
			continue
		for action: String in reach.targets:
			var cells: Array = reach.targets[action]
			for c: Vector2i in cells:
				if not reached.has(c):
					reached[c] = {}
				reached[c][at] = true
			if not cells.is_empty():
				continue
			var e: Array = Computer.EFFECTS[action]
			var text := "%s: \"%s\" changes nothing: no %s within %d of where the player stands, in the %s" % [
				where, action, " or ".join(e[0]), e[2], "chunk" if in_chunk else "same overmap tile"]
			var named := (e[0] as Array).any(func(t: String) -> bool: return elsewhere.contains("\"%s\"" % t))
			if named:
				_add(Severity.NOTE, Code.DOOR_ELSEWHERE, text + " in the rows; a \"set\"/place_terrain entry may put one there")
			else:
				_add(Severity.WARNING, Code.NO_DOOR, text)
		if not reach.other_locked.is_empty():
			var ids := PackedStringArray()
			for c: Vector2i in reach.other_locked:
				var t: String = terrain[c.y * resolved.size.x + c.x]
				if not ids.has(t):
					ids.append(t)
			_add(Severity.NOTE, Code.OTHER_LOCKED, "%s: %d other locked door%s in reach (%s) that no computer action opens" % [
				where, reach.other_locked.size(), "" if reach.other_locked.size() == 1 else "s", ", ".join(ids)])
	# Consoles sharing doors: one note per pair.
	var pairs := {}
	for c: Vector2i in reached:
		var list: Array = reached[c].keys()
		list.sort()
		for i in list.size():
			for j in range(i + 1, list.size()):
				var k := "%s %s" % [list[i], list[j]]
				if not pairs.has(k):
					pairs[k] = [list[i], list[j], []]
				pairs[k][2].append(c)
	for k: String in pairs:
		var a: Vector2i = pairs[k][0]
		var b: Vector2i = pairs[k][1]
		var doors: Array = pairs[k][2]
		_to(Target.CELL, consoles[a][0])
		_cell_target(a)
		_add(Severity.NOTE, Code.SHARED_DOOR, "the consoles at (%d, %d) and (%d, %d) both reach %d door%s, e.g. (%d, %d)" % [
			a.x, a.y, b.x, b.y, doors.size(), "" if doors.size() == 1 else "s", doors[0].x, doors[0].y])


static func _on_edge(at: Vector2i, size: Vector2i) -> bool:
	return at.x == 0 or at.y == 0 or at.x == size.x - 1 or at.y == size.y - 1


## Consoles in the chunks the map places. The overlay draws one pick per
## placement, but BN may pick any "chunks" or "else_chunks" option, any
## mapgen of that id and any of the entry's rotations: each pick whose chunk
## may put down a console is laid alone over the map (its rows plus the
## drawn chunks, without that placement's own) and its consoles are judged
## like the map's own. A chunk that a picked chunk places is judged the
## same way, inside that pick. One finding per placing entry and pick (the
## mapgens of an id that fail the same way are one finding), pointing at the
## map's own entry.
func _check_chunk_consoles(mapgen: Dictionary, resolved: ResolvedMapgen, placements: Array[Placement],
		overlay: ChunkOverlay) -> void:
	if overlay.size != resolved.size:
		return
	var own := console_cells(resolved, placements)
	for s in overlay.stamps:
		if s.depth == 0 and not _console_ids(overlay.objects, s).is_empty():
			var base := ChunkOverlay.build(index, mapgen, resolved, overlay.objects, {s.uid: ChunkOverlay.NOTHING},
					overlay.chunk_cache)
			_judge_picks(mapgen, resolved, own, base, s, s, {})


## The ids stamp [param s] can pick whose chunks may put down a console.
func _console_ids(objects: Callable, s: ChunkOverlay.Stamp) -> PackedStringArray:
	var ids := PackedStringArray()
	for opt: Array in s.options + s.else_options:
		if opt[0] and opt[0] != "null" and not ids.has(opt[0]) and _may_have_console(objects, opt[0], {}):
			ids.append(opt[0])
	return ids


## Judges every pick of stamp [param s] laid over [param base] (an overlay
## without s's chunk); [param forced] holds the picks of s's parents.
func _judge_picks(mapgen: Dictionary, resolved: ResolvedMapgen, own: Dictionary, base: ChunkOverlay,
		s: ChunkOverlay.Stamp, top: ChunkOverlay.Stamp, forced: Dictionary) -> void:
	for id in _console_ids(base.objects, s):
		var refs: Array = index.nested.get(id, [])
		for rot in s.rotations:
			## problem text -> [severity, mapgen numbers, view, overhang]
			var groups := {}
			for vi in refs.size():
				var f2 := forced.duplicate()
				f2[s.uid] = [id, refs[vi], rot]
				var built := base.replay(s, f2)
				var st := built.stamps[0]
				var judged := _judge_stamp(mapgen, resolved, own, built, st)
				if judged[0] >= 0:
					if not groups.has(judged[1]):
						groups[judged[1]] = [judged[0], [], judged[2], judged[3]]
					groups[judged[1]][1].append(vi + 1)
				for child in built.children(st):
					if _console_ids(base.objects, child).is_empty():
						continue
					var f3 := f2.duplicate()
					f3[child.uid] = ChunkOverlay.NOTHING
					_judge_picks(mapgen, resolved, own, base.replay(s, f3), child, top, f2)
			for text: String in groups:
				var g: Array = groups[text]
				var line := "%s%s: %s" % [s.path, _pick_text(s, id, rot, g[1], refs.size()), text]
				# Different picks of an outer chunk can land an inner one alike.
				if _console_texts.has(line):
					continue
				_console_texts[line] = true
				_to_stamp(top)
				var f := _add(g[0], Code.CONSOLE_OVERHANG if g[3] else Code.CHUNK_CONSOLE, line)
				f.view = g[2]


## [most severe Severity (-1: nothing wrong), the problems as one text, the
## first judged console's view (see Finding.view), true if a console lands
## past its tile] for the consoles of [param st], the forced stamp of
## overlay [param built].
func _judge_stamp(mapgen: Dictionary, resolved: ResolvedMapgen, own: Dictionary, built: ChunkOverlay,
		st: ChunkOverlay.Stamp) -> Array:
	var worst := -1
	var parts := PackedStringArray()
	var view := []
	var overhang := false
	if st.consoles.is_empty():
		return [worst, "", view, overhang]
	var in_chunk := mapgen.has("nested_mapgen_id")
	var grids := tile_grids(resolved, built, own)
	var elsewhere := ""
	for o: Variant in [mapgen.get("object"), built.objects.call(st.ref).get("object")]:
		if o is Dictionary:
			elsewhere += JSON.stringify([o.get("set"), o.get("place_terrain"), o.get("translate_ter")])
	var bounds := Rect2i(Vector2i.ZERO, resolved.size)
	for c: Array in st.consoles:
		var at: Vector2i = c[0]
		var data: Dictionary = c[1]
		var problems := PackedStringArray()
		var sev := -1
		if not (bounds.has_point(at) and st.tile.has_point(at)):
			if in_chunk:
				continue  # Judged in the maps placing this chunk.
			problems.append("it lands past the overmap tile of the entry; BN adds a computer only to a submap already generated")
			sev = Severity.WARNING
			overhang = true
		else:
			var reach := console_reach(index, resolved.size, grids, at, data)
			if reach.stands.is_empty():
				problems.append("no cell next to it can be stood on, so nobody can use it")
				sev = Severity.NOTE if in_chunk and _on_edge(at, resolved.size) else Severity.WARNING
			for action: String in reach.targets:
				if not reach.targets[action].is_empty() or reach.stands.is_empty():
					continue
				var e: Array = Computer.EFFECTS[action]
				var named := (e[0] as Array).any(func(t: String) -> bool: return elsewhere.contains("\"%s\"" % t))
				problems.append("\"%s\" changes nothing: no %s within %d of where the player stands, in the same overmap tile%s" % [
					action, " or ".join(e[0]), e[2], " in the rows; a \"set\"/place_terrain entry may put one there" if named else ""])
				var level := Severity.NOTE if named else Severity.WARNING
				sev = level if sev < 0 else mini(sev, level)
		if problems.is_empty():
			continue
		parts.append("its console %sat (%d, %d): %s" % ["'%s' " % c[2] if c[2] else "", at.x, at.y, "; ".join(problems)])
		worst = sev if worst < 0 else mini(worst, sev)
		if view.is_empty() and bounds.has_point(at):
			var cells: Array[Vector2i] = [at]
			view = [resolved.size, grids, cells, data]
	return [worst, "; ".join(parts), view, overhang]


## " > chunk_a (5% of chunks, mapgens 1-3 of 8, rotation 1)": the pick,
## naming only what BN chooses at random.
func _pick_text(s: ChunkOverlay.Stamp, id: String, rot: int, variants: Array, of: int) -> String:
	var parts := PackedStringArray()
	for pair: Array in [["chunks", s.options], ["else_chunks", s.else_options]]:
		var total := 0
		var w := 0
		for o: Array in pair[1]:
			total += maxi(o[1], 0)
			if o[0] == id:
				w += maxi(o[1], 0)
		if w <= 0:
			continue
		if pair[0] == "else_chunks":
			parts.append("else_chunks" + (" %s" % _percent(w, total) if w < total else ""))
		elif w < total:
			parts.append(_percent(w, total))
	if of > 1:
		if variants.size() == of:
			parts.append("any of its %d mapgens" % of)
		else:
			parts.append("mapgen%s %s of %d" % ["" if variants.size() == 1 else "s", _numbers(variants), of])
	if s.rotations.size() > 1:
		parts.append("rotation %d" % rot)
	return " > %s%s" % [id, " (%s)" % ", ".join(parts) if parts else ""]


static func _percent(w: int, total: int) -> String:
	var p := 100.0 * w / total
	return "%d%%" % roundi(p) if p >= 1 else "%.1f%%" % p


## "1, 3-5" for [1, 3, 4, 5].
static func _numbers(list: Array) -> String:
	var out := PackedStringArray()
	var i := 0
	while i < list.size():
		var j := i
		while j + 1 < list.size() and list[j + 1] == list[j] + 1:
			j += 1
		out.append(str(list[i]) if i == j else "%d-%d" % [list[i], list[j]])
		i = j + 1
	return ", ".join(out)


## True when chunk [param id] (any of its mapgens, their palettes, or a
## chunk they place) may put down a console.
func _may_have_console(objects: Callable, id: String, seen: Dictionary) -> bool:
	if _console_chunks.has(id):
		return _console_chunks[id]
	if seen.has(id):
		return false
	seen[id] = true
	var found := false
	for ref: DataIndex.MapgenRef in index.nested.get(id, []):
		var obj: Variant = objects.call(ref).get("object")
		if not obj is Dictionary:
			continue
		var datas: Array = [obj]
		for pid in index.palette_closure(DataIndex.palette_options(obj)):
			var def := index.palette(pid)
			if def:
				datas.append(def.data)
		for d: Dictionary in datas:
			if _defines_computer(d):
				found = true
			else:
				for cid in DataIndex.chunk_options(d):
					if _may_have_console(objects, cid, seen):
						found = true
						break
			if found:
				break
		if found:
			break
	_console_chunks[id] = found
	return found


static func _defines_computer(d: Dictionary) -> bool:
	if d.get("place_computers") is Array and not d.place_computers.is_empty():
		return true
	if d.get("computers") is Dictionary and not d.computers.is_empty():
		return true
	var mapping: Variant = d.get("mapping")
	if mapping is Dictionary:
		for key: String in mapping:
			if mapping[key] is Dictionary and mapping[key].has("computers"):
				return true
	return false


## Every console of the map: cell -> [key ("" for a placement), computer
## JSON, placement title, placement index]. A symbol's last computer is the
## one BN keeps; a place_computers entry counts only on a single cell.
static func console_cells(resolved: ResolvedMapgen, placements: Array[Placement]) -> Dictionary:
	var out := {}
	for y in resolved.size.y:
		for x in resolved.size.x:
			var key := resolved.cells[y][x]
			var info: ResolvedMapgen.SymbolInfo = resolved.symbols.get(key)
			if info == null or not info.extras.has("computers"):
				continue
			var list := Computer.all_in(info.extras.computers[-1].value)
			if not list.is_empty():
				out[Vector2i(x, y)] = [key, list[-1], "", -1]
	for p in placements:
		if p.member == "place_computers" and p.status == Placement.Status.OK and p.span().size == Vector2i.ONE:
			out[p.span().position] = ["", p.entry, p.title(), p.index]
	return out


## [terrain, furniture] ids of every cell (row-major; "" for none): the
## chunk overlay's, else the symbol's (terrain: else fill_ter); t_console
## and no furniture where [param consoles] has one.
static func tile_grids(resolved: ResolvedMapgen, overlay: ChunkOverlay, consoles: Dictionary) -> Array[PackedStringArray]:
	var ter := PackedStringArray()
	var furn := PackedStringArray()
	ter.resize(resolved.size.x * resolved.size.y)
	furn.resize(ter.size())
	var chunks := overlay != null and overlay.size == resolved.size
	for y in resolved.size.y:
		for x in resolved.size.x:
			var i := y * resolved.size.x + x
			var t := resolved.terrain_at(x, y)
			var f := resolved.furniture_at(x, y)
			ter[i] = t.id() if t else ""
			furn[i] = f.id() if f else ""
			if chunks and overlay.ter[i]:
				ter[i] = overlay.ter[i]
			if chunks and overlay.furn[i]:
				furn[i] = overlay.furn[i]
	for c: Vector2i in consoles:
		ter[c.y * resolved.size.x + c.x] = Computer.CONSOLE
		furn[c.y * resolved.size.x + c.x] = ""
	return [ter, furn]


## What a console at [param at] with computer [param data] reaches.
class Reach:
	## Where the player can stand to use it.
	var stands: Array[Vector2i] = []
	## Door action -> the cells it changes (any stand cell reaching them).
	var targets := {}
	## Door action -> cell -> how many stand cells reach it.
	var counts := {}
	## Other locked doors (see Computer.is_locked_door) an unlock action reaches.
	var other_locked: Array[Vector2i] = []


## [param grids] are tile_grids() of a map of [param size] cells. A cell
## without terrain is one a chunk leaves as the map placing it has it, so
## it counts as a place to stand unless its furniture blocks it.
static func console_reach(p_index: DataIndex, size: Vector2i, grids: Array[PackedStringArray],
		at: Vector2i, data: Dictionary) -> Reach:
	var r := Reach.new()
	var w := size.x
	var terrain := grids[0]
	var furniture := grids[1]
	r.stands = Computer.stand_cells(at, size, func(c: Vector2i) -> bool:
		var t := terrain[c.y * w + c.x]
		var f := furniture[c.y * w + c.x]
		if t.is_empty():
			return f.is_empty() or f == "f_null" or (p_index.furniture.has(f) and p_index.furniture[f].move_cost >= 0)
		return p_index.passable(t, f))
	var others := {}
	for action in Computer.of(data).door_actions():
		var e: Array = Computer.EFFECTS[action]
		if e[2] <= 0:
			continue  # The whole z-level: other maps may hold its targets.
		var hits := {}
		for s in r.stands:
			var box := Computer.reach_rect(s, e[2], size)
			for y in range(box.position.y, box.end.y):
				for x in range(box.position.x, box.end.x):
					var c := Vector2i(x, y)
					if not Computer.in_reach(s, c, e[2]):
						continue
					var t := terrain[y * w + x]
					if (e[0] as Array).has(t):
						hits[c] = hits.get(c, 0) + 1
					elif Computer.UNLOCKS.has(action) and Computer.is_locked_door(t, e[0]):
						others[c] = true
		var cells: Array[Vector2i] = []
		cells.assign(hits.keys())
		r.targets[action] = cells
		r.counts[action] = hits
	r.other_locked.assign(others.keys())
	return r


# --- Palettes ------------------------------------------------------------------

func _check_palette(data: Dictionary) -> void:
	var params: Variant = data.get("parameters")
	_params = params if params is Dictionary else {}
	_to(Target.PALETTE_KEY, "")
	var list: Variant = data.get("palettes")
	if list is Array:
		for v: Variant in list:
			for id in MapgenResolver.possible_ids(v, "", _params):
				if index.palette(id) == null:
					_error(false, Code.UNKNOWN_PALETTE, "includes unknown palette \"%s\"%s" % [id, _mods_note()])
	for piece in own_pieces(data):
		_to(Target.PALETTE_KEY, piece[0])
		_check_piece(piece[1], piece[2], true)


# --- Pieces --------------------------------------------------------------------

## Checks one mapping value of [param kind] (or a place_* entry holding the
## same piece). [param used]: BN checks it (a used key, a placement, any
## palette key); otherwise only converted ids count and the rest are notes.
func _check_piece(kind: String, value: Variant, used: bool, prefix := "") -> void:
	if prefix.is_empty():
		prefix = "'%s' %s: " % [_key, kind]
	if TILE_WRAPPERS.has(kind):
		var id_kind := "trap" if kind == "traps" else kind
		for alt in _alternatives(value, TILE_WRAPPERS[kind]):
			_check_value(id_kind, alt, used, prefix)
		return
	for piece: Variant in (value if value is Array else [value]):
		if not piece is Dictionary:
			continue
		for spec: Array in PIECE_FIELDS.get(kind, []):
			if piece.has(spec[0]):
				if spec[1] == "group_or_item" and not piece[spec[0]] is String:
					continue  # An inline item group.
				_check_value(spec[1], piece[spec[0]], used, prefix)
		match kind:
			"monster":
				if not piece.has("group") and piece.has("monster"):
					var m: Variant = piece.monster
					for e: Variant in (m if m is Array else [m]):
						_check_value("monster", e[0] if e is Array and e.size() == 2 else e, used, prefix)
			"sealed_item":
				if piece.get("item") is Dictionary:
					_check_piece("item", piece.item, used, prefix)
				if piece.get("items") is Dictionary:
					_check_piece("items", piece.items, used, prefix)
			"nested":
				_check_nested(piece, used, prefix)
	if kind == "computers":
		_check_computers(value, used, prefix)


## A "computers" value (or a place_computers entry): BN reads each one when
## it loads the map or palette, whether the rows use the key or not.
func _check_computers(value: Variant, used: bool, prefix: String) -> void:
	if not (value is Dictionary or (value is Array and value.all(func(v: Variant) -> bool: return v is Dictionary))):
		_error(true, Code.COMPUTER, prefix + "must be an object (or a list of objects)")
		return
	for data in Computer.all_in(value):
		for issue: Array in Computer.of(data).issues():
			match issue[0]:
				Computer.Issue.NOT_LIST:
					_add(Severity.WARNING, Code.COMPUTER_IGNORED, prefix + issue[1])
				Computer.Issue.NO_OPTIONS:
					if used:
						_add(Severity.WARNING, Code.NO_OPTIONS, prefix + issue[1])
				_:
					_error(true, Code.COMPUTER, prefix + issue[1])


## The pieces of a terrain/furniture/trap value: an id, an object (wrapping
## the value in [param wrapper], or a param/distribution/switch), or a list
## of alternatives ([piece, count] pairs allowed).
static func _alternatives(value: Variant, wrapper: String) -> Array:
	var out := []
	for v: Variant in (value if value is Array else [value]):
		if v is Array and not v.is_empty():
			v = v[0]
		if v is Dictionary and v.has(wrapper):
			v = v[wrapper]
		out.append(v)
	return out


## Checks a mapgen_value (an id, or a param/distribution/switch) of
## [param kind].
func _check_value(kind: String, value: Variant, used: bool, prefix: String) -> void:
	var plain := value is String
	if value is Dictionary and value.has("param") and not _params.has(str(value.param)):
		if used:
			_error(false, Code.UNDEFINED_PARAMETER, "%suses undefined parameter \"%s\"" % [prefix, value.param])
		return
	var converted := plain and CONVERTED.has(kind)
	for id in MapgenResolver.possible_ids(value, "", _params):
		if _known(kind, id):
			continue
		var text := "%sunknown %s \"%s\"%s" % [prefix, ID_KINDS[kind][0], id, _mods_note()]
		if kind == "fuel" and index.has_id("item", id):
			text = "%s\"%s\" isn't a gas pump fuel (%s)" % [prefix, id, ", ".join(FUELS.slice(1))]
		if used or converted:
			_error(false, Code.BAD_FUEL if kind == "fuel" else Code.UNKNOWN_ID, text)
		else:
			_add(Severity.NOTE, Code.UNUSED_KEY_ID, text + "; the rows don't use this symbol, so BN doesn't check it")


## place_nested / "nested": chunk ids, neighbors' overmap terrain types,
## connections, and the placing rotation.
func _check_nested(piece: Dictionary, used: bool, prefix: String) -> void:
	for member in ["chunks", "else_chunks"]:
		for option in DataIndex.weighted_ids(piece.get(member)):
			_check_value("chunk", option[0], used, prefix)
	for pair in [["neighbors", "oter_type"], ["connections", "overmap_connection"]]:
		var dirs: Variant = piece.get(pair[0])
		if dirs is Dictionary:
			for dir: String in dirs:
				for id: Variant in (dirs[dir] if dirs[dir] is Array else [dirs[dir]]):
					_check_value(pair[1], str(id), used, prefix + "%s %s: " % [pair[0], dir])
	if piece.has("neighbors") or piece.has("joins") or piece.has("connections"):
		var conds := PackedStringArray()
		for c in ["neighbors", "joins", "connections"]:
			if piece.has(c):
				conds.append(c)
		var alt := DataIndex.weighted_ids(piece.get("else_chunks"))
		_add(Severity.NOTE, Code.CONDITIONAL, "%splaces its chunks only if its %s match, else %s (the editor always draws \"chunks\")" % [
			prefix, "/".join(conds), ", ".join(alt.map(func(o: Array) -> String: return o[0])) if alt else "nothing"])
	if piece.has("rotation"):
		var r := Placement.IntRange.parse(piece.rotation)
		if not r.valid():
			_error(true, Code.MALFORMED, prefix + "rotation must be an int or [min, max]")
		elif r.lo() < 0 or r.hi() > 4:
			_error(false, Code.ROTATION, prefix + "rotation %s is outside 0-4 (BN asserts)" % r.text())


## True when [param id] names an existing object of [param kind] (or is the
## kind's "nothing" id).
func _known(kind: String, id: String) -> bool:
	if id == ID_KINDS[kind][1]:
		return true
	match kind:
		"terrain": return index.terrain.has(id)
		"furniture": return index.furniture.has(id)
		"item_group": return index.item_groups.has(id)
		"group_or_item": return index.item_groups.has(id) or index.has_id("item", id)
		"monster_group": return index.monster_groups.has(id)
		"vehicle_group": return index.has_id("vehicle_group", id) or index.has_id("vehicle", id)
		"chunk": return id.is_empty() or index.nested.has(id)
		"oter_type": return index.overmap_terrain.has(id)
		"fuel": return FUELS.has(id)
	return index.has_id(kind, id)


## The id kind (a key of ID_KINDS) field [param key] of a [param member]
## entry names, as _check_piece reads it, or "" when it isn't an id. A
## "set" entry's "id" depends on its operation in [param entry].
static func field_id_kind(member: String, key: String, entry: Dictionary) -> String:
	match member:
		"place_loot":
			return {"group": "item_group", "item": "item"}.get(key, "")
		"place_monster":
			if key == "monster":
				return "monster"
		"set":
			if key != "id":
				return ""
			for form in ["point", "set", "line", "square"]:
				if entry.get(form) is String:
					return SET_OPERATIONS.get(entry[form], "")
			return ""
	var kind: String = MEMBER_PIECES.get(member, "")
	if TILE_WRAPPERS.has(kind):
		return ("trap" if kind == "traps" else kind) if key == TILE_WRAPPERS[kind] else ""
	for spec: Array in PIECE_FIELDS.get(kind, []):
		if spec[0] == key:
			return spec[1]
	return ""


## Whether [param p_index] knows [param id] as an id of [param kind] (a
## key of ID_KINDS), as the id checks judge it.
static func is_known(p_index: DataIndex, kind: String, id: String) -> bool:
	var v := Validator.new()
	v.index = p_index
	return v._known(kind, id)


## Every id of [param kind] (a key of ID_KINDS) [param index] knows, sorted:
## the ids _known accepts (the "nothing" id only where the index has it).
static func id_candidates(index: DataIndex, kind: String) -> PackedStringArray:
	var ids := {}
	match kind:
		"terrain": ids = index.terrain
		"furniture": ids = index.furniture
		"item_group": ids = index.item_groups
		"group_or_item": ids = index.item_groups.merged(index.ids.get("item", {}))
		"monster_group": ids = index.monster_groups
		"vehicle_group": ids = index.ids.get("vehicle_group", {}).merged(index.ids.get("vehicle", {}))
		"chunk": ids = index.nested
		"oter_type": ids = index.overmap_terrain
		"fuel": return PackedStringArray(FUELS.slice(1))
		_: ids = index.ids.get(kind, {})
	var out := PackedStringArray(ids.keys())
	out.sort()
	return out


## " in the loaded mods" when mods other than core are loaded: an id from a
## mod that isn't loaded is unknown here.
func _mods_note() -> String:
	return " in the loaded mods" if index.mods.size() > 1 else ""


# --- Stairs between levels ------------------------------------------------------

## Each overmap tile's stairs against the tile above (GOES_UP) and below
## (GOES_DOWN) in every building placing the map, as game::find_stairs
## pairs them (see Stairs): the other tile has no stairs back at all (or no
## mapgen draws it), a WARNING: BN drops the player at the same x,y; none of
## them at the same cells, a NOTE: the player arrives at the nearest one;
## the building has no tile there, a NOTE: what the overmap puts there
## (another special, a lab) decides. A finding names the first place and
## counts the others with the same text. Every enabled mapgen of the other tile is paired (each is a
## finding of its own, named). Levels are compared in world orientation:
## each tile turned by its rotation in the building.
func _check_stairs(ref: DataIndex.MapgenRef, grid: Stairs.Grid, stairs: Stairs) -> void:
	## text -> [Finding, buildings]
	var seen := {}
	for place in BuildingLevels.places(index, ref):
		for id in ref.ids:
			var at := ref.position_of(id)
			var bt := place.building.at(place.origin + Vector3i(at.x, at.y, 0))
			if bt == null or bt.oter != id:
				continue
			for dz: int in [1, -1]:
				var mine := grid.cells(at, Stairs.UP if dz > 0 else Stairs.DOWN)
				if mine.is_empty():
					continue
				for pair in _stair_pairs(id, ref.ids.size() > 1, at * OMT_CELLS, bt, dz, mine, place, stairs):
					_add_at_place(seen, place, pair, at * OMT_CELLS + mine[0])
	_name_places(seen)


## Adds [param pair] ([severity, text, code, the other levels' mapgens])
## at map cell [param cell] for [param place], or counts the place in the
## finding [param seen] already has with the same text.
func _add_at_place(seen: Dictionary, place: BuildingLevels.Place, pair: Array, cell: Vector2i) -> void:
	var text: String = pair[1]
	var f: Finding
	if seen.has(text):
		seen[text][1].append(place.label())
		f = seen[text][0]
	else:
		_to(Target.CELL, "")
		_cell_target(cell)
		f = _add(pair[0], pair[2], text)
		seen[text] = [f, [place.label()]]
	for r: DataIndex.MapgenRef in pair[3]:
		if not f.levels.has(r):
			f.levels.append(r)


## Puts the first place, and how many others, before each text of
## [param seen] (see _add_at_place).
func _name_places(seen: Dictionary) -> void:
	for text: String in seen:
		var f: Finding = seen[text][0]
		var where: Array = seen[text][1]
		f.text = "in %s%s: %s" % [where[0], " and %d other place%s" % [where.size() - 1,
				"" if where.size() == 2 else "s"] if where.size() > 1 else "", text]


## [severity, text, code, mapgens] for the stairs [param mine] (tile-local cells) of tile
## [param bt] ([param id]) against the tile [param dz] levels away.
## [param offset] is the tile's first cell in the map ([param multi]: one
## of several tiles); texts give map cells.
func _stair_pairs(id: String, multi: bool, offset: Vector2i, bt: DataIndex.BuildingTile, dz: int, mine: Array[Vector2i],
		place: BuildingLevels.Place, stairs: Stairs) -> Array:
	var out := []
	var what := "stairs %s at %s%s" % ["up" if dz > 0 else "down", _cells_text(mine, offset),
			" (tile %s)" % id if multi else ""]
	var other := place.building.at(bt.point + Vector3i(0, 0, dz))
	var level := "the tile %s (z %d)" % ["above" if dz > 0 else "below", bt.point.z + dz]
	if other == null:
		out.append([Severity.NOTE, "%s: %s has no tile %s (z %d); they connect only if what the overmap puts there (another special, a lab, ...) has stairs %s" % [
				what, place.building.id, "above" if dz > 0 else "below", bt.point.z + dz, "down" if dz > 0 else "up"], Code.STAIRS_NO_TILE, []])
		return out
	var refs: Array[DataIndex.MapgenRef] = []
	for r in BuildingLevels.mapgens(index, other.oter):
		if not r.disabled:
			refs.append(r)
	if refs.is_empty():
		out.append([Severity.WARNING, "%s: no mapgen draws %s, %s, so it has no stairs back" % [
				what, other.oter, level], Code.STAIRS, []])
		return out
	var turns := _turns(other.dir) - _turns(bt.dir)
	for i in refs.size():
		var g := stairs.grid_for(refs[i])
		if g == null:
			continue
		var theirs := {}
		for c in g.cells(refs[i].position_of(other.oter), Stairs.LANDING if dz > 0 else Stairs.UP):
			theirs[ChunkOverlay.rotate(c, turns, Vector2i(OMT_CELLS, OMT_CELLS))] = true
		var name := other.oter
		if refs.size() > 1:
			name += " (mapgen %d of %d, weight %d)" % [i + 1, refs.size(), refs[i].weight]
		if theirs.is_empty():
			out.append([Severity.WARNING, "%s: %s, %s, has no stairs %s anywhere in the tile; BN drops the player at the same x,y" % [
					what, name, level, "down" if dz > 0 else "up"], Code.STAIRS, [refs[i]]])
		elif not mine.any(func(c: Vector2i) -> bool: return theirs.has(c)):
			var near: Vector2i = theirs.keys()[0]
			for c: Vector2i in theirs:
				if _dist(c, mine[0]) < _dist(near, mine[0]):
					near = c
			out.append([Severity.NOTE, "%s: %s, %s, has its stairs %s elsewhere, e.g. over (%d, %d); BN takes the player to the nearest" % [
					what, name, level, "down" if dz > 0 else "up", offset.x + near.x, offset.y + near.y], Code.STAIRS_OFFSET, [refs[i]]])
	return out


## Each elevator control's floors (see Stairs.elevator_levels), in every
## building placing the map: no other level has an ELEVATOR cell within
## reach of the control's cell, a WARNING (only this floor is offered); a
## level whose mapgen has its elevator farther off, a NOTE (BN leaves that
## floor out); a control with no ELEVATOR cell next to it, a NOTE (the
## player can't stand in the car to ride it). Controls with the same
## findings are one finding. A console with elevator_on at a level of the
## building without any t_elevator_control_off, a NOTE: it switches on
## those of the whole z-level, so other buildings nearby may have some.
func _check_elevators(ref: DataIndex.MapgenRef, grid: Stairs.Grid, stairs: Stairs, resolved: ResolvedMapgen,
		placements: Array[Placement]) -> void:
	var seen := {}
	var places := BuildingLevels.places(index, ref)
	for place in places:
		for id in ref.ids:
			var at := ref.position_of(id)
			var bt := place.building.at(place.origin + Vector3i(at.x, at.y, 0))
			if bt == null or bt.oter != id:
				continue
			var controls := grid.cells(at, Stairs.CONTROL)
			## text -> [severity, code, cells, mapgens]
			var by_text := {}
			for c in controls:
				for pair in _elevator_findings(grid, at, c, bt, place, stairs):
					if not by_text.has(pair[1]):
						by_text[pair[1]] = [pair[0], pair[2], [] as Array[Vector2i], pair[3]]
					by_text[pair[1]][2].append(c)
			for text: String in by_text:
				var cells: Array[Vector2i] = by_text[text][2]
				var what := "elevator controls at %s%s" % [_cells_text(cells, at * OMT_CELLS),
						" (tile %s)" % id if ref.ids.size() > 1 else ""]
				_add_at_place(seen, place, [by_text[text][0], "%s: %s" % [what, text], by_text[text][1],
						by_text[text][3]], at * OMT_CELLS + cells[0])
	_name_places(seen)
	if places.is_empty():
		return
	var consoles := console_cells(resolved, placements)
	for at: Vector2i in consoles:
		if not Computer.of(consoles[at][1]).door_actions().has("elevator_on"):
			continue
		for place in places:
			if _level_has(place, stairs, Stairs.CONTROL_OFF):
				continue
			if consoles[at][0]:
				_to(Target.CELL, consoles[at][0])
				_cell_target(at)
			else:
				_to(Target.PLACEMENT, "", "place_computers", consoles[at][3])
			_add(Severity.NOTE, Code.ELEVATOR_ON, "console at (%d, %d): \"elevator_on\" switches on every %s on the z-level, and %s has none at z %d (other buildings nearby may)" % [
					at.x, at.y, Stairs.CONTROL_OFF_ID, place.building.id, place.origin.z])
			break


## [severity, text, code, mapgens] for the elevator control at tile-local cell
## [param c] of tile [param at] (building tile [param bt]).
func _elevator_findings(grid: Stairs.Grid, at: Vector2i, c: Vector2i, bt: DataIndex.BuildingTile,
		place: BuildingLevels.Place, stairs: Stairs) -> Array:
	var out := []
	var o := at * OMT_CELLS
	# The car is the ELEVATOR cells around the player, next to the control
	# (in this map; one on the map's edge may have it in the next map).
	var p := o + c
	var car := p.x == 0 or p.y == 0 or p.x == grid.size.x - 1 or p.y == grid.size.y - 1
	for y in range(maxi(0, p.y - 1), mini(grid.size.y, p.y + 2)):
		for x in range(maxi(0, p.x - 1), mini(grid.size.x, p.x + 2)):
			if grid.at(Vector2i(x, y)) & Stairs.ELEVATOR:
				car = true
	if not car:
		out.append([Severity.NOTE, "no elevator floor (ELEVATOR terrain) next to them, so the player can't stand in the car to ride it", Code.ELEVATOR_OFFSET, []])
	var levels := stairs.elevator_levels(place.building, bt, c)
	var reached := levels.keys().filter(func(z: int) -> bool: return not levels[z].near.is_empty())
	if reached.is_empty():
		var others := Array(place.building.levels()).filter(func(z: int) -> bool: return z != bt.point.z)
		var refs := []
		for z: int in others:
			var t := place.building.at(Vector3i(bt.point.x, bt.point.y, z))
			if t:
				refs.append_array(BuildingLevels.mapgens(index, t.oter).filter(
						func(x: DataIndex.MapgenRef) -> bool: return not x.disabled))
		out.append([Severity.WARNING, "no other level of %s (%s) has elevator floor (ELEVATOR terrain) within %d cells of the same spot in its tile, so only this floor is offered" % [
				place.building.id, "z " + ", ".join(others.map(str)) if not others.is_empty() else "it has one level",
				Stairs.ELEVATOR_REACH], Code.ELEVATOR, refs])
	for z: int in levels:
		for f: Array in levels[z].far:
			var r: DataIndex.MapgenRef = f[0]
			var other := place.building.at(Vector3i(bt.point.x, bt.point.y, z))
			var enabled := BuildingLevels.mapgens(index, other.oter).filter(func(x: DataIndex.MapgenRef) -> bool: return not x.disabled)
			var name := other.oter
			if enabled.size() > 1:
				name += " (mapgen %d of %d, weight %d)" % [enabled.find(r) + 1, enabled.size(), r.weight]
			out.append([Severity.NOTE, "%s (z %d) has its elevator floor farther than %d cells off, e.g. at (%d, %d); BN doesn't offer that floor" % [
					name, z, Stairs.ELEVATOR_REACH, o.x + f[1].x, o.y + f[1].y], Code.ELEVATOR_OFFSET, [r]])
	return out


## True when some enabled mapgen of a tile of [param place]'s level may
## put down a cell with [param bit].
func _level_has(place: BuildingLevels.Place, stairs: Stairs, bit: int) -> bool:
	for t in place.building.level(place.origin.z):
		for r in BuildingLevels.mapgens(index, t.oter):
			if r.disabled:
				continue
			var g := stairs.grid_for(r)
			if g and not g.cells(r.position_of(t.oter), bit).is_empty():
				return true
	return false


static func _turns(dir: String) -> int:
	return maxi(0, DataIndex.DIRECTIONS.find(dir))


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## "(3, 4)" or "(3, 4) and 2 more cells": [param cells] moved by
## [param offset].
static func _cells_text(cells: Array[Vector2i], offset: Vector2i) -> String:
	var t := "(%d, %d)" % [offset.x + cells[0].x, offset.y + cells[0].y]
	if cells.size() > 1:
		t += " and %d more cell%s" % [cells.size() - 1, "" if cells.size() == 2 else "s"]
	return t


# --- Adding findings -----------------------------------------------------------

func _to(target: Target, key := "", member := "", i := -1) -> void:
	_target = target
	_key = key
	_member = member
	_index = i
	_cell = -Vector2i.ONE


func _cell_target(c: Vector2i) -> void:
	_cell = c


## Findings about chunk stamp [param s] (depth 0) point at its entry, or
## at its cell for a "nested" mapping.
func _to_stamp(s: ChunkOverlay.Stamp) -> void:
	if s.member == "place_nested":
		_to(Target.PLACEMENT, "", "place_nested", s.index)
	else:
		_to(Target.CELL, s.key)
		_cell_target(s.anchor.position)


func _error(load_fails: bool, code: Code, text: String) -> void:
	_add(Severity.ERROR, code, text).load_fails = load_fails


func _add(severity: Severity, code: Code, text: String) -> Finding:
	var f := Finding.new()
	f.severity = severity
	f.code = code
	f.text = text
	f.target = _target
	f.key = _key
	f.member = _member
	f.index = _index
	f.cell = _cell
	f.palette = _palette
	findings.append(f)
	return f

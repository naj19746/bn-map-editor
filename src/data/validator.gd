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
	DOOR_ELSEWHERE, OTHER_LOCKED, SHARED_DOOR,
}

const NOT_CHECKED := "Not checked yet: sign and graffiti snippets, zone types and factions, mapgen " \
		+ "flags, parameter scopes and types, the PLANT rule for furniture outside sealed_item, " \
		+ "paint on NO_PAINT terrain, joins; computers inside nested chunks (judged only in the chunk " \
		+ "itself, not where it's placed), doors from \"set\"/place_terrain."

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
				if code in [Code.NO_OPTIONS, Code.NO_STAND, Code.NO_DOOR]:
					return "it does nothing in game"
				return "BN silently skips it"
		return "works, but oddly"

	## One line: "error: <text> (BN won't load this map)".
	func describe() -> String:
		var where := "palette %s: " % palette if palette and target == Target.PALETTE_KEY else ""
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


## Every finding for map [param mapgen] (a whole mapgen object) of
## [param ref], resolved as [param resolved], with [param placements] and
## its chunk [param overlay] (null to skip the chunk checks). Palettes it
## uses are left to validate_palette().
static func validate_map(p_index: DataIndex, ref: DataIndex.MapgenRef, mapgen: Dictionary,
		resolved: ResolvedMapgen, placements: Array[Placement], overlay: ChunkOverlay) -> Array[Finding]:
	var v := Validator.new()
	v.index = p_index
	v._check_map(ref, mapgen, resolved, placements, overlay)
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
	if not chunk:
		_check_consoles(obj, resolved, placements, overlay)
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
		if top.member == "place_nested":
			_to(Target.PLACEMENT, "", "place_nested", top.index)
		else:
			_to(Target.CELL, top.key)
			_cell_target(top.anchor.position)
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
## a note.
func _check_consoles(obj: Dictionary, resolved: ResolvedMapgen, placements: Array[Placement],
		overlay: ChunkOverlay) -> void:
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
			var text := "%s: \"%s\" changes nothing: no %s within %d of where the player stands, in the same overmap tile" % [
				where, action, " or ".join(e[0]), e[2]]
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


## [param grids] are tile_grids() of a map of [param size] cells.
static func console_reach(p_index: DataIndex, size: Vector2i, grids: Array[PackedStringArray],
		at: Vector2i, data: Dictionary) -> Reach:
	var r := Reach.new()
	var w := size.x
	var terrain := grids[0]
	var furniture := grids[1]
	r.stands = Computer.stand_cells(at, size, func(c: Vector2i) -> bool:
		return p_index.passable(terrain[c.y * w + c.x], furniture[c.y * w + c.x]))
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


## " in the loaded mods" when mods other than core are loaded: an id from a
## mod that isn't loaded is unknown here.
func _mods_note() -> String:
	return " in the loaded mods" if index.mods.size() > 1 else ""


# --- Adding findings -----------------------------------------------------------

func _to(target: Target, key := "", member := "", i := -1) -> void:
	_target = target
	_key = key
	_member = member
	_index = i
	_cell = -Vector2i.ONE


func _cell_target(c: Vector2i) -> void:
	_cell = c


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

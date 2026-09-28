class_name Placement
extends RefCounted
## One entry of a mapgen's coordinate placement lists ("place_items", "set",
## ...), read the way BN reads it (mapgen.cpp: jmapgen_objects::load_objects,
## common_check_bounds, setup_setmap).
##
## x/y are an int, [n] or [first, second]. BN anchors an entry at its FIRST
## values: in a multi-tile map the entry belongs to the overmap tile (OMT)
## holding (first x, first y), and is dropped without an error when that is
## outside the map. Only the second values are checked against that tile's
## far edge (a load error), so a reversed range such as [31, 16] passes and,
## since rng() swaps its bounds, reaches back into the previous tile.
## "set" entries never get the tile offset: each runs in every tile of the
## building, and one with a coordinate past 23 runs in none. A nested
## chunk's place_* entries are bounded by 24x24, not its mapgensize (only
## "set" uses mapgensize).
##
## [member entry] is the live JSON object; edits go through MapDocument.

enum Layer { ITEMS, MONSTERS, VEHICLES, NESTED, OTHER }
## How "chance" reads for a kind.
enum Chance { NONE, PERCENT, ONE_IN }
## Where BN puts the entry. SPANS_BACK and OUTSIDE_CHUNK still load.
enum Status {
	OK,
	## Anchored outside the map (or, for "set", a coordinate past the tile):
	## BN drops it without a word.
	DROPPED,
	## A second value leaves the anchor's tile: BN refuses to load the map.
	CROSSES,
	## A reversed range reaches back into the previous tile (or before 0).
	SPANS_BACK,
	## A nested chunk's entry reaches past the chunk's mapgensize.
	OUTSIDE_CHUNK,
}

## What kind of problem an entry of [member issues] is (the status ones
## match [member status]).
enum Issue {
	DROPPED, CROSSES, SPANS_BACK, OUTSIDE_CHUNK,
	## x/y (or x2/y2, chance, ...) aren't ints or ranges: a JSON error in BN.
	MALFORMED,
	## place_items chance outside 1-100: BN places nothing.
	ITEMS_CHANCE,
	## place_loot needs exactly one of group and item.
	LOOT_GROUP_ITEM,
	## place_monster has neither monster nor group.
	NO_MONSTER,
}

const OMT := 24
const LAYER_NAMES := ["Items", "Monsters", "Vehicles", "Nested", "Other"]

## member -> [layer, short label, the members naming what it places, how
## "chance" reads, the default chance]. Every coordinate list BN reads
## (mapgen_function_json_base::setup_common), "add" being the old name of
## "place_item".
const KINDS := {
	"place_items": [Layer.ITEMS, "I", ["item"], Chance.PERCENT, 1],
	"place_item": [Layer.ITEMS, "i", ["item"], Chance.PERCENT, 100],
	"add": [Layer.ITEMS, "i", ["item"], Chance.PERCENT, 100],
	"place_loot": [Layer.ITEMS, "L", ["group", "item"], Chance.PERCENT, 100],
	"place_artifact": [Layer.ITEMS, "A", [], Chance.PERCENT, 100],
	"place_liquids": [Layer.ITEMS, "liquid", ["liquid"], Chance.ONE_IN, 1],
	"place_monster": [Layer.MONSTERS, "m", ["monster", "group"], Chance.PERCENT, 100],
	"place_monsters": [Layer.MONSTERS, "M", ["monster"], Chance.ONE_IN, 1],
	"place_vehicles": [Layer.VEHICLES, "V", ["vehicle"], Chance.PERCENT, 1],
	"place_nested": [Layer.NESTED, "N", ["chunks"], Chance.NONE, 0],
	"set": [Layer.OTHER, "set", ["id"], Chance.ONE_IN, 1],
	"place_terrain": [Layer.OTHER, "ter", ["ter"], Chance.NONE, 0],
	"place_furniture": [Layer.OTHER, "furn", ["furn"], Chance.NONE, 0],
	"place_traps": [Layer.OTHER, "trap", ["trap"], Chance.NONE, 0],
	"place_fields": [Layer.OTHER, "field", ["field"], Chance.NONE, 0],
	"place_signs": [Layer.OTHER, "sign", ["signage", "snippet"], Chance.NONE, 0],
	"place_graffiti": [Layer.OTHER, "graffiti", ["text", "snippet"], Chance.NONE, 0],
	"place_npcs": [Layer.OTHER, "npc", ["class"], Chance.NONE, 0],
	"place_toilets": [Layer.OTHER, "toilet", [], Chance.NONE, 0],
	"place_gaspumps": [Layer.OTHER, "gas", ["fuel"], Chance.NONE, 0],
	"place_vendingmachines": [Layer.OTHER, "vend", ["item_group"], Chance.NONE, 0],
	"place_rubble": [Layer.OTHER, "rubble", ["rubble_type"], Chance.NONE, 0],
	"place_computers": [Layer.OTHER, "computer", ["name"], Chance.NONE, 0],
	"place_zones": [Layer.OTHER, "zone", ["type"], Chance.NONE, 0],
	"place_ter_furn_transforms": [Layer.OTHER, "transform", ["transform"], Chance.NONE, 0],
	"place_remove_all": [Layer.OTHER, "remove", [], Chance.NONE, 0],
	"faction_owner": [Layer.OTHER, "owner", ["id"], Chance.NONE, 0],
	"translate_ter": [Layer.OTHER, "translate", ["from"], Chance.NONE, 0],
}

## The fields each kind reads (after x/y), as [key, type, help]. Types:
## "id" (a string, or any mapgen value written as JSON), "range" (int or
## [min, max]), "int", "float", "bool", "text", "json". The order is also
## where a newly set field goes.
const FIELDS := {
	"place_items": [
		["item", "id", "item group (or an item id)"],
		["chance", "range", "% per placement, default 1; must be 1-100 or nothing is placed"],
		["repeat", "range", "times to roll, default 1"],
	],
	"place_item": [
		["item", "id", "item id"],
		["amount", "range", "count per spawn, default 1"],
		["chance", "range", "%, default 100 (exactly one); otherwise an expected count in %, scaled by the item spawn rate"],
		["repeat", "range", "times to roll, default 1"],
		["active", "bool", "activate the item, default false"],
	],
	"place_loot": [
		["group", "id", "item group (give group OR item)"],
		["item", "id", "item id (give group OR item)"],
		["chance", "int", "%, default 100, a plain int; scaled by the item spawn rate unless 100"],
		["ammo", "int", "% chance of ammo, default 0"],
		["magazine", "int", "% chance of a magazine, default 0"],
		["repeat", "range", "times to roll, default 1"],
	],
	"place_monster": [
		["monster", "id", "monster id, or a weighted list [[id, weight], ...] (give monster OR group)"],
		["group", "id", "monster group: one pick from it"],
		["chance", "range", "%, default 100, scaled by spawn density (capped)"],
		["repeat", "range", "times to roll, default 1"],
		["pack_size", "range", "monsters per success, default 1"],
		["one_or_none", "bool", "at most one per roll; default true only without repeat and pack_size"],
		["friendly", "bool", "default false"],
		["name", "text", "the monster's name"],
		["target", "bool", "mission target, default false"],
		["use_pack_size", "bool", "use the group's pack size, default false"],
	],
	"place_monsters": [
		["monster", "id", "monster group"],
		["chance", "range", "one in N, default 1"],
		["density", "float", "default: the map's monster density"],
		["repeat", "range", "times to roll, default 1"],
		["target", "bool", "mission target, default false"],
	],
	"place_vehicles": [
		["vehicle", "id", "vehicle group (every vehicle prototype is also a group)"],
		["chance", "range", "%, DEFAULT 1, scaled by the vehicle spawn rate unless 100"],
		["rotation", "json", "degrees: an int, or a list to pick one from"],
		["fuel", "int", "% fuel, default -1 (random)"],
		["status", "int", "-1 light damage (default), 0 undamaged, 1 disabled"],
		["locked", "bool", "doors locked"],
		["place_beyond_bounds", "bool", "may stick out of the map, default false"],
		["repeat", "range", "times to roll, default 1"],
	],
	"place_nested": [
		["chunks", "json", "nested chunk ids or [id, weight] pairs"],
		["else_chunks", "json", "used when neighbors/joins don't match"],
		["neighbors", "json", "conditions on neighbouring overmap terrain"],
		["joins", "json", "conditions on joins"],
		["rotation", "json", "turns the chunk"],
		["repeat", "range", "times to place, default 1"],
	],
	"place_computers": [
		["name", "text", "the console's title"],
		["access_denied", "text", "shown when logging in fails; default: BN's message"],
		["security", "int", "hack difficulty, default 0 (no hack)"],
		["target", "bool", "the mission target, default false"],
		["options", "json", "[{name, action, security}]"],
		["failures", "json", "[{action}]: one fires when a hack fails"],
	],
	"set": [
		["point", "text", "terrain, furniture, trap, radiation or bash (one cell)"],
		["line", "text", "terrain, furniture, trap, radiation or bash (x,y to x2,y2)"],
		["square", "text", "terrain, furniture, trap, radiation or bash (x,y to x2,y2)"],
		["id", "id", "the terrain, furniture or trap id"],
		["x2", "range", "far end (line/square)"],
		["y2", "range", "far end (line/square)"],
		["amount", "range", "radiation amount"],
		["chance", "int", "one in N, default 1"],
		["repeat", "range", "times to apply, default 1"],
	],
}

## Mapping kinds (a symbol's extras) by layer; the others count as OTHER.
const MAPPING_LAYERS := {
	"items": Layer.ITEMS, "item": Layer.ITEMS, "sealed_item": Layer.ITEMS, "liquids": Layer.ITEMS,
	"artifact": Layer.ITEMS, "artifacts": Layer.ITEMS,
	"monsters": Layer.MONSTERS, "monster": Layer.MONSTERS,
	"vehicles": Layer.VEHICLES,
	"nested": Layer.NESTED,
}


## A jmapgen_int as written: an int, [n] or [first, second].
class IntRange:
	enum Form { MISSING, INT, ONE, PAIR, INVALID }

	var first := 0
	var second := 0
	var form := Form.MISSING

	## [param one_means_both]: [n] is n..n (x, y) rather than n..default
	## (repeat, chance, amount, pack_size: jmapgen_int with defaults).
	static func parse(v: Variant, default_first := 0, default_second := 0, one_means_both := true) -> IntRange:
		var r := IntRange.new()
		r.first = default_first
		r.second = default_second
		if v == null:
			return r
		if IntRange._is_int(v):
			r.form = Form.INT
			r.first = int(v)
			r.second = r.first
		elif v is Array and (v.size() == 1 or v.size() == 2) and IntRange._is_int(v[0]) and IntRange._is_int(v[-1]):
			r.form = Form.ONE if v.size() == 1 else Form.PAIR
			r.first = int(v[0])
			r.second = int(v[1]) if v.size() == 2 else (r.first if one_means_both else default_second)
		else:
			r.form = Form.INVALID
		return r

	## An int, or a float holding one (data read with Godot's JSON).
	static func _is_int(v: Variant) -> bool:
		return v is int or (v is float and v == floorf(v))

	func valid() -> bool:
		return form != Form.INVALID

	func lo() -> int:
		return mini(first, second)

	func hi() -> int:
		return maxi(first, second)

	func reversed() -> bool:
		return second < first

	## The value in the form it was written (null when missing or invalid).
	func to_json() -> Variant:
		match form:
			Form.INT: return first
			Form.ONE: return [first]
			Form.PAIR: return [first, second]
		return null

	func shifted(d: int) -> IntRange:
		var r := IntRange.new()
		r.form = form
		r.first = first + d
		r.second = second + d
		return r

	## [param lo]..[param hi] written like this one: one cell stays an int or
	## [n] if it was one, and a reversed range stays reversed.
	func spanning(p_lo: int, p_hi: int) -> IntRange:
		var r := IntRange.new()
		if p_lo == p_hi and (form == Form.INT or form == Form.ONE):
			r.form = form
			r.first = p_lo
			r.second = p_lo
			return r
		r.form = Form.PAIR
		r.first = p_hi if reversed() else p_lo
		r.second = p_lo if reversed() else p_hi
		return r

	## "3", or "1-3" for a range ("3-1" when reversed).
	func text() -> String:
		return str(first) if first == second else "%d-%d" % [first, second]


## Where a map's placements can go: its size in cells and whether it's a
## chunk (nested_mapgen_id / update_mapgen_id).
class Geometry:
	var size := Vector2i(OMT, OMT)
	var chunk := false

	static func of(mapgen: Dictionary, p_size: Vector2i) -> Geometry:
		var g := Geometry.new()
		g.size = p_size
		g.chunk = mapgen.has("nested_mapgen_id") or mapgen.has("update_mapgen_id")
		return g

	## Overmap tiles across and down (1x1 for a chunk).
	func omts() -> Vector2i:
		return Vector2i.ONE if chunk else Vector2i(maxi(1, size.x / Placement.OMT), maxi(1, size.y / Placement.OMT))

	## The cells a placement anchored at [param cell] must stay in: its
	## tile, or the chunk.
	func tile_of(cell: Vector2i) -> Rect2i:
		if chunk:
			return Rect2i(Vector2i.ZERO, size)
		var t := (cell / Placement.OMT).clamp(Vector2i.ZERO, omts() - Vector2i.ONE)
		return Rect2i(t * Placement.OMT, Vector2i(Placement.OMT, Placement.OMT))


var member := ""
## Position in the member's list.
var index := 0
var entry: Dictionary
var x: IntRange
var y: IntRange
## The far corner of a "set" line/square, else null.
var x2: IntRange
var y2: IntRange
var status := Status.OK
## The OMT owning the entry, (-1, -1) when dropped. Always (0, 0) for "set".
var anchor_omt := -Vector2i.ONE
var problems := PackedStringArray()
## [member problems] again, as [Issue, text].
var issues: Array = []
var geometry: Geometry


## Every placement entry of [param mapgen] (a whole mapgen object), in
## member order, for a map of [param size] cells.
static func read_all(mapgen: Dictionary, size: Vector2i) -> Array[Placement]:
	var out: Array[Placement] = []
	var obj: Variant = mapgen.get("object")
	if not obj is Dictionary:
		return out
	var g := Geometry.of(mapgen, size)
	for m: String in obj:
		if not KINDS.has(m) or not obj[m] is Array:
			continue
		var list: Array = obj[m]
		for i in list.size():
			if list[i] is Dictionary:
				out.append(read(m, i, list[i], g))
	return out


static func read(p_member: String, i: int, p_entry: Dictionary, g: Geometry) -> Placement:
	var p := Placement.new()
	p.member = p_member
	p.index = i
	p.entry = p_entry
	p.geometry = g
	p.x = IntRange.parse(p_entry.get("x"))
	p.y = IntRange.parse(p_entry.get("y"))
	if p_member == "set" and (p_entry.has("line") or p_entry.has("square")):
		p.x2 = IntRange.parse(p_entry.get("x2"))
		p.y2 = IntRange.parse(p_entry.get("y2"))
	p._classify()
	p._check_fields()
	return p


func layer() -> Layer:
	return KINDS[member][0]


func chance_kind() -> Chance:
	return KINDS[member][3]


## "place_items #3".
func title() -> String:
	return "%s #%d" % [member, index + 1]


## True for a "set" entry, whose coordinates are local to each tile.
func is_set() -> bool:
	return member == "set"


## The cells BN can use, min..max whatever order the ranges are written in
## (for "set", in tile coordinates; a line/square includes x2/y2).
func span() -> Rect2i:
	var lo := Vector2i(x.lo(), y.lo())
	var hi := Vector2i(x.hi(), y.hi())
	if x2 != null:
		lo = lo.min(Vector2i(x2.lo(), y2.lo()))
		hi = hi.max(Vector2i(x2.hi(), y2.hi()))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Where to draw it, in map cells: the span, repeated in every tile for a
## "set" entry that runs (a dropped one is drawn where it's written).
func instances() -> Array[Rect2i]:
	var r := span()
	var out: Array[Rect2i] = []
	if not is_set() or status == Status.DROPPED or geometry.chunk:
		out.append(r)
		return out
	var omts := geometry.omts()
	for ty in omts.y:
		for tx in omts.x:
			out.append(Rect2i(r.position + Vector2i(tx, ty) * OMT, r.size))
	return out


## What it places, e.g. "GROUP_ZOMBIE" or "square terrain t_floor".
func what() -> String:
	var parts := PackedStringArray()
	if is_set():
		for op in ["point", "line", "square"]:
			if entry.has(op):
				parts.append("%s %s" % [op, str(entry[op])])
	for key: String in KINDS[member][2]:
		if entry.has(key):
			var v: Variant = entry[key]
			parts.append(v if v is String else JSON.stringify(v))
	return " ".join(parts)


## The canvas label, e.g. "I 50%", "M 1/10", "V 1% x2-3".
func label() -> String:
	var parts := PackedStringArray([KINDS[member][1]])
	var c := chance_text()
	if c:
		parts.append(c)
	if entry.has("repeat"):
		parts.append("x" + IntRange.parse(entry.repeat, 1, 1, false).text())
	return " ".join(parts)


## The chance as it reads for this kind ("50%", "1/10"), default included;
## "" for kinds without one.
func chance_text() -> String:
	var kind: Chance = KINDS[member][3]
	if kind == Chance.NONE:
		return ""
	var def: int = KINDS[member][4]
	var c := IntRange.parse(entry.get("chance"), def, def, false)
	if not c.valid():
		return "chance?"
	var lo_hi := str(c.first) if c.first == c.second else "%d-%d" % [c.lo(), c.hi()]
	return lo_hi + "%" if kind == Chance.PERCENT else "1/" + lo_hi


## A position change BN would refuse or drop, or "" (SPANS_BACK and
## OUTSIDE_CHUNK entries still load; editing never creates them).
func blocking_problem() -> String:
	if status == Status.CROSSES or status == Status.DROPPED:
		return problems[0]
	return ""


func _classify() -> void:
	if not x.valid() or not y.valid() or x.form == IntRange.Form.MISSING or y.form == IntRange.Form.MISSING:
		status = Status.CROSSES
		_issue(Issue.MALFORMED, "%s: x and y must each be an int or [min, max]" % title())
		return
	if is_set():
		_classify_set()
		return
	# Chunks: 24x24 regardless of mapgensize (jmapgen_objects keeps the
	# default size). Maps: the tile holding the first values.
	var total := Vector2i(OMT, OMT) if geometry.chunk else geometry.omts() * OMT
	var first := Vector2i(x.first, y.first)
	if first.x < 0 or first.y < 0 or first.x >= total.x or first.y >= total.y:
		status = Status.DROPPED
		_issue(Issue.DROPPED, "%s is anchored at (%d, %d), outside the map, so BN drops it" % [title(), first.x, first.y])
		return
	anchor_omt = first / OMT
	var local_second := Vector2i(x.second, y.second) - anchor_omt * OMT
	if local_second.x > OMT - 1 or local_second.y > OMT - 1:
		status = Status.CROSSES
		_issue(Issue.CROSSES, "%s: its range leaves overmap tile (%d, %d); BN refuses to load the map (\"coordinate range cannot cross grid boundaries\")" % [
			title(), anchor_omt.x, anchor_omt.y])
	elif local_second.x < 0 or local_second.y < 0:
		status = Status.SPANS_BACK
		_issue(Issue.SPANS_BACK, "%s: its reversed range reaches back out of overmap tile (%d, %d) (BN uses %d-%d, %d-%d)" % [
			title(), anchor_omt.x, anchor_omt.y, x.lo(), x.hi(), y.lo(), y.hi()])
	elif geometry.chunk and (x.hi() >= geometry.size.x or y.hi() >= geometry.size.y):
		status = Status.OUTSIDE_CHUNK
		_issue(Issue.OUTSIDE_CHUNK, "%s reaches past the chunk's mapgensize %dx%d (BN allows up to 24x24)" % [
			title(), geometry.size.x, geometry.size.y])


## "set" never gets the tile offset and is checked against mapgensize (24x24
## for a map). A first value outside it drops the entry; a second one past
## it is a load error.
func _classify_set() -> void:
	var bound := geometry.size if geometry.chunk else Vector2i(OMT, OMT)
	var pairs: Array = [[x, y]]
	if x2 != null:
		if not x2.valid() or not y2.valid() or x2.form == IntRange.Form.MISSING or y2.form == IntRange.Form.MISSING:
			status = Status.CROSSES
			_issue(Issue.MALFORMED, "%s: a line or square needs x2 and y2" % title())
			return
		pairs.append([x2, y2])
	for pair: Array in pairs:
		var rx: IntRange = pair[0]
		var ry: IntRange = pair[1]
		if rx.first < 0 or ry.first < 0 or rx.first >= bound.x or ry.first >= bound.y:
			status = Status.DROPPED
			var why := "outside the map" if geometry.chunk or geometry.omts() == Vector2i.ONE \
					else "past the tile: \"set\" runs in every tile without the tile offset, so it runs in none"
			_issue(Issue.DROPPED, "%s is at (%d, %d), %s; BN drops it" % [title(), rx.first, ry.first, why])
			return
	for pair: Array in pairs:
		if pair[0].second > bound.x - 1 or pair[1].second > bound.y - 1:
			status = Status.CROSSES
			_issue(Issue.CROSSES, "%s: its range leaves the %dx%d area; BN refuses to load the map" % [title(), bound.x, bound.y])
			return
	anchor_omt = Vector2i.ZERO


func _issue(code: Issue, text: String) -> void:
	problems.append(text)
	issues.append([code, text])


## Field checks BN makes when loading or placing (not id lookups).
func _check_fields() -> void:
	match member:
		"place_items":
			var c := IntRange.parse(entry.get("chance"), 1, 1, false)
			if c.valid() and (c.lo() < 1 or c.hi() > 100):
				_issue(Issue.ITEMS_CHANCE, "%s: chance %s is outside 1-100, so BN places nothing" % [title(), c.text()])
		"place_loot":
			if entry.has("group") == entry.has("item"):
				_issue(Issue.LOOT_GROUP_ITEM, "%s: needs exactly one of \"group\" and \"item\"" % title())
			if entry.has("chance") and not IntRange._is_int(entry.chance):
				_issue(Issue.MALFORMED, "%s: chance must be a plain int" % title())
		"place_monster":
			if not entry.has("group") and not entry.has("monster"):
				_issue(Issue.NO_MONSTER, "%s: needs \"monster\" or \"group\"" % title())
	var kind: Chance = KINDS[member][3]
	if kind != Chance.NONE and entry.has("chance") and not IntRange.parse(entry.chance).valid():
		_issue(Issue.MALFORMED, "%s: chance must be an int or [min, max]" % title())


## The field list for [param p_member]: x, y, then FIELDS (or the kind's id
## members for kinds without a list).
static func field_specs(p_member: String) -> Array:
	var out: Array = [["x", "xy", "column: an int or [first, second]; the first value anchors it"],
			["y", "xy", "row: an int or [first, second]; the first value anchors it"]]
	if FIELDS.has(p_member):
		out.append_array(FIELDS[p_member])
	elif KINDS.has(p_member):
		for key: String in KINDS[p_member][2]:
			out.append([key, "id", ""])
		out.append(["repeat", "range", "times to place, default 1"])
	return out


## The order fields are written in, for inserting a new one: the kind's id
## members, then x/y, then the rest.
static func field_order(p_member: String) -> Array:
	var order: Array = []
	if KINDS.has(p_member):
		order.append_array(KINDS[p_member][2])
	if p_member == "set":
		order = ["point", "line", "square", "id"]
	order.append_array(["x", "y", "x2", "y2"])
	for spec: Array in field_specs(p_member):
		if not order.has(spec[0]):
			order.append(spec[0])
	return order


## A new entry for [param p_member] at [param rect] (map cells), with the
## fields it can't do without left empty to fill in.
static func template(p_member: String, rect: Rect2i) -> Dictionary:
	var fields := {}
	match p_member:
		"place_items": fields = {"item": "", "chance": 100}
		"place_loot": fields = {"group": ""}
		"place_monster": fields = {"monster": ""}
		"place_vehicles": fields = {"vehicle": "", "chance": 100, "rotation": 0}
		"place_nested": fields = {"chunks": []}
		"place_computers": fields = Computer.preset("door")
		_:
			if KINDS.has(p_member) and not KINDS[p_member][2].is_empty():
				fields[KINDS[p_member][2][0]] = ""
	# What it places first, then x/y, then the rest (as BN's files do).
	var e := {}
	for key: String in fields:
		if KINDS[p_member][2].has(key):
			e[key] = fields[key]
	e["x"] = rect.position.x if rect.size.x == 1 else [rect.position.x, rect.end.x - 1]
	e["y"] = rect.position.y if rect.size.y == 1 else [rect.position.y, rect.end.y - 1]
	for key: String in fields:
		if not e.has(key):
			e[key] = fields[key]
	return e


## Kinds the Add button offers.
const ADDABLE := ["place_items", "place_item", "place_loot", "place_monster", "place_monsters",
	"place_vehicles", "place_nested", "place_signs", "place_npcs", "place_terrain", "place_furniture",
	"place_traps", "place_fields", "place_liquids", "place_toilets", "place_vendingmachines",
	"place_rubble", "place_graffiti", "place_computers", "faction_owner"]


## A bitmask of Layer bits for what the symbol's own mappings place
## (items, monsters, ...), for marking its cells.
static func mapping_layers(info: ResolvedMapgen.SymbolInfo) -> int:
	var mask := 0
	if info == null:
		return mask
	for kind: String in info.extras:
		mask |= 1 << MAPPING_LAYERS.get(kind, Layer.OTHER)
	return mask


## The x/y (and x2/y2) values that put this entry at [param rect] (map
## cells, as returned by instances()), keeping how each value is written. For
## "set", [param instance] is which instance was moved.
func values_for(rect: Rect2i, moved_only := false, instance := 0) -> Dictionary:
	var offset := Vector2i.ZERO
	if is_set() and status != Status.DROPPED and not geometry.chunk:
		var omts := geometry.omts()
		offset = Vector2i(instance % omts.x, instance / omts.x) * OMT
	var r := Rect2i(rect.position - offset, rect.size)
	var out := {}
	if x2 == null:
		out["x"] = x.spanning(r.position.x, r.end.x - 1).to_json()
		out["y"] = y.spanning(r.position.y, r.end.y - 1).to_json()
		return out
	# A line/square: moving shifts every value; resizing sets the far corner.
	var s := span()
	var d := r.position - s.position
	if moved_only:
		out["x"] = x.shifted(d.x).to_json()
		out["y"] = y.shifted(d.y).to_json()
		out["x2"] = x2.shifted(d.x).to_json()
		out["y2"] = y2.shifted(d.y).to_json()
	else:
		out["x"] = x.spanning(r.position.x, r.position.x).to_json()
		out["y"] = y.spanning(r.position.y, r.position.y).to_json()
		out["x2"] = x2.spanning(r.end.x - 1, r.end.x - 1).to_json()
		out["y2"] = y2.spanning(r.end.y - 1, r.end.y - 1).to_json()
	return out


## [param rect] moved (not resized) so it sits inside one tile (or the
## chunk), the tile holding its top-left corner, clamped to the map.
static func clamp_move(rect: Rect2i, g: Geometry) -> Rect2i:
	var tile := g.tile_of(rect.position.clamp(Vector2i.ZERO, g.size - Vector2i.ONE))
	var size := rect.size.min(tile.size)
	var pos := rect.position.clamp(tile.position, tile.end - size)
	return Rect2i(pos, size)


## The rect from [param anchor] to [param corner] (either order), cut to
## [param anchor]'s tile.
static func clamp_span(anchor: Vector2i, corner: Vector2i, g: Geometry) -> Rect2i:
	var tile := g.tile_of(anchor)
	var a := anchor.clamp(tile.position, tile.end - Vector2i.ONE)
	var c := corner.clamp(tile.position, tile.end - Vector2i.ONE)
	var lo := a.min(c)
	return Rect2i(lo, a.max(c) - lo + Vector2i.ONE)

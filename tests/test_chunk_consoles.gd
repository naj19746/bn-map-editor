extends "res://tests/support/test_case.gd"
## Consoles inside nested chunks (Stage 8d) on a small fake BN: a chunk
## opened alone judges its own consoles (cells it leaves undefined count as
## the parent's floor; an edge console standing outside it is a note), and
## a map judges every chunk each placement can pick (chunks and
## else_chunks, every mapgen, every rotation, chunks inside chunks), one
## finding per entry and pick, with the pick's reach for the canvas.

const TempTree := preload("res://tests/support/temp_tree.gd")

const MAPS := "data/json/mapgen/parents.json"
const CHUNKS := "data/json/mapgen/nested/rooms.json"
const DOOR_PC := {"name": "Door", "options": [{"name": "Unlock", "action": "unlock"}]}
const TER := {".": "t_floor", "#": "t_wall", "D": "t_door_metal_locked"}
## A 5x5 room: console at (2, 1), a locked metal door at (2, 4).
const ROOM := ["#####", "#.6.#", "#...#", "#...#", "##D##"]
## The same room without its door.
const SHUT := ["#####", "#.6.#", "#...#", "#...#", "#####"]

var _root := ""
var _index: DataIndex


static func _rows(marks: Dictionary, w := 24) -> Array:
	var rows := []
	for y in 24:
		var row := PackedStringArray()
		for x in w:
			row.append(marks.get(Vector2i(x, y), "."))
		rows.append("".join(row))
	return rows


static func _chunk(id: String, rows: Array, extra := {}, weight := -1) -> Dictionary:
	var obj := {"mapgensize": [rows[0].length(), rows.size()], "rows": rows, "terrain": TER,
		"computers": {"6": DOOR_PC}}
	obj.merge(extra, true)
	var o := {"type": "mapgen", "method": "json", "nested_mapgen_id": id, "object": obj}
	if weight >= 0:
		o["weight"] = weight
	return o


static func _map(id: Variant, obj: Dictionary) -> Dictionary:
	var o := {"fill_ter": "t_floor", "terrain": TER}
	o.merge(obj, true)
	return {"type": "mapgen", "method": "json", "om_terrain": id, "object": o}


func _setup() -> void:
	var things := []
	for t: Array in [["t_floor", ".", 2, []], ["t_wall", "#", 0, ["WALL"]], ["t_console", "6", 0, []],
			["t_door_metal_locked", "+", 0, []], ["t_door_metal_c", "'", 2, []]]:
		things.append({"type": "terrain", "id": t[0], "symbol": t[1], "color": "white", "move_cost": t[2], "flags": t[3]})
	things.append({"type": "overmap_terrain", "id": ["p_pick", "p_else", "p_rot", "p_nest", "p_over", "p_door",
		"p_wide_w", "p_wide_e"], "name": "x"})
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/things.json": things,
		CHUNKS: [
			_chunk("room_ok", ROOM),
			_chunk("room_far", SHUT),
			# Two mapgens: the second has no door.
			_chunk("vault", ROOM),
			_chunk("vault", SHUT),
			# The console sits in the top wall: nowhere to stand inside.
			_chunk("edge", ["#6#", "###", "###"]),
			# Only the console is defined: the rest keeps the parent's cells.
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "open", "object": {"mapgensize": [3, 3],
				"rows": ["   ", " 6 ", "   "], "terrain": {"6": "t_console"}, "computers": {"6": DOOR_PC}}},
			# Places room_far inside itself.
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "outer", "object": {"mapgensize": [8, 8],
				"rows": _rows({}, 8).slice(0, 8), "terrain": TER,
				"place_nested": [{"chunks": ["room_far"], "x": 1, "y": 1}]}},
			# The console at (4, 2) of a 5x5 room.
			_chunk("big", ["#####", "#...6", "#...#", "#...#", "##D##"]),
		],
		MAPS: [
			_map("p_pick", {"rows": _rows({}), "place_nested": [{"chunks": [["room_ok", 90], ["room_far", 10]], "x": 2, "y": 2}]}),
			_map("p_else", {"rows": _rows({}), "place_nested": [{"chunks": ["room_ok"], "else_chunks": ["vault"],
				"neighbors": {"north": "p_pick"}, "x": 2, "y": 2}]}),
			_map("p_rot", {"rows": _rows({}), "place_nested": [{"chunks": ["room_far"], "rotation": [0, 1], "x": 2, "y": 2}]}),
			_map("p_nest", {"rows": _rows({}), "place_nested": [{"chunks": ["outer"], "x": 10, "y": 10}]}),
			_map("p_over", {"rows": _rows({}), "place_nested": [{"chunks": ["big"], "x": 18, "y": 2}]}),
			# The parent's own door, 3 below room_far's console, is reached.
			_map("p_door", {"rows": _rows({Vector2i(4, 6): "D"}), "place_nested": [{"chunks": ["room_far"], "x": 2, "y": 1}]}),
			# Past the first tile, inside the second: still a warning.
			_map([["p_wide_w", "p_wide_e"]], {"rows": _rows({}, 48), "place_nested": [{"chunks": ["big"], "x": 18, "y": 2}]}),
		],
	}
	_root = TempTree.make(files)
	_index = DataIndex.load_bn(_root)
	check_eq(_index.errors, PackedStringArray(), "index errors")


func _cleanup() -> void:
	TempTree.remove(_root)


func _validate(id: String, ref_i := 0) -> Array[Validator.Finding]:
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for(id)[ref_i]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	return Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for))


## "severity code target" per console finding.
static func _consoles(list: Array[Validator.Finding]) -> PackedStringArray:
	var out := PackedStringArray()
	for f in list:
		if not f.code in [Validator.Code.NO_STAND, Validator.Code.NO_DOOR, Validator.Code.EDGE_CONSOLE,
				Validator.Code.CHUNK_CONSOLE, Validator.Code.CONSOLE_OVERHANG, Validator.Code.DOOR_ELSEWHERE]:
			continue
		var where := "%s@%d,%d" % [f.key, f.cell.x, f.cell.y] if f.target == Validator.Target.CELL \
				else "%s#%d" % [f.member, f.index]
		out.append("%s %s %s" % [["E", "W", "N"][f.severity], Validator.Code.keys()[f.code], where])
	return out


static func _texts(list: Array[Validator.Finding], code: Validator.Code) -> PackedStringArray:
	var out := PackedStringArray()
	for f in list:
		if f.code == code:
			out.append(f.text)
	return out


func test_chunk_alone() -> void:
	_setup()
	check_eq(_consoles(_validate("room_ok")), PackedStringArray())
	check_eq(_consoles(_validate("room_far")), PackedStringArray(["W NO_DOOR 6@2,1"]))
	check(_texts(_validate("room_far"), Validator.Code.NO_DOOR)[0].ends_with("in the chunk"), "says where it looked")
	check_eq(_consoles(_validate("vault", 0)), PackedStringArray())
	check_eq(_consoles(_validate("vault", 1)), PackedStringArray(["W NO_DOOR 6@2,1"]))
	check_eq(_consoles(_validate("edge")), PackedStringArray(["N EDGE_CONSOLE 6@1,0"]),
			"on the edge: the player may stand in the parent")
	check_eq(_consoles(_validate("open")), PackedStringArray(["W NO_DOOR 6@1,1"]),
			"undefined cells around it can be stood on (the parent's floor)")
	# A chunk placing a chunk judges it too, as a parent does.
	check_eq(_consoles(_validate("outer")), PackedStringArray(["W CHUNK_CONSOLE place_nested#0"]))
	_cleanup()


func test_every_pick_judged_in_parent() -> void:
	_setup()
	# 90% room_ok (drawn) reaches its door; 10% room_far doesn't.
	var found := _validate("p_pick")
	check_eq(_consoles(found), PackedStringArray(["W CHUNK_CONSOLE place_nested#0"]))
	check_eq(_texts(found, Validator.Code.CHUNK_CONSOLE), PackedStringArray([
		"place_nested #1 > room_far (10%): its console '6' at (4, 3): \"unlock\" changes nothing: no t_door_metal_locked within 8 of where the player stands, in the same overmap tile"]))
	var f: Validator.Finding = found.filter(func(x: Validator.Finding) -> bool: return x.code == Validator.Code.CHUNK_CONSOLE)[0]
	check_eq(f.describe().ends_with("(it does nothing in game)"), true)
	check_eq(f.view[0], Vector2i(24, 24), "the view: map size")
	check_eq(f.view[2], [Vector2i(4, 3)] as Array[Vector2i], "the console cell")
	# The view's grids hold room_far, not the drawn room_ok: no door at (4, 6).
	check_eq(f.view[1][0][6 * 24 + 4], "t_wall")
	# else_chunks and mapgens: only the vault's second mapgen fails.
	check_eq(_texts(_validate("p_else"), Validator.Code.CHUNK_CONSOLE), PackedStringArray([
		"place_nested #1 > vault (else_chunks, mapgen 2 of 2): its console '6' at (4, 3): \"unlock\" changes nothing: no t_door_metal_locked within 8 of where the player stands, in the same overmap tile"]))
	# Each rotation is a pick.
	var rot := _texts(_validate("p_rot"), Validator.Code.CHUNK_CONSOLE)
	check_eq(rot.size(), 2, str(rot))
	check(rot[0].begins_with("place_nested #1 > room_far (rotation 0): its console '6' at (4, 3)"), rot[0])
	check(rot[1].begins_with("place_nested #1 > room_far (rotation 1): its console '6' at (5, 4)"), rot[1])
	# A chunk inside a chunk, pointed at the top-level entry.
	var nest := _validate("p_nest")
	check_eq(_consoles(nest), PackedStringArray(["W CHUNK_CONSOLE place_nested#0"]))
	check(_texts(nest, Validator.Code.CHUNK_CONSOLE)[0].begins_with(
			"place_nested #1 > outer > place_nested #1 > room_far: its console '6' at (13, 12)"), str(_texts(nest, Validator.Code.CHUNK_CONSOLE)))
	# The parent's own door counts.
	check_eq(_consoles(_validate("p_door")), PackedStringArray())
	_cleanup()


func test_console_past_its_tile() -> void:
	_setup()
	# big's console is its (4, 1): at x 18 it lands at (22, 3), in the tile;
	# at x 20, at (24, 3), past it.
	check_eq(_consoles(_validate("p_over")), PackedStringArray(), "(22, 3) is inside the tile")
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for("p_over")[0]
	var mapgen := objects.object_for(ref)
	mapgen.object.place_nested[0].x = 20
	var r := MapgenResolver.resolve(_index, mapgen)
	var found := Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for))
	check_eq(_consoles(found), PackedStringArray(["W CONSOLE_OVERHANG place_nested#0"]), "(24, 3): off the map")
	check(found.any(func(f: Validator.Finding) -> bool: return f.describe().ends_with("(BN crashes if that tile isn't generated yet)")),
			"says why")
	# In a 2x1 map, (24, 3) is in the map but past the entry's tile.
	var wide := MapgenObjects.new(_index)
	var wref: DataIndex.MapgenRef = _index.mapgens_for("p_wide_w")[0]
	var wmap := wide.object_for(wref)
	wmap.object.place_nested[0].x = 20
	var wr := MapgenResolver.resolve(_index, wmap)
	check_eq(_consoles(Validator.validate_map(_index, wref, wmap, wr, Placement.read_all(wmap, wr.size),
			ChunkOverlay.build(_index, wmap, wr, wide.object_for))), PackedStringArray(["W CONSOLE_OVERHANG place_nested#0"]))
	_cleanup()


## Editing a chunk the parent only may pick (not the one drawn) updates the
## parent's findings, and the Problems tab draws the pick's reach.
func test_session_and_problems_tab() -> void:
	_setup()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.load_index(_root)
	var parent = main.open_id("p_pick")
	check_eq(_consoles(parent.doc.findings()), PackedStringArray(["W CHUNK_CONSOLE place_nested#0"]))
	check_eq(parent.doc.chunk_overlay().stamps[0].chunk_id, "room_ok", "room_ok is drawn")
	main.show_drawer_tab(main._problems_panel)
	var f: Validator.Finding = parent.doc.findings().filter(func(x: Validator.Finding) -> bool: return x.code == Validator.Code.CHUNK_CONSOLE)[0]
	main.show_finding(f)
	check(parent.canvas.reach != null, "the pick's reach is drawn")
	check_eq(parent.canvas.reach.consoles, [Vector2i(4, 3)] as Array[Vector2i])
	check(parent.canvas.reach.targets.is_empty(), "reaching nothing")
	check(parent.canvas.reach.stands.has(Vector2i(4, 4)), "stands inside the room")
	# Give room_far its door: the parent's warning goes.
	var chunk = main.open_id("room_far")
	chunk.doc.add_symbol("D", "t_door_metal_locked", "")
	chunk.doc.paint([Vector2i(2, 4)] as Array[Vector2i], "D")
	check_eq(_consoles(chunk.doc.findings()), PackedStringArray())
	check_eq(_consoles(parent.doc.findings()), PackedStringArray(), "the parent was told")
	main.free()
	TempTree.remove(ws)
	_cleanup()

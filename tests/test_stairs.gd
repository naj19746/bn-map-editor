extends "res://tests/support/test_case.gd"
## Stage 10c: stairs paired across a building's levels (Stairs, and the
## Validator's stair findings), against a fake BN checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _index: DataIndex


## A 24x24 map of "." with [param marks] ({Vector2i: char}) drawn in.
static func _rows(marks: Dictionary) -> Array:
	var rows := []
	for y in 24:
		var row := ""
		for x in 24:
			row += marks.get(Vector2i(x, y), ".")
		rows.append(row)
	return rows


static func _map(om: String, marks: Dictionary, extra := {}, top := {}) -> Dictionary:
	var obj := {"fill_ter": "t_floor", "rows": _rows(marks),
			"terrain": {"<": "t_stairs_up", ">": "t_stairs_down", "~": "t_water_dp", "O": "t_open_air"}}
	obj.merge(extra)
	var m := {"type": "mapgen", "method": "json", "om_terrain": om, "object": obj}
	m.merge(top)
	return m


## Buildings:
## - stack: z -1 s_base, 0 s_ground, 1 s_up (two mapgens), 2 s_roof (no
##   mapgen).
## - turned: z 0 t_ground (north), z 1 t_up (east).
func _init_tree() -> void:
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_stairs_up", "symbol": "<", "color": "white", "move_cost": 2,
				"flags": ["GOES_UP"]},
			{"type": "terrain", "id": "t_stairs_down", "symbol": ">", "color": "white", "move_cost": 2,
				"flags": ["GOES_DOWN"]},
			{"type": "terrain", "id": "t_open_air", "symbol": " ", "color": "white", "move_cost": 2,
				"flags": ["NO_FLOOR"]},
			{"type": "terrain", "id": "t_water_dp", "symbol": "~", "color": "blue", "move_cost": 0,
				"flags": ["DEEP_WATER", "GOES_DOWN"]}],
		"data/json/oter.json": [{"type": "overmap_terrain", "id": ["s_base", "s_ground", "s_up", "s_roof",
				"t_ground", "t_up"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "stack", "overmaps": [
				{"point": [0, 0, -1], "overmap": "s_base_north"},
				{"point": [0, 0, 0], "overmap": "s_ground_north"},
				{"point": [0, 0, 1], "overmap": "s_up_north"},
				{"point": [0, 0, 2], "overmap": "s_roof_north"}]},
			{"type": "city_building", "id": "turned", "overmaps": [
				{"point": [0, 0, 0], "overmap": "t_ground_north"},
				{"point": [0, 0, 1], "overmap": "t_up_east"}]},
		],
		"data/json/mapgen/stack.json": [
			# Its stairs down come from a chunk.
			_map("s_ground", {Vector2i(3, 3): "<"}, {"place_nested": [{"chunks": ["stair_chunk"], "x": 9, "y": 9}]}),
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "stair_chunk", "object": {
				"mapgensize": [3, 3], "rows": ["   ", " > ", "   "], "terrain": {">": "t_stairs_down"}}},
			_map("s_up", {Vector2i(3, 3): ">", Vector2i(6, 6): "<", Vector2i(20, 20): "O"}, {}, {"weight": 100}),
			# Its stairs down come from place_terrain, 5 cells off; deep water isn't stairs.
			_map("s_up", {Vector2i(1, 1): "~"}, {"place_terrain": [{"ter": "t_stairs_down", "x": 8, "y": 8}]},
					{"weight": 50}),
			_map("s_base", {Vector2i(10, 10): "<", Vector2i(1, 1): ">"}),
			_map("t_ground", {Vector2i(0, 0): "<"}),
			# Placed turned east: (0, 23) lands on the ground's (0, 0).
			_map("t_up", {Vector2i(0, 23): ">"}),
		],
	})
	_index = DataIndex.load_bn(_root)


func _findings(id: String, i := 0) -> PackedStringArray:
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for(id)[i]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	var out := PackedStringArray()
	for f in Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for), Stairs.new(_index, objects.object_for)):
		out.append("%s %s %s: %s" % [f.severity_name(), Validator.Code.keys()[f.code], f.cell, f.text])
	return out


func test_stair_cells() -> void:
	_init_tree()
	check_eq(_index.errors, PackedStringArray())
	var objects := MapgenObjects.new(_index)
	var stairs := Stairs.new(_index, objects.object_for)
	var ground := stairs.grid_for(_index.mapgens_for("s_ground")[0])
	check_eq(ground.cells(Vector2i.ZERO, Stairs.UP), [Vector2i(3, 3)] as Array[Vector2i])
	check_eq(ground.cells(Vector2i.ZERO, Stairs.DOWN), [Vector2i(10, 10)] as Array[Vector2i], "from the chunk")
	var b := stairs.grid_for(_index.mapgens_for("s_up")[1])
	check_eq(b.cells(Vector2i.ZERO, Stairs.LANDING), [Vector2i(8, 8)] as Array[Vector2i],
			"place_terrain counts, deep water doesn't")
	TempTree.remove(_root)


func test_stair_findings() -> void:
	_init_tree()
	check_eq(_findings("s_ground"), PackedStringArray([
		"note STAIRS_OFFSET (3, 3): in stack (0, 0, z 0): stairs up at (3, 3): s_up (mapgen 2 of 2, weight 50), the tile above (z 1), has its stairs down elsewhere, e.g. over (8, 8); BN takes the player to the nearest"]),
		"paired with the first s_up and the chunk's stairs with s_base; the second s_up is off")
	check_eq(_findings("s_up", 0), PackedStringArray([
		"warning STAIRS (6, 6): in stack (0, 0, z 1): stairs up at (6, 6): no mapgen draws s_roof, the tile above (z 2), so it has no stairs back"]))
	check_eq(_findings("s_up", 1), PackedStringArray([
		"note STAIRS_OFFSET (8, 8): in stack (0, 0, z 1): stairs down at (8, 8): s_ground, the tile below (z 0), has its stairs up elsewhere, e.g. over (3, 3); BN takes the player to the nearest"]))
	check_eq(_findings("s_base"), PackedStringArray([
		"note STAIRS_NO_TILE (1, 1): in stack (0, 0, z -1): stairs down at (1, 1): stack has no tile below (z -2); they connect only if what the overmap puts there (another special, a lab, ...) has stairs up"]))
	check_eq(_findings("t_ground"), PackedStringArray(), "compared turned: the east tile's (0, 23) is over (0, 0)")
	check_eq(_findings("t_up"), PackedStringArray())

	# Without the building data (no Stairs), nothing is paired.
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for("s_base")[0]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	check_eq(Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size), null).size(), 0)
	TempTree.remove(_root)


func test_ghosts() -> void:
	_init_tree()
	var ground: DataIndex.MapgenRef = _index.mapgens_for("s_ground")[0]
	var place := BuildingLevels.places(_index, ground)[0]
	var below := LevelNav.ghosts(_index, place, ground, -1)
	if check_eq(below.size(), 1, "the basement"):
		check_eq(below[0].ref.title(), "s_base")
		check_eq(below[0].rect(), Rect2i(0, 0, 24, 24))
	var up_b: DataIndex.MapgenRef = _index.mapgens_for("s_up")[1]
	var above := LevelNav.ghosts(_index, place, ground, 1, [up_b])
	check_eq(above[0].ref, up_b, "the mapgen open in a tab")
	check_eq(LevelNav.ghosts(_index, place, ground, 1)[0].ref, _index.mapgens_for("s_up")[0], "else the first")
	var t_ground: DataIndex.MapgenRef = _index.mapgens_for("t_ground")[0]
	var t_up: DataIndex.MapgenRef = _index.mapgens_for("t_up")[0]
	var t_above := LevelNav.ghosts(_index, BuildingLevels.places(_index, t_ground)[0], t_ground, 1)
	check_eq(t_above[0].turns(), 1, "the east tile over a north one")
	var t_below := LevelNav.ghosts(_index, BuildingLevels.places(_index, t_up)[0], t_up, 0)
	check_eq(t_below[0].turns(), 3, "the north tile under the east one, as t_up is drawn unturned")

	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	check_eq(main.settings.ghost, -1, "the level below by default")
	var m: Variant = main.open_id("s_ground")
	var ghosts: Array[LevelNav.Neighbor] = m.canvas.ghosts
	if check_eq(ghosts.size(), 1, "the basement under the ground floor"):
		check(ghosts[0].ascii != null)
		check_eq(ghosts[0].stairs, [Vector2i(10, 10)] as Array[Vector2i], "its stairs up")
		check_eq(ghosts[0].ascii.chars[10 * 24 + 10], "<")
	check(not m.canvas.ghost_above)
	main.set_ghost(1)
	ghosts = m.canvas.ghosts
	if check_eq(ghosts.size(), 1):
		check_eq(ghosts[0].stairs, [Vector2i(3, 3)] as Array[Vector2i], "the first s_up's stairs down")
	check(m.canvas.ghost_above)
	check_eq(main._ghost_picker.get_selected_id(), 2)
	main.set_ghost_dim(false)
	check(not m.canvas.ghost_dim)
	check(not main._dim_button.button_pressed)
	main.set_ghost(0)
	check_eq(m.canvas.ghosts.size(), 0, "no ghost")
	main.set_ghost(1)

	# Turned: the east tile's stairs (0, 23) land on the ground's (0, 0).
	var t: Variant = main.open_id("t_ground")
	if check_eq(t.canvas.ghosts.size(), 1):
		check_eq(t.canvas.ghosts[0].stairs, [Vector2i(0, 0)] as Array[Vector2i])
		check_eq(t.canvas.ghosts[0].ascii.chars[0], ">")
	var top: Variant = main.open_id("s_up")
	if check_eq(top.canvas.ghosts.size(), 1, "the roof tile"):
		check_eq(top.canvas.ghosts[0].ref, null, "no mapgen draws it: nothing to draw")
	# Open air shows the ghost; floor hides it.
	check_eq(top.ascii.see_through[0], 0)
	check_eq(top.ascii.see_through[20 * 24 + 20], 1)

	# Selecting a stair finding shows the level the stairs lead to.
	main.set_ghost(-1)
	var g: Variant = main.open_id("s_ground")
	var found: Array[Validator.Finding] = g.doc.findings()
	if check_eq(found.size(), 1):
		main.show_finding(found[0])
		check_eq(main.settings.ghost, 1, "stairs up: the level above")
		check_eq(g.canvas.focus, Rect2i(3, 3, 1, 1))
	main.free()
	TempTree.remove(_root)
	TempTree.remove(ws)

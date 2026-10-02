extends "res://tests/support/test_case.gd"
## Stage 11c: views and findings kept fresh. Other levels' edits reach a
## map's stair findings, neighbours and ghost; files another program saves
## are picked up by the editor and the MCP server. Against a fake BN
## checkout.

const TempTree := preload("res://tests/support/temp_tree.gd")
const GROUND_FILE := "data/json/mapgen/fb.json"

var _root := ""
var _ws := ""


## A 24x24 map of "." with [param marks] ({Vector2i: char}) drawn in.
static func _map(om: String, marks: Dictionary) -> Dictionary:
	var rows := []
	for y in 24:
		var row := ""
		for x in 24:
			row += marks.get(Vector2i(x, y), ".")
		rows.append(row)
	return {"type": "mapgen", "method": "json", "om_terrain": om, "object": {"fill_ter": "t_floor",
			"rows": rows, "terrain": {"<": "t_stairs_up", ">": "t_stairs_down", "#": "t_rock"}}}


## Building fb: z 0 fb_ground (stairs up at (5, 5)) and fb_side east of it;
## z 1 fb_up, with no stairs down yet. other_map isn't in a building.
func _setup() -> void:
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "name": "bn", "core": true,
				"path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white", "move_cost": 2},
			{"type": "terrain", "id": "t_rock", "symbol": "#", "color": "white", "move_cost": 0},
			{"type": "terrain", "id": "t_stairs_up", "symbol": "<", "color": "white", "move_cost": 2,
				"flags": ["GOES_UP"]},
			{"type": "terrain", "id": "t_stairs_down", "symbol": ">", "color": "white", "move_cost": 2,
				"flags": ["GOES_DOWN"]}],
		"data/json/oter.json": [{"type": "overmap_terrain", "id": ["fb_ground", "fb_side", "fb_up", "other_map"]}],
		"data/json/buildings.json": [
			{"type": "city_building", "id": "fb", "overmaps": [
				{"point": [0, 0, 0], "overmap": "fb_ground_north"},
				{"point": [1, 0, 0], "overmap": "fb_side_north"},
				{"point": [0, 0, 1], "overmap": "fb_up_north"}]},
			{"type": "region_settings", "id": "default", "city": {"houses": {"fb": 100}}}],
		GROUND_FILE: [_map("fb_ground", {Vector2i(5, 5): "<"}), _map("fb_side", {}), _map("fb_up", {}),
				_map("other_map", {})],
	})
	_ws = TempTree.make({})


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


static func _codes(found: Array[Validator.Finding]) -> Array:
	return found.map(func(f: Validator.Finding) -> int: return f.code)


func test_other_levels_notify() -> void:
	_setup()
	var index := DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	var s := EditSession.new(index, Workspace.open(_ws, _root))
	var ground := s.open(index.mapgens_for("fb_ground")[0])
	var up := s.open(index.mapgens_for("fb_up")[0])
	var other := s.open(index.mapgens_for("other_map")[0])
	check(_codes(ground.findings()).has(Validator.Code.STAIRS), "no stairs down above yet")
	var told := []
	ground.levels_changed.connect(func() -> void: told.append("ground"))
	other.levels_changed.connect(func() -> void: told.append("other"))
	var edited := []
	s.map_edited.connect(func(r: DataIndex.MapgenRef) -> void: edited.append(r.title()))

	# A stroke: each set_cells reports the map; its end tells the building.
	up.begin_stroke("Paint")
	up.set_cells([Vector2i(5, 5)] as Array[Vector2i], ">")
	check_eq(edited, ["fb_up"], "cells painted")
	check_eq(told, [], "not before the stroke ends")
	up.end_stroke()
	check_eq(told, ["ground"], "the building's other open map; other_map isn't in it")
	check(not _codes(ground.findings()).has(Validator.Code.STAIRS), "the stairs are there now")
	up.undo()
	check(_codes(ground.findings()).has(Validator.Code.STAIRS), "and gone again with undo")
	check_eq(told, ["ground", "ground"])

	# A closed map is no longer told.
	s.close(ground)
	up.redo()
	check_eq(told.size(), 2)
	_cleanup()


## The accept: a stair finding on z 0 goes away when the stairs are painted
## on z 1 in another tab; neighbours and the ghost redraw.
func test_main_redraws_levels() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	main.set_ghost(1)
	var up: Variant = main.open_id("fb_up")
	var side: Variant = main.open_id("fb_side")
	var ground: Variant = main.open_id("fb_ground")
	if not check(up != null and side != null and ground != null, "opened"):
		main.free()
		_cleanup()
		return
	check(_codes(ground.doc.findings()).has(Validator.Code.STAIRS))
	check(main._problems_button.text.contains("warning") or main._problems_button.text.contains("error"),
			main._problems_button.text)
	var ghost: LevelNav.Neighbor = ground.canvas.ghosts[0]
	check_eq(ghost.stairs, [] as Array[Vector2i], "no stairs down on the ghost")

	# Painted in fb_up's document (as another tab, or the palette editor, would).
	up.doc.paint([Vector2i(5, 5)] as Array[Vector2i], ">")
	check(main._levels_stale, "the current map's findings are stale")
	main.flush_level_views()
	check(not _codes(ground.doc.findings()).has(Validator.Code.STAIRS), "the finding went")
	check_eq(main._problems_button.text, "No problems")
	ghost = ground.canvas.ghosts[0]
	check_eq(ghost.ascii.chars[5 * 24 + 5], ">", "the ghost redrew")
	check_eq(ghost.stairs, [Vector2i(5, 5)] as Array[Vector2i], "and marks the new stairs")

	# The neighbour fb_side, during a stroke.
	side.doc.begin_stroke("Paint")
	side.doc.set_cells([Vector2i(0, 0)] as Array[Vector2i], "#")
	main.flush_level_views()
	var n: LevelNav.Neighbor = ground.canvas.neighbors[0]
	check_eq(n.ref, side.ref)
	check_eq(n.ascii.chars[0], "#", "the neighbour redrew mid-stroke")
	side.doc.end_stroke()
	main.free()
	_cleanup()


## The accept: files another EditSession saves to the workspace (a new
## mapgen, an edit of an open map) are picked up without F5; with unsaved
## edits a banner asks instead.
func test_main_reloads_from_disk() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.settings.mods = PackedStringArray()
	main.load_index(_root)
	main.open_id("fb_up")
	var m: Variant = main.open_id("fb_ground")
	main.set_brush("<")
	m.canvas.cell_size = 11.0
	check_eq(main.check_disk(), PackedStringArray(), "nothing changed")

	# Another process (the MCP server) adds a mapgen in a new workspace file.
	var other_index := DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	var other := EditSession.new(other_index, Workspace.open(_ws, _root))
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/new.json"
	spec.ids = [PackedStringArray(["n_new"])] as Array[PackedStringArray]
	spec.fill_ter = "t_floor"
	check(other.create_mapgen(spec) != null, other.last_error)
	check_eq(other.save(spec.rel_path), "")
	check_eq(main.check_disk(), PackedStringArray(["manifest.json", spec.rel_path]))
	check(not main.index.mapgens_for("n_new").is_empty(), "the browser's index has it")
	check_eq(main.maps.size(), 2, "tabs reopened")
	m = main.current_map()
	check_eq(m.ref.title(), "fb_ground", "the same tab is current")
	check_eq([m.brush, m.canvas.cell_size], ["<", 11.0], "brush and view kept")
	check_eq(m.place.building.id, "fb")
	check_eq(main.check_disk(), PackedStringArray(), "seen once")

	# It edits the open map's file.
	var theirs := other.open(other_index.mapgens_for("fb_ground")[0])
	theirs.paint([Vector2i(1, 1)] as Array[Vector2i], "<")
	check_eq(other.save(GROUND_FILE), "")
	check_eq(main.check_disk(), PackedStringArray([GROUND_FILE, "manifest.json"]))
	m = main.current_map()
	check_eq(m.ascii.chars[1 * 24 + 1], "<", "the tab shows their edit")
	check_eq(m.ref.source.path, GROUND_FILE)

	# With unsaved edits: the banner, and saving still refuses.
	main.set_tool(MapTool.Kind.PAINT)
	m.canvas.cell_pressed.emit(Vector2i(2, 2), false, false)
	m.canvas.cell_released.emit(Vector2i(2, 2), false)
	check(m.doc.can_undo(), "painted")
	theirs.paint([Vector2i(3, 3)] as Array[Vector2i], "<")
	check_eq(other.save(GROUND_FILE), "")
	check_eq(main.check_disk(), PackedStringArray([GROUND_FILE]))
	check(main._disk_banner.visible, "the banner is up")
	check(main._disk_label.text.contains("unsaved edits in " + GROUND_FILE), main._disk_label.text)
	check(main.save_current().contains("changed on disk"), "save refuses")
	main.keep_disk_edits()
	check(not main._disk_banner.visible)
	check_eq(main.check_disk(), PackedStringArray(), "kept: not asked again")
	check(m.doc.can_undo(), "the edits are still there")
	# Reload (lose my edits) takes the disk's version.
	main.reload_from_disk()
	m = main.current_map()
	check_eq([m.ascii.chars[2 * 24 + 2], m.ascii.chars[3 * 24 + 3]], [".", "<"])

	# A map that is gone from its file is dropped from the tabs.
	var f := FileAccess.open(_ws.path_join(GROUND_FILE), FileAccess.WRITE)
	f.store_string(JSON.stringify([_map("fb_side", {}), _map("fb_up", {})]))
	f.close()
	main.check_disk()
	check_eq(main.maps.map(func(x: Variant) -> String: return x.ref.title()), ["fb_up"])
	check(main._status.text.contains("Closed fb_ground"), main._status.text)
	main.free()
	_cleanup()


## The MCP server picks up the editor's saves before a call.
func test_mcp_reloads_from_disk() -> void:
	_setup()
	var tools := McpTools.new(McpTools.load_session.bind(_root, PackedStringArray(), _ws))
	var got: Dictionary = tools.call_tool("get_map", {"id": "fb_ground"})
	check(not got.has("reloaded"))
	var editor := EditSession.new(DataIndex.load_bn(_root, PackedStringArray(), null, _ws), Workspace.open(_ws, _root))
	var doc := editor.open(editor.index.mapgens_for("fb_ground")[0])
	doc.paint([Vector2i(1, 1)] as Array[Vector2i], "<")
	check_eq(editor.save(GROUND_FILE), "")
	got = tools.call_tool("get_map", {"id": "fb_ground"})
	check_eq(got.get("reloaded"), [GROUND_FILE, "manifest.json"], "the editor's save")
	check_eq(got.rows[1].substr(1, 1), "<", "read again")
	got = tools.call_tool("get_map", {"id": "fb_ground"})
	check(not got.has("reloaded"), "once")

	# Unsaved edits here: a warning, once.
	tools.call_tool("paint_cells", {"id": "fb_ground", "key": "#", "cells": [[2, 2]]})
	doc.paint([Vector2i(3, 3)] as Array[Vector2i], "<")
	check_eq(editor.save(GROUND_FILE), "")
	got = tools.call_tool("get_map", {"id": "fb_ground"})
	check(str(got.get("disk_warning")).contains(GROUND_FILE + " changed on disk"), str(got.get("disk_warning")))
	check_eq(got.rows[2].substr(2, 1), "#", "the edits are kept")
	var saved: Variant = tools.call_tool("save", {})
	check(saved is McpTools.Failure and saved.message.contains("changed on disk"), "save refuses")
	_cleanup()

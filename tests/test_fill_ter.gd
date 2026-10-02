extends "res://tests/support/test_case.gd"
## Editing a map's fill_ter: MapDocument.set_fill_ter and the Legend's row.

const TempTree := preload("res://tests/support/temp_tree.gd")

var _root := ""
var _ws := ""


func _setup() -> void:
	var ter := []
	for id in ["t_floor", "t_wall", "t_grass", "t_dirt"]:
		ter.append({"type": "terrain", "id": id, "symbol": id[2], "color": "white"})
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 else "#h" + " ".repeat(22))
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": ter + [
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "overmap_terrain", "id": ["house"], "name": "house"},
		],
		"data/json/mapgen/house.json": [
			{"type": "mapgen", "method": "json", "om_terrain": "house",
				"object": {"fill_ter": "t_grass", "rows": rows, "terrain": {"#": "t_wall"},
					"furniture": {"h": "f_chair"}}},
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "chunk",
				"object": {"mapgensize": [2, 2], "rows": ["##", "##"], "terrain": {"#": "t_wall"}}},
		],
	})
	_ws = TempTree.make({})


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


func test_set_fill_ter() -> void:
	_setup()
	var index := DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	var session := EditSession.new(index, Workspace.open(_ws, _root))
	var doc := session.open(index.mapgens_for("house")[0])
	check_eq(doc.keys_without_terrain(), PackedStringArray([" ", "h"]))
	check_eq(doc.set_fill_ter("t_dirt"), "")
	check_eq(doc.object().fill_ter, "t_dirt")
	check_eq(doc.resolved.terrain_at(1, 1).id(), "t_dirt", "h shows the new fill_ter")
	check_eq(doc.undo_name(), "Set fill_ter t_dirt")
	check_eq(doc.set_fill_ter(""), "")
	check(not doc.object().has("fill_ter"), "blank removes it")
	check_eq(doc.undo_name(), "Remove fill_ter")
	check(doc.problems().size() > 0, "cells without terrain are a problem now")
	doc.undo()
	check_eq(doc.object().fill_ter, "t_dirt")
	doc.undo()
	check_eq(doc.object().fill_ter, "t_grass")
	check(doc.set_fill_ter("t_nope").begins_with("Unknown terrain"))
	check_eq(doc.object().fill_ter, "t_grass", "refused")
	var chunk := session.open(index.mapgens_for("chunk")[0])
	check(chunk.set_fill_ter("t_dirt").begins_with("A chunk has no fill_ter"))
	check(not chunk.object().has("fill_ter"))
	_cleanup()


func test_legend_row() -> void:
	_setup()
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main.settings_file = ""
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m: Variant = main.open_id("house")
	if not check(m != null, "open house"):
		main.free()
		_cleanup()
		return
	var legend: LegendPanel = main._legend
	check(legend.fill_row.visible)
	check_eq(legend.fill_edit.text, "t_grass")
	legend.fill_edit.text = "t_dirt"
	check_eq(legend.apply_fill(), "")
	check_eq(m.doc.object().fill_ter, "t_dirt")
	check_eq(m.ascii.resolved.fill_ter, "t_dirt", "redrawn")
	check(main._status.text.contains("fill_ter is now t_dirt"), main._status.text)
	legend.fill_edit.text = ""
	check_eq(legend.apply_fill(), "")
	check(not m.doc.object().has("fill_ter"))
	check(main._status.text.contains("now have no terrain"), main._status.text)
	check_eq(legend.fill_edit.text, "")
	legend.fill_edit.text = "t_nope"
	check(legend.apply_fill().begins_with("Unknown terrain"))
	check_eq(legend.fill_edit.text, "", "refused: shows the map's again")
	main.undo()
	check_eq(legend.fill_edit.text, "t_dirt", "undo shows in the row")
	var c: Variant = main.open_id("chunk")
	if check(c != null, "open chunk"):
		check(not legend.fill_row.visible, "a chunk has no fill_ter")
	main.free()
	_cleanup()

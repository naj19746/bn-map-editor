extends "res://tests/support/test_case.gd"
## Validation (Stage 7) against a small fake BN checkout: each seeded
## problem is caught at BN's severity with the right target, palette
## findings come once per palette, and ids BN accepts (aliases, vehicle
## prototypes, null ids, Lua-registered mapgen ids) aren't findings.

const TempTree := preload("res://tests/support/temp_tree.gd")

const MAPS := "data/json/mapgen/maps.json"

var _root := ""
var _index: DataIndex


static func _blank(fill := ".") -> Array:
	var rows := []
	for y in 24:
		rows.append(fill.repeat(24))
	return rows


static func _map(id: Variant, obj: Dictionary, extra := {}) -> Dictionary:
	var o := {"type": "mapgen", "method": "json", "om_terrain": id, "object": obj}
	o.merge(extra)
	return o


func _setup() -> void:
	var rows := _blank()
	rows[0] = "T?" + ".".repeat(22)
	var files := {
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/preload.lua": 'game.add_hook("on_make_mapgen_factory_list", function(params)\n' \
				+ '  params.results:insert(#params.results + 1, "lua_map")\nend)\n',
		"data/json/things.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_grass", "symbol": ".", "color": "green"},
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
			{"type": "overmap_terrain", "id": ["house", "no_fill"], "name": "x"},
			{"type": "overmap_connection", "id": "local_road"},
			{"type": "GENERIC", "id": "rock"},
			{"type": "FUEL", "id": "gasoline"},
			{"type": "COMESTIBLE", "id": "water"},
			{"type": "MIGRATION", "id": "old_rock", "replace": "rock"},
			{"type": "item_group", "id": "stuff", "items": ["rock"]},
			{"type": "MONSTER", "id": "mon_zombie", "alias": "mon_zed"},
			{"type": "monstergroup", "name": "GROUP_Z", "monsters": []},
			{"type": "vehicle", "id": "car"},
			{"type": "vehicle_group", "id": "parking"},
			{"type": "trap", "id": "tr_pit"},
			{"type": "field_type", "id": "fd_fire"},
			{"type": "npc", "id": "bandit"},
		],
		"data/json/mapgen_palettes/pal.json": [
			{"type": "palette", "id": "good_pal", "terrain": {".": "t_floor"}, "items": {"x": {"item": "stuff"}}},
			# 'q' is used by no map; BN checks it anyway, once, as the palette's.
			{"type": "palette", "id": "bad_pal", "item": {"q": {"item": "nope_item"}}},
			{"type": "palette", "id": "outer_pal", "palettes": ["bad_pal"]},
			{"type": "palette", "id": "map_pal", "mapping": {"m": {"terrain": "t_floor"}}, "terrain": {"n": "t_floor"}},
		],
		"data/json/mapgen/nested/chunks.json": [
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "room",
				"object": {"mapgensize": [2, 2], "rows": ["..", ".."], "rotation": [0, 3]}},
			{"type": "mapgen", "method": "json", "nested_mapgen_id": "still",
				"object": {"mapgensize": [1, 1], "rows": ["."], "rotation": [0, 0]}},
		],
		MAPS: [
			_map("house", {"fill_ter": "t_grass", "rows": rows,
				"palettes": ["good_pal", "outer_pal", "bad_pal"],
				"terrain": {"u": "t_nope_unused"},
				"traps": {"T": "tr_nope"},
				"items": {"u": {"item": "nope_group_unused"}},
				"place_item": [{"item": "nope_item", "x": 1, "y": 1}, {"item": "old_rock", "x": 1, "y": 1},
					{"item": "rock", "x": 1, "y": 1}],
				"place_monster": [{"monster": "mon_nope", "x": 1, "y": 1}, {"monster": "mon_zed", "x": 1, "y": 1},
					{"monster": [["mon_zombie", 10], ["mon_gone", 5]], "x": 1, "y": 1}],
				"place_vehicles": [{"vehicle": "veh_nope", "x": 1, "y": 1}, {"vehicle": "car", "x": 1, "y": 1},
					{"vehicle": "parking", "x": 1, "y": 1}],
				"place_nested": [{"chunks": ["nope_chunk", "null"], "x": 1, "y": 1},
					{"chunks": ["room"], "neighbors": {"north": ["nope_oter", "house"]},
						"connections": {"east": "nope_road"}, "x": 3, "y": 3},
					{"chunks": ["room"], "rotation": 5, "x": 6, "y": 6}],
				"place_loot": [{"group": "nope_group", "x": 1, "y": 1}, {"group": "stuff", "item": "rock", "x": 1, "y": 1}],
				"place_items": [{"item": "stuff", "x": 30, "y": 1, "chance": 5}, {"item": "stuff", "x": [20, 30], "y": 1},
					{"item": "stuff", "x": 1, "y": 1, "chance": 0}],
				"place_gaspumps": [{"fuel": "water", "x": 1, "y": 1}, {"fuel": "gasoline", "x": 2, "y": 1}],
				"place_fields": [{"field": "fd_fire", "x": 1, "y": 1}, {"field": "fd_nope", "x": 1, "y": 1}],
				"set": [{"point": "terrain", "id": "t_nope", "x": 1, "y": 1},
					{"point": "trap", "id": "tr_pit", "x": 1, "y": 1},
					{"point": "water", "id": "t_floor", "x": 1, "y": 1}],
			}),
			_map("lua_map", {"fill_ter": "t_grass"}),
			_map("no_fill", {"rows": _blank("m").slice(0, 23) + [" ".repeat(23) + "n"], "palettes": ["map_pal"]}),
			_map("unused_map", {"fill_ter": "t_grass"}),
			_map("fema", {"fill_ter": "t_nope", "place_loot": [{"group": "nope", "x": 1, "y": 1}]}, {"weight": 0}),
		],
	}
	_root = TempTree.make(files)
	_index = DataIndex.load_bn(_root)


func _cleanup() -> void:
	TempTree.remove(_root)


func _validate(id: String) -> Array[Validator.Finding]:
	var objects := MapgenObjects.new(_index)
	var ref: DataIndex.MapgenRef = _index.mapgens_for(id)[0]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(_index, mapgen)
	return Validator.validate_map(_index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(_index, mapgen, r, objects.object_for))


## "severity code target" per finding, e.g. "E! UNKNOWN_ID place_loot#0"
## (E! = BN won't load, E = reported on load, W, N).
static func _summary(list: Array[Validator.Finding]) -> PackedStringArray:
	var out := PackedStringArray()
	for f in list:
		var sev: String = ["E", "W", "N"][f.severity] + ("!" if f.load_fails else "")
		var where := ""
		match f.target:
			Validator.Target.SYMBOL: where = "'%s'" % f.key
			Validator.Target.CELL: where = "%s@%d,%d" % [f.key, f.cell.x, f.cell.y]
			Validator.Target.PLACEMENT: where = "%s#%d" % [f.member, f.index]
			Validator.Target.PALETTE_KEY: where = "%s:'%s'" % [f.palette, f.key]
		out.append("%s %s %s" % [sev, Validator.Code.keys()[f.code], where])
	return out


func test_seeded_problems_at_bn_severity() -> void:
	_setup()
	var got := _summary(_validate("house"))
	var want := PackedStringArray([
		# Symbols: undefined '?' (reported); the used trap 'T' (reported); an
		# unused key's plain terrain is still converted (reported), its item
		# group isn't checked (note).
		"E UNDEFINED_SYMBOL '?'",
		"E UNKNOWN_ID 'u'",
		"N UNUSED_KEY_ID 'u'",
		"E UNKNOWN_ID 'T'",
		# Placements, in member order.
		"E UNKNOWN_ID place_item#0",
		"E UNKNOWN_ID place_item#1",
		"E UNKNOWN_ID place_monster#0",
		"E UNKNOWN_ID place_monster#2",
		"E UNKNOWN_ID place_vehicles#0",
		"E UNKNOWN_ID place_nested#0",
		"E UNKNOWN_ID place_nested#1",
		"E UNKNOWN_ID place_nested#1",
		"N CONDITIONAL place_nested#1",
		"E ROTATION place_nested#2",
		"E! LOOT_GROUP_ITEM place_loot#1",
		"E! UNKNOWN_ID place_loot#0",
		"W DROPPED place_items#0",
		"E! CROSSES place_items#1",
		"W ITEMS_CHANCE place_items#2",
		"E BAD_FUEL place_gaspumps#0",
		"E UNKNOWN_ID place_fields#1",
		"E! UNKNOWN_ID set#0",
		"E! SET_OPERATION set#2",
	])
	var a := got.duplicate()
	var b := want.duplicate()
	a.sort()
	b.sort()
	check_eq(a, b)
	if a != b:
		print("     got: ", "\n          ".join(got))
	# Texts say which id and how BN reacts.
	var texts := _validate("house").map(func(f: Validator.Finding) -> String: return f.describe())
	check(texts.has("error: place_loot #1: unknown item group \"nope_group\" (BN won't load this map)"), str(texts))
	check(texts.has("error: place_item #2: unknown item \"old_rock\" (BN reports this on every load)"),
			"a migrated id is still unknown to mapgen")
	check(texts.has("error: place_gaspumps #1: \"water\" isn't a gas pump fuel (gasoline, diesel, jp8, avgas) (BN reports this on every load)"), str(texts))
	_cleanup()


func test_palettes_once_each() -> void:
	_setup()
	var bad := _summary(Validator.validate_palette(_index, "bad_pal", _index.palette("bad_pal").data))
	check_eq(bad, PackedStringArray(["E UNKNOWN_ID bad_pal:'q'"]), "an unused key is checked in a palette")
	check_eq(Validator.validate_palette(_index, "good_pal", _index.palette("good_pal").data).size(), 0)
	# The house lists bad_pal directly and through outer_pal: one finding.
	var all := _summary(Validator.validate_palettes(_index, PackedStringArray(["good_pal", "outer_pal", "bad_pal"])))
	check_eq(all, PackedStringArray(["E UNKNOWN_ID bad_pal:'q'"]))
	# The map's own findings leave palette definitions to the palette.
	for f in _validate("house"):
		check(f.target != Validator.Target.PALETTE_KEY and f.key != "q", f.describe())
	_cleanup()


func test_mapgen_ids_bn_uses() -> void:
	_setup()
	check_eq(_summary(_validate("lua_map")), PackedStringArray(), "registered by a Lua hook")
	check_eq(_summary(_validate("unused_map")), PackedStringArray(["E NOT_USED "]))
	# Without fill_ter, only a plain "terrain" member gives a key terrain;
	# BN doesn't count one from "mapping". Undefined ' ' has none either.
	check_eq(_summary(_validate("no_fill")), PackedStringArray(["E! NO_TERRAIN 'm'", "E! NO_TERRAIN ' '"]))
	# Weight 0: BN never loads it, so nothing else counts.
	check_eq(_summary(_validate("fema")), PackedStringArray(["N DISABLED "]))
	check(_index.mapgens_for("fema")[0].disabled, "marked")
	# A chunk's own rotation does nothing; [0, 0] is what BN does anyway.
	check_eq(_summary(_validate("room")), PackedStringArray(["N CHUNK_ROTATION "]))
	check_eq(_summary(_validate("still")), PackedStringArray())
	_cleanup()


func test_main_scene_problems_tab() -> void:
	_setup()
	var ws := TempTree.make({})
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = ws
	main.load_index(_root)
	var m = main.open_id("house")
	var panel: ProblemsPanel = main._problems_panel
	# The status bar counts errors and warnings (the palette's included).
	check_eq(main._problems_button.text, "20 errors, 2 warnings")
	# (TabContainer tracks no tabs outside the tree, so which tab shows isn't
	# checked here.)
	check_eq(panel.list.get_root().get_child_count(), panel.findings.size(), "all listed")
	check_eq(panel.findings[0].severity, Validator.Severity.ERROR, "errors first")
	panel.toggles[Validator.Severity.ERROR].button_pressed = false
	check_eq(panel.list.get_root().get_child_count(), panel.findings.size() - 20, "errors hidden")
	panel.toggles[Validator.Severity.ERROR].button_pressed = true

	# A placement: selected on the map and outlined.
	var i := _find(panel, Validator.Target.PLACEMENT, "place_loot", 0)
	panel.activate(i)
	check_eq([main._placements_panel.member, main._placements_panel.index], ["place_loot", 0])
	check_eq(m.canvas.focus, Rect2i(1, 1, 1, 1))
	check(main._placements_panel._problems.text.contains("unknown item group \"nope_group\""),
			"the inspector lists the entry's findings: " + main._placements_panel._problems.text)
	# A symbol: highlighted, its first cell outlined.
	panel.activate(_find(panel, Validator.Target.SYMBOL, "", -1, "?"))
	check_eq(m.canvas.highlight_key, "?")
	check_eq(m.canvas.focus, Rect2i(1, 0, 1, 1))
	# A palette key: the palette editor opens at it.
	panel.activate(_find(panel, Validator.Target.PALETTE_KEY, "", -1, "q"))
	var editor: PaletteEditor = main._palette_editor
	check_eq(editor.doc.id, "bad_pal")
	check_eq(editor.key_edit.text, "q", "the key is selected")
	check(editor.problems.text.contains("unknown item \"nope_item\""), editor.problems.text)

	# Fixing one updates the counts.
	check_eq(m.doc.set_placement_fields("place_loot", 0, {"group": "stuff"}), "")
	check_eq(main._problems_button.text, "19 errors, 2 warnings")
	main.free()
	TempTree.remove(ws)
	_cleanup()


## The index in [param panel] of the first finding at that target.
static func _find(panel: ProblemsPanel, target: Validator.Target, member := "", i := -1, key := "") -> int:
	for j in panel.findings.size():
		var f := panel.findings[j]
		if f.target == target and f.member == member and f.index == i and (key.is_empty() or f.key == key):
			return j
	return -1

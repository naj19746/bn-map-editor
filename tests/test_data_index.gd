extends "res://tests/support/test_case.gd"
## DataIndex, ModCatalog and CellText against small fake BN checkouts.

const TempTree := preload("res://tests/support/temp_tree.gd")


static func _mod(id: String, deps := ["bn"], extra := {}) -> Array:
	var info := {"type": "MOD_INFO", "id": id, "name": id, "dependencies": deps}
	info.merge(extra)
	return [info]


static func _ter(id: String, fields := {}) -> Dictionary:
	var t := {"type": "terrain", "id": id}
	t.merge(fields)
	return t


func _fake_bn() -> String:
	return TempTree.make({
		"data/mods/bn/modinfo.json": _mod("bn", [], {"core": true, "path": "../../json"}),
		"data/mods/mod_a/modinfo.json": _mod("mod_a", ["bn", "mod_b"]),
		"data/mods/mod_b/modinfo.json": _mod("mod_b"),
		"data/mods/nested/deeper/modinfo.json": _mod("deep", ["bn", "nowhere"]),
		"data/mods/in_path/modinfo.json": _mod("in_path", ["bn"], {"path": "content"}),
		"data/mods/in_path/content/t.json": [_ter("t_in_path", {"symbol": "p", "color": "red"})],
		# Core: t_child copies t_late, which only loads later (a subfolder).
		"data/json/a.json": [
			_ter("t_base", {"name": "base", "symbol": "#", "color": "white", "alias": ["t_old"]}),
			_ter("t_child", {"copy-from": "t_late", "color": ["red", "green", "blue", "cyan"]}),
			{"type": "terrain", "abstract": "t_abstract_wall", "symbol": "LINE_XOXO", "color": "brown"},
			_ter("t_wall", {"copy-from": "t_abstract_wall", "name": "wall"}),
			_ter("t_bg", {"copy-from": "t_base", "bgcolor": "i_blue"}),
			_ter("t_orphan", {"copy-from": "t_missing"}),
			{"type": "furniture", "id": "f_chair", "symbol": "h", "color": "brown"},
		],
		"data/json/b.json": {"type": "palette", "id": "pal_single_object", "terrain": {}},
		"data/json/sub/late.json": [
			_ter("t_late", {"name": "late", "symbol": "L", "color": "yellow"}),
			{"type": "item_group", "id": "ig_x", "items": []},
			{"type": "monstergroup", "name": "GROUP_X", "monsters": []},
		],
		# mod_b replaces t_base; mod_a's interaction files load only with mod_b.
		"data/mods/mod_b/b.json": [_ter("t_base", {"symbol": "B", "color": "white"})],
		"data/mods/mod_a/mod_interactions/mod_b/x.json": [
			{"type": "furniture", "id": "f_with_b", "symbol": "b", "color": "red"}],
		"data/mods/mod_a/mod_interactions/in_path/x.json": [
			{"type": "furniture", "id": "f_with_in_path", "symbol": "i", "color": "red"}],
	})


func test_catalog_and_load_order() -> void:
	var root := _fake_bn()
	var cat := ModCatalog.scan(root)
	check_eq(cat.core_ids(), PackedStringArray(["bn"]))
	check_eq(cat.get_mod("bn").path, root.path_join("data/json"))
	check_eq(cat.get_mod("in_path").path, root.path_join("data/mods/in_path/content"))
	check(cat.has("deep"), "modinfo.json found in a nested folder")

	var order := cat.load_order(PackedStringArray(["mod_a", "mod_b", "mod_a"]))
	check_eq(order.errors, PackedStringArray())
	check_eq(order.mods, PackedStringArray(["bn", "mod_b", "mod_a"]), "deps first, dupes dropped")
	check_eq(cat.load_order(PackedStringArray()).mods, PackedStringArray(["bn"]))

	var bad := cat.load_order(PackedStringArray(["deep", "nope"]))
	check_eq(bad.errors.size(), 2, "missing dependency + unknown mod: %s" % [bad.errors])
	TempTree.remove(root)


func test_copy_from_and_overrides() -> void:
	var root := _fake_bn()
	var index := DataIndex.load_bn(root)
	check_eq(index.mods, PackedStringArray(["bn"]))
	check_eq(index.errors.size(), 1, "only t_orphan fails: %s" % [index.errors])
	check(not index.terrain.has("t_orphan"))

	var child: DataIndex.TileDef = index.terrain.get("t_child")
	if check(child != null, "deferred copy-from resolved"):
		check_eq(child.symbol, PackedStringArray(["L", "L", "L", "L"]))
		check_eq(child.color, PackedStringArray(["red", "green", "blue", "cyan"]))
		check_eq(child.name, "late")
		check_eq(child.looks_like, "t_late")
		check_eq(child.source.path, "data/json/a.json")
		check_eq(child.source.index, 1)

	var wall: DataIndex.TileDef = index.terrain.get("t_wall")
	check_eq(wall.ascii(), "│", "LINE_XOXO from an abstract")
	check(not index.terrain.has("t_abstract_wall"), "abstracts aren't real ids")

	var bg: DataIndex.TileDef = index.terrain.get("t_bg")
	check_eq(bg.bgcolor, true)
	check_eq(bg.color[0], "i_blue")
	check_eq(bg.ascii(), "#")
	check(index.terrain.get("t_old") == index.terrain.get("t_base"), "alias")

	check_eq(index.palette("pal_single_object").source.path, "data/json/b.json")
	check(index.item_groups.has("ig_x"))
	check(index.monster_groups.has("GROUP_X"), "monstergroups use \"name\"")
	check(not index.furniture.has("f_with_b"), "interaction needs mod_b")
	TempTree.remove(root)


func test_mod_override_and_interactions() -> void:
	var root := _fake_bn()
	var index := DataIndex.load_bn(root, PackedStringArray(["mod_a", "in_path"]))
	check_eq(index.mods, PackedStringArray(["bn", "mod_b", "mod_a", "in_path"]))
	var base: DataIndex.TileDef = index.terrain.get("t_base")
	check_eq(base.ascii(), "B", "a later mod replaces the definition")
	check_eq(base.source.mod, "mod_b")
	check_eq(index.terrain["t_bg"].ascii(), "#", "copies made before the override keep theirs")
	check(index.furniture.has("f_with_b"))
	check(index.furniture.has("f_with_in_path"))
	check(index.terrain.has("t_in_path"), "modinfo \"path\" is followed")
	TempTree.remove(root)


func test_bfs_file_order() -> void:
	var root := TempTree.make({
		"d/b.json": "[]", "d/a.json": "[]", "d/z/a.json": "[]", "d/c/x.json": "[]",
		"d/c/y/q.json": "[]", "d/mod_interactions/m/i.json": "[]", "d/note.txt": "",
	})
	var files := DataIndex.data_files(root.path_join("d"))
	for i in files.size():
		files[i] = files[i].trim_prefix(root + "/d/")
	check_eq(files, PackedStringArray(["a.json", "b.json", "c/x.json", "z/a.json", "c/y/q.json"]))
	TempTree.remove(root)


func test_cell_split() -> void:
	check_eq(CellText.split_row("ab.#"), PackedStringArray(["a", "b", ".", "#"]))
	check_eq(CellText.split_row("│◌π"), PackedStringArray(["│", "◌", "π"]))
	# U+0331 (combining macron below) joins the char before it.
	check_eq(CellText.split_row("a̱b"), PackedStringArray(["a̱", "b"]))
	check_eq(CellText.split_row(""), PackedStringArray())
	check_eq(CellText.starts_cell(0x0331), false)
	check_eq(CellText.starts_cell(0x4E00), true)

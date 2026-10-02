extends "res://tests/support/test_case.gd"
## Stage 3 acceptance: edit real BN maps, save them to a temp workspace, and
## check that the diff against BN's original touches only the edited rows
## and the map's own "terrain"/"furniture" entries.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")

static var _core: DataIndex


func _core_index(workspace: String) -> DataIndex:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	# The workspace is empty, so the index is plain BN plus that folder.
	if _core == null:
		_core = DataIndex.load_bn(bn)
	_core.workspace_path = workspace
	return _core


## A symbol of [param doc] that isn't [param not_key] and has terrain.
static func _other_key(doc: MapDocument, not_key: String) -> String:
	for key in doc.resolved.used_keys():
		var info: ResolvedMapgen.SymbolInfo = doc.resolved.symbols.get(key)
		if key != not_key and info and info.terrain:
			return key
	return ""


## Edits [param id]'s map: paints [param cells] (one per row, so each edited
## row changes) with an existing symbol, adds a new symbol and paints it, then
## saves and checks the diff. [param notes] starts each problem the map has
## anyway (BN's own data), in order.
func _edit_and_check(id: String, cells: Array[Vector2i], notes := PackedStringArray()) -> void:
	var ws := TempTree.make({})
	var index := _core_index(ws)
	if index == null:
		return
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var ref: DataIndex.MapgenRef = index.mapgens_for(id)[0]
	var doc := session.open(ref)
	if not check(doc != null, session.last_error):
		return
	var rel := ref.source.path
	var bn_file := index.bn_path.path_join(rel)
	var bn_sha := FileAccess.get_sha256(bn_file)
	var before := BnJson.parse(FileAccess.get_file_as_string(bn_file)).value as Array

	var edited_rows := {}
	for i in cells.size() - 1:
		var p := cells[i]
		doc.paint([p], _other_key(doc, doc.resolved.key_at(p.x, p.y)))
		edited_rows[p.y] = true
	var key := doc.suggest_key("t_floor", "f_chair")
	check_eq(doc.add_symbol(key, "t_floor", "f_chair"), "")
	doc.paint([cells[-1]], key)
	edited_rows[cells[-1].y] = true
	var problems := doc.problems()
	check_eq(problems.size(), notes.size(), "no problems after editing but BN's own: %s" % problems)
	for i in mini(problems.size(), notes.size()):
		check(problems[i].begins_with(notes[i]), problems[i])
	check_eq(session.save(rel), "")
	check_eq(session.last_notes, PackedStringArray(), "nothing normalized")
	check_eq(FileAccess.get_sha256(bn_file), bn_sha, "BN's file is untouched")

	# Object level: only the edited object changed, and only in its rows and
	# own terrain/furniture.
	var saved_path := ws.path_join(rel)
	var after := BnJson.parse(FileAccess.get_file_as_string(saved_path)).value as Array
	check_eq(after.size(), before.size())
	for i in before.size():
		if i != ref.source.index:
			check_eq(BnJson.stringify(after[i]), BnJson.stringify(before[i]), "object %d unchanged" % i)
	var old_obj: Dictionary = before[ref.source.index].object
	var new_obj: Dictionary = after[ref.source.index].object
	for member: String in new_obj:
		if member in ["rows", "terrain", "furniture"]:
			continue
		check_eq(BnJson.stringify(new_obj[member]), BnJson.stringify(old_obj.get(member)), member)
	for y in old_obj.rows.size():
		check_eq(old_obj.rows[y] != new_obj.rows[y], edited_rows.has(y), "row %d changed?" % y)
	for member in ["terrain", "furniture"]:
		var old_defs: Dictionary = old_obj.get(member, {})
		var new_defs: Dictionary = new_obj.get(member, {})
		var expect := old_defs.duplicate()
		expect[key] = "t_floor" if member == "terrain" else "f_chair"
		check_eq(new_defs, expect, member + " gains exactly the new symbol")

	# Text level: every line of the diff is an edited row or inside the
	# object's terrain/furniture.
	var out := []
	OS.execute("diff", ["-U0", bn_file, saved_path], out, true)
	var lines := "".join(PackedStringArray(out)).split("\n")
	var row_text := {}
	for y: int in edited_rows:
		row_text[BnJson.encode_string(old_obj.rows[y])] = true
		row_text[BnJson.encode_string(new_obj.rows[y])] = true
	var changed := 0
	var stray := PackedStringArray()
	for l in lines:
		if l.begins_with("---") or l.begins_with("+++") or not (l.begins_with("-") or l.begins_with("+")):
			continue
		changed += 1
		var t := l.substr(1).strip_edges().trim_suffix(",")
		var is_def := t.begins_with("\"terrain\"") or t.begins_with("\"furniture\"") or t == "}" \
				or t.begins_with(BnJson.encode_string(key) + ":") or (t.ends_with("\"") and t.contains("\": \""))
		if not row_text.has(t) and not is_def:
			stray.append(l)
	check(changed > 0, "the diff isn't empty")
	check_eq(stray, PackedStringArray(), "diff lines outside the rows and terrain/furniture")
	TempTree.remove(ws)


## 2x2, no own terrain/furniture yet: both members get added.
func test_edit_apartments_tower() -> void:
	# The stairs above are 3 cells off (Stage 10c).
	_edit_and_check("apartments_mod_tower_NW",
			[Vector2i(3, 5), Vector2i(30, 30), Vector2i(40, 10), Vector2i(10, 44)],
			PackedStringArray(["note: in apartments_mod (1, 1, z 0): stairs up at (20, 12)"]))


## A 1x1 house that already has its own terrain and furniture.
func test_edit_house() -> void:
	_edit_and_check("house_01", [Vector2i(5, 5), Vector2i(12, 12), Vector2i(8, 20)])


## Stage 10d on core: a new level above 2Story02's roof goes into
## multitile_city_buildings.json; saved, every other object of that file and
## of the map's file is byte-identical, and BN's files are untouched.
func test_new_level_core() -> void:
	var ws := TempTree.make({})
	var index := _core_index(ws)
	if index == null:
		return
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var ref: DataIndex.MapgenRef = index.mapgens_for("2Story02_roof")[0]
	var place := BuildingLevels.places(index, ref)[0]
	check_eq(place.building.id, "2Story02")
	var b_rel := place.building.overmaps_source.path
	check_eq(b_rel, "data/json/overmap/multitile_city_buildings.json")
	var map_rel := ref.source.path
	var shas := {}
	var before := {}
	for rel in [b_rel, map_rel]:
		shas[rel] = FileAccess.get_sha256(index.bn_path.path_join(rel))
		before[rel] = BnJson.parse(FileAccess.get_file_as_string(index.bn_path.path_join(rel))).value
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = map_rel
	spec.ids = [PackedStringArray(["2Story02_attic_test"])] as Array[PackedStringArray]
	spec.fill_ter = "t_flat_roof"
	spec.level = EditSession.LevelTarget.new()
	spec.level.building = "2Story02"
	spec.level.origin = place.origin + Vector3i(0, 0, 1)
	spec.overmap_base = session.level_stub_base("2Story02", spec.level.origin, true)
	check_eq(spec.overmap_base, "generic_city_house_roof", "like the roof's")
	var doc := session.create_mapgen(spec)
	if not check(doc != null, session.last_error):
		TempTree.remove(ws)
		return
	check_eq(index.buildings["2Story02"].levels(), PackedInt32Array([-1, 0, 1, 2, 3]))
	check_eq(session.save_all(), PackedStringArray())
	for rel: String in shas:
		check_eq(FileAccess.get_sha256(index.bn_path.path_join(rel)), shas[rel], "BN's %s untouched" % rel)
	var after: Array = BnJson.parse(FileAccess.get_file_as_string(ws.path_join(b_rel))).value
	var old: Array = before[b_rel]
	check_eq(after.size(), old.size())
	var b_i := place.building.overmaps_source.index
	for i in old.size():
		if i != b_i:
			check_eq(BnJson.stringify(after[i]), BnJson.stringify(old[i]), "object %d unchanged" % i)
	var list: Array = after[b_i].overmaps
	check_eq(list.slice(0, -1), old[b_i].overmaps, "the old entries as they were")
	check_eq(list[-1], {"point": [0, 0, 3], "overmap": "2Story02_attic_test_north"})
	var maps: Array = BnJson.parse(FileAccess.get_file_as_string(ws.path_join(map_rel))).value
	check_eq(maps.size(), before[map_rel].size() + 2, "the map and its overmap_terrain appended")
	for i in before[map_rel].size():
		check_eq(BnJson.stringify(maps[i]), BnJson.stringify(before[map_rel][i]), "map file object %d unchanged" % i)
	check_eq(maps[-1].get("copy-from"), "generic_city_house_roof")
	# Saved, the level is in the workspace the index reads: load BN afresh
	# for later tests.
	_core = null
	TempTree.remove(ws)

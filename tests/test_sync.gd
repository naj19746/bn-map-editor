extends "res://tests/support/test_case.gd"
## Stage 3b: the Sync window (WorkspaceSync, SyncDialog). Pushes go into
## temp BN trees only.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")
const HOUSE := "data/json/mapgen/house.json"

var _root := ""
var _ws := ""
var _index: DataIndex
var _session: EditSession


func _setup() -> bool:
	var rows := []
	for y in 24:
		rows.append("#".repeat(24) if y == 0 or y == 23 else "#" + ".".repeat(22) + "#")
	_root = TempTree.make({
		"data/mods/bn/modinfo.json": [{"type": "MOD_INFO", "id": "bn", "core": true, "path": "../../json"}],
		"data/json/ter.json": [
			{"type": "terrain", "id": "t_floor", "symbol": ".", "color": "white"},
			{"type": "terrain", "id": "t_wall", "symbol": "#", "color": "white"},
			{"type": "terrain", "id": "t_grass", "symbol": ",", "color": "green"},
			{"type": "overmap_terrain", "abstract": "generic_city_building", "name": "city building"},
			{"type": "overmap_terrain", "id": ["house"], "name": "house"},
		],
		HOUSE: [
			{"type": "mapgen", "method": "json", "om_terrain": "house",
				"object": {"fill_ter": "t_grass", "rows": rows, "terrain": {"#": "t_wall", ".": "t_floor"}}},
			{"type": "item_group", "id": "stuff", "items": [["rock", 10]]},
		],
	})
	# TempTree writes JSON.stringify output; make BN's files formatter-clean,
	# as real BN files are, so a save only differs where it was edited.
	for rel in [HOUSE, "data/json/ter.json"]:
		var path := _root.path_join(rel)
		var text := JsonFormatter.format(BnJson.stringify(BnJson.parse(FileAccess.get_file_as_string(path)).value)).text
		_write(path, text)
	_ws = TempTree.make({})
	_reload()
	return true


## A fresh index and session over the same BN and workspace.
func _reload() -> void:
	_index = DataIndex.load_bn(_root, PackedStringArray(), null, _ws)
	check_eq(_index.errors, PackedStringArray(), "index errors")
	_session = EditSession.new(_index, Workspace.open(_ws, _root))


func _cleanup() -> void:
	TempTree.remove(_root)
	TempTree.remove(_ws)


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Opens house, paints a wall into the middle and saves it.
func _edit_house() -> MapDocument:
	var doc := _session.open(_index.mapgens_for("house")[0])
	if not check(doc != null, _session.last_error):
		return null
	doc.paint([Vector2i(5, 5)], "#")
	check_eq(_session.save(HOUSE), "", "save")
	return doc


func _sync() -> WorkspaceSync:
	return WorkspaceSync.new(_session.workspace)


func test_push_modified_file() -> void:
	if not _setup():
		return
	var doc := _edit_house()
	var sync := _sync()
	var list := sync.scan()
	check_eq(list.size(), 1)
	var s := list[0]
	check_eq(s.rel, HOUSE)
	check_eq(s.state, WorkspaceSync.State.MODIFIED)
	check(not s.is_conflict())
	check_eq(s.summary_text(), "1 changed")
	check_eq(str(s.changes[0]), "changed mapgen house")
	check_eq(s.unchanged, 1, "the item_group is unchanged")

	var saved := FileAccess.get_file_as_bytes(_ws.path_join(HOUSE))
	check_eq(sync.push(HOUSE), "")
	check_eq(FileAccess.get_file_as_bytes(_root.path_join(HOUSE)), saved, "BN has the workspace file")
	check(not FileAccess.file_exists(_ws.path_join(HOUSE)), "workspace copy deleted")
	check(not DirAccess.dir_exists_absolute(_ws.path_join("data")), "empty folders removed")
	check(not FileAccess.file_exists(_root.path_join(HOUSE) + WorkspaceSync.TEMP_SUFFIX), "no temp file left")
	check_eq(_session.workspace.files, {}, "manifest entry dropped")
	check_eq(Workspace.open(_ws, _root).files, {}, "manifest saved")
	check(sync.scan().is_empty(), "nothing left to sync")
	check_eq(_index.file_path(HOUSE), _root.path_join(HOUSE), "the index reads BN again")

	# The map stays open; its next save is based on BN's new file.
	_session.mark_pushed(HOUSE)
	check(not _session.is_dirty(HOUSE), "clean after the push")
	doc.paint([Vector2i(6, 6)], "#")
	check_eq(_session.save(HOUSE), "")
	check_eq(_session.workspace.files[HOUSE].get("base_sha256"), FileAccess.get_sha256(_root.path_join(HOUSE)),
			"new base is the pushed file")
	check_eq(sync.status(HOUSE).state, WorkspaceSync.State.MODIFIED)
	_cleanup()


## Stage 3b acceptance: BN's file changing after the base was recorded is a
## conflict, pushed only with overwrite.
func test_conflict_when_bn_changed() -> void:
	if not _setup():
		return
	_edit_house()
	var bn_file := _root.path_join(HOUSE)
	var theirs := FileAccess.get_file_as_string(bn_file).replace("\"rock\"", "\"stone\"")
	_write(bn_file, theirs)
	var sync := _sync()
	var s := sync.status(HOUSE)
	check_eq(s.state, WorkspaceSync.State.CHANGED_IN_BN)
	check(s.is_conflict())
	check_eq(s.summary_text(), "2 changed", "compared with BN as it is now")
	check(sync.push(HOUSE).contains("BN changed since the base"), "refused without overwrite")
	check_eq(FileAccess.get_file_as_string(bn_file), theirs, "BN untouched")
	check(FileAccess.file_exists(_ws.path_join(HOUSE)), "workspace copy kept")

	check_eq(sync.push(HOUSE, true), "", "overwrite")
	check_eq(FileAccess.get_file_as_string(bn_file).contains("stone"), false, "BN's change overwritten")
	check(not FileAccess.file_exists(_ws.path_join(HOUSE)))
	_cleanup()


func test_conflict_when_bn_deleted() -> void:
	if not _setup():
		return
	_edit_house()
	DirAccess.remove_absolute(_root.path_join(HOUSE))
	var s := _sync().status(HOUSE)
	check_eq(s.state, WorkspaceSync.State.DELETED_IN_BN)
	check(s.is_conflict())
	check_eq(s.summary_text(), "2 added")
	_cleanup()


func test_new_file() -> void:
	if not _setup():
		return
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/shed.json"
	spec.ids = EditSession.default_ids("shed", 1, 1)
	var doc := _session.create_mapgen(spec)
	if not check(doc != null, _session.last_error):
		return
	check_eq(_session.save(spec.rel_path), "")
	var sync := _sync()
	var s := sync.status(spec.rel_path)
	check_eq(s.state, WorkspaceSync.State.NEW)
	check_eq(s.summary_text(), "2 added", "the mapgen and its overmap_terrain")
	check_eq(str(s.changes[0]), "added mapgen shed")
	check_eq(str(s.changes[1]), "added overmap_terrain shed")
	check_eq(sync.push(spec.rel_path), "")
	check(FileAccess.file_exists(_root.path_join(spec.rel_path)), "created in BN")
	_session.mark_pushed(spec.rel_path)
	check(not _session.is_dirty(spec.rel_path), "a pushed new file isn't dirty")
	doc.paint([Vector2i(1, 1)], ".")
	check_eq(_session.save(spec.rel_path), "")
	check(not _session.workspace.files[spec.rel_path].get("new", false), "no longer new: BN has it")

	# A new file whose path BN has taken in the meantime.
	spec.rel_path = "data/json/mapgen/barn.json"
	spec.ids = EditSession.default_ids("barn", 1, 1)
	check(_session.create_mapgen(spec) != null, _session.last_error)
	check_eq(_session.save(spec.rel_path), "")
	_write(_root.path_join(spec.rel_path), "[]\n")
	s = sync.status(spec.rel_path)
	check_eq(s.state, WorkspaceSync.State.ADDED_IN_BN)
	check(s.is_conflict())
	_cleanup()


func test_same_untracked_missing() -> void:
	if not _setup():
		return
	var sync := _sync()
	# A copy identical to BN: pushing only drops it.
	_write(_ws.path_join(HOUSE), FileAccess.get_file_as_string(_root.path_join(HOUSE)))
	var s := sync.status(HOUSE)
	check_eq(s.state, WorkspaceSync.State.SAME)
	check(not s.is_conflict())
	var bn_time := FileAccess.get_modified_time(_root.path_join(HOUSE))
	check_eq(sync.push(HOUSE), "")
	check_eq(FileAccess.get_modified_time(_root.path_join(HOUSE)), bn_time, "BN not rewritten")
	check(not FileAccess.file_exists(_ws.path_join(HOUSE)))

	# A workspace file with no manifest entry, where BN has one: no base.
	_write(_ws.path_join(HOUSE), "[]\n")
	check_eq(sync.status(HOUSE).state, WorkspaceSync.State.UNTRACKED)
	check(sync.status(HOUSE).is_conflict())
	check_eq(sync.status(HOUSE).summary_text(), "2 removed")
	# ... and where BN has none: new.
	_write(_ws.path_join("data/json/extra.json"), "[]\n")
	check_eq(sync.status("data/json/extra.json").state, WorkspaceSync.State.NEW)

	# A manifest entry whose file is gone.
	sync.workspace.files["data/json/gone.json"] = {"new": true}
	var list := sync.scan()
	check_eq(list.map(func(x: WorkspaceSync.FileStatus) -> String: return x.rel),
			["data/json/extra.json", "data/json/gone.json", HOUSE], "sorted, manifest and files")
	check_eq(list[1].state, WorkspaceSync.State.MISSING)
	check(not list[1].can_push())
	check(sync.push("data/json/gone.json") != "", "nothing to push")
	check_eq(sync.remove_copy("data/json/gone.json"), "", "forget it")
	check(not sync.workspace.files.has("data/json/gone.json"))
	_cleanup()


func test_refuses_unsafe_paths() -> void:
	for rel in ["../x.json", "/etc/x.json", "data/../../x.json", "data//x.json", "C:/x.json", "data\\x.json", ""]:
		check(WorkspaceSync.check_rel(rel) != "", "refused: " + rel)
	check_eq(WorkspaceSync.check_rel("data/json/mapgen/x.json"), "")
	var root := TempTree.make({})
	var ws := TempTree.make({"x.json": "[]"})
	var workspace := Workspace.open(ws, root)
	workspace.files["../outside.json"] = {"new": true}
	var sync := WorkspaceSync.new(workspace)
	check(sync.push("../outside.json") != "", "a manifest path can't leave BN")
	check(not FileAccess.file_exists(root.get_base_dir().path_join("outside.json")))
	TempTree.remove(root)
	TempTree.remove(ws)


## Objects pair by key and occurrence, so weighted variants of one
## om_terrain line up; objects without an id are labelled by position.
func test_summary_pairs_objects() -> void:
	var a := "[{\"type\":\"mapgen\",\"om_terrain\":\"x\",\"weight\":1},{\"type\":\"mapgen\",\"om_terrain\":\"x\",\"weight\":2}," \
		+ "{\"type\":\"speech\",\"speaker\":\"a\"},{\"type\":\"monstergroup\",\"name\":\"GROUP_A\"}," \
		+ "{\"type\":\"mapgen\",\"om_terrain\":[[\"a_1\",\"a_2\"],[\"a_3\",\"a_4\"]]}]"
	var b := "[{\"type\":\"mapgen\",\"om_terrain\":\"x\",\"weight\":1},{\"type\":\"mapgen\",\"om_terrain\":\"x\",\"weight\":3}," \
		+ "{\"type\":\"speech\",\"speaker\":\"b\"},{\"type\":\"mapgen\",\"om_terrain\":[[\"a_1\",\"a_2\"],[\"a_3\",\"a_4\"]]}," \
		+ "{\"type\":\"terrain\",\"id\":\"t_new\",\"name\":{\"str\":\"new\"}}]"
	var s := WorkspaceSync.FileStatus.new()
	WorkspaceSync._summarize(s, a.to_utf8_buffer(), b.to_utf8_buffer())
	check_eq(s.changes.map(func(c: WorkspaceSync.ObjectChange) -> String: return str(c)), [
		"changed mapgen x (2nd)", "changed speech #3", "added terrain t_new", "removed monstergroup GROUP_A",
	])
	check_eq(s.unchanged, 2)
	check_eq(WorkspaceSync.object_id({"om_terrain": [["a", "b"], ["c", "d"]]}), "a ... d (4)")
	check_eq(WorkspaceSync.object_id({"name": {"str": "x"}}), "", "a translated name isn't an id")
	check_eq(WorkspaceSync.ordinal(2), "2nd")
	check_eq(WorkspaceSync.ordinal(13), "13th")
	check_eq(WorkspaceSync.ordinal(23), "23rd")

	var bad := WorkspaceSync.FileStatus.new()
	WorkspaceSync._summarize(bad, a.to_utf8_buffer(), "[{".to_utf8_buffer())
	check(bad.summary_error.begins_with("the workspace file doesn't parse"), bad.summary_error)


func test_sync_dialog() -> void:
	if not _setup():
		return
	_edit_house()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = "data/json/mapgen/shed.json"
	spec.ids = EditSession.default_ids("shed", 1, 1)
	var shed := _session.create_mapgen(spec)
	check_eq(_session.save(spec.rel_path), "")
	_write(_ws.path_join("data/json/other.json"), "[]\n")
	_write(_root.path_join("data/json/other.json"), "[{\"type\": \"x\"}]\n")
	shed.paint([Vector2i(2, 2)], "#")

	var dialog := SyncDialog.new()
	var changed := []
	dialog.files_changed.connect(func(reload: bool) -> void: changed.append(reload))
	dialog.setup(_session)
	var rows := {}
	for item in dialog.tree.get_root().get_children():
		rows[item.get_text(0)] = item
	check_eq(rows.size(), 3)
	check(rows[HOUSE].is_checked(0), "modified: checked")
	check(not rows["data/json/other.json"].is_checked(0), "conflict: unchecked")
	check(rows["data/json/other.json"].get_text(1).begins_with("conflict"))
	check(not rows[spec.rel_path].is_checked(0), "unsaved edits: not pushable")
	check(not rows[spec.rel_path].is_editable(0))
	check(rows[spec.rel_path].get_text(1).contains("save first"))
	check_eq(rows[HOUSE].get_text(2), "1 changed")

	rows[HOUSE].select(0)
	check(dialog.details.text.contains("changed mapgen house"), dialog.details.text)

	check_eq(dialog.push(PackedStringArray([spec.rel_path])).size(), 1, "dirty file refused")
	check_eq(dialog.push(PackedStringArray([HOUSE])), PackedStringArray())
	check_eq(changed, [false])
	check(not _session.workspace.files.has(HOUSE))
	check_eq(dialog.statuses.size(), 2, "list refreshed")
	check(dialog.discard(spec.rel_path).contains("open in the editor"), "open file can't be discarded")
	check_eq(dialog.discard("data/json/other.json"), "")
	check_eq(changed, [false, true])
	check(FileAccess.file_exists(_root.path_join("data/json/other.json")), "BN's file stays")
	check(not FileAccess.file_exists(_ws.path_join("data/json/other.json")))
	dialog.free()
	_cleanup()


## Stage 3b acceptance on real data: edit a real BN map, save it to a temp
## workspace, push into a temp copy of BN's file, and detect a conflict once
## that copy changes after the base was recorded.
func test_push_real_map_into_bn_copy() -> void:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return
	var ws := TempTree.make({})
	var index := DataIndex.load_bn(bn, PackedStringArray(), null, ws)
	var rel := index.mapgens_for("house_01")[0].source.path
	# The temp "BN" holds a byte copy of the real file, so the base recorded
	# from the real one matches it. Sync and the session write only there.
	var bn_copy := TempTree.make({rel: FileAccess.get_file_as_string(bn.path_join(rel))})
	var bn_sha := FileAccess.get_sha256(bn.path_join(rel))
	check_eq(FileAccess.get_sha256(bn_copy.path_join(rel)), bn_sha)
	var session := EditSession.new(index, Workspace.open(ws, bn_copy))
	var sync := WorkspaceSync.new(session.workspace)
	var doc := session.open(index.mapgens_for("house_01")[0])
	if not check(doc != null, session.last_error):
		return
	var p := Vector2i(3, 3)
	var key := ""
	for k in doc.resolved.used_keys():
		if k != doc.resolved.key_at(p.x, p.y) and doc.resolved.symbols.get(k) and doc.resolved.symbols[k].terrain:
			key = k
			break
	doc.paint([p], key)
	check_eq(session.save(rel), "")

	var s := sync.status(rel)
	check_eq(s.state, WorkspaceSync.State.MODIFIED)
	check_eq(s.changes.size(), 1, s.summary_text())
	if s.changes.size() == 1:
		check(s.changes[0].label.contains("house_01"), s.changes[0].label)
	check(s.unchanged > 0)
	var saved := FileAccess.get_file_as_bytes(ws.path_join(rel))
	check_eq(sync.push(rel), "")
	session.mark_pushed(rel)
	check_eq(FileAccess.get_file_as_bytes(bn_copy.path_join(rel)), saved, "pushed")
	check_eq(FileAccess.get_sha256(bn.path_join(rel)), bn_sha, "the real BN is untouched")

	# Edit and save again (new base: the pushed file), then BN's copy changes.
	doc.paint([p + Vector2i(1, 0)], key)
	check_eq(session.save(rel), "")
	check_eq(sync.status(rel).state, WorkspaceSync.State.MODIFIED)
	var f := FileAccess.open(bn_copy.path_join(rel), FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("\n")
	f.close()
	check_eq(sync.status(rel).state, WorkspaceSync.State.CHANGED_IN_BN, "conflict after BN changed")
	check(sync.push(rel) != "", "not pushed")
	TempTree.remove(bn_copy)
	TempTree.remove(ws)


## The Sync window through the main scene: push, then the tab and browser
## follow BN.
func test_main_scene_sync() -> void:
	if not _setup():
		return
	var main: Control = load("res://main.tscn").instantiate()
	main.auto_start = false
	main._ready()
	main._workspace_override = _ws
	main.load_index(_root)
	var m: Variant = main.open_id("house")
	if not check(m != null, "opened"):
		main.free()
		return
	var doc: MapDocument = m.doc
	doc.paint([Vector2i(4, 4)], "#")
	check_eq(main.save_current(), "")
	main._sync_dialog.setup(main.session)
	check_eq(main._sync_dialog.statuses.size(), 1)
	check_eq(main._sync_dialog.push(PackedStringArray([HOUSE])), PackedStringArray())
	check(main._status.text.begins_with("Pushed into"), main._status.text)
	check(not main.session.is_dirty(HOUSE), "still clean")
	check(not main._tabs.get_tab_title(0).ends_with(" *"))
	check(not main.index.in_workspace(HOUSE), "the browser shows BN's file")
	main.free()
	_cleanup()

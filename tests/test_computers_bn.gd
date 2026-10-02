extends "res://tests/support/test_case.gd"
## Stage 8 acceptance on core data: every core computer goes through the
## Computer model and back unchanged, police_station's consoles reach
## exactly their own doors, and editing one option of a real map changes
## only that option's line in the diff against BN.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")

static var _core: DataIndex


func _core_index() -> DataIndex:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return null
	if _core == null:
		_core = DataIndex.load_bn(bn)
	return _core


## Sets every field of [param c] to the value it already has.
static func _touch_all(c: Computer) -> void:
	c.set_name(c.name())
	c.set_access_denied(c.access_denied())
	c.set_security(c.security())
	c.set_target(c.target())
	var opts := c.options()
	for i in opts.size():
		var o := opts[i]
		var sec: Variant = o.get("security", 0)
		c.set_option(i, Computer._text(o.get("name")), str(o.get("action", "")), int(sec))
	for f in c.failures():
		c.set_failure(f, true)


func test_core_computers_round_trip() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var sources: Array = []
	for ref in index.mapgens:
		if ref.method == "json":
			sources.append(objects.object_for(ref).get("object", {}))
	for id: String in index.palettes:
		sources.append(index.palette(id).data)
	var n := 0
	var actions := {}
	for data: Dictionary in sources:
		for piece: Array in Validator.own_pieces(data):
			if piece[1] != "computers":
				continue
			for comp in Computer.all_in(piece[2]):
				n += 1
				var before := BnJson.stringify(comp)
				var c := Computer.of(comp.duplicate(true))
				_touch_all(c)
				check_eq(BnJson.stringify(c.data), before, "'%s' round trip" % piece[0])
				for issue: Array in c.issues():
					check(false, "'%s': %s" % [piece[0], issue[1]])
				for a in c.actions():
					actions[a] = actions.get(a, 0) + 1
	check_eq(n, 118, "computers in core")
	check_eq(actions.get("unlock", 0), 46)
	check_eq(actions.get("unlock_disarm", 0), 20)
	check_eq(actions.get("unlock_labpass", 0), 13)
	for a: String in actions:
		check(Computer.ACTIONS.has(a), "known action " + a)


func test_police_station_reach() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var ref: DataIndex.MapgenRef = index.mapgens_for("police")[0]
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(index, mapgen)
	var placements := Placement.read_all(mapgen, r.size)
	var consoles := Validator.console_cells(r, placements)
	var grids := Validator.tile_grids(r, ChunkOverlay.build(index, mapgen, r, objects.object_for), consoles)
	check_eq(consoles.size(), 2, "two consoles")
	var want := {"5": Vector2i(2, 11), "6": Vector2i(21, 6)}
	for at: Vector2i in consoles:
		var key: String = consoles[at][0]
		var reach := Validator.console_reach(index, r.size, grids, at, consoles[at][1])
		check(not reach.stands.is_empty(), key + " can be used")
		check_eq(Array(reach.targets.get("unlock")), [want[key]], "'%s' reaches its own door only" % key)
		# The barred cell doors and the plain locked doors are in reach, and
		# never open.
		check(not reach.other_locked.is_empty(), key + " has other locked doors nearby")


## The canvas's view of police "5" and "6": exactly the doors above, from
## every cell a player can stand next to each console.
func test_police_station_reach_view() -> void:
	var index := _core_index()
	if index == null:
		return
	var ws := TempTree.make({})
	var session := EditSession.new(index, Workspace.open(ws, BnEnv.bn_path()))
	var doc := session.open(index.mapgens_for("police")[0])
	var want := {"5": Vector2i(2, 11), "6": Vector2i(21, 6)}
	for key: String in want:
		var v := doc.reach_view(key)
		check_eq(v.consoles.size(), 1, key)
		print("     '%s' at %s: stands %s, %d cells in reach, other locked %s" % [key, v.consoles[0],
				v.stands.keys(), v.area.size(), v.other_locked.keys()])
		check_eq(v.targets, {want[key]: true}, "'%s' reaches its door from every stand cell" % key)
		for s: Vector2i in v.stands:
			check((s - v.consoles[0]).abs().x <= 1 and (s - v.consoles[0]).abs().y <= 1, "next to it")
			check(v.area.has(s), "a stand cell is in reach of itself")
	session.close(doc)
	TempTree.remove(ws)


func test_edit_one_option_diff() -> void:
	var index := _core_index()
	if index == null:
		return
	var ws := TempTree.make({})
	index.workspace_path = ws
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var ref: DataIndex.MapgenRef = index.mapgens_for("police")[0]
	var doc := session.open(ref)
	if not check(doc != null, session.last_error):
		return
	var data: Dictionary = doc.computer("5").duplicate(true)
	var c := Computer.of(data)
	c.set_option(0, "Unlock the Supply Room", "unlock", 0)
	check_eq(doc.set_computer("5", data), "")
	check_eq(doc.computer("5").options[0], {"name": "Unlock the Supply Room", "action": "unlock"})
	var rel := ref.source.path
	check_eq(session.save(rel), "")
	var out := []
	OS.execute("diff", ["-U0", index.bn_path.path_join(rel), ws.path_join(rel)], out, true)
	var changed := PackedStringArray()
	for l in "".join(PackedStringArray(out)).split("\n"):
		if (l.begins_with("-") or l.begins_with("+")) and not (l.begins_with("---") or l.begins_with("+++")):
			changed.append(l[0] + l.substr(1).strip_edges())
	check_eq(changed, PackedStringArray([
		"-\"options\": [ { \"name\": \"Unlock Supply Room\", \"action\": \"unlock\" } ],",
		"+\"options\": [ { \"name\": \"Unlock the Supply Room\", \"action\": \"unlock\" } ],",
	]))
	index.workspace_path = ""
	TempTree.remove(ws)


## Stage 8d: editing one option of a real palette's computer (school_palette
## '6') changes only that option's line of the palette's file.
func test_edit_palette_computer_diff() -> void:
	var index := _core_index()
	if index == null:
		return
	var ws := TempTree.make({})
	index.workspace_path = ws
	var session := EditSession.new(index, Workspace.open(ws, index.bn_path))
	var doc := session.open_palette(index.palette("school_palette"))
	if not check(doc != null, session.last_error):
		return
	var data: Dictionary = doc.computer("6").duplicate(true)
	Computer.of(data).set_option(2, "Emergency Bell", "toll", 0)
	var c := doc.build_set_computer("6", data)
	check_eq(session.impact_of(doc, c).size(), 1, "the one school map painting '6'")
	doc.commit(c)
	var rel := doc.file.rel_path
	check_eq(session.save(rel), "")
	var out := []
	OS.execute("diff", ["-U0", index.bn_path.path_join(rel), ws.path_join(rel)], out, true)
	var changed := PackedStringArray()
	for l in "".join(PackedStringArray(out)).split("\n"):
		if (l.begins_with("-") or l.begins_with("+")) and not (l.begins_with("---") or l.begins_with("+++")):
			changed.append(l[0] + l.substr(1).strip_edges())
	check_eq(changed, PackedStringArray([
		"-{ \"name\": \"Emergency Toll\", \"action\": \"toll\" }",
		"+{ \"name\": \"Emergency Bell\", \"action\": \"toll\" }",
	]))
	index.workspace_path = ""
	TempTree.remove(ws)


## Stage 8d: a lab's vault chunks (only in "else_chunks", placed by a chunk
## the map places) are judged in the map. Their consoles reach their doors
## in core, so their computer is swapped for one toggling shutters (none in
## reach) through the objects the overlay reads: every vault pick is named.
func test_core_vault_picks_judged() -> void:
	var index := _core_index()
	if index == null:
		return
	var objects := MapgenObjects.new(index)
	var shutters := {"name": "Shutters", "options": [{"name": "Toggle", "action": "shutters"}]}
	var swapped := func(ref: DataIndex.MapgenRef) -> Dictionary:
		var o := objects.object_for(ref)
		if ref.kind != DataIndex.MapgenRef.NESTED or not ref.ids[0].ends_with("_vault") or not ref.ids[0].begins_with("lab_"):
			return o
		var copy: Dictionary = o.duplicate(true)
		copy.object["computers"] = {"6": shutters}
		return copy
	var ref: DataIndex.MapgenRef = null
	for r in index.mapgens_for("lab_4side"):
		if r.source.path.ends_with("lab_floorplan_cross.json") and r.source.index == 0:
			ref = r
	if not check(ref != null, "lab_floorplan_cross.json #0"):
		return
	var mapgen := objects.object_for(ref)
	var r := MapgenResolver.resolve(index, mapgen)
	var found := Validator.validate_map(index, ref, mapgen, r, Placement.read_all(mapgen, r.size),
			ChunkOverlay.build(index, mapgen, r, swapped))
	var named := {}
	for f in found:
		if f.code == Validator.Code.CHUNK_CONSOLE:
			check_eq(f.target, Validator.Target.PLACEMENT)
			check(f.text.contains("\"shutters\" changes nothing"), f.text)
			for id in ["lab_n_vault", "lab_e_vault", "lab_s_vault", "lab_w_vault"]:
				if f.text.contains("> %s (else_chunks" % id):
					named[id] = true
	check_eq(named.size(), 4, "every vault named: %s" % [found.map(func(f: Validator.Finding) -> String: return f.text)])

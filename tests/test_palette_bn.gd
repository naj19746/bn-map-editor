extends "res://tests/support/test_case.gd"
## Stage 4 acceptance: edit a palette defined inside a mapgen file while maps
## from that file are open. The diff against BN touches only that palette's
## entry, the open maps using it redraw, the warning names exactly the maps a
## brute-force resolve of every map finds changed, and undo restores both.

const BnEnv := preload("res://tests/support/bn_env.gd")
const TempTree := preload("res://tests/support/temp_tree.gd")

const SCHOOL := "data/json/mapgen/school_1.json"
const THEATER := "data/json/mapgen/drive-in_theater.json"


static func _titles(affected: Array[PaletteImpact.Affected]) -> PackedStringArray:
	var out := PackedStringArray()
	for a in affected:
		out.append("%s#%d %s" % [a.ref.source.path, a.ref.source.index, " ".join(a.keys)])
	out.sort()
	return out


func _json_refs(index: DataIndex) -> Array[DataIndex.MapgenRef]:
	var out: Array[DataIndex.MapgenRef] = []
	for ref in index.mapgens:
		if ref.method == "json":
			out.append(ref)
	return out


## The first line (1-based) and last line of top-level object [param i] in
## [param text].
static func _object_lines(text: String, i: int) -> Vector2i:
	var r := BnJson.parse(text)
	var bytes := text.to_utf8_buffer()
	var start := bytes.slice(0, r.spans[i].x).get_string_from_utf8().count("\n") + 1
	var end := bytes.slice(0, r.spans[i].y).get_string_from_utf8().count("\n") + 1
	return Vector2i(start, end)


func test_edit_palette_in_mapgen_file() -> void:
	var bn := BnEnv.bn_path()
	if bn.is_empty():
		skip("no BN checkout (set BN_PATH)")
		return
	var ws := TempTree.make({})
	var index := DataIndex.load_bn(bn, PackedStringArray(), null, ws)
	var session := EditSession.new(index, Workspace.open(ws, bn))
	var school_def := index.palette("school_palette")
	var theater_def := index.palette("car_theater")
	if not check(school_def.source.path == SCHOOL and theater_def.source.path == THEATER, "palettes moved"):
		return

	# Open maps: three schools (school_4 doesn't use 'i') and an unrelated house.
	var open := {}
	for i in [0, 1, 3]:
		var ref: DataIndex.MapgenRef = null
		for r in index.mapgens:
			if r.source.path == SCHOOL and r.source.index == i:
				ref = r
		open[i] = session.open(ref)
	var house := session.open(index.mapgens_for("house_01")[0])
	var redrawn := {}
	for d: MapDocument in [open[0], open[1], open[3], house]:
		var on_changed := func(full: bool, title: String) -> void: redrawn[title] = full
		d.changed.connect(on_changed.bind(d.ref.title()))
	var school := session.open_palette(school_def)
	check(school.file == open[0].file, "shared JsonFile")
	var bn_text := FileAccess.get_file_as_string(bn.path_join(SCHOOL))
	var bn_sha := FileAccess.get_sha256(bn.path_join(SCHOOL))
	var original := school.file.compose()

	# Brute force: every json mapgen, before and after.
	var all := _json_refs(index)
	var brute := PaletteImpact.new(session)
	var t := Time.get_ticks_msec()
	var before := brute.capture(all)
	print("     brute-force resolve of %d mapgens in %d ms" % [all.size(), Time.get_ticks_msec() - t])

	# 1. school_palette 'i': linoleum gray -> white.
	var c := school.build_set_tiles("i", "t_linoleum_white", null)
	t = Time.get_ticks_msec()
	var warning := session.impact_of(school, c)
	print("     warning for school_palette in %d ms" % (Time.get_ticks_msec() - t))
	check_eq(school.tile_value("i", "terrain"), "t_linoleum_gray", "measuring doesn't apply")
	school.commit(c)
	var mid := brute.capture(all)
	check_eq(_titles(warning), _titles(PaletteImpact.diff(all, before, mid)), "warning = brute force")
	check_eq(warning.size(), 3, "school_1..3 use 'i'")
	check_eq(redrawn, {open[0].ref.title(): true, open[1].ref.title(): true, open[3].ref.title(): true},
			"open users redraw, the house doesn't")
	var cell := Vector2i(-1, -1)
	for y in open[0].resolved.size.y:
		var x: int = open[0].resolved.cells[y].find("i")
		if x >= 0:
			cell = Vector2i(x, y)
			break
	check_eq(open[0].resolved.terrain_at(cell.x, cell.y).id(), "t_linoleum_white", "the open map shows it")

	# Only the palette's object changed, and the diff stays inside it.
	check_eq(session.save(SCHOOL), "")
	check_eq(FileAccess.get_sha256(bn.path_join(SCHOOL)), bn_sha, "BN's file is untouched")
	var saved_text := FileAccess.get_file_as_string(ws.path_join(SCHOOL))
	var old_objects: Array = BnJson.parse(bn_text).value
	var new_objects: Array = BnJson.parse(saved_text).value
	for i in old_objects.size():
		if i != school_def.source.index:
			check_eq(BnJson.stringify(new_objects[i]), BnJson.stringify(old_objects[i]), "object %d" % i)
	var expect: Dictionary = old_objects[school_def.source.index].duplicate(true)
	expect.terrain["i"] = "t_linoleum_white"
	check_eq(BnJson.stringify(new_objects[school_def.source.index]), BnJson.stringify(expect), "just 'i'")
	var old_span := _object_lines(bn_text, school_def.source.index)
	var new_span := _object_lines(saved_text, school_def.source.index)
	var out := []
	OS.execute("diff", ["-U0", bn.path_join(SCHOOL), ws.path_join(SCHOOL)], out, true)
	var hunks := 0
	for l in "".join(PackedStringArray(out)).split("\n"):
		if not l.begins_with("@@"):
			continue
		hunks += 1
		# @@ -a[,n] +b[,m] @@
		var parts := l.split(" ")
		var a := int(parts[1].substr(1).split(",")[0])
		var b := int(parts[2].substr(1).split(",")[0])
		check(a >= old_span.x and a <= old_span.y and b >= new_span.x and b <= new_span.y,
				"hunk outside the palette: " + l)
	check_eq(hunks, 1, "one changed line")

	# 2. car_theater 'b', reached through car_theater_full's include and as
	# the second option of the big map's distribution.
	var theater := session.open_palette(theater_def)
	var c2 := theater.build_set_tiles("b", "t_pavement", null)
	var warning2 := session.impact_of(theater, c2)
	theater.commit(c2)
	var after := brute.capture(all)
	check_eq(_titles(warning2), _titles(PaletteImpact.diff(all, mid, after)), "warning = brute force (options)")
	check(_titles(warning2).size() >= 1 and _titles(warning2)[0].begins_with(THEATER + "#2 "), str(_titles(warning2)))

	# Undo restores the palette, the file and the open maps.
	school.undo()
	check_eq(open[0].resolved.terrain_at(cell.x, cell.y).id(), "t_linoleum_gray", "undo redraws")
	check(school.file.is_dirty(), "differs from the saved copy again")
	check_eq(school.file.compose(), original, "same text as BN's")
	theater.undo()
	check(not theater.file.is_dirty())
	check_eq(_titles(PaletteImpact.diff(all, before, brute.capture(all))), PackedStringArray(),
			"every map is back as it was")

	for d: MapDocument in [open[0], open[1], open[3], house]:
		session.close(d)
	session.close_palette(school)
	session.close_palette(theater)
	check_eq(index.palette("school_palette").data.terrain["i"], "t_linoleum_white",
			"discarded after saving: the index has the saved version")
	TempTree.remove(ws)

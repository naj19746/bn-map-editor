class_name McpTools
extends RefCounted
## The MCP server's tools: name -> description, input schema and handler.
##
## Handlers take the call's arguments and return a Dictionary (sent back as
## JSON text) or a Failure. They are plain methods, so tests call them
## directly. Everything goes through the editor's own classes: maps are
## opened in an EditSession (as the editor opens them), read with BnJson so
## ints stay ints, and judged by the Validator.
##
## The index loads on the first call that needs it ([member loader]), so
## initialize answers at once.

## Ids a list shows at most unless the call asks for more.
const DEFAULT_LIMIT := 50
const MAX_LIMIT := 1000
## Id kinds lookup_id takes: Validator.ID_KINDS plus palettes.
const PALETTE_KIND := "palette"


## A handler's error, sent as a tool result with isError set.
class Failure:
	var message := ""

	func _init(p_message: String) -> void:
		message = p_message


## Builds the session on first use: returns an EditSession, or a String
## saying why it couldn't.
var loader := Callable()
var session: EditSession
## Index load errors and the workspace problem, if any (list_mods shows them).
var load_errors := PackedStringArray()

var _tools := {}


func _init(p_loader := Callable()) -> void:
	loader = p_loader
	_add("search_maps", "Find mapgen entries by om_terrain / nested_mapgen_id / update_mapgen_id or file path " \
			+ "(case-insensitive substring; empty lists all). Returns each entry's ids, kind, file and object index; " \
			+ "pass id (+ variant) or file + index to the other map tools.", {
		"query": _string("Substring of an id or of the file path, e.g. 'house' or 'mapgen/lab'."),
		"kind": _enum("Only this kind of entry.", ["om_terrain", "nested", "update"]),
		"limit": _int("Entries returned at most (default %d)." % DEFAULT_LIMIT),
	}, [], search_maps)
	_add("get_map", "One mapgen: its raw rows, a legend saying what each symbol used in the rows places and " \
			+ "where that is defined (the map itself, fill_ter, or a palette and the palettes including it), its " \
			+ "placements (place_* and set entries, as written), the nested chunks it places, and an ASCII view " \
			+ "(terrain/furniture symbols as BN draws them, walls joined, chunks drawn over).",
			_map_props({
		"season": _enum("Season for the ASCII view (default spring).", ["spring", "summer", "autumn", "winter"]),
		"show_furniture": _bool("Draw furniture over terrain in the ASCII view (default true)."),
		"show_chunks": _bool("Draw the nested chunks the map places in the ASCII view (default true)."),
	}), [], get_map)
	_add("get_palette", "One palette: what each key it defines (itself or through the palettes it includes) " \
			+ "places and where, its includes, and its own JSON as written.", {
		"id": _string("The palette id."),
		"include_json": _bool("Include the palette's own JSON object (default true)."),
	}, ["id"], get_palette)
	_add("validate_map", "What BN would say about a mapgen when loading it: findings with severity (error: BN " \
			+ "won't load it, or reports it on every load; warning: BN silently skips something; note: works, " \
			+ "but oddly) and what each points at (a symbol, cell, placement or palette key).", _map_props({
		"include_palettes": _bool("Also check the palettes the map uses (default true)."),
	}), [], validate_map)
	_add("validate_palette", "What BN would say about a palette when loading it (see validate_map for severities).", {
		"id": _string("The palette id."),
		"include_includes": _bool("Also check the palettes it includes (default true)."),
	}, ["id"], validate_palette)
	_add("lookup_id", "Check or find ids BN knows (in the loaded mods): terrain, furniture, items, monsters, " \
			+ "groups, nested chunks, palettes, ... Returns whether the exact query is known and the ids containing it.", {
		"kind": _enum("The kind of id.", _kinds()),
		"query": _string("The id, or a substring of the ids to list (case-insensitive)."),
		"limit": _int("Ids returned at most (default %d)." % DEFAULT_LIMIT),
	}, ["kind"], lookup_id)
	_add("list_mods", "The mods in the BN checkout, which are loaded and in what order, and any load errors. " \
			+ "The loaded set is fixed for the session (the server's --mods argument).", {}, [], list_mods)
	_add("sync_status", "The workspace (where edits are saved; never the BN checkout): each file's state against " \
			+ "BN (new, modified, conflict, ...) and which objects differ, plus files with unsaved edits. " \
			+ "Pushing into BN is done by a person in the editor's Sync window.", {}, [], sync_status)


## Loads BN at [param bn_path] (core plus [param mods]) with the workspace
## at [param workspace_root] layered on top, as the editor does: an
## EditSession, or a String saying why not.
static func load_session(bn_path: String, mods: PackedStringArray, workspace_root: String) -> Variant:
	if bn_path.is_empty() or not DirAccess.dir_exists_absolute(bn_path.path_join("data/json")):
		return "no BN checkout at \"%s\" (pass --bn or set BN_PATH)" % bn_path
	var ws_problem := Workspace.check_root(workspace_root, bn_path)
	var index := DataIndex.load_bn(bn_path, mods, null, "" if ws_problem else workspace_root)
	return EditSession.new(index, Workspace.open(workspace_root, bn_path))


# --- Registry ------------------------------------------------------------------

func _add(name: String, description: String, props: Dictionary, required: Array, handler: Callable) -> void:
	var schema := {"type": "object", "properties": props, "additionalProperties": false}
	if not required.is_empty():
		schema["required"] = required
	_tools[name] = {"name": name, "description": description, "inputSchema": schema, "handler": handler}


## tools/list's "tools": name, description and inputSchema of each.
func list() -> Array:
	var out := []
	for name: String in _tools:
		var t: Dictionary = _tools[name]
		out.append({"name": name, "description": t.description, "inputSchema": t.inputSchema})
	return out


func has(name: String) -> bool:
	return _tools.has(name)


## Runs tool [param name] with [param args]: its result or a Failure.
func call_tool(name: String, args: Dictionary) -> Variant:
	var problem := _check_args(_tools[name].inputSchema, args)
	if problem:
		return Failure.new(problem)
	return _tools[name].handler.call(args)


## Why [param args] don't fit [param schema], or "". Checks the member
## names, required members and the simple types used here.
static func _check_args(schema: Dictionary, args: Dictionary) -> String:
	var props: Dictionary = schema.properties
	for k: String in args:
		if not props.has(k):
			return "Unknown argument \"%s\" (takes: %s)." % [k, ", ".join(PackedStringArray(props.keys()))]
		var v: Variant = args[k]
		var ok := true
		match props[k].type:
			"string": ok = v is String and (not props[k].has("enum") or props[k].enum.has(v))
			"integer": ok = v is int or (v is float and v == floorf(v))
			"boolean": ok = v is bool
		if not ok:
			return "\"%s\" must be %s." % [k, "one of " + ", ".join(props[k].enum) if props[k].has("enum") \
					else {"string": "a string", "integer": "an integer", "boolean": "true or false"}[props[k].type]]
	for k: String in schema.get("required", []):
		if not args.has(k):
			return "Missing argument \"%s\"." % k
	return ""


static func _string(description: String) -> Dictionary:
	return {"type": "string", "description": description}


static func _int(description: String) -> Dictionary:
	return {"type": "integer", "description": description}


static func _bool(description: String) -> Dictionary:
	return {"type": "boolean", "description": description}


static func _enum(description: String, values: Array) -> Dictionary:
	return {"type": "string", "description": description, "enum": values}


## The arguments naming a map, plus [param extra].
static func _map_props(extra: Dictionary) -> Dictionary:
	var props := {
		"id": _string("An om_terrain / nested_mapgen_id / update_mapgen_id."),
		"variant": _int("Which of the id's mapgen entries (0-based, as search_maps lists them; default 0)."),
		"file": _string("Instead of id: the file, relative to the BN checkout (as search_maps gives it)."),
		"index": _int("With file: the object's index in the file's top-level array."),
	}
	props.merge(extra)
	return props


static func _kinds() -> Array:
	var out: Array = Validator.ID_KINDS.keys()
	out.append(PALETTE_KIND)
	return out


# --- Shared --------------------------------------------------------------------

## The session, loaded on first use; null when loading failed (see load_errors).
func _session() -> EditSession:
	if session == null and loader.is_valid():
		var got: Variant = loader.call()
		loader = Callable()
		if got is EditSession:
			session = got
			load_errors = session.index.errors.duplicate()
			if session.workspace.error:
				load_errors.append(session.workspace.error)
			var ws_problem := Workspace.check_root(session.workspace.root, session.index.bn_path)
			if ws_problem:
				load_errors.append("workspace unusable: " + ws_problem)
		else:
			load_errors.append(str(got))
	return session


func _no_session() -> Failure:
	return Failure.new("No BN data loaded: %s" % ("; ".join(load_errors) if load_errors.size() else "no loader"))


## The mapgen [param args] name (id + variant, or file + index), or a Failure.
func _find_ref(args: Dictionary) -> Variant:
	var index := session.index
	if args.has("file"):
		if not args.has("index"):
			return Failure.new("Pass \"index\" with \"file\".")
		for ref in index.mapgens:
			if ref.source.path == args.file and ref.source.index == int(args.index):
				return ref
		return Failure.new("No mapgen at %s #%d." % [args.file, int(args.index)])
	if not args.has("id"):
		return Failure.new("Pass \"id\" (or \"file\" and \"index\").")
	var refs := index.mapgens_for(args.id)
	if refs.is_empty():
		return Failure.new("No mapgen for \"%s\"; search_maps finds ids." % args.id)
	var v := int(args.get("variant", 0))
	if v < 0 or v >= refs.size():
		return Failure.new("\"%s\" has %d mapgen entries (variant 0-%d)." % [args.id, refs.size(), refs.size() - 1])
	return refs[v]


## How search results and map headers name [param ref].
func _ref_info(ref: DataIndex.MapgenRef) -> Dictionary:
	var index := session.index
	var variants := index.mapgens_for(ref.title())
	var info := {
		"ids": Array(ref.ids),
		"kind": {DataIndex.MapgenRef.OM_TERRAIN: "om_terrain", DataIndex.MapgenRef.NESTED: "nested",
			DataIndex.MapgenRef.UPDATE: "update"}[ref.kind],
		"file": ref.source.path,
		"index": ref.source.index,
		"mod": ref.source.mod,
	}
	if variants.size() > 1:
		info["variant"] = variants.find(ref)
		info["variants"] = variants.size()
	if not ref.grid.is_empty():
		info["omt_grid"] = ref.grid.map(func(row: PackedStringArray) -> Array: return Array(row))
	if ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		info["mapgensize"] = [ref.chunk_size.x, ref.chunk_size.y]
	if ref.weight != 1000:
		info["weight"] = ref.weight
	if ref.method != "json":
		info["method"] = ref.method
	if ref.disabled:
		info["disabled"] = true
	if index.in_workspace(ref.source.path):
		info["in_workspace"] = true
	return info


## The palette definition BN uses for [param id], or a Failure.
func _find_palette(id: String) -> Variant:
	var def := session.index.palette(id)
	if def == null:
		return Failure.new("No palette \"%s\"; lookup_id with kind \"palette\" finds ids." % id)
	return def


## Points the index's definitions of [param ids] and the palettes they
## include at their objects read with BnJson (the index reads with Godot's
## JSON, where 30 becomes 30.0), so what a map resolves to shows values as
## written. An open palette's definition already is its live object.
func _exact_palettes(ids: PackedStringArray) -> void:
	for id in session.index.palette_closure(ids):
		var def := session.index.palette(id)
		if def and session.palette_doc_for(def) == null:
			def.data = _palette_object(def)


## [param def]'s object as the file has it (read with BnJson: ints stay
## ints), or its index data if the file can't be read.
func _palette_object(def: DataIndex.Definition) -> Dictionary:
	var doc := session.palette_doc_for(def)
	if doc:
		return doc.palette()
	var f := session.get_file(def.source.path)
	if f and def.source.index < f.objects.size() and f.objects[def.source.index] is Dictionary:
		return f.objects[def.source.index]
	return def.data


static func _binding(b: ResolvedMapgen.Binding) -> Dictionary:
	var out := {"value": b.value, "from": b.source_label()}
	if b.ids.size() > 1 or (b.ids.size() == 1 and not b.value is String):
		out["ids"] = Array(b.ids)
	return out


## What [param info] places: terrain and furniture in effect, and every
## other mapping kind's pieces (these all apply).
static func _symbol(info: ResolvedMapgen.SymbolInfo) -> Dictionary:
	var out := {}
	if info.terrain:
		out["terrain"] = _binding(info.terrain)
	elif info.null_terrain:
		out["terrain"] = {"value": "t_null", "note": "t_null: the cell keeps what was there"}
	if info.furniture:
		out["furniture"] = _binding(info.furniture)
	for kind: String in info.extras:
		out[kind] = info.extras[kind].map(_binding)
	return out


static func _finding(f: Validator.Finding) -> Dictionary:
	var out := {
		"severity": f.severity_name(),
		"code": Validator.Code.keys()[f.code],
		"text": f.text,
		"reaction": f.reaction(),
	}
	if f.severity == Validator.Severity.ERROR:
		out["wont_load"] = f.load_fails
	match f.target:
		Validator.Target.SYMBOL:
			out["symbol"] = f.key
		Validator.Target.CELL:
			out["cell"] = [f.cell.x, f.cell.y]
		Validator.Target.PLACEMENT:
			out["placement"] = {"member": f.member, "index": f.index}
		Validator.Target.PALETTE_KEY:
			out["palette"] = f.palette
			if f.key:
				out["symbol"] = f.key
	return out


static func _findings(list: Array[Validator.Finding]) -> Dictionary:
	var n := Validator.count(list)
	return {
		"errors": n[0], "warnings": n[1], "notes": n[2],
		"findings": list.map(_finding),
	}


static func _limit(args: Dictionary) -> int:
	return clampi(int(args.get("limit", DEFAULT_LIMIT)), 1, MAX_LIMIT)


# --- search_maps / get_map -----------------------------------------------------

func search_maps(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var query: String = args.get("query", "").strip_edges().to_lower()
	var kind: String = {"om_terrain": DataIndex.MapgenRef.OM_TERRAIN, "nested": DataIndex.MapgenRef.NESTED,
		"update": DataIndex.MapgenRef.UPDATE}.get(args.get("kind", ""), "")
	var limit := _limit(args)
	var maps := []
	var total := 0
	for ref in session.index.mapgens:
		if kind and ref.kind != kind:
			continue
		if query and not _matches(ref, query):
			continue
		total += 1
		if maps.size() < limit:
			maps.append(_ref_info(ref))
	return {"total": total, "shown": maps.size(), "maps": maps}


static func _matches(ref: DataIndex.MapgenRef, query: String) -> bool:
	if ref.source.path.to_lower().contains(query):
		return true
	for id in ref.ids:
		if id.to_lower().contains(query):
			return true
	return false


## Opens the map [param args] name for editing (or returns the open one).
func _open(args: Dictionary) -> Variant:
	var ref: Variant = _find_ref(args)
	if ref is Failure:
		return ref
	_exact_palettes(ref.palettes)
	var doc := session.open(ref)
	if doc == null:
		return Failure.new(session.last_error)
	return doc


func get_map(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _open(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var r := doc.resolved
	var obj := doc.object()
	var out := _ref_info(doc.ref)
	out["size"] = [r.size.x, r.size.y]
	if r.fill_ter:
		out["fill_ter"] = r.fill_ter
	if obj.has("palettes"):
		out["palettes"] = obj.palettes
	if not r.choices.is_empty():
		out["palette_choices"] = Array(r.choices)
	out["rows"] = obj.get("rows")
	var legend := {}
	var fill := r.fill_binding()
	for key in r.used_keys():
		var info: ResolvedMapgen.SymbolInfo = r.symbols.get(key)
		if info == null and not key in ["", " ", "."]:
			legend[key] = {"undefined": true}
			continue
		var sym := _symbol(info) if info else {}
		if not sym.has("terrain") and fill:
			sym = {"terrain": _binding(fill)}.merged(sym)
		if sym.is_empty():
			sym["note"] = "places nothing: the cell stays as it was"
		legend[key] = sym
	out["legend"] = legend
	var unused := PackedStringArray()
	for key in doc.own_keys():
		if not legend.has(key):
			unused.append(key)
	if not unused.is_empty():
		out["own_symbols_not_in_rows"] = Array(unused)
	var placements := []
	for p in doc.placements():
		var e := {"member": p.member, "index": p.index, "entry": p.entry}
		if p.status != Placement.Status.OK:
			e["status"] = Placement.Status.keys()[p.status].to_lower()
		if not p.problems.is_empty():
			e["problems"] = Array(p.problems)
		placements.append(e)
	out["placements"] = placements
	var overlay := doc.chunk_overlay()
	var chunks := []
	for s in overlay.stamps:
		var c := {"chunk": s.chunk_id if s.chunk_id else null, "at": [s.anchor.position.x, s.anchor.position.y],
			"by": "'%s' nested mapping" % s.key if s.member == "nested" else "place_nested #%d" % s.index}
		if s.depth > 0:
			c["depth"] = s.depth
		chunks.append(c)
	if not chunks.is_empty():
		out["chunks"] = chunks
	var season: int = ["spring", "summer", "autumn", "winter"].find(args.get("season", "spring"))
	var ascii := AsciiMap.build(session.index, r, season, args.get("show_furniture", true),
			overlay if args.get("show_chunks", true) else null)
	var lines := []
	for y in ascii.size.y:
		lines.append("".join(ascii.chars.slice(y * ascii.size.x, (y + 1) * ascii.size.x)))
	out["ascii"] = lines
	var n := Validator.count(doc.findings())
	out["problems"] = {"errors": n[0], "warnings": n[1], "notes": n[2]}
	out["dirty"] = session.is_dirty(doc.file.rel_path)
	return out


# --- get_palette ---------------------------------------------------------------

func get_palette(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _find_palette(args.id)
	if got is Failure:
		return got
	var def: DataIndex.Definition = got
	var data := _palette_object(def)
	_exact_palettes(PackedStringArray([def.id]))
	var out := {"id": def.id, "file": def.source.path, "index": def.source.index, "mod": def.source.mod}
	var defs: Array = session.index.palettes.get(def.id, [])
	if defs.size() > 1:
		out["replaces"] = defs.slice(0, -1).map(func(d: DataIndex.Definition) -> String: return str(d.source))
	var includes := DataIndex.palette_options(data)
	if not includes.is_empty():
		out["includes"] = Array(includes)
	# Read as if it were a chunk: its own keys come out as "map".
	var view := MapgenResolver.resolve(session.index, {"nested_mapgen_id": def.id, "object": data})
	var keys := {}
	var sorted: Array = view.symbols.keys()
	sorted.sort()
	for key: String in sorted:
		var sym := _symbol(view.symbols[key])
		for kind: String in sym:
			for b: Dictionary in (sym[kind] if sym[kind] is Array else [sym[kind]]):
				if b.get("from") == ResolvedMapgen.SOURCE_MAP:
					b["from"] = "this palette"
		keys[key] = sym
	out["keys"] = keys
	if not view.problems.is_empty():
		out["problems"] = Array(view.problems)
	if args.get("include_json", true):
		out["json"] = data
	return out


# --- validate_map / validate_palette -------------------------------------------

func validate_map(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var ref: Variant = _find_ref(args)
	if ref is Failure:
		return ref
	var with_palettes: bool = args.get("include_palettes", true)
	var list: Array[Validator.Finding]
	var doc := _open_doc(ref)
	if doc:
		list = doc.findings(with_palettes)
	elif ref.method != "json":
		return Failure.new("%s is a %s mapgen; only json mapgen is checked." % [ref.title(), ref.method])
	else:
		list = map_findings(session, ref, with_palettes)
	var out := _ref_info(ref)
	out.merge(_findings(list))
	return out


## The open document of [param ref], or null.
func _open_doc(ref: DataIndex.MapgenRef) -> MapDocument:
	for d in session.docs:
		if d.ref == ref:
			return d
	return null


## Findings for [param ref] without opening it, as MapDocument.findings()
## would give them; files open in [param s] are read live.
static func map_findings(s: EditSession, ref: DataIndex.MapgenRef, with_palettes := true) -> Array[Validator.Finding]:
	var index := s.index
	var mapgen := s.objects.object_for(ref)
	var resolved := MapgenResolver.resolve(index, mapgen)
	var placements := Placement.read_all(mapgen, resolved.size)
	var overlay := ChunkOverlay.build(index, mapgen, resolved, s.objects.object_for)
	var out := Validator.validate_map(index, ref, mapgen, resolved, placements, overlay)
	var obj: Variant = mapgen.get("object")
	if with_palettes and not ref.disabled and obj is Dictionary:
		out.append_array(Validator.validate_palettes(index, DataIndex.palette_options(obj)))
	return Validator.sorted(out)


func validate_palette(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _find_palette(args.id)
	if got is Failure:
		return got
	var def: DataIndex.Definition = got
	var list := Validator.validate_palette(session.index, def.id, _palette_object(def))
	if args.get("include_includes", true):
		var includes := session.index.palette_closure(DataIndex.palette_options(_palette_object(def)))
		includes.erase(def.id)
		for id in includes:
			var inc := session.index.palette(id)
			if inc:
				list.append_array(Validator.validate_palette(session.index, id, inc.data))
	var out := {"id": def.id, "file": def.source.path}
	out.merge(_findings(Validator.sorted(list)))
	return out


# --- lookup_id -----------------------------------------------------------------

func lookup_id(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var index := session.index
	var kind: String = args.kind
	var query: String = args.get("query", "").strip_edges()
	var candidates: PackedStringArray
	var known: bool
	if kind == PALETTE_KIND:
		candidates = PackedStringArray(index.palettes.keys())
		candidates.sort()
		known = index.palettes.has(query)
	else:
		candidates = Validator.id_candidates(index, kind)
		known = Validator.is_known(index, kind, query)
	var low := query.to_lower()
	var limit := _limit(args)
	var ids := []
	var total := 0
	for id in candidates:
		if low and not id.to_lower().contains(low):
			continue
		total += 1
		if ids.size() < limit:
			ids.append(_id_info(kind, id))
	var out := {"kind": kind, "total": total, "shown": ids.size(), "ids": ids}
	if query:
		out = {"query": query, "known": known}.merged(out)
	return out


## An id, with its name and symbol for terrain and furniture.
func _id_info(kind: String, id: String) -> Variant:
	var table: Dictionary = {"terrain": session.index.terrain, "furniture": session.index.furniture}.get(kind, {})
	var def: DataIndex.TileDef = table.get(id)
	if def == null:
		return id
	return {"id": id, "name": def.name, "symbol": def.ascii()}


# --- list_mods / sync_status ---------------------------------------------------

func list_mods(_args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var index := session.index
	var mods := []
	var ids: Array = index.catalog.mods.keys()
	ids.sort()
	for id: String in ids:
		var m: ModCatalog.ModInfo = index.catalog.mods[id]
		var e := {"id": id, "name": m.name, "path": index.relative_path(m.path)}
		if m.core:
			e["core"] = true
		if m.obsolete:
			e["obsolete"] = true
		if not m.dependencies.is_empty():
			e["dependencies"] = Array(m.dependencies)
		var at := index.mods.find(id)
		if at >= 0:
			e["loaded"] = at
		mods.append(e)
	var out := {"bn_path": index.bn_path, "loaded": Array(index.mods), "mods": mods}
	if not load_errors.is_empty():
		out["load_errors"] = Array(load_errors)
	return out


func sync_status(_args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var ws := session.workspace
	var files := []
	for s in WorkspaceSync.new(ws).scan():
		var e := {"file": s.rel, "state": s.text(), "summary": s.summary_text()}
		if s.is_conflict():
			e["conflict"] = true
		if not s.changes.is_empty():
			e["changes"] = s.changes.map(func(c: WorkspaceSync.ObjectChange) -> String: return str(c))
		files.append(e)
	var out := {"workspace": ws.root, "files": files, "unsaved": Array(session.dirty_files())}
	if session.index.workspace_path.is_empty():
		out["note"] = "The workspace isn't layered over BN: nothing can be saved (%s)." % "; ".join(load_errors)
	return out

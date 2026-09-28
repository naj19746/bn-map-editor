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
## The edit tools change the open maps in memory (each call one undo step)
## and save writes files to the workspace, as the editor saves: never into
## BN. The editor may have the same workspace open, so a save refuses to
## overwrite a file that changed on disk since it was read (reload re-reads).
## Before each call the session looks for such changes
## (EditSession.external_changes): with no unsaved edits it reloads and the
## answer says "reloaded"; with some, the answer carries a "disk_warning".
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


## Builds the session on first use (and again on reload): returns an
## EditSession, or a String saying why it couldn't.
var loader := Callable()
var session: EditSession
## Index load errors and the workspace problem, if any (list_mods shows them).
var load_errors := PackedStringArray()

var _tools := {}
var _load_tried := false


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
			+ "placements (place_* and set entries, as written), the nested chunks it places, an ASCII view " \
			+ "(terrain/furniture symbols as BN draws them, walls joined, chunks drawn over), and for an " \
			+ "om_terrain map its levels: each building placing it, where and turned how, with the tiles " \
			+ "above and below it and the mapgens drawing them (get_building has every level).",
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
	_add_edit_tools()
	_add_placement_tools()
	_add_level_tools()
	_add_palette_tools()


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
	var disk := _check_disk() if name != "reload" else {}
	var out: Variant = _tools[name].handler.call(args)
	if disk.is_empty():
		return out
	if out is Dictionary:
		out.merge(disk)
	elif out is Failure:
		out.message += " (%s)" % (("reloaded first: %s changed on disk" % ", ".join(disk.reloaded)) \
				if disk.has("reloaded") else disk.disk_warning)
	return out


## Files another program (the editor) changed since the session read them:
## with no unsaved edits, loads again ({"reloaded": files}); else
## {"disk_warning": text}, once per change. {} when nothing changed.
func _check_disk() -> Dictionary:
	if session == null:
		return {}
	var changed := session.external_changes()
	if changed.is_empty():
		return {}
	var dirty := session.dirty_files()
	if dirty.is_empty():
		session = null
		load_errors = PackedStringArray()
		_load_tried = false
		_session()
		return {"reloaded": Array(changed)}
	session.accept_external()
	return {"disk_warning": ("%s changed on disk (saved by the editor?) while %s ha%s unsaved edits here: " \
			+ "saving a changed file is refused; reload with discard: true to take the disk's version.") % [
				", ".join(changed), ", ".join(dirty), "s" if dirty.size() == 1 else "ve"]}


## Why [param args] don't fit [param schema], or "". Checks the member
## names, required members and the simple types used here.
static func _check_args(schema: Dictionary, args: Dictionary) -> String:
	var props: Dictionary = schema.properties
	for k: String in args:
		if not props.has(k):
			return "Unknown argument \"%s\" (takes: %s)." % [k, ", ".join(PackedStringArray(props.keys()))]
		var type: String = props[k].get("type", "")
		var ok: bool = _is_type(args[k], type) and (not props[k].has("enum") or props[k].enum.has(args[k]))
		if ok and type == "array" and props[k].has("items"):
			var item_type: String = props[k].items.type
			ok = args[k].all(func(e: Variant) -> bool: return _is_type(e, item_type))
			type = "list of " + {"string": "strings", "integer": "integers", "array": "lists"}[item_type]
		if not ok:
			return "\"%s\" must be %s." % [k, "one of " + ", ".join(props[k].enum) if props[k].has("enum") \
					else {"string": "a string", "integer": "an integer", "boolean": "true or false",
						"array": "a list", "object": "an object"}.get(type, "a " + type)]
	for k: String in schema.get("required", []):
		if not args.has(k):
			return "Missing argument \"%s\"." % k
	return ""


## True when [param v] fits JSON schema type [param type] ("" is any).
static func _is_type(v: Variant, type: String) -> bool:
	match type:
		"string": return v is String
		"integer": return v is int or (v is float and v == floorf(v))
		"boolean": return v is bool
		"array": return v is Array
		"object": return v is Dictionary
	return true


static func _string(description: String) -> Dictionary:
	return {"type": "string", "description": description}


static func _int(description: String) -> Dictionary:
	return {"type": "integer", "description": description}


static func _bool(description: String) -> Dictionary:
	return {"type": "boolean", "description": description}


static func _enum(description: String, values: Array) -> Dictionary:
	return {"type": "string", "description": description, "enum": values}


## A list; [param item_type] checks each element's type ("" for any).
static func _array(description: String, item_type := "") -> Dictionary:
	var out := {"type": "array", "description": description}
	if item_type:
		out["items"] = {"type": item_type}
	return out


static func _object(description: String) -> Dictionary:
	return {"type": "object", "description": description}


## Any JSON value (null included).
static func _any(description: String) -> Dictionary:
	return {"description": description}


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
	if session == null and loader.is_valid() and not _load_tried:
		_load_tried = true
		var got: Variant = loader.call()
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
	if f.building:
		out["building"] = f.building
	if not f.levels.is_empty():
		# The other levels a stair or elevator finding is about, to open.
		out["other_levels"] = f.levels.map(func(r: DataIndex.MapgenRef) -> Dictionary:
			return {"file": r.source.path, "index": r.source.index, "map": r.title()})
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
	return _map_view(got, args)


## What get_map answers for [param doc]; [param args] has the view options.
func _map_view(doc: MapDocument, args: Dictionary) -> Dictionary:
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
	if doc.ref.kind == DataIndex.MapgenRef.OM_TERRAIN:
		out["levels"] = _levels(doc.ref)
	out["dirty"] = session.is_dirty(doc.file.rel_path)
	var stale := session.check_on_disk(doc.file.rel_path)
	if stale:
		out["changed_on_disk"] = stale
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
		keys[key] = _palette_symbol(view.symbols[key])
	out["keys"] = keys
	if not view.problems.is_empty():
		out["problems"] = Array(view.problems)
	var doc := session.palette_doc_for(def)
	if doc:
		out["dirty"] = session.is_dirty(def.source.path)
		if doc.can_undo():
			out["undo"] = doc.undo_name()
	if args.get("include_json", true):
		out["json"] = data
	return out


## A palette's key as get_palette shows it: the palette's own definitions
## are "from": "this palette".
static func _palette_symbol(info: ResolvedMapgen.SymbolInfo) -> Dictionary:
	var sym := _symbol(info)
	for kind: String in sym:
		for b: Dictionary in (sym[kind] if sym[kind] is Array else [sym[kind]]):
			if b.get("from") == ResolvedMapgen.SOURCE_MAP:
				b["from"] = "this palette"
	return sym


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
		# The stair check reads other levels, which may have been edited since.
		doc.forget_findings()
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
	var out := Validator.validate_map(index, ref, mapgen, resolved, placements, overlay,
			Stairs.new(index, s.objects.object_for))
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
	# The editor may have saved or pushed since.
	ws.reload_manifest()
	var files := []
	for s in WorkspaceSync.new(ws).scan():
		var e := {"file": s.rel, "state": s.text(), "summary": s.summary_text()}
		if s.is_conflict():
			e["conflict"] = true
		if not s.changes.is_empty():
			e["changes"] = s.changes.map(func(c: WorkspaceSync.ObjectChange) -> String: return str(c))
		files.append(e)
	var out := {"workspace": ws.root, "files": files, "unsaved": Array(session.dirty_files())}
	var stale := session.changed_on_disk()
	if not stale.is_empty():
		out["changed_on_disk"] = Array(stale)
	if session.index.workspace_path.is_empty():
		out["note"] = "The workspace isn't layered over BN: nothing can be saved (%s)." % "; ".join(load_errors)
	return out


# --- Edit tools: registry ------------------------------------------------------

func _add_edit_tools() -> void:
	var key := _string("The symbol to paint: one the map defines (itself or through its palettes; get_map's " \
			+ "legend), or ' ' / '.' to leave the cell undefined (fill_ter, or what's below in a chunk).")
	_add("paint_cells", "Paint symbol key on the given cells of a map. Every edit tool changes the map in " \
			+ "memory as one undo step and answers the cells changed, the undo step's name and the map's problem " \
			+ "counts; get_map shows the result, save writes it.", _map_props({
		"key": key,
		"cells": _array("[[x, y], ...], 0-based from the top-left cell.", "array"),
	}), ["key", "cells"], paint_cells)
	_add("paint_rect", "Paint a rectangle with corners (x, y) and (x2, y2), both included.", _map_props({
		"key": key, "x": _int("A corner's column."), "y": _int("A corner's row."),
		"x2": _int("The other corner's column."), "y2": _int("The other corner's row."),
		"filled": _bool("Fill it (default true); false paints the outline only."),
	}), ["key", "x", "y", "x2", "y2"], paint_rect)
	_add("paint_line", "Paint a straight line from (x, y) to (x2, y2), both included.", _map_props({
		"key": key, "x": _int("Start column."), "y": _int("Start row."),
		"x2": _int("End column."), "y2": _int("End row."),
	}), ["key", "x", "y", "x2", "y2"], paint_line)
	_add("fill", "Flood fill: paint the cells connected to (x, y) (up/down/left/right) that have the same " \
			+ "symbol as it.", _map_props({"key": key, "x": _int("Column."), "y": _int("Row.")}),
			["key", "x", "y"], fill)
	_add("paint_rows", "Lay rows of text over the map with their top-left at (x, y): each character is " \
			+ "painted as a symbol, like the map's own rows. Every symbol used must be defined (or ' ' / '.'). " \
			+ "One call can redraw a room or the whole map.", _map_props({
		"x": _int("Column of the first character (default 0)."),
		"y": _int("Row of the first line (default 0)."),
		"rows": _array("Lines of symbols, e.g. [\"#####\", \"#...#\"].", "string"),
		"skip": _string("A character that leaves the cell under it unchanged (default: none)."),
	}), ["rows"], paint_rows)
	_add("add_symbol", "Define a new symbol in the map's own terrain/furniture (never in a palette: palettes " \
			+ "are shared by other maps). Give a terrain, a furniture or both.", _map_props({
		"key": _string("The new symbol: one character the map doesn't define yet (default: a free one, the " \
				+ "furniture's or terrain's own symbol if it is free)."),
		"terrain": _string("Terrain id (lookup_id finds ids)."),
		"furniture": _string("Furniture id."),
	}), [], add_symbol)
	_add("remove_symbol", "Remove a symbol from the map's own terrain/furniture (a palette's definition, if " \
			+ "any, then applies). Cells still using it stay as they are.", _map_props({
		"key": _string("The symbol."),
	}), ["key"], remove_symbol)
	var palette := _string("Instead of a map: a palette id (its edits have an undo history of their own).")
	_add("undo", "Undo the map's (or palette's) last edit (edits made in this session only).",
			_map_props({"palette": palette}), [], undo)
	_add("redo", "Redo the map's (or palette's) last undone edit.", _map_props({"palette": palette}), [], redo)
	_add("save", "Write a file with unsaved edits to the workspace (formatted as BN's json_formatter does; " \
			+ "objects not edited stay byte-identical), or every such file. Never writes into BN. Refused when " \
			+ "the file changed on disk since it was read (reload), or when a placement would stop BN loading " \
			+ "the map. Answers the file's state against BN and which objects differ. A file whose map was made a " \
			+ "building level (create_mapgen's level) is saved with the building's file.", {
		"file": _string("The file (relative, as get_map gives it); default: every file with unsaved edits."),
	}, [], save)
	_add("discard", "Throw away a file's unsaved edits (and new maps not saved yet): its maps close and " \
			+ "read the file again when next used. A new level's edits to its building's file go too.", {
		"file": _string("The file (relative, as get_map gives it)."),
	}, ["file"], discard)
	_add("reload", "Read BN and the workspace again. Files the editor saves are picked up by themselves " \
			+ "(an answer then says \"reloaded\"), or warned about (\"disk_warning\") while there are unsaved " \
			+ "edits here. Refused while there are unsaved edits, unless discard is true.", {
		"discard": _bool("Throw away unsaved edits (default false)."),
	}, [], reload)


func _add_placement_tools() -> void:
	var members: Array = Placement.KINDS.keys()
	_add("add_placement", "Add a coordinate placement (place_items, place_monster, place_nested, set, ...) to " \
			+ "a map. x/y are an int or an inclusive [min, max] range, in map cells; they must stay inside one " \
			+ "24x24 tile (BN refuses the map otherwise) and inside the map (BN drops it), and are never moved " \
			+ "for you. Answers the entry as added and what BN would say about it (e.g. unknown ids).",
			_map_props({
		"member": _enum("The placement list.", members),
		"entry": _object("The entry, e.g. {\"group\": \"GROUP_ZOMBIE\", \"x\": [3, 8], \"y\": 5, \"chance\": 20}. " \
				+ "\"set\" entries use tile-local x/y and are applied in every tile."),
	}), ["member", "entry"], add_placement)
	_add("update_placement", "Change fields of a placement (get_map lists them by member and index), and/or " \
			+ "move it keeping its size and how its ranges are written.", _map_props({
		"member": _enum("The placement list.", members),
		"index": _int("The entry's index in the list (0-based)."),
		"fields": _object("Fields to set; a null value removes the field."),
		"move_to": _array("[x, y]: the new top-left of the cells it covers (tile-local for \"set\").", "integer"),
	}), ["member", "index"], update_placement)
	_add("remove_placement", "Remove a placement. Later entries of the same list move down one index.",
			_map_props({
		"member": _enum("The placement list.", members),
		"index": _int("The entry's index in the list (0-based)."),
	}), ["member", "index"], remove_placement)
	_add("set_map_palettes", "Replace the map's palettes list (later palettes win over earlier ones; the " \
			+ "map's own symbols win over all).", _map_props({
		"palettes": _array("Palette ids (or distribution/param objects, as BN takes them); [] removes the list."),
	}), ["palettes"], set_map_palettes)
	_add("set_symbol_mapping", "Set what a symbol of the map places besides terrain/furniture: a nested chunk, " \
			+ "monsters, items, a vehicle, toilet or vending machine. Written in the map itself (not a palette).",
			_map_props({
		"key": _string("The symbol."),
		"kind": _enum("The mapping.", Placement.MAPPING_KINDS.keys()),
		"value": _any("One piece object (e.g. {\"chunks\": [\"my_chunk\"]} for nested, {\"item\": \"group\", " \
				+ "\"chance\": 50} for items) or a list of them; null removes the map's own mapping."),
	}), ["key", "kind", "value"], set_symbol_mapping)
	_add("create_mapgen", "Create a new mapgen: an om_terrain map (one id, or a grid of ids for a map of " \
			+ "several tiles) or a nested chunk, in a new file or appended to an existing one. Its rows start " \
			+ "blank (' ' everywhere). Unsaved until save; discard removes it again. Answers what get_map does.", {
		"file": _string("Relative .json path inside a loaded mod, e.g. data/json/mapgen/my_house.json."),
		"om_terrain": _any("An om_terrain id, or a grid: rows of ids, e.g. [[\"a_1\", \"a_2\"]]."),
		"nested_id": _string("Instead of om_terrain: the chunk's nested_mapgen_id."),
		"mapgensize": _array("With nested_id: [width, height], 1-24 each.", "integer"),
		"fill_ter": _string("Default terrain of an om_terrain map (default %s)." % EditSession.DEFAULT_FILL),
		"palettes": _array("Palette ids to use.", "string"),
		"add_overmap_terrain": _bool("Also add a minimal overmap_terrain for om_terrain ids that have none, so " \
				+ "BN uses the map (default true)."),
		"level": _object("Make the map a level of a building: {\"building\": id, \"point\": [x, y, z] of the " \
				+ "map's top-left tile, \"dir\": north|east|south|west|none (default: the rotation of the " \
				+ "building's tile at the same x, y on another level, else north)}. Tiles the building doesn't " \
				+ "list yet are added to its \"overmaps\" (in the definition supplying the list: with copy-from " \
				+ "that is the base's, maybe in another file); tiles it lists with these ids are just drawn. " \
				+ "Omitted fill_ter / palettes get suggestions (a roof, an id ending in _roof: t_flat_roof and " \
				+ "roof_palette; below ground t_thconc_floor; above, the floor below's fill), and new " \
				+ "overmap_terrain copy the point's other levels'. save of the map's file saves the building's " \
				+ "file too; discard takes both back."),
	}, ["file"], create_mapgen)


# --- Edit tools: shared --------------------------------------------------------

## The open document for [param args]'s map, loading the session first, or
## a Failure.
func _edit_doc(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	return _open(args)


## What every edit answers: [param extra], the undo step, problem counts
## and whether the file has unsaved edits.
func _edited(doc: MapDocument, extra := {}) -> Dictionary:
	var out := extra.duplicate()
	out["undo"] = doc.undo_name()
	var n := Validator.count(doc.findings())
	out["problems"] = {"errors": n[0], "warnings": n[1], "notes": n[2]}
	out["dirty"] = session.is_dirty(doc.file.rel_path)
	return out


## Why [param key] can't be painted in [param doc], or "".
static func _check_paint_key(doc: MapDocument, key: String) -> String:
	var shape := MapDocument.check_key_shape(key)
	if shape:
		return "'%s': %s" % [key, shape]
	if not doc.defines_key(key):
		return "'%s' isn't defined in %s; add_symbol defines it (or use a symbol from get_map's legend)." % [
			key, doc.ref.title()]
	return ""


## Paints each key of [param by_key] (key -> Array[Vector2i]) as one undo
## step named [param name]: the edit answer, or a Failure if a key can't be
## painted (then nothing is).
func _paint(doc: MapDocument, by_key: Dictionary, name: String) -> Variant:
	for key: String in by_key:
		var problem := _check_paint_key(doc, key)
		if problem:
			return Failure.new(problem)
	var size := doc.size()
	var target := {}
	var outside := 0
	for key: String in by_key:
		for p: Vector2i in by_key[key]:
			if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
				outside += 1
			else:
				target[p] = key
	var changed := 0
	for p: Vector2i in target:
		if doc.resolved.cells[p.y][p.x] != target[p]:
			changed += 1
	doc.begin_group(name)
	for key: String in by_key:
		doc.paint(by_key[key], key, name)
	doc.end_group()
	var out := {"changed": changed}
	if outside:
		out["outside"] = "%d cell(s) outside the %dx%d map were skipped." % [outside, size.x, size.y]
	return _edited(doc, out)


static func _point(args: Dictionary, x := "x", y := "y") -> Vector2i:
	return Vector2i(int(args[x]), int(args[y]))


# --- paint_* / fill ------------------------------------------------------------

func paint_cells(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var points: Array[Vector2i] = []
	for c: Array in args.cells:
		if c.size() != 2 or not _is_type(c[0], "integer") or not _is_type(c[1], "integer"):
			return Failure.new("Each cell is [x, y] (two integers), not %s." % BnJson.stringify(c))
		points.append(Vector2i(int(c[0]), int(c[1])))
	return _paint(got, {args.key: points}, "Paint '%s'" % args.key)


func paint_rect(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var points := Shapes.rect(_point(args), _point(args, "x2", "y2"), args.get("filled", true))
	return _paint(got, {args.key: points}, "Rectangle '%s'" % args.key)


func paint_line(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	return _paint(got, {args.key: Shapes.line(_point(args), _point(args, "x2", "y2"))}, "Line '%s'" % args.key)


func fill(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var start := _point(args)
	if not Rect2i(Vector2i.ZERO, doc.size()).has_point(start):
		return Failure.new("(%d, %d) is outside the %dx%d map." % [start.x, start.y, doc.size().x, doc.size().y])
	return _paint(doc, {args.key: Shapes.flood(doc.resolved.cells, start)}, "Fill '%s'" % args.key)


func paint_rows(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var skip: String = args.get("skip", "")
	if skip and CellText.split_row(skip).size() != 1:
		return Failure.new("skip is one character.")
	var at := Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var by_key := {}
	for j in args.rows.size():
		var cells := CellText.split_row(args.rows[j])
		for i in cells.size():
			if cells[i] == skip:
				continue
			if not by_key.has(cells[i]):
				by_key[cells[i]] = [] as Array[Vector2i]
			by_key[cells[i]].append(at + Vector2i(i, j))
	var undefined := PackedStringArray()
	for key: String in by_key:
		if _check_paint_key(got, key):
			undefined.append("'%s'" % key)
	if not undefined.is_empty():
		return Failure.new("Not defined in %s: %s. add_symbol defines a symbol; get_map's legend lists the " \
				% [got.ref.title(), ", ".join(undefined)] + "defined ones." + (" Pass skip to leave cells alone." \
				if not args.has("skip") else ""))
	return _paint(got, by_key, "Paint rows")


# --- Symbols -------------------------------------------------------------------

func add_symbol(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var ter: String = args.get("terrain", "")
	var furn: String = args.get("furniture", "")
	var key: String = args.get("key", "")
	if not args.has("key"):
		key = doc.suggest_key(ter, furn)
		if key.is_empty():
			return Failure.new("No free symbol left in %s." % doc.ref.title())
	var err := doc.add_symbol(key, ter, furn)
	if err:
		return Failure.new(err)
	return _edited(doc, {"symbol": {key: _symbol(doc.resolved.symbols[key])}})


func remove_symbol(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	if not doc.own_keys().has(args.key):
		return Failure.new("'%s' isn't in the map's own terrain/furniture (its own symbols: %s)." % [
			args.key, " ".join(doc.own_keys())])
	doc.remove_own_symbol(args.key)
	var info: ResolvedMapgen.SymbolInfo = doc.resolved.symbols.get(args.key)
	var out := {"symbol": {args.key: _symbol(info) if info else null}}
	var cells := 0
	for row in doc.resolved.cells:
		cells += row.count(args.key)
	if cells:
		out["cells_using_it"] = cells
	return _edited(doc, out)


# --- undo / redo ---------------------------------------------------------------

func undo(args: Dictionary) -> Variant:
	if args.has("palette"):
		return _palette_history(args.palette, true)
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	if not doc.can_undo():
		return Failure.new("Nothing to undo in %s (this session's edits only)." % doc.ref.title())
	var name := doc.undo_name()
	doc.undo()
	return _edited(doc, {"undone": name, "redo": doc.redo_name()})


func redo(args: Dictionary) -> Variant:
	if args.has("palette"):
		return _palette_history(args.palette, false)
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	if not doc.can_redo():
		return Failure.new("Nothing to redo in %s." % doc.ref.title())
	var name := doc.redo_name()
	doc.redo()
	return _edited(doc, {"redone": name})


# --- save / discard / reload ---------------------------------------------------

func save(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var rels := session.dirty_files()
	if args.has("file"):
		if not session.files.has(args.file):
			return Failure.new("%s isn't open (nothing edited in it)." % args.file)
		if not session.is_dirty(args.file):
			return {"saved": [], "note": "%s has no unsaved edits." % args.file}
		rels = PackedStringArray([args.file])
		# A new level's building (and city list) edits go with its map.
		for rel in session.linked_files(args.file):
			if session.is_dirty(rel) and not rels.has(rel):
				rels.append(rel)
	if rels.is_empty():
		return {"saved": [], "note": "Nothing to save."}
	var saved := []
	var errors := PackedStringArray()
	var sync := WorkspaceSync.new(session.workspace)
	for rel in rels:
		var err := session.save(rel)
		if err:
			errors.append("%s: %s" % [rel, err])
			continue
		var s := sync.status(rel)
		var e := {"file": rel, "state": s.text(), "summary": s.summary_text()}
		if not s.changes.is_empty():
			e["changes"] = s.changes.map(func(c: WorkspaceSync.ObjectChange) -> String: return str(c))
		if not session.last_notes.is_empty():
			e["notes"] = Array(session.last_notes)
		saved.append(e)
	if saved.is_empty():
		return Failure.new("Not saved: " + "; ".join(errors))
	var out := {"workspace": session.workspace.root, "saved": saved}
	if not errors.is_empty():
		out["errors"] = Array(errors)
	return out


func discard(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var rel: String = args.file
	if not session.files.has(rel):
		return Failure.new("%s isn't open." % rel)
	var dirty := session.is_dirty(rel)
	var closed := session.discard(rel)
	return {"file": rel, "discarded_edits": dirty, "closed": Array(closed)}


func reload(args: Dictionary) -> Variant:
	var dirty := session.dirty_files() if session else PackedStringArray()
	if not dirty.is_empty() and not args.get("discard", false):
		return Failure.new("Unsaved edits in %s: save them, or reload with discard: true." % ", ".join(dirty))
	session = null
	load_errors = PackedStringArray()
	_load_tried = false
	if _session() == null:
		return _no_session()
	var out := {"mapgens": session.index.mapgens.size(), "palettes": session.index.palettes.size()}
	if not dirty.is_empty():
		out["discarded"] = Array(dirty)
	if not load_errors.is_empty():
		out["load_errors"] = Array(load_errors)
	return out


# --- Placements ----------------------------------------------------------------

## The placement [param member] #[param i] of [param doc] as get_map lists
## it, with the findings that point at it.
func _placement_info(doc: MapDocument, member: String, i: int) -> Dictionary:
	var p := doc.placement(member, i)
	var out := {"member": member, "index": i, "entry": p.entry}
	if p.status != Placement.Status.OK:
		out["status"] = Placement.Status.keys()[p.status].to_lower()
	var findings := []
	for f in doc.findings(false):
		if f.target == Validator.Target.PLACEMENT and f.member == member and f.index == i:
			findings.append(_finding(f))
	if not findings.is_empty():
		out["findings"] = findings
	return out


func add_placement(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var member: String = args.member
	var list: Variant = doc.object().get(member)
	var i: int = list.size() if list is Array else 0
	var err := doc.add_placement(member, args.entry)
	if err:
		return Failure.new(err)
	return _edited(doc, {"placement": _placement_info(doc, member, i)})


func update_placement(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var member: String = args.member
	var i := int(args.index)
	var p := doc.placement(member, i)
	if p == null:
		return Failure.new("%s has no %s entry #%d (0-based); get_map lists them." % [doc.ref.title(), member, i])
	var fields: Dictionary = args.get("fields", {}).duplicate()
	if args.has("move_to"):
		var to: Array = args.move_to
		if to.size() != 2:
			return Failure.new("move_to is [x, y].")
		for k in ["x", "y", "x2", "y2"]:
			if fields.has(k):
				return Failure.new("Give either move_to or \"%s\" in fields, not both." % k)
		fields.merge(p.values_for(Rect2i(Vector2i(int(to[0]), int(to[1])), p.span().size), true))
	if fields.is_empty():
		return Failure.new("Pass fields and/or move_to.")
	var undo_before := doc.undo_name()
	var err := doc.set_placement_fields(member, i, fields)
	if err:
		return Failure.new(err)
	var out := {"placement": _placement_info(doc, member, i)}
	if doc.undo_name() == undo_before:
		out["note"] = "Nothing changed: the entry already had these values."
	return _edited(doc, out)


func remove_placement(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var member: String = args.member
	var i := int(args.index)
	var p := doc.placement(member, i)
	if p == null:
		return Failure.new("%s has no %s entry #%d (0-based); get_map lists them." % [doc.ref.title(), member, i])
	var removed := p.entry
	var after: int = doc.object()[member].size() - i - 1
	doc.remove_placement(member, i)
	var out := {"removed": removed}
	if after > 0:
		out["note"] = "The %d later %s entries moved down one index." % [after, member]
	return _edited(doc, out)


func set_map_palettes(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var list: Array = args.palettes
	for v: Variant in list:
		if not (v is String or v is Dictionary):
			return Failure.new("A palettes entry is an id or a distribution/param object, not %s." % BnJson.stringify(v))
	var params: Variant = doc.object().get("parameters")
	var ids := DataIndex.palette_options({"palettes": list, "parameters": params if params is Dictionary else {}})
	for id in ids:
		if session.index.palette(id) == null:
			return Failure.new("Unknown palette \"%s\"; lookup_id with kind \"palette\" finds ids." % id)
	_exact_palettes(ids)
	doc.set_palettes(list)
	return _edited(doc, {"palettes": doc.palette_list()})


func set_symbol_mapping(args: Dictionary) -> Variant:
	var got: Variant = _edit_doc(args)
	if got is Failure:
		return got
	var doc: MapDocument = got
	var err := doc.set_own_piece(args.key, args.kind, args.value)
	if err:
		return Failure.new(err)
	var info: ResolvedMapgen.SymbolInfo = doc.resolved.symbols.get(args.key)
	var out := {"symbol": {args.key: _symbol(info) if info else null}}
	var findings := []
	for f in doc.findings(false):
		if f.target == Validator.Target.SYMBOL and f.key == args.key:
			findings.append(_finding(f))
	if not findings.is_empty():
		out["findings"] = findings
	return _edited(doc, out)


# --- create_mapgen -------------------------------------------------------------

func create_mapgen(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var spec := EditSession.NewMapgen.new()
	spec.rel_path = args.file
	if args.has("om_terrain") == args.has("nested_id"):
		return Failure.new("Pass om_terrain (a map) or nested_id (a chunk).")
	if args.has("nested_id"):
		if not args.has("mapgensize") or args.mapgensize.size() != 2:
			return Failure.new("A chunk needs mapgensize: [width, height].")
		if args.has("fill_ter"):
			return Failure.new("A chunk has no fill_ter (BN ignores it there); paint its terrain instead.")
		spec.ids.append(PackedStringArray([args.nested_id]))
		spec.chunk_size = Vector2i(int(args.mapgensize[0]), int(args.mapgensize[1]))
	else:
		var om: Variant = args.om_terrain
		if args.has("mapgensize"):
			return Failure.new("mapgensize is for a chunk (nested_id); an om_terrain map is 24x24 per id.")
		if om is String:
			spec.ids.append(PackedStringArray([om]))
		elif om is Array and not om.is_empty() and om.all(func(row: Variant) -> bool:
				return row is Array and row.all(func(id: Variant) -> bool: return id is String)):
			for row: Array in om:
				spec.ids.append(PackedStringArray(row))
		else:
			return Failure.new("om_terrain is an id or a grid (a list of rows, each a list of ids).")
		spec.fill_ter = args.get("fill_ter", EditSession.DEFAULT_FILL)
	spec.palettes = PackedStringArray(args.get("palettes", []))
	spec.add_overmap_terrain = false
	var level := {}
	if args.has("level"):
		if spec.is_chunk():
			return Failure.new("A chunk isn't a building level; level is for an om_terrain map.")
		var got: Variant = _level_spec(args, spec)
		if got is Failure:
			return got
		level = got
	_exact_palettes(spec.palettes)
	session.last_error = ""
	var doc := session.create_mapgen(spec)
	if doc == null:
		return Failure.new(session.last_error)
	var added := PackedStringArray()
	if args.get("add_overmap_terrain", true) and not spec.is_chunk():
		added = session.add_missing_overmap_terrain(doc, spec.overmap_base)
	var out := _map_view(doc, {})
	if not added.is_empty():
		out["overmap_terrain_added"] = Array(added)
	if not level.is_empty():
		if session.last_error:
			level["error"] = "created, but not added to the building: " + session.last_error
		out["level"] = level
		var linked := session.linked_files(spec.rel_path)
		if not linked.is_empty():
			out["linked_files"] = Array(linked)
			out["save_note"] = "save with this file also saves %s; discard takes both back." % ", ".join(linked)
	return out


# --- Building levels -----------------------------------------------------------

func _add_level_tools() -> void:
	_add("get_building", "A city_building or overmap_special (a building's floors are separate om_terrain " \
			+ "maps; only the building's \"overmaps\" list stacks them): every level's tiles by z with their " \
			+ "point, om_terrain, rotation and the mapgens drawing them (or none: BN then uses its fallback). " \
			+ "An unknown id lists the buildings containing it.", {
		"id": _string("The city_building / overmap_special id."),
		"z": _int("Only this level."),
	}, ["id"], get_building)
	_add("validate_building", "What BN would say about a city_building / overmap_special (see validate_map " \
			+ "for severities): terrains in \"overmaps\" that don't exist, points listed twice, tiles no mapgen " \
			+ "draws, and a city_building no region's city list names (cities never place it). Stair and " \
			+ "elevator findings are validate_map's, per map (with the other levels' files and indexes).", {
		"id": _string("The city_building / overmap_special id."),
	}, ["id"], validate_building)
	_add("create_building", "Create a city_building placing a map's tiles at z 0 facing north (add its other " \
			+ "levels with create_mapgen's level), optionally named in a city list so cities spawn it (without " \
			+ "one it never spawns in a city). In a mod the list entry is a region_overlay next to the " \
			+ "building; in core it edits data/json/regional_map_settings.json. Unsaved until save (answers every " \
			+ "file touched); discard of the building's file takes it back.", _map_props({
		"building": _string("The new city_building id."),
		"building_file": _string("Where the building goes (relative .json path in a loaded mod; default: " \
				+ "the map's file)."),
		"city_list": _enum("The city list to name it in (default: none).", EditSession.CITY_LISTS),
		"weight": _int("Its weight in the city list (default 100)."),
	}), ["building"], create_building)


## One tile of a building: point, om_terrain, rotation, the mapgens that
## draw it; [param place] (optional) adds where it is from that map's
## top-left tile.
func _building_tile(t: DataIndex.BuildingTile, place: BuildingLevels.Place = null) -> Dictionary:
	var out := {"om_terrain": t.oter}
	if t.placed:
		out["point"] = [t.point.x, t.point.y, t.point.z]
	if place:
		out["offset"] = [t.point.x - place.origin.x, t.point.y - place.origin.y]
	if t.dir:
		out["dir"] = t.dir
	var refs := BuildingLevels.mapgens(session.index, t.oter)
	if refs.is_empty():
		out["no_mapgen"] = true
	else:
		out["mapgens"] = refs.map(_level_mapgen)
	return out


## How a tile's mapgen is named: file + index (what the map tools take),
## the grid id when it draws several tiles, weight when not the default.
func _level_mapgen(ref: DataIndex.MapgenRef) -> Dictionary:
	var out := {"file": ref.source.path, "index": ref.source.index}
	if ref.ids.size() > 1:
		out["map"] = ref.title()
	if ref.weight != 1000:
		out["weight"] = ref.weight
	if ref.disabled:
		out["disabled"] = true
	return out


## get_map's "levels": per building placing [param ref], its place, the
## building's z list and the tiles one level up and down under the map's
## footprint (else the nearest tile of that level, marked).
func _levels(ref: DataIndex.MapgenRef) -> Array:
	var index := session.index
	var size := ref.size_omt()
	var out := []
	for p in BuildingLevels.places(index, ref):
		var e := {"building": p.building.id, "type": p.building.type,
			"origin": [p.origin.x, p.origin.y, p.origin.z], "z_levels": Array(p.building.levels())}
		if p.dir:
			e["dir"] = p.dir
		if p.turn_note():
			e["note"] = "placed turned %s: BN turns the map when it draws it here" % p.dir
		for side: Array in [["above", 1], ["below", -1]]:
			var z: int = p.origin.z + side[1]
			var tiles := []
			for t in BuildingLevels.level(index, p, z):
				var at := t.cell / BuildingLevels.OMT
				if at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y:
					tiles.append(_building_tile(t.tile, p))
			var lv := {"z": z, "tiles": tiles}
			if tiles.is_empty():
				var near := BuildingLevels.step(index, p, size, z)
				if near:
					var t := _building_tile(near.tile, p)
					t["nearest"] = true
					tiles.append(t)
					lv["note"] = "no tile of z %d over this map; the nearest one" % z
				else:
					lv["note"] = "%s has no level z %d" % [p.building.id, z]
			e[side[0]] = lv
		out.append(e)
	return out


## Building [param id], or a Failure listing the ids containing it.
func _find_building(id: String) -> Variant:
	var b: DataIndex.Building = session.index.buildings.get(id)
	if b:
		return b
	var like := PackedStringArray()
	for other: String in session.index.buildings:
		if other.to_lower().contains(id.to_lower()) and like.size() < DEFAULT_LIMIT:
			like.append(other)
	like.sort()
	return Failure.new("No city_building / overmap_special \"%s\".%s" % [id,
			" Ids containing it: " + ", ".join(like) if like.size() else ""])


func validate_building(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var found: Variant = _find_building(args.id)
	if found is Failure:
		return found
	var b: DataIndex.Building = found
	var out := {"id": b.id, "type": b.type, "file": b.source.path, "index": b.source.index}
	out.merge(_findings(Validator.sorted(Validator.validate_building(session.index, b))))
	if b.type == "city_building":
		out["city_lists"] = Array(session.index.city_listed.get(b.id, PackedStringArray()))
	return out


func get_building(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var index := session.index
	var found: Variant = _find_building(args.id)
	if found is Failure:
		return found
	var b: DataIndex.Building = found
	var out := {"id": b.id, "type": b.type, "file": b.source.path, "index": b.source.index, "mod": b.source.mod}
	var src := b.overmaps_source
	if src and (src.path != b.source.path or src.index != b.source.index):
		out["overmaps_from"] = {"file": src.path, "index": src.index,
			"note": "copy-from: the \"overmaps\" list in effect is this definition's; a new level edits it there"}
	elif src == null:
		out["note"] = "no \"overmaps\" list"
	if b.mutable:
		out["mutable"] = true
		out["note"] = "a mutable special: its pieces are placed by rules, so they have no points or levels"
		out["pieces"] = b.tiles.map(func(t: DataIndex.BuildingTile) -> Dictionary: return _building_tile(t))
		return out
	out["z_levels"] = Array(b.levels())
	var levels := []
	for z in b.levels():
		if args.has("z") and z != int(args.z):
			continue
		levels.append({"z": z, "tiles": b.level(z).map(
				func(t: DataIndex.BuildingTile) -> Dictionary: return _building_tile(t))})
	if args.has("z") and levels.is_empty():
		return Failure.new("%s has no level z %d (levels: %s)." % [b.id, int(args.z), Array(b.levels())])
	out["levels"] = levels
	var sharing := PackedStringArray()
	for other: String in index.buildings:
		var ob: DataIndex.Building = index.buildings[other]
		if other != b.id and src and ob.overmaps_source and ob.overmaps_source.path == src.path \
				and ob.overmaps_source.index == src.index:
			sharing.append(other)
	if not sharing.is_empty():
		out["shares_overmaps_with"] = Array(sharing)
	return out


## Reads create_mapgen's "level" into [param spec] (spec.level, and
## fill_ter / palettes / overmap_base where [param args] leave them out):
## a Dictionary for the answer's "level", or a Failure.
func _level_spec(args: Dictionary, spec: EditSession.NewMapgen) -> Variant:
	var index := session.index
	var level: Dictionary = args.level
	for k: String in level:
		if not k in ["building", "point", "dir"]:
			return Failure.new("Unknown level member \"%s\" (takes: building, point, dir)." % k)
	if not level.get("building") is String:
		return Failure.new("level.building must be a city_building / overmap_special id.")
	var p: Variant = level.get("point")
	if not (p is Array and p.size() == 3 and p.all(func(v: Variant) -> bool: return _is_type(v, "integer"))):
		return Failure.new("level.point must be [x, y, z] (ints): the building point of the map's top-left tile.")
	var dir: Variant = level.get("dir", null)
	if dir != null and not dir in DataIndex.DIRECTIONS + ["none"]:
		return Failure.new("level.dir must be one of north, east, south, west, none.")
	var b: DataIndex.Building = index.buildings.get(level.building)
	if b == null:
		return Failure.new("No city_building / overmap_special \"%s\" (get_building finds ids)." % level.building)
	var origin := Vector3i(int(p[0]), int(p[1]), int(p[2]))
	var target := EditSession.LevelTarget.new()
	target.building = b.id
	target.origin = origin
	var near: DataIndex.BuildingTile = null
	for t in b.tiles:
		if t.placed and t.point.x == origin.x and t.point.y == origin.y and t.point.z != origin.z:
			var d := absi(t.point.z - origin.z) * 2 + (0 if t.point.z < origin.z else 1)
			if near == null or d < absi(near.point.z - origin.z) * 2 + (0 if near.point.z < origin.z else 1):
				near = t
	target.dir = "" if dir == "none" else dir if dir else near.dir if near else "north"
	var out := {"building": b.id, "point": [origin.x, origin.y, origin.z], "dir": target.dir if target.dir else "none"}
	# Tiles the building lists already, drawn by no mapgen yet: fill them.
	var entries := target.entries(spec.ids)
	var existing := entries.filter(func(e: Array) -> bool: return b.at(e[0]) != null)
	if existing.size() == entries.size() and entries.all(func(e: Array) -> bool:
			return b.at(e[0]).oter == e[1].trim_suffix("_" + target.dir)):
		out["dir"] = b.at(origin).dir if b.at(origin).dir else "none"
		out["tiles_added"] = []
		out["note"] = "%s already lists these tiles; the new map draws them." % b.id
	else:
		spec.level = target
		out["tiles_added"] = entries.map(func(e: Array) -> Dictionary:
				return {"point": [e[0].x, e[0].y, e[0].z], "overmap": e[1]})
		out["note"] = session.level_tiles_note(b.id)
	var roof := spec.ids[0][0].ends_with("_roof")
	var fill_near := ""
	if near and not BuildingLevels.mapgens(index, near.oter).is_empty():
		var obj: Variant = session.objects.object_for(BuildingLevels.mapgens(index, near.oter)[0]).get("object")
		if obj is Dictionary and obj.get("fill_ter") is String:
			fill_near = obj.fill_ter
	var defaults := BuildingLevels.new_level_defaults(index, origin.z, roof, fill_near, near.point.z if near else 0)
	var suggested := {}
	if not args.has("fill_ter") and defaults[0]:
		spec.fill_ter = defaults[0]
		suggested["fill_ter"] = spec.fill_ter
	if not args.has("palettes") and not defaults[1].is_empty():
		spec.palettes = defaults[1]
		suggested["palettes"] = Array(spec.palettes)
	spec.overmap_base = session.level_stub_base(b.id, origin, roof)
	if not suggested.is_empty():
		out["defaults_used"] = suggested
	return out


func create_building(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _find_ref(args)
	if got is Failure:
		return got
	var ref: DataIndex.MapgenRef = got
	if ref.kind != DataIndex.MapgenRef.OM_TERRAIN:
		return Failure.new("Only an om_terrain map can be a building's level.")
	var rel: String = args.get("building_file", ref.source.path)
	var entries := []
	for id in ref.ids:
		var at := ref.position_of(id)
		entries.append([Vector3i(at.x, at.y, 0), id + "_north"])
	var list: String = args.get("city_list", "")
	var problem := session.check_new_building(rel, args.building, list)
	if problem:
		return Failure.new(problem)
	var before := session.dirty_files()
	var err := session.create_building(rel, args.building, entries, list, int(args.get("weight", 100)))
	if not session.index.buildings.has(args.building):
		return Failure.new(err)
	var touched := PackedStringArray()
	for f in session.dirty_files():
		if not before.has(f) or f == rel or session.linked_files(rel).has(f):
			touched.append(f)
	var out := {"building": args.building, "file": rel,
		"tiles": entries.map(func(e: Array) -> Dictionary:
			return {"point": [e[0].x, e[0].y, e[0].z], "overmap": e[1]}),
		"files_touched": Array(touched)}
	if list:
		out["city_list"] = session.city_list_note(rel) if not err else "not added: " + err
	else:
		out["note"] = "In no city list: cities won't spawn it until a region's city list names it."
	return out


# --- Palettes ------------------------------------------------------------------

func _add_palette_tools() -> void:
	var dry_run := _bool("Only measure which maps would change; the palette stays as it is (default false).")
	var limit := _int("Changed maps listed at most (default %d; the count is always given)." % DEFAULT_LIMIT)
	_add("edit_palette_key", "Change what a palette key places: terrain, furniture, a computer, or its other " \
			+ "mappings (nested, items, monsters, ...). A palette is shared: the answer lists every map whose " \
			+ "rows use a symbol the edit changes, and the maps placing a nested chunk that changes (\"via\"); " \
			+ "dry_run measures that without editing. Omitted fields stay as they are. One undo step (undo " \
			+ "with palette); save writes the palette's file.", {
		"id": _string("The palette id."),
		"key": _string("The symbol."),
		"terrain": _any("A terrain id, or any mapgen value (a distribution, ...); \"\" or null removes the " \
				+ "palette's own terrain for the key."),
		"furniture": _any("A furniture id or mapgen value; \"\" or null removes it."),
		"computer": _any("A computer object, as the palette's \"computers\" takes it; null removes it. A new " \
				+ "computer on a key the palette gives no terrain gets t_console too."),
		"mappings": _object("Other mappings by kind (%s), each one piece object or a list of them; a null " \
				% ", ".join(Placement.MAPPING_KINDS.keys()) + "value removes the palette's own mapping of that kind."),
		"dry_run": dry_run,
		"limit": limit,
	}, ["id", "key"], edit_palette_key)
	_add("set_palette_includes", "Replace the palettes a palette includes (later ones win over earlier ones; " \
			+ "its own keys win over all). Answers the maps that change, as edit_palette_key does.", {
		"id": _string("The palette id."),
		"palettes": _array("Palette ids (or distribution/param objects); [] removes the list."),
		"dry_run": dry_run,
		"limit": limit,
	}, ["id", "palettes"], set_palette_includes)
	_add("create_palette", "Create an empty palette in a new file or appended to an existing one; fill it " \
			+ "with edit_palette_key / set_palette_includes and point maps at it with set_map_palettes. Unsaved " \
			+ "until save; discard removes it again.", {
		"file": _string("Relative .json path inside a loaded mod, e.g. data/json/mapgen_palettes/my_pal.json."),
		"id": _string("The new palette id."),
	}, ["file", "id"], create_palette)


## The palette BN uses for [param id], opened for editing, or a Failure.
func _palette_doc(id: String) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _find_palette(id)
	if got is Failure:
		return got
	var doc := session.open_palette(got)
	if doc == null:
		return Failure.new("Can't open palette %s: %s" % [id, session.last_error])
	return doc


## The maps of [param affected] (sorted by id), the first [param limit]
## named with what changes in them.
func _impact(affected: Array[PaletteImpact.Affected], limit: int) -> Dictionary:
	var list := affected.duplicate()
	list.sort_custom(func(a: PaletteImpact.Affected, b: PaletteImpact.Affected) -> bool:
		return a.ref.title() < b.ref.title())
	var maps := []
	for a: PaletteImpact.Affected in list.slice(0, limit):
		var e := {"id": a.ref.title(), "file": a.ref.source.path, "index": a.ref.source.index}
		var variants := session.index.mapgens_for(a.ref.title())
		if variants.size() > 1:
			e["variant"] = variants.find(a.ref)
		if a.via:
			e["via_chunk"] = a.via
		else:
			e["symbols"] = Array(a.keys)
		maps.append(e)
	var out := {"count": affected.size(), "maps": maps}
	if affected.size() > limit:
		out["not_listed"] = affected.size() - limit
	return out


## Measures [param c] on [param doc], commits it unless dry_run, and
## answers the maps it changes, [param key]'s meaning afterwards (when
## given), and the palette's findings (those about [param key] only, when
## given).
func _palette_edit(doc: PaletteDocument, c: PaletteDocument.Change, args: Dictionary, key := "") -> Dictionary:
	var dry: bool = args.get("dry_run", false)
	var affected := session.impact_of(doc, c)
	var out := {"palette": doc.id, "file": doc.file.rel_path}
	if dry:
		out["dry_run"] = true
	out["would_change" if dry else "maps_changed"] = _impact(affected, _limit(args))
	doc.apply(c, true)
	if key:
		var info: ResolvedMapgen.SymbolInfo = doc.view().symbols.get(key)
		out["key"] = {key: _palette_symbol(info) if info else null}
	var list: Array[Validator.Finding] = []
	for f in Validator.validate_palette(session.index, doc.id, doc.palette()):
		if not key or f.key == key:
			list.append(f)
	doc.apply(c, false)
	if not list.is_empty():
		out["findings"] = Validator.sorted(list).map(_finding)
	if not dry:
		doc.commit(c)
		out["undo"] = doc.undo_name()
		out["dirty"] = session.is_dirty(doc.file.rel_path)
	return out


func edit_palette_key(args: Dictionary) -> Variant:
	var got: Variant = _palette_doc(args.id)
	if got is Failure:
		return got
	var doc: PaletteDocument = got
	var key: String = args.key
	var mappings: Dictionary = args.get("mappings", {})
	var steps: Array[Callable] = []
	var problem := ""
	if args.has("terrain") or args.has("furniture"):
		var tiles := []
		for kind: String in PaletteDocument.TILE_KINDS:
			var v: Variant = args.get(kind)
			if args.has(kind) and not (v == null or v is String or v is Dictionary or v is Array):
				return Failure.new("%s is an id or a mapgen value (object or list), not %s." % [kind, BnJson.stringify(v)])
			# null keeps a tile in PaletteDocument; here null removes it.
			tiles.append(("" if v == null else v) if args.has(kind) else null)
		problem = doc.check_tiles(key, tiles[0], tiles[1])
		steps.append(doc.build_set_tiles.bind(key, tiles[0], tiles[1]))
	if not problem and args.has("computer"):
		if args.computer is Dictionary:
			problem = doc.check_computer(key)
			steps.append(doc.build_set_computer.bind(key, args.computer))
		elif args.computer == null:
			problem = doc.check_piece(key, "computers", null)
			steps.append(doc.build_set_piece.bind(key, "computers", null))
		else:
			problem = "computer is an object, or null to remove it."
	for kind: String in mappings:
		if problem:
			break
		if not Placement.MAPPING_KINDS.has(kind):
			problem = "Unknown mapping kind \"%s\" (one of %s)." % [kind, ", ".join(Placement.MAPPING_KINDS.keys())]
		else:
			problem = doc.check_piece(key, kind, mappings[kind])
			steps.append(doc.build_set_piece.bind(key, kind, mappings[kind]))
	if problem:
		return Failure.new(problem)
	if steps.is_empty():
		return Failure.new("Give terrain, furniture, computer or mappings to change.")
	var c := doc.build_steps("Edit '%s'" % key, steps)
	if c == null:
		return Failure.new("Nothing changes: palette %s already has that for '%s'." % [doc.id, key])
	return _palette_edit(doc, c, args, key)


func set_palette_includes(args: Dictionary) -> Variant:
	var got: Variant = _palette_doc(args.id)
	if got is Failure:
		return got
	var doc: PaletteDocument = got
	var list: Array = args.palettes
	for v: Variant in list:
		if not (v is String or v is Dictionary):
			return Failure.new("A palettes entry is an id or a distribution/param object, not %s." % BnJson.stringify(v))
	var params: Variant = doc.palette().get("parameters")
	var ids := DataIndex.palette_options({"palettes": list, "parameters": params if params is Dictionary else {}})
	for id in ids:
		if session.index.palette(id) == null:
			return Failure.new("Unknown palette \"%s\"; lookup_id with kind \"palette\" finds ids." % id)
	if session.index.palette_closure(ids).has(doc.id):
		return Failure.new("Palette %s would include itself." % doc.id)
	_exact_palettes(ids)
	var c := doc.build_set_includes(list)
	if c == null:
		return Failure.new("Nothing changes: palette %s already includes that." % doc.id)
	var out := _palette_edit(doc, c, args)
	if not args.get("dry_run", false):
		out["includes"] = doc.includes().duplicate(true)
	return out


func create_palette(args: Dictionary) -> Variant:
	if _session() == null:
		return _no_session()
	var problem := session.check_new_palette(args.file, args.id)
	if problem:
		return Failure.new(problem)
	var doc := session.create_palette(args.file, args.id)
	if doc == null:
		return Failure.new(session.last_error)
	return {"palette": doc.id, "file": doc.file.rel_path, "index": doc.object_index,
		"dirty": session.is_dirty(doc.file.rel_path)}


## undo ([param back]) or redo in palette [param id].
func _palette_history(id: String, back: bool) -> Variant:
	if _session() == null:
		return _no_session()
	var got: Variant = _find_palette(id)
	if got is Failure:
		return got
	var doc := session.palette_doc_for(got)
	var what := "undo" if back else "redo"
	if doc == null or not (doc.can_undo() if back else doc.can_redo()):
		return Failure.new("Nothing to %s in palette %s (this session's edits only)." % [what, id])
	var out := {"palette": id}
	if back:
		out["undone"] = doc.undo_name()
		doc.undo()
		out["redo"] = doc.redo_name()
	else:
		out["redone"] = doc.redo_name()
		doc.redo()
	out["dirty"] = session.is_dirty(doc.file.rel_path)
	return out

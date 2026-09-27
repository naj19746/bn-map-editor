class_name MapgenResolver
extends RefCounted
## Resolves a json mapgen object against a DataIndex: splits its rows into
## cells and works out what each symbol means.
##
## Follows BN's mapgen_palette: the map's "palettes" are applied in order, each
## one applying its own included palettes before its own definitions, and the
## map's own definitions come last. Every definition of a symbol is applied in
## that order, so for terrain and furniture the last one wins, while items,
## monsters and the rest all apply. A plain "t_null" terrain (or "f_null"
## furniture) is dropped by BN, so it doesn't replace an earlier one, but the
## key still counts as defined.

const OMT_SIZE := 24

## The per-symbol mapping kinds BN reads from a palette or a map's "object",
## in the order it reads them.
const MAPPING_KINDS := [
	"terrain", "furniture", "fields", "npcs", "signs", "vendingmachines", "toilets",
	"gaspumps", "items", "monsters", "vehicles", "item", "artifact", "artifacts", "traps",
	"monster", "rubble", "computers", "sealed_item", "nested", "liquids", "graffiti",
	"translate", "zones", "ter_furn_transforms", "faction_owner_character", "remove_all",
]

var _index: DataIndex
var _result: ResolvedMapgen
var _picks := {}


## [param mapgen] is a whole top-level mapgen object (with "object" inside).
## A "palettes" entry with several possible palettes (a distribution or
## param) shows its first option, unless [param picks] maps the choice's
## number (in [member ResolvedMapgen.choice_options] order) to another.
static func resolve(index: DataIndex, mapgen: Dictionary, picks := {}) -> ResolvedMapgen:
	var r := MapgenResolver.new()
	r._index = index
	r._picks = picks
	r._result = ResolvedMapgen.new()
	r._run(mapgen)
	return r._result


## Resolves [param mapgen] once per palette option: first as resolve() does,
## then with each other option of each choice picked in turn (BN adds every
## option, each applying only when chosen). One result when there's no choice.
static func resolve_variants(index: DataIndex, mapgen: Dictionary) -> Array[ResolvedMapgen]:
	var first := resolve(index, mapgen)
	var out: Array[ResolvedMapgen] = [first]
	for c in first.choice_options.size():
		for j in range(1, first.choice_options[c].size()):
			out.append(resolve(index, mapgen, {c: j}))
	return out


func _run(mapgen: Dictionary) -> void:
	var res := _result
	var obj: Variant = mapgen.get("object", {})
	if not obj is Dictionary:
		res.problems.append("\"object\" is not an object")
		return
	res.size = _size(mapgen)
	if obj.get("fill_ter") is String:
		res.fill_ter = obj.fill_ter
	if obj.get("predecessor_mapgen") is String:
		res.predecessor_mapgen = obj.predecessor_mapgen
	res.draws_over = not mapgen.has("om_terrain")
	_merge_parameters(obj)

	for p: Variant in obj.get("palettes", []):
		_add_palette_value(p, PackedStringArray())
	_add_mappings(obj, ResolvedMapgen.SOURCE_MAP, PackedStringArray())

	_read_rows(obj)
	_check()


func _size(mapgen: Dictionary) -> Vector2i:
	if mapgen.has("nested_mapgen_id") or mapgen.has("update_mapgen_id"):
		var ms: Variant = mapgen.get("object", {}).get("mapgensize")
		if ms is Array and ms.size() == 2:
			return Vector2i(int(ms[0]), int(ms[1]))
		return Vector2i(OMT_SIZE, OMT_SIZE)
	var om: Variant = mapgen.get("om_terrain")
	if om is Array and not om.is_empty() and om[0] is Array:
		for row: Variant in om:
			_result.omt_ids.append(PackedStringArray(row))
		return Vector2i(om[0].size() * OMT_SIZE, om.size() * OMT_SIZE)
	return Vector2i(OMT_SIZE, OMT_SIZE)


## Parameters defined first win, so the map's own come before its palettes'.
func _merge_parameters(data: Dictionary) -> void:
	var params: Variant = data.get("parameters")
	if params is Dictionary:
		for name: String in params:
			if not _result.parameters.has(name):
				_result.parameters[name] = params[name]


## A "palettes" entry: an id, or a distribution/param/switch picking one.
func _add_palette_value(value: Variant, chain: PackedStringArray) -> void:
	var ids := possible_ids(value, "", _result.parameters)
	if ids.is_empty():
		_result.problems.append("can't work out a palette from %s" % JSON.stringify(value))
		return
	var pick := 0
	if ids.size() > 1:
		pick = clampi(_picks.get(_result.choice_options.size(), 0), 0, ids.size() - 1)
		_result.choice_options.append(ids)
		_result.choices.append("palette %s chosen from %s" % [ids[pick], ", ".join(ids)])
	_add_palette(ids[pick], chain)


func _add_palette(id: String, chain: PackedStringArray) -> void:
	if chain.has(id):
		_result.problems.append("palette loop: %s -> %s" % [" -> ".join(chain), id])
		return
	var def := _index.palette(id)
	if def == null:
		_result.problems.append("unknown palette \"%s\"" % id)
		return
	var inner := chain.duplicate()
	inner.append(id)
	_merge_parameters(def.data)
	for p: Variant in def.data.get("palettes", []):
		_add_palette_value(p, inner)
	_add_mappings(def.data, id, inner)
	_result.palettes.append(id)


func _add_mappings(data: Dictionary, source: String, chain: PackedStringArray) -> void:
	var mapping: Variant = data.get("mapping")
	for kind: String in MAPPING_KINDS:
		# BN reads "mapping" before the plain member for each kind.
		if mapping is Dictionary:
			for key: String in mapping:
				var entry: Variant = mapping[key]
				if entry is Dictionary and entry.has(kind):
					_bind(key, kind, entry[kind], source, chain)
		var defs: Variant = data.get(kind)
		if defs is Dictionary:
			for key: String in defs:
				_bind(key, kind, defs[key], source, chain)


func _bind(key: String, kind: String, value: Variant, source: String,
		chain: PackedStringArray) -> void:
	var b := ResolvedMapgen.Binding.new()
	b.value = value
	b.source = source
	b.chain = chain
	# Any mention defines the key for BN, even a piece it then drops.
	var info: ResolvedMapgen.SymbolInfo = _result.symbols.get(key)
	if info == null:
		info = ResolvedMapgen.SymbolInfo.new()
		info.key = key
		_result.symbols[key] = info
	var is_tile := kind == "terrain" or kind == "furniture"
	if is_tile:
		if value is String and value == ("t_null" if kind == "terrain" else "f_null"):
			if kind == "terrain":
				info.null_terrain = true
			return
		b.ids = possible_ids(value, kind, _result.parameters)
	if kind == "terrain":
		info.terrain = b
	elif kind == "furniture":
		info.furniture = b
	else:
		if not info.extras.has(kind):
			info.extras[kind] = []
		info.extras[kind].append(b)


## The ids a mapgen value can produce, in the order written. [param kind] is
## "terrain" or "furniture" (whose objects may wrap the id in "ter"/"furn"),
## or "" for a plain value such as a palette id.
static func possible_ids(value: Variant, kind: String, params: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	_collect_ids(value, kind, params, out, 0)
	# Drop duplicates, keeping the first.
	var seen := {}
	var unique := PackedStringArray()
	for id in out:
		if not seen.has(id):
			seen[id] = true
			unique.append(id)
	return unique


static func _collect_ids(value: Variant, kind: String, params: Dictionary,
		out: PackedStringArray, depth: int) -> void:
	if depth > 8:
		return
	if value is String:
		out.append(value)
	elif value is Array:
		# A list of alternatives: ids, objects, or [piece, count] pairs.
		for e: Variant in value:
			if e is Array and not e.is_empty():
				_collect_ids(e[0], kind, params, out, depth + 1)
			else:
				_collect_ids(e, kind, params, out, depth + 1)
	elif value is Dictionary:
		var wrapper := "ter" if kind == "terrain" else ("furn" if kind == "furniture" else "")
		if wrapper and value.has(wrapper):
			_collect_ids(value[wrapper], kind, params, out, depth + 1)
		elif value.has("param"):
			var p: Variant = params.get(str(value.param))
			var before := out.size()
			if p is Dictionary and p.has("default"):
				_collect_ids(p.default, kind, params, out, depth + 1)
			if out.size() == before and value.get("fallback") is String:
				out.append(value.fallback)
		elif value.has("distribution"):
			for e: Variant in value.distribution:
				if e is Array and not e.is_empty():
					_collect_ids(e[0], kind, params, out, depth + 1)
				else:
					_collect_ids(e, kind, params, out, depth + 1)
		elif value.has("switch"):
			var on := PackedStringArray()
			_collect_ids(value.switch, "", params, on, depth + 1)
			var cases: Variant = value.get("cases", {})
			if cases is Dictionary:
				if on.is_empty():
					on = PackedStringArray(cases.keys())
				for c in on:
					if cases.has(c):
						_collect_ids(cases[c], kind, params, out, depth + 1)


func _read_rows(obj: Dictionary) -> void:
	var res := _result
	var rows: Variant = obj.get("rows")
	if not rows is Array:
		var blank := PackedStringArray()
		blank.resize(res.size.x)
		for y in res.size.y:
			res.cells.append(blank.duplicate())
		return
	if rows.size() != res.size.y:
		res.problems.append("rows: expected %d rows, found %d" % [res.size.y, rows.size()])
	for y in rows.size():
		var cells := CellText.split_row(str(rows[y]))
		if cells.size() != res.size.x:
			res.problems.append("row %d: expected %d columns, found %d" % [y + 1, res.size.x, cells.size()])
			# Pad or cut so every row indexes safely.
			var fixed := cells.slice(0, res.size.x)
			while fixed.size() < res.size.x:
				fixed.append("")
			cells = fixed
		res.cells.append(cells)
	# Keep size and cells consistent even when the row count is wrong.
	res.size.y = res.cells.size()


## BN's load-time checks on symbols, plus unknown terrain/furniture ids.
func _check() -> void:
	var res := _result
	var has_fallback := not res.fill_ter.is_empty() or not res.predecessor_mapgen.is_empty() \
			or res.draws_over
	if not res.fill_ter.is_empty() and not _index.terrain.has(res.fill_ter):
		res.problems.append("fill_ter: unknown terrain \"%s\"" % res.fill_ter)
	for key in res.used_keys():
		if key.is_empty():
			continue
		var info: ResolvedMapgen.SymbolInfo = res.symbols.get(key)
		var has_terrain := info != null and (info.terrain != null or info.null_terrain)
		if not has_terrain and not has_fallback:
			res.problems.append("'%s' has no terrain and there is no fill_ter" % key)
		if info == null:
			if key != " " and key != ".":
				res.problems.append("'%s' has no terrain, furniture or other definition" % key)
			continue
		_check_ids(key, info.terrain, _index.terrain, "terrain")
		_check_ids(key, info.furniture, _index.furniture, "furniture")


func _check_ids(key: String, b: ResolvedMapgen.Binding, table: Dictionary, what: String) -> void:
	if b == null:
		return
	if b.ids.is_empty():
		_result.problems.append("'%s': can't work out the %s from %s (%s)" % [
			key, what, JSON.stringify(b.value), b.source])
	for id in b.ids:
		if not table.has(id):
			_result.problems.append("'%s': unknown %s \"%s\" (%s)" % [key, what, id, b.source])

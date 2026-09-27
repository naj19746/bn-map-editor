class_name ResolvedMapgen
extends RefCounted
## A mapgen's rows split into cells, and what every symbol means once its
## palettes are applied. Built by MapgenResolver.

const SOURCE_MAP := "map"
const SOURCE_FILL := "fill_ter"


## One definition of a symbol, e.g. its terrain, and where it came from.
class Binding:
	## The JSON value as written: an id, a list, or a distribution/param/switch.
	var value: Variant
	## The ids it can produce, in the order written (terrain and furniture only).
	var ids := PackedStringArray()
	## SOURCE_MAP, SOURCE_FILL, or the id of the palette that defined it.
	var source := ""
	## The palette include path, outermost first, e.g. [the map's palette,
	## the palette it includes]. Empty for the map itself and fill_ter.
	var chain := PackedStringArray()

	## The id to display: the first one written, or "" if none can be worked out.
	func id() -> String:
		return ids[0] if not ids.is_empty() else ""

	func from_palette() -> bool:
		return source != SOURCE_MAP and source != SOURCE_FILL

	## Where it's defined, for display: "map", "fill_ter", "palette p", or
	## "palette inner (via outer)" for an included palette.
	func source_label() -> String:
		if not from_palette():
			return source
		if chain.size() > 1:
			return "palette %s (via %s)" % [source, " > ".join(chain.slice(0, -1))]
		return "palette " + source


## Everything a symbol maps to. BN treats any key that appears in a mapping
## as defined, even if all its pieces were dropped.
class SymbolInfo:
	var key := ""
	## The terrain in effect (later definitions replace earlier ones), or null.
	var terrain: Binding
	## Like terrain.
	var furniture: Binding
	## Other mapping kinds ("items", "monsters", "traps", ...) -> Array of
	## Binding. These all apply, so every definition is kept, in order.
	var extras := {}
	## True when some definition set the terrain to a plain "t_null", which
	## BN skips: the cell keeps fill_ter, or what was there for nested chunks.
	var null_terrain := false


## Width x height in cells.
var size := Vector2i.ZERO
## Rows of cell keys. A map without "rows" has all-"" keys.
var cells: Array[PackedStringArray] = []
## key -> SymbolInfo, for every key the palettes or the map define.
var symbols := {}
var fill_ter := ""
var predecessor_mapgen := ""
## True for nested_mapgen_id / update_mapgen_id entries, which draw over an
## existing map, so a cell without terrain is fine there.
var draws_over := false
## For a multi-tile building, the om_terrain ids by row (like the JSON).
var omt_ids: Array[PackedStringArray] = []
## Palettes in the order they were applied (included palettes first).
var palettes := PackedStringArray()
## name -> parameter definition, from the map and its palettes.
var parameters := {}
## Where a random choice was made for display (e.g. a palette distribution).
var choices := PackedStringArray()
## For each "palettes" entry with several possible palettes, in the order
## met: its options. MapgenResolver.resolve's picks index into these.
var choice_options: Array[PackedStringArray] = []
var problems := PackedStringArray()

var _fill: Binding


func key_at(x: int, y: int) -> String:
	return cells[y][x]


## The terrain at a cell: its symbol's terrain, else fill_ter; null if neither.
func terrain_at(x: int, y: int) -> Binding:
	var info: SymbolInfo = symbols.get(cells[y][x])
	if info != null and info.terrain != null:
		return info.terrain
	return fill_binding()


func furniture_at(x: int, y: int) -> Binding:
	var info: SymbolInfo = symbols.get(cells[y][x])
	return info.furniture if info != null else null


## A Binding for fill_ter, or null if the map has none.
func fill_binding() -> Binding:
	if _fill == null and not fill_ter.is_empty():
		_fill = Binding.new()
		_fill.value = fill_ter
		_fill.ids = PackedStringArray([fill_ter])
		_fill.source = SOURCE_FILL
	return _fill


## What [param key] places, as text: equal texts mean the same terrain,
## furniture and extras, wherever they are defined. For comparing a map
## before and after an edit. Numbers compare by value, so a value read with
## Godot's JSON (floats) matches the same value read with BnJson.
func key_signature(key: String) -> String:
	var info: SymbolInfo = symbols.get(key)
	if info == null:
		return "undefined"
	var extras := {}
	var kinds: Array = info.extras.keys()
	kinds.sort()
	for kind: String in kinds:
		extras[kind] = info.extras[kind].map(func(b: Binding) -> Variant: return b.value)
	return JSON.stringify(_numbers_as_floats([
		info.terrain.value if info.terrain else null, info.null_terrain,
		info.furniture.value if info.furniture else null, extras]))


static func _numbers_as_floats(v: Variant) -> Variant:
	if v is int:
		return float(v)
	if v is Array:
		return v.map(_numbers_as_floats)
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _numbers_as_floats(v[k])
		return out
	return v


## The distinct keys used in the rows, in first-seen order.
func used_keys() -> PackedStringArray:
	var seen := {}
	for row in cells:
		for k in row:
			seen[k] = true
	return PackedStringArray(seen.keys())

class_name MapBrowser
extends VBoxContainer
## Every mapgen entry in the index, as mod > file > entry. The search box
## matches om_terrain / nested ids and file paths. Activating an entry
## (double-click or Enter) emits open_requested.

signal open_requested(ref: DataIndex.MapgenRef)

## Entries shown at most while searching, so a short query stays fast.
const MAX_RESULTS := 2000

var _search: LineEdit
var _tree: Tree
var _count: Label
var _index: DataIndex
var _timer: Timer


func _init() -> void:
	name = "Browser"
	_search = LineEdit.new()
	_search.placeholder_text = "Search om_terrain / nested id / file"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _timer.start())
	_search.text_submitted.connect(func(_t: String) -> void: _open_first())
	add_child(_search)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.15
	_timer.timeout.connect(_rebuild)
	add_child(_timer)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 90)
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)
	_count = Label.new()
	_count.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	add_child(_count)


func set_index(index: DataIndex) -> void:
	_index = index
	_rebuild()


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


## The label for an entry: its id(s), and the size/kind/weight column.
static func entry_text(ref: DataIndex.MapgenRef) -> PackedStringArray:
	var name := ref.title()
	var info := PackedStringArray()
	match ref.kind:
		DataIndex.MapgenRef.OM_TERRAIN:
			if not ref.grid.is_empty():
				var s := ref.size_omt()
				info.append("%dx%d" % [s.x, s.y])
			elif ref.ids.size() > 1:
				name += " +%d" % (ref.ids.size() - 1)
		DataIndex.MapgenRef.NESTED:
			info.append("nest %dx%d" % [ref.chunk_size.x, ref.chunk_size.y])
		DataIndex.MapgenRef.UPDATE:
			info.append("update")
	if ref.weight != 1000:
		info.append("w%d" % ref.weight)
	if ref.method != "json":
		info.append(ref.method)
	return PackedStringArray([name, " ".join(info)])


func _matches(ref: DataIndex.MapgenRef, query: String) -> bool:
	if ref.source.path.to_lower().contains(query):
		return true
	for id in ref.ids:
		if id.to_lower().contains(query):
			return true
	return false


func _rebuild() -> void:
	_tree.clear()
	if _index == null:
		_count.text = ""
		return
	var query := _search.text.strip_edges().to_lower()
	var root := _tree.create_item()
	var mods := {}
	var files := {}
	var shown := 0
	for ref in _index.mapgens:
		if query and not _matches(ref, query):
			continue
		if shown >= MAX_RESULTS:
			shown += 1
			continue
		shown += 1
		var mod_item: TreeItem = mods.get(ref.source.mod)
		if mod_item == null:
			mod_item = _tree.create_item(root)
			var info := _index.catalog.get_mod(ref.source.mod)
			mod_item.set_text(0, info.name if info else ref.source.mod)
			mod_item.set_tooltip_text(0, ref.source.mod)
			mod_item.set_selectable(0, false)
			mod_item.set_selectable(1, false)
			mod_item.collapsed = query.is_empty() and not mods.is_empty()
			mods[ref.source.mod] = mod_item
		var file_item: TreeItem = files.get(ref.source.path)
		if file_item == null:
			file_item = _tree.create_item(mod_item)
			file_item.set_text(0, _file_label(ref))
			file_item.set_tooltip_text(0, ref.source.path)
			file_item.set_selectable(0, false)
			file_item.set_selectable(1, false)
			file_item.collapsed = query.is_empty()
			files[ref.source.path] = file_item
		var item := _tree.create_item(file_item)
		var text := entry_text(ref)
		item.set_text(0, text[0])
		item.set_text(1, text[1])
		item.set_metadata(0, ref)
		item.set_tooltip_text(0, "%s\n%s #%d" % [", ".join(ref.ids), ref.source.path, ref.source.index])
		if ref.method != "json":
			item.set_custom_color(0, Color(0.5, 0.5, 0.5))
			item.set_tooltip_text(0, "Lua mapgen: not supported")
	if shown > MAX_RESULTS:
		_count.text = "%d matches (first %d shown)" % [shown, MAX_RESULTS]
	else:
		_count.text = "%d mapgen entries" % shown


## A file's path within its mod's data folder.
func _file_label(ref: DataIndex.MapgenRef) -> String:
	var info := _index.catalog.get_mod(ref.source.mod)
	if info:
		var rel := _index.relative_path(info.path)
		if ref.source.path.begins_with(rel + "/"):
			return ref.source.path.substr(rel.length() + 1)
	return ref.source.path


func _on_activated() -> void:
	var item := _tree.get_selected()
	if item and item.get_metadata(0) is DataIndex.MapgenRef:
		open_requested.emit(item.get_metadata(0))


func _open_first() -> void:
	var item := _tree.get_root().get_first_child() if _tree.get_root() else null
	while item and not item.get_metadata(0) is DataIndex.MapgenRef:
		item = item.get_next_in_tree()
	if item:
		item.select(0)
		open_requested.emit(item.get_metadata(0))

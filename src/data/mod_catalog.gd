class_name ModCatalog
extends RefCounted
## The mods (content packs) in a BN checkout, and the order to load them in.
##
## Mirrors BN's mod_manager: every file named modinfo.json under data/mods
## (searched recursively) can hold MOD_INFO objects. Core is itself a mod
## ("bn", "core": true, "path": "../../json"). A mod's data lives in the folder
## of its modinfo.json joined with its optional "path".


class ModInfo:
	var id := ""
	var name := ""
	var core := false
	var obsolete := false
	var dependencies := PackedStringArray()
	var conflicts := PackedStringArray()
	## Absolute, simplified data folder.
	var path := ""
	## Absolute path of the modinfo.json that defined it.
	var info_file := ""


class LoadOrder:
	var mods := PackedStringArray()
	## Empty on success.
	var errors := PackedStringArray()

	func ok() -> bool:
		return errors.is_empty()


var bn_path := ""
## id -> ModInfo
var mods := {}
## Problems found while scanning (duplicate ids, unreadable files).
var errors := PackedStringArray()


static func scan(p_bn_path: String) -> ModCatalog:
	var catalog := ModCatalog.new()
	catalog.bn_path = p_bn_path
	catalog._scan()
	return catalog


func _scan() -> void:
	var dupes := {}
	var found: Array[ModInfo] = []
	for file in _find_modinfo_files(bn_path.path_join("data/mods")):
		for info in _read_modinfo(file):
			found.append(info)
	for info in found:
		if mods.has(info.id):
			dupes[info.id] = true
		mods[info.id] = info
	# Like BN: mods sharing an id are all dropped.
	for id: String in dupes:
		mods.erase(id)
		errors.append("several mods have id \"%s\"; none of them are loaded" % id)


static func _find_modinfo_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f == "modinfo.json":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_find_modinfo_files(dir.path_join(d)))
	return out


func _read_modinfo(file: String) -> Array[ModInfo]:
	var out: Array[ModInfo] = []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK:
		errors.append("%s: %s" % [file, json.get_error_message()])
		return out
	var objects: Variant = json.data
	if objects is Dictionary:
		objects = [objects]
	if not objects is Array:
		return out
	for o: Variant in objects:
		if not (o is Dictionary and o.get("type") == "MOD_INFO"):
			continue
		var info := ModInfo.new()
		info.id = str(o.get("id", o.get("ident", "")))
		info.name = str(o.get("name", info.id))
		info.core = o.get("core", false) == true
		info.obsolete = o.get("obsolete", false) == true
		info.dependencies = PackedStringArray(o.get("dependencies", []))
		info.conflicts = PackedStringArray(o.get("conflicts", []))
		info.path = file.get_base_dir().path_join(str(o.get("path", ""))).simplify_path()
		info.info_file = file
		out.append(info)
	return out


func has(id: String) -> bool:
	return mods.has(id)


func get_mod(id: String) -> ModInfo:
	return mods.get(id)


## Ids of every core mod, sorted.
func core_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in mods:
		if mods[id].core:
			out.append(id)
	out.sort()
	return out


## The order BN loads [param selected] in: duplicates dropped, the core mod
## first (the "bn" mod if none was selected), and each mod's dependencies
## placed before it (BN's mod manager adds those when a mod is picked).
## Otherwise the selection order is kept, since later mods override earlier ones.
func load_order(selected: PackedStringArray) -> LoadOrder:
	var result := LoadOrder.new()
	var wanted := PackedStringArray()
	var core := ""
	for id in selected:
		if not mods.has(id):
			result.errors.append("unknown mod \"%s\"" % id)
		elif mods[id].core:
			if core.is_empty():
				core = id
			elif core != id:
				result.errors.append("more than one core mod selected (%s, %s)" % [core, id])
		elif not wanted.has(id):
			wanted.append(id)
	if core.is_empty():
		core = "bn"
		if not mods.has(core):
			result.errors.append("core mod \"bn\" not found")
			return result
	result.mods.append(core)
	for id in wanted:
		_add_with_dependencies(id, result, PackedStringArray())
	for id in result.mods:
		for other in mods[id].conflicts:
			if result.mods.has(other):
				result.errors.append("mod \"%s\" conflicts with \"%s\"" % [id, other])
	return result


func _add_with_dependencies(id: String, result: LoadOrder, visiting: PackedStringArray) -> void:
	if result.mods.has(id):
		return
	if visiting.has(id):
		result.errors.append("dependency loop: %s -> %s" % [" -> ".join(visiting), id])
		return
	if not mods.has(id):
		result.errors.append("missing dependency \"%s\" (needed by %s)" % [id, visiting[-1]])
		return
	visiting.append(id)
	for dep in mods[id].dependencies:
		if mods.has(dep) and mods[dep].core:
			if dep != result.mods[0]:
				result.errors.append("mod \"%s\" needs core \"%s\"" % [id, dep])
			continue
		_add_with_dependencies(dep, result, visiting)
	visiting.remove_at(visiting.size() - 1)
	result.mods.append(id)

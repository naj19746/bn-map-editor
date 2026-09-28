class_name Computer
extends RefCounted
## One computer as mapgen writes it: a "computers" symbol mapping value or
## a place_computers entry, read the way BN reads it (mapgen.cpp:
## jmapgen_computer; computer.cpp: computer_option/computer_failure
## ::from_json; computer_session.cpp for what each action does).
##
## Wherever a computer lands BN sets t_console and f_null, whatever the
## symbol's own terrain says. "name" and "access_denied" are translations,
## "security" an int (default 0), "target" a bool (the mission target),
## "options" [{name, action, security}] and "failures" [{action}]. Options
## and failures are read only when they're lists; an unknown action, or an
## entry that isn't an object, makes BN refuse the map.
##
## [member data] is the JSON object itself: the setters change it in place
## and keep every field they don't touch as it is written, in its order.

## The terrain BN puts under every computer.
const CONSOLE := "t_console"

enum Group { DOORS, INFO, SPECIAL }
const GROUP_NAMES := ["Doors", "Info", "Special"]

## action -> [label, Group, what it does]. Every value of BN's
## computer_action but "null".
const ACTIONS := {
	"unlock": ["Unlock doors", Group.DOORS, "Turns every locked metal door (t_door_metal_locked) within 8 of the player into a closed metal door."],
	"unlock_disarm": ["Unlock doors, disarm turrets", Group.DOORS, "Like unlock, and removes the turrets of the player's submap."],
	"unlock_labpass": ["Unlock with a lab pass", Group.DOORS, "Needs (and uses up) a lab pass (labpass), then unlocks and disarms like unlock_disarm."],
	"lock": ["Lock doors", Group.DOORS, "Turns every closed metal door (t_door_metal_c) within 8 of the player back into a locked one."],
	"open": ["Open doors", Group.DOORS, "Turns every locked metal door within 25 of the player into floor (t_floor): the door is gone."],
	"open_disarm": ["Open doors, disarm turrets", Group.DOORS, "Like open, and removes the turrets of the player's submap."],
	"shutters": ["Toggle shutters", Group.DOORS, "Opens closed reinforced glass shutters within 8 of the player and closes open ones."],
	"release": ["Release specimens", Group.DOORS, "Sounds an alarm and turns reinforced glass (t_reinforced_glass) within 25 of the player into floor."],
	"release_bionics": ["Release bionics", Group.DOORS, "Sounds an alarm and turns reinforced glass within 3 of the player into floor."],
	"release_disarm": ["Release bionics, disarm turrets", Group.DOORS, "Like release_bionics, and removes the turrets of the player's submap."],
	"elevator_on": ["Activate elevator", Group.DOORS, "Switches on every elevator control (t_elevator_control_off) on the z-level."],
	"amigara_log": ["Amigara log", Group.INFO, "Shows the Amigara mine logs."],
	"blood_anal": ["Blood analysis", Group.INFO, "Analyzes a blood sample in a centrifuge (f_centrifuge) next to the console."],
	"data_anal": ["Memory bank analysis", Group.INFO, "Reads a memory bank placed next to the console."],
	"emerg_mess": ["Emergency message", Group.INFO, "Shows the emergency evacuation message."],
	"emerg_ref_center": ["Refugee center directions", Group.INFO, "Marks the nearest refugee center (gives the reach-the-refugee-center mission)."],
	"list_bionics": ["List bionics", Group.INFO, "Lists the bionics stored on the z-level."],
	"maps": ["Download area map", Group.INFO, "Reveals the overmap for 40 tiles around."],
	"map_sewer": ["Download sewer map", Group.INFO, "Reveals the sewers around."],
	"map_subway": ["Download subway map", Group.INFO, "Reveals the subway around."],
	"radio_archive": ["Radio archive", Group.INFO, "Plays the radio archive."],
	"research": ["Research notes", Group.INFO, "Shows lab research notes; raises the alert level."],
	"sr1_mess": ["Sarcophagus reminder 1", Group.INFO, "A hazardous waste sarcophagus security reminder."],
	"sr2_mess": ["Sarcophagus reminder 2", Group.INFO, "A hazardous waste sarcophagus security reminder."],
	"sr3_mess": ["Sarcophagus reminder 3", Group.INFO, "A hazardous waste sarcophagus security reminder."],
	"sr4_mess": ["Sarcophagus reminder 4", Group.INFO, "A hazardous waste sarcophagus security reminder."],
	"srcf_1_mess": ["Sarcophagus memo 1", Group.INFO, "A hazardous waste sarcophagus memo."],
	"srcf_2_mess": ["Sarcophagus memo 2", Group.INFO, "A hazardous waste sarcophagus memo."],
	"srcf_3_mess": ["Sarcophagus memo 3", Group.INFO, "A hazardous waste sarcophagus memo."],
	"srcf_seal_order": ["Sarcophagus seal order", Group.INFO, "Shows the order to seal the sarcophagus."],
	"tower_unresponsive": ["Radio tower unresponsive", Group.INFO, "Says the radio tower is unresponsive."],
	"geiger": ["Radiation readings", Group.INFO, "Shows the radiation around the console and the player's dose."],
	"amigara_start": ["Amigara start", Group.SPECIAL, "Starts the Amigara horror event."],
	"cascade": ["Resonance cascade", Group.SPECIAL, "Starts a resonance cascade (portals and explosions)."],
	"complete_disable_external_power": ["Disable external power", Group.SPECIAL, "Completes the Old Guard \"disable external power\" mission."],
	"conveyor": ["Run conveyor", Group.SPECIAL, "Cycles the irradiator's conveyor belt (loading bay, platform, unloading bay)."],
	"deactivate_shock_vent": ["Deactivate shock vents", Group.SPECIAL, "Removes shock vent fields within 10 of the player."],
	"disconnect": ["Disconnect", Group.SPECIAL, "Shows a disconnect message."],
	"download_software": ["Download software", Group.SPECIAL, "Gives the mission's software onto a USB drive (needs \"target\")."],
	"extract_rad_source": ["Extract radiation source", Group.SPECIAL, "Takes cobalt-60 from a radiation platform (t_rad_platform) within 10."],
	"irradiator": ["Run irradiator", Group.SPECIAL, "Irradiates the items on a radiation platform."],
	"miss_disarm": ["Disarm missile", Group.SPECIAL, "Disarms the nuclear missile (the missile silo)."],
	"portal": ["Open portal", Group.SPECIAL, "Opens a portal between the radio towers of the lab."],
	"repeater_mod": ["Install repeater mod", Group.SPECIAL, "Uses a radio repeater mod to complete the Old Guard radio mission."],
	"sample": ["Sewage sample", Group.SPECIAL, "Fills containers on counters next to sewage pumps with sewage."],
	"srcf_elevator": ["Sarcophagus elevator", Group.SPECIAL, "Powers the sarcophagus elevators (needs the access code)."],
	"srcf_seal": ["Seal sarcophagus", Group.SPECIAL, "Detonates the charges that seal the sarcophagus."],
	"terminate": ["Terminate specimens", Group.SPECIAL, "Kills monsters in the containment cells of the z-level."],
	"toll": ["Toll the bells", Group.SPECIAL, "Rings the church bells (a very loud sound)."],
}

## Actions that change terrain around the player: action -> [the terrain
## ids it changes, the terrain they become, radius (0: the whole z-level),
## toggles back]. Radius actions use map::translate_radius with the
## player's position (next to the console), trig distance, and only in the
## player's own overmap tile. "lock" counts a locked door too: it re-locks
## what an unlock opened.
const EFFECTS := {
	"unlock": [["t_door_metal_locked"], "t_door_metal_c", 8, false],
	"unlock_disarm": [["t_door_metal_locked"], "t_door_metal_c", 8, false],
	"unlock_labpass": [["t_door_metal_locked"], "t_door_metal_c", 8, false],
	"lock": [["t_door_metal_c", "t_door_metal_locked"], "t_door_metal_locked", 8, false],
	"open": [["t_door_metal_locked"], "t_floor", 25, false],
	"open_disarm": [["t_door_metal_locked"], "t_floor", 25, false],
	"shutters": [["t_reinforced_glass_shutter_open", "t_reinforced_glass_shutter"], "t_reinforced_glass_shutter", 8, true],
	"release": [["t_reinforced_glass"], "t_thconc_floor", 25, false],
	"release_bionics": [["t_reinforced_glass"], "t_thconc_floor", 3, false],
	"release_disarm": [["t_reinforced_glass"], "t_thconc_floor", 3, false],
	"elevator_on": [["t_elevator_control_off"], "t_elevator_control", 0, false],
}
## Actions that unlock or open doors, whose reach may hold other kinds of
## locked doors they never touch.
const UNLOCKS := ["unlock", "unlock_disarm", "unlock_labpass", "open", "open_disarm"]

## failure -> [label, what happens]. Every value of BN's
## computer_failure_type but "null".
const FAILURES := {
	"shutdown": ["Shut down", "The console breaks (t_console_broken)."],
	"alarm": ["Alarm", "A loud alarm; above ground, the police come after a while."],
	"manhacks": ["Manhacks", "4-8 manhacks drop from the ceiling."],
	"secubots": ["Secubot", "A secubot comes out of the floor."],
	"damage": ["Shock", "The console shocks the player (1-10 damage everywhere)."],
	"destroy_blood": ["Destroy blood sample", "Destroys a blood sample in a centrifuge nearby."],
	"destroy_data": ["Destroy memory bank", "Destroys a memory bank next to the console."],
	"pump_explode": ["Pump explodes", "The z-level's sewage pumps explode."],
	"pump_leak": ["Pump leaks", "The z-level's sewage pumps leak sewage."],
	"amigara": ["Amigara", "Starts the Amigara horror and explosions."],
}

## Where a missing field goes, in the order data uses.
const FIELD_ORDER := ["name", "access_denied", "security", "target", "options", "failures"]
const OPTION_ORDER := ["name", "action", "security"]

const SECURITY_HINT := "0: anyone can use it. Above 0, logging in needs a hack: Computer skill d6s " \
		+ "against this many d6s (3 is about even at Computer 3). A failed hack fires one random " \
		+ "failure below, or locks the console for 45 minutes if there are none; a success sets it to 0."
const OPTION_SECURITY_HINT := "An option with its own security asks for another hack before it runs " \
		+ "(and a failed one fires a failure too)."
const TARGET_HINT := "Links the console to the mission that generated the map (download_software uses it)."

## Ready-made computers: id -> [label, description, the JSON].
const PRESETS := {
	"door": ["Door control", "Anyone can unlock the locked metal doors near it.", {
		"name": "Door control",
		"options": [{"name": "Unlock doors", "action": "unlock"}],
	}],
	"secured": ["Secured door", "Needs a hack (security 3); a failure shuts it down, sounds an alarm or drops manhacks (like the police station's).", {
		"name": "Security terminal",
		"security": 3,
		"options": [{"name": "Unlock doors", "action": "unlock"}],
		"failures": [{"action": "shutdown"}, {"action": "alarm"}, {"action": "manhacks"}],
	}],
	"lab": ["Lab door", "Unlocks with a lab pass, or a hard hack (like the labs').", {
		"name": "Lab entrance",
		"security": 1,
		"options": [{"name": "UNLOCK ENTRANCE", "action": "unlock", "security": 5},
			{"name": "ENTER EMERGENCY OVERRIDE CODE", "action": "unlock_labpass"}],
		"failures": [{"action": "damage"}, {"action": "shutdown"}],
	}],
}

## What kind of problem an entry of issues() is.
enum Issue {
	## Not an object (or, for a mapping value, a list of objects).
	NOT_OBJECT,
	## "options"/"failures" is there but not a list: BN ignores it.
	NOT_LIST,
	## An entry of "options"/"failures" isn't an object: a JSON error.
	ENTRY_NOT_OBJECT,
	## An option or failure without an "action": a JSON error.
	NO_ACTION,
	## An unknown option or failure action: a JSON error.
	UNKNOWN_ACTION,
	## "security" isn't an int, "target" isn't a bool, ...: a JSON error.
	MALFORMED,
	## No options: the console does nothing.
	NO_OPTIONS,
}

var data: Dictionary


static func of(p_data: Dictionary) -> Computer:
	var c := Computer.new()
	c.data = p_data
	return c


## The computers a mapping value holds: an object, or a list of them (BN
## places each; the last one stays). Not-objects are left out.
static func all_in(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Variant in (value if value is Array else [value]):
		if v is Dictionary:
			out.append(v)
	return out


## A copy of preset [param id]'s JSON.
static func preset(id: String) -> Dictionary:
	return PRESETS[id][2].duplicate(true)


## "Unlock doors", or the action itself for an unknown one.
static func action_label(action: String) -> String:
	return ACTIONS[action][0] if ACTIONS.has(action) else action


## One line on what [param action] does, "" if unknown.
static func action_text(action: String) -> String:
	return ACTIONS[action][2] if ACTIONS.has(action) else ""


## The actions of [param group], in label order.
static func actions_in(group: Group) -> PackedStringArray:
	var out: Array = ACTIONS.keys().filter(func(a: String) -> bool: return ACTIONS[a][1] == group)
	out.sort_custom(func(a: String, b: String) -> bool: return ACTIONS[a][0] < ACTIONS[b][0])
	return PackedStringArray(out)


## A translation's text: a string, or an object's "str".
static func _text(v: Variant) -> String:
	if v is String:
		return v
	if v is Dictionary:
		return str(v.get("str", v.get("str_sp", "")))
	return ""


# --- Reading -------------------------------------------------------------------

func name() -> String:
	return _text(data.get("name"))


func access_denied() -> String:
	return _text(data.get("access_denied"))


func security() -> int:
	var v: Variant = data.get("security", 0)
	return int(v) if v is int or v is float else 0


func target() -> bool:
	return data.get("target") == true


## The options that are objects, as written.
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Variant = data.get("options")
	if list is Array:
		for o: Variant in list:
			if o is Dictionary:
				out.append(o)
	return out


## The option actions, in order ("" for a missing one).
func actions() -> PackedStringArray:
	var out := PackedStringArray()
	for o in options():
		out.append(str(o.get("action", "")))
	return out


## The failure actions, in order (duplicates kept: each is one pick).
func failures() -> PackedStringArray:
	var out := PackedStringArray()
	var list: Variant = data.get("failures")
	if list is Array:
		for f: Variant in list:
			if f is Dictionary:
				out.append(str(f.get("action", "")))
	return out


## The option actions that change terrain around it (see EFFECTS).
func door_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for a in actions():
		if EFFECTS.has(a) and not out.has(a):
			out.append(a)
	return out


## One line for lists: "Door control: unlock (security 3)".
func summary() -> String:
	var acts := actions()
	var text := name() if name() else "(no name)"
	text += ": " + (", ".join(acts) if not acts.is_empty() else "no options")
	if security() > 0:
		text += " (security %d)" % security()
	return text


## [Issue, text] for everything BN would reject, ignore or find odd.
func issues() -> Array:
	var out := []
	for member in ["name", "access_denied"]:
		if data.has(member) and not (data[member] is String or data[member] is Dictionary):
			out.append([Issue.MALFORMED, "\"%s\" must be a string" % member])
	if data.has("security") and not Placement.IntRange._is_int(data.security):
		out.append([Issue.MALFORMED, "\"security\" must be an int"])
	if data.has("target") and not data.target is bool:
		out.append([Issue.MALFORMED, "\"target\" must be true or false"])
	for pair in [["options", ACTIONS, "option"], ["failures", FAILURES, "failure"]]:
		var member: String = pair[0]
		var known: Dictionary = pair[1]
		if not data.has(member):
			continue
		var list: Variant = data[member]
		if not list is Array:
			out.append([Issue.NOT_LIST, "\"%s\" isn't a list, so BN ignores it" % member])
			continue
		for i in list.size():
			var e: Variant = list[i]
			var what := "%s #%d" % [pair[2], i + 1]
			if not e is Dictionary:
				out.append([Issue.ENTRY_NOT_OBJECT, "%s isn't an object" % what])
			elif not e.get("action") is String:
				out.append([Issue.NO_ACTION, "%s has no \"action\"" % what])
			elif not known.has(e.action):
				out.append([Issue.UNKNOWN_ACTION, "%s: unknown action \"%s\"" % [what, e.action]])
			elif member == "options" and e.has("security") and not Placement.IntRange._is_int(e.security):
				out.append([Issue.MALFORMED, "%s: \"security\" must be an int" % what])
	if options().is_empty() and not (data.get("options") is Array and not data.options.is_empty()):
		out.append([Issue.NO_OPTIONS, "it has no options, so the console does nothing"])
	return out


# --- Editing -------------------------------------------------------------------

func set_name(text: String) -> void:
	if text != name() or not data.has("name"):
		_put("name", text)


## "" removes it (BN's default message then).
func set_access_denied(text: String) -> void:
	if text.is_empty():
		data.erase("access_denied")
	elif text != access_denied():
		_put("access_denied", text)


## 0 is BN's default, so it's only written if it already was.
func set_security(n: int) -> void:
	if n == 0 and not data.has("security"):
		return
	if not (data.has("security") and security() == n):
		_put("security", n)


func set_target(on: bool) -> void:
	if on:
		_put("target", true)
	else:
		data.erase("target")


## Adds an option at the end. Security 0 isn't written.
func add_option(option_name: String, action: String, sec := 0) -> void:
	var list: Array = data.get("options") if data.get("options") is Array else []
	var o := {"name": option_name, "action": action}
	if sec != 0:
		o["security"] = sec
	list.append(o)
	_put("options", list)


## Changes option #[param i]: only the fields whose value differs, so an
## untouched option keeps its form.
func set_option(i: int, option_name: String, action: String, sec: int) -> void:
	var o: Dictionary = options()[i]
	if _text(o.get("name")) != option_name or not o.has("name"):
		ObjectMembers.set_member(o, "name", option_name, OPTION_ORDER)
	if o.get("action") != action:
		ObjectMembers.set_member(o, "action", action, OPTION_ORDER)
	var had: Variant = o.get("security")
	if sec == 0 and had == null:
		pass
	elif not (Placement.IntRange._is_int(had) and int(had) == sec):
		ObjectMembers.set_member(o, "security", sec, OPTION_ORDER)


func remove_option(i: int) -> void:
	var o := options()[i]
	var list: Array = data.options
	list.erase(o)
	if list.is_empty():
		data.erase("options")


## Moves option #[param i] to [param to].
func move_option(i: int, to: int) -> void:
	var list: Array = data.options
	var o := options()[i]
	var dest := options()[to]
	list.erase(o)
	list.insert(list.find(dest) + (1 if to > i else 0), o)


## Turns failure [param action] on (added at the end) or off (every copy
## removed; the list goes when empty).
func set_failure(action: String, on: bool) -> void:
	var has := failures().has(action)
	if on == has:
		return
	var list: Array = data.get("failures") if data.get("failures") is Array else []
	if on:
		list.append({"action": action})
	else:
		list = list.filter(func(f: Variant) -> bool: return not (f is Dictionary and f.get("action") == action))
	if list.is_empty():
		data.erase("failures")
	else:
		_put("failures", list)


## Replaces security, options and failures with preset [param id]'s,
## keeping the name (and access-denied text) if there is one.
func apply_preset(id: String) -> void:
	var p := preset(id)
	if name().is_empty():
		set_name(p.name)
	data.erase("security")
	data.erase("options")
	data.erase("failures")
	for key in ["security", "options", "failures"]:
		if p.has(key):
			_put(key, p[key])


func _put(key: String, value: Variant) -> void:
	ObjectMembers.set_member(data, key, value, FIELD_ORDER)


# --- Reach ---------------------------------------------------------------------

## Where the player can stand to use a console at [param at]: the 8
## neighbours inside [param size] that [param passable] (cell -> bool)
## accepts.
static func stand_cells(at: Vector2i, size: Vector2i, passable: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var c := at + Vector2i(dx, dy)
			if (dx or dy) and c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y and passable.call(c):
				out.append(c)
	return out


## The cells within reach of a player at [param stand] for an action of
## [param radius]: trig distance, and only in the stand cell's overmap tile
## (of 24x24 cells), cut to [param size].
static func reach_rect(stand: Vector2i, radius: int, size: Vector2i) -> Rect2i:
	var tile := Rect2i(stand / Placement.OMT * Placement.OMT, Vector2i(Placement.OMT, Placement.OMT))
	var box := Rect2i(stand - Vector2i(radius, radius), Vector2i(radius, radius) * 2 + Vector2i.ONE)
	return box.intersection(tile).intersection(Rect2i(Vector2i.ZERO, size))


static func in_reach(stand: Vector2i, cell: Vector2i, radius: int) -> bool:
	return stand / Placement.OMT == cell / Placement.OMT and Vector2(cell - stand).length() <= radius + 0.0001


## True for terrain that is some kind of locked door (not [param but]'s).
static func is_locked_door(ter_id: String, but: Array) -> bool:
	return ter_id.begins_with("t_door") and ter_id.contains("locked") and not but.has(ter_id)

class_name SyncDialog
extends AcceptDialog
## The Sync window: lists workspace files against the BN checkout, with an
## object-level summary of what pushing each would change, and pushes the
## checked ones into BN (see WorkspaceSync).
##
## Conflicts start unchecked; pushing a checked conflict asks first and
## overwrites BN's version. A file with unsaved edits in the editor can't be
## pushed until it is saved, and a file open in the editor can't be discarded.

## Files were pushed into BN or discarded from the workspace. [param
## reload_needed] is true when the loaded data may now be out of date (a
## discarded workspace copy's content is still in the index).
signal files_changed(reload_needed: bool)

var sync: WorkspaceSync
var session: EditSession
var statuses: Array[WorkspaceSync.FileStatus] = []
var tree: Tree
var details: TextEdit
var push_button: Button
var discard_button: Button
var _header: Label
var _confirm: ConfirmationDialog
var _pending := Callable()


func _init() -> void:
	title = "Sync with BN"
	ok_button_text = "Close"
	min_size = Vector2i(900, 560)
	var box := VBoxContainer.new()
	add_child(box)
	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_header)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	tree = Tree.new()
	tree.columns = 3
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.set_column_title(0, "File")
	tree.set_column_title(1, "Status")
	tree.set_column_title(2, "Objects")
	tree.set_column_expand_ratio(0, 3)
	tree.set_column_expand_ratio(1, 2)
	tree.set_column_expand_ratio(2, 2)
	tree.custom_minimum_size = Vector2(0, 260)
	tree.item_selected.connect(_show_details)
	tree.item_edited.connect(_update_buttons)
	split.add_child(tree)
	details = TextEdit.new()
	details.editable = false
	details.custom_minimum_size = Vector2(0, 140)
	split.add_child(details)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Compare the workspace with BN again"
	refresh.pressed.connect(refresh_list)
	buttons.add_child(refresh)
	push_button = Button.new()
	push_button.text = "Push checked to BN"
	push_button.tooltip_text = "Copy the checked files into the BN checkout and drop their workspace copies.\nNothing is committed; review and commit in BN yourself."
	push_button.pressed.connect(_on_push_pressed)
	buttons.add_child(push_button)
	discard_button = Button.new()
	discard_button.text = "Discard workspace copy..."
	discard_button.tooltip_text = "Delete the selected file's workspace copy (its edits are lost) and use BN's file again"
	discard_button.pressed.connect(_on_discard_pressed)
	buttons.add_child(discard_button)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func() -> void:
		var then := _pending
		_pending = Callable()
		then.call())
	add_child(_confirm)


func open(p_session: EditSession) -> void:
	setup(p_session)
	popup_centered_ratio(0.7)


func setup(p_session: EditSession) -> void:
	session = p_session
	sync = WorkspaceSync.new(session.workspace)
	refresh_list()


## Scans again and rebuilds the list, keeping what was checked.
func refresh_list() -> void:
	# rel -> checked, for rows already listed.
	var was_checked := {}
	if tree.get_root():
		for item in tree.get_root().get_children():
			was_checked[item.get_metadata(0).rel] = item.is_checked(0)
	var ws := session.workspace
	var commit := Workspace.bn_commit(ws.bn_path)
	_header.text = "Workspace: %s\nBN: %s%s\nPush copies files into BN and deletes their workspace copies. Nothing is committed." % [
		ws.root, ws.bn_path, " (at %s)" % commit.left(10) if commit else ""]
	statuses = sync.scan()
	tree.clear()
	var root := tree.create_item()
	for s in statuses:
		var item := tree.create_item(root)
		var blocked := _push_blocker(s)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, blocked.is_empty())
		item.set_checked(0, blocked.is_empty() and was_checked.get(s.rel, not s.is_conflict()))
		item.set_text(0, s.rel)
		item.set_text(1, s.text() + ("; " + blocked if blocked else ""))
		if s.is_conflict() or s.state == WorkspaceSync.State.MISSING:
			item.set_custom_color(1, Color(1, 0.6, 0.5))
		item.set_text(2, "" if s.state in [WorkspaceSync.State.SAME, WorkspaceSync.State.MISSING] else s.summary_text())
		item.set_tooltip_text(0, s.rel)
		item.set_metadata(0, s)
	if statuses.is_empty():
		details.text = "The workspace has no files. Edits saved in the editor show up here."
	else:
		details.text = "Select a file for details."
	_update_buttons()


## The checked files.
func checked() -> Array[WorkspaceSync.FileStatus]:
	var out: Array[WorkspaceSync.FileStatus] = []
	var root := tree.get_root()
	if root == null:
		return out
	for item in root.get_children():
		if item.is_checked(0):
			out.append(item.get_metadata(0))
	return out


func set_checked(rel: String, on: bool) -> void:
	for item in tree.get_root().get_children():
		if item.get_metadata(0).rel == rel:
			item.set_checked(0, on)
	_update_buttons()


func selected() -> WorkspaceSync.FileStatus:
	var item := tree.get_selected()
	return item.get_metadata(0) if item else null


## Why [param s] can't be pushed right now, or "".
func _push_blocker(s: WorkspaceSync.FileStatus) -> String:
	if not s.can_push():
		return "nothing to push"
	if session.is_dirty(s.rel):
		return "unsaved changes in the editor, save first"
	return ""


## Pushes [param rels]; conflicts among them are overwritten only with
## [param overwrite]. Returns the errors.
func push(rels: PackedStringArray, overwrite := false) -> PackedStringArray:
	var errors := PackedStringArray()
	var done := 0
	for rel in rels:
		var err := "unsaved changes in the editor, save first" if session.is_dirty(rel) else sync.push(rel, overwrite)
		if err:
			errors.append("%s: %s" % [rel, err])
			continue
		session.mark_pushed(rel)
		done += 1
	refresh_list()
	var lines := PackedStringArray(["Pushed %d file(s) into %s." % [done, session.workspace.bn_path]])
	lines.append_array(errors)
	details.text = "\n".join(lines)
	if done:
		files_changed.emit(false)
	return errors


## Deletes the workspace copy of [param rel]. Returns an error or "".
func discard(rel: String) -> String:
	var err := "it's open in the editor, close its maps first" if session.files.has(rel) \
			else sync.remove_copy(rel)
	refresh_list()
	details.text = "Can't discard %s: %s" % [rel, err] if err else "Discarded the workspace copy of %s." % rel
	if not err:
		files_changed.emit(true)
	return err


func _on_push_pressed() -> void:
	var rels := PackedStringArray()
	var conflicts := PackedStringArray()
	for s in checked():
		rels.append(s.rel)
		if s.is_conflict():
			conflicts.append("%s (%s)" % [s.rel, s.text()])
	if rels.is_empty():
		return
	if conflicts.is_empty():
		push(rels)
		return
	_ask("Overwrite BN's version", "These files conflict with BN. Pushing them replaces BN's file, losing its changes since the base:\n  %s" % "\n  ".join(conflicts),
			"Overwrite", push.bind(rels, true))


func _on_discard_pressed() -> void:
	var s := selected()
	if s == null:
		return
	var what := "Forget %s? It is no longer in the workspace; this drops its manifest entry." % s.rel \
			if s.state == WorkspaceSync.State.MISSING \
			else "Delete the workspace copy of %s? Its edits are lost and BN's file is used again." % s.rel
	_ask("Discard workspace copy", what, "Discard", discard.bind(s.rel))


func _ask(p_title: String, text: String, ok: String, then: Callable) -> void:
	_confirm.title = p_title
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok
	_pending = then
	_confirm.popup_centered()


func _update_buttons() -> void:
	push_button.disabled = checked().is_empty()
	discard_button.disabled = selected() == null


func _show_details() -> void:
	_update_buttons()
	var s := selected()
	if s == null:
		return
	var lines := PackedStringArray([s.rel, "Status: " + s.text()])
	var blocked := _push_blocker(s)
	if blocked:
		lines.append("Can't push: " + blocked)
	if s.entry.get("new", false):
		lines.append("Base: a new file")
	elif s.entry.has("base_sha256"):
		lines.append("Base: sha256 %s, BN commit %s" % [str(s.entry.base_sha256).left(12),
				str(s.entry.get("base_commit", "")).left(10) if s.entry.get("base_commit", "") else "unknown"])
	else:
		lines.append("Base: none (not in the manifest)")
	match s.state:
		WorkspaceSync.State.CHANGED_IN_BN:
			lines.append("BN's file changed since the base. Pushing overwrites those changes; the list below compares with BN's file as it is now, so it includes them reversed.")
		WorkspaceSync.State.DELETED_IN_BN:
			lines.append("BN's file was deleted or renamed since the base. Pushing recreates it.")
		WorkspaceSync.State.ADDED_IN_BN:
			lines.append("BN now has its own file at this path. Pushing replaces it.")
		WorkspaceSync.State.UNTRACKED:
			lines.append("No base was recorded for this file, so BN's changes can't be told apart from the workspace's.")
		WorkspaceSync.State.SAME:
			lines.append("Identical to BN's file. Pushing just drops the workspace copy.")
		WorkspaceSync.State.MISSING:
			lines.append("The manifest lists it, but the workspace file is gone. Discard forgets the entry.")
	if s.summary_error:
		lines.append(s.summary_error)
	elif not s.changes.is_empty() or s.unchanged:
		lines.append("")
		lines.append("Pushing would change these objects in BN (%d unchanged):" % s.unchanged)
		for c in s.changes:
			lines.append("  " + str(c))
	details.text = "\n".join(lines)

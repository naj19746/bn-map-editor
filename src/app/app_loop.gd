class_name AppLoop
extends SceneTree
## The project's main loop (application/run/main_loop_type). Started with
## --mcp it serves MCP on stdio instead of opening the editor, so an exported
## build is also the MCP server:
##   <binary> --headless --mcp [--bn <path>] [--workspace <path>] [--mods <id,...>]
## The flags after --mcp are McpServer.serve_stdio's; Godot hands on the ones
## it doesn't know, so they may come before or after a "--". Only MCP
## messages may reach stdout, so the project turns off the engine's header
## (application/run/print_header).


func _initialize() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var at := args.find("--mcp")
	if at < 0:
		return
	# The main scene is already under root but not yet in the tree; free it
	# before it would build the editor.
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	if DisplayServer.get_name() != "headless":
		printerr("BN Map Editor: serving MCP on stdio; pass --headless to open no window.")
	McpServer.serve_stdio(args.slice(at + 1))
	quit()

extends SceneTree
## The BN Map Editor's MCP server, on stdio, run from source:
##   godot --headless --no-header --path . -s tools/mcp_server.gd -- \
##       [--bn <path>] [--workspace <path>] [--mods <id,id,...>]
## An exported build runs the same server with --mcp (AppLoop). See
## McpServer.serve_stdio for the defaults.


func _initialize() -> void:
	McpServer.serve_stdio(OS.get_cmdline_user_args())
	quit()

extends SceneTree
## The BN Map Editor's MCP server, on stdio (see McpServer, McpTools):
##   godot --headless --no-header --path . -s tools/mcp_server.gd -- \
##       [--bn <path>] [--workspace <path>] [--mods <id,id,...>]
## Defaults are the editor's: $BN_PATH or the saved BN folder (else
## ../Cataclysm-BN), the saved workspace (else the default one) and the
## saved mods. Only MCP messages go to stdout; errors go to stderr.


func _initialize() -> void:
	var settings := AppSettings.load_from()
	var bn := settings.effective_bn_path()
	if bn.is_empty() or not DirAccess.dir_exists_absolute(bn.path_join("data/json")):
		bn = ProjectSettings.globalize_path("res://").path_join("../Cataclysm-BN").simplify_path()
	var ws := settings.workspace_path if settings.workspace_path else Workspace.default_root()
	var mods := settings.mods
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1):
		match args[i]:
			"--bn": bn = args[i + 1]
			"--workspace": ws = args[i + 1]
			"--mods": mods = PackedStringArray(Array(args[i + 1].split(",", false)).map(
					func(m: String) -> String: return m.strip_edges()))
	var tools := McpTools.new(McpTools.load_session.bind(bn, mods, ws))
	McpServer.new(tools).run()
	quit()

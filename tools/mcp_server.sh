#!/usr/bin/env bash
# Starts the MCP server on stdio. Args go to tools/mcp_server.gd:
#   [--bn <path>] [--workspace <path>] [--mods <id,id,...>]
# Imports first (quietly, to stderr) so class_name globals resolve in a fresh
# checkout. Uses $GODOT, else `godot` on PATH.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"

if [ ! -f "$root/.godot/global_script_class_cache.cfg" ]; then
	"$godot" --headless --path "$root" --import >&2 2>/dev/null || true
fi
exec "$godot" --headless --no-header --path "$root" -s tools/mcp_server.gd -- "$@"

#!/usr/bin/env bash
# Runs the headless test suite. Extra args filter tests by "file::method" substring.
# Imports first so class_name globals resolve in a fresh checkout.
# Uses $GODOT, else `godot` on PATH.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"

"$godot" --headless --path "$root" --import >/dev/null 2>&1
exec "$godot" --headless --path "$root" -s tests/run_tests.gd -- "$@"

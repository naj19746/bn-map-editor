# BN Map Editor

A Godot 4.7 (GDScript) map editor for Cataclysm-BN JSON mapgen. The design, scope and staged
roadmap live in `PLAN.MD`; read it before starting a stage. BN is expected at `../Cataclysm-BN`
(override with `BN_PATH`).

## Commands

- Build json_formatter from the BN checkout into `build/`: `tools/build_json_formatter.sh [BN_PATH]`
  (uses `$CXX`, else clang++, else g++).
- Run all tests headless: `tools/run_tests.sh [FILTER...]`. A filter matches a `file::method`
  substring, e.g. `tools/run_tests.sh roundtrip`. Exit code is 1 on any failure.
- Tests call `godot --headless --path . --import` first. Without it, a fresh checkout has no
  class_name cache and `-s` scripts can't see `BnJson` etc.

## Layout

- `src/json/bn_json.gd` (`BnJson`): the JSON reader/writer used for anything that gets saved.
- `src/json/json_formatter.gd` (`JsonFormatter`): runs BN's json_formatter via a temp file.
- `src/data/`: read-only BN index. `ModCatalog` (mods, load order), `DataIndex` (terrain/furniture with
  copy-from, palettes, groups, mapgen refs by id), `MapgenResolver` -> `ResolvedMapgen` (a map's cells
  and what each symbol means, with sources), `CellText` (rows -> cells, BN's wcwidth rule).
- `src/edit/`: editing, no nodes. `EditSession` (open files/maps, save, new mapgen, overmap_terrain
  stubs), `MapDocument` (one mapgen: paint, new symbol, undo/redo, writes straight into the BnJson
  object), `JsonFile` (a parsed file; untouched top-level objects are written back as their
  original text), `Workspace` (workspace folder + manifest.json, never inside BN), `WorkspaceSync`
  (workspace vs BN status, object summary, push into BN), `MapTool`
  (Paint/Line/Rect/Fill/Pick on press/move/release), `Shapes`.
- `src/app/app_settings.gd` (`AppSettings`): settings in user://settings.cfg.
- `src/view/`: display logic without nodes, testable headless. `AsciiMap` (what each cell looks like,
  wall joining, hover text), `BnColors` (BN color names -> RGB).
- `src/ui/`: controls built in code (`MapCanvas`, `LegendPanel`, `MapBrowser`, `ModsDialog`,
  `NewSymbolDialog`, `NewMapDialog`, `SyncDialog`). `main.gd` builds the window;
  `godot --path . -- --open <id> [--bn <path>] [--workspace <path>]` opens a map at startup.
- `tests/test_*.gd`: test files; every `test_*` method runs. They extend
  `tests/support/test_case.gd` (`check`, `check_eq`, `skip`). `tests/support/bn_env.gd` finds BN;
  `tests/support/temp_tree.gd` builds fake BN checkouts in a temp dir.
- `tools/`: shell scripts. `build/`: local binaries (gitignored).

## Rules

- Never save with Godot's `JSON` class (it turns ints into floats). Save with
  `BnJson.stringify` and then `JsonFormatter.format`. `JSON.parse_string` is fine for read-only
  indexing, where it is ~20x faster than `BnJson.parse`.
- `check_eq` is type-strict (`1` != `1.0`). Keep it that way; int vs float is what breaks saves.
- Never write into the BN checkout, from tests or from the editor. Use a temp dir or the workspace.
  The one exception is `WorkspaceSync.push`, run only when the user pushes from the Sync window;
  tests push into a temp BN tree. UI tests set `main._workspace_override` to a temp dir (the
  default is the user's real workspace).
- Change a JsonFile object only through code that calls `touch(i)` first (MapDocument does);
  otherwise the change is invisible to `compose()` and `is_dirty()`.
- A script error inside a test is a failure (the runner hooks `Logger`), so a test that hits
  `push_error` on purpose will fail.
- Tests run inside `SceneTree._initialize`, before the root enters the tree: `_ready` doesn't fire
  and awaited frames never come. UI tests call `_ready()` directly (see `tests/test_viewer.gd`).
- Inner classes can't call their outer class's static functions unqualified; use
  `BnJson.encode_string(...)`.
- Commit the `*.uid` and `*.import` files Godot generates next to scripts and assets.

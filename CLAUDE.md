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

## MCP server

`tools/mcp_server.sh [--bn <path>] [--workspace <path>] [--mods <id,id>]` runs a stdio MCP server
(`tools/mcp_server.gd`; defaults are the editor's saved settings). Register it with Claude Code:
`claude mcp add bn-map-editor -- /abs/path/to/bn_map_editor/tools/mcp_server.sh`, or in `.mcp.json`:

```json
{"mcpServers": {"bn-map-editor": {"command": "/abs/path/to/bn_map_editor/tools/mcp_server.sh", "args": []}}}
```

- Read tools: search_maps, get_map, get_palette, validate_map, validate_palette, lookup_id,
  list_mods, sync_status, get_building, validate_building. Edit tools (in memory, one undo step per call): paint_cells/rect/line,
  fill, paint_rows (paint answers say what each key means: `keys`), add_symbol (or several: "symbols"),
  remove_symbol, rename_symbol, undo, redo, add/update/remove_placement (add several: "entries"; a
  batch is all or nothing, `MapDocument.cancel_group`), set_map_palettes, set_map_fields (fill_ter,
  rotation, predecessor_mapgen), set_symbol_mapping, create_mapgen (with "level": a building's new
  floor; a roof when an id has the word "roof", `BuildingLevels.is_roof_id`, or "level.roof");
  save (workspace only; a map's file also saves its linked building file), discard, reload.
  Levels: get_map's "levels", get_building, create_building. Palettes: edit_palette_key,
  set_palette_includes (both answer PaletteImpact's changed maps; dry_run measures only),
  rename_key (repaints the maps taking the key from it), create_palette, delete_palette,
  undo/redo with "palette" (undo also restores a deleted palette until its file is saved,
  in order with edits of another definition of its id).
- The editor and the server may share a workspace: a save refuses when the file changed on disk
  since it was read (`EditSession.check_on_disk`), and manifest changes go through
  `Workspace.set_entry`, which re-reads manifest.json first. Both notice the other's saves
  (`EditSession.external_changes`): the server before each tool call (reloads when clean, answering
  "reloaded"; else a "disk_warning"), the editor every 3 s and on focus (`main.check_disk`: reloads
  keeping the tabs, or a banner when there are unsaved edits). Writes the session makes itself
  (save; Sync's push/discard via `accept_external`) don't count.
- Only MCP messages may reach stdout: never `print()` in src/ (errors go to stderr).
- A handler returns a Dictionary or an `McpTools.Failure`; tests call them via `call_tool`, which
  checks the arguments against the tool's schema. Output values must be JSON types
  (`BnJson.stringify` rejects PackedStringArray: wrap with `Array()`).
- The index reads palettes with Godot's JSON (floats); `McpTools._exact_palettes` points the
  definitions a map uses at BnJson-read objects before resolving, so values come back as written.

## Layout

- `src/json/bn_json.gd` (`BnJson`): the JSON reader/writer used for anything that gets saved.
- `src/json/json_formatter.gd` (`JsonFormatter`): runs BN's json_formatter via a temp file.
- `src/data/`: read-only BN index. `ModCatalog` (mods, load order), `DataIndex` (terrain/furniture with
  copy-from, palettes, groups, mapgen refs by id), `MapgenResolver` -> `ResolvedMapgen` (a map's cells
  and what each symbol means, with sources), `DataIndex.buildings` (city_building / overmap_special
  z-stacks: `Building`, `BuildingTile`, `buildings_using(oter)`; `overmaps_source`, the definition
  whose "overmaps" list is in effect; `city_listed`, the region city lists naming a building;
  `has_mapgen_for(oter)`, JSON or BN's builtin C++ mapgens), `BuildingLevels` (a map's places in
  buildings, mutable specials using it, each level's
  tiles and mapgens, the step up/down; new level ids and fill suggestions), `Stairs` (cells that may
  hold stairs, elevator floor and elevator controls: every id choice, place_terrain/"set", every
  chunk pick; the Validator pairs stairs with the levels above/below as game::find_stairs does,
  and elevator controls with the floors iexamine::elevator offers), `CellText` (rows -> cells, BN's wcwidth rule),
  `Placement` (one place_*/"set" entry read BN's way: first-value anchor, dropped/crossing/reversed
  ranges, "set" in every OMT; `IntRange` keeps how a jmapgen_int is written), `ChunkOverlay` (the
  nested chunks a map places, laid over its cells in BN's order, rotation and recursion; footprints,
  overhang; chunk consoles per stamp; `forced` picks and `replay()` for judging other picks), `MapgenObjects` (a MapgenRef's object: open file live, else a cached parse),
  `Validator` (what BN would say about a map, palette or building (`validate_building`): findings
  with severity, "won't load" vs "reported on load", and a target to select; stair and elevator
  findings carry the other levels' mapgens; console reach, also for every chunk pick a map
  can place), `Computer` (one computer's JSON:
  action/failure tables, presets, form-keeping setters, reach geometry).
- `src/edit/`: editing, no nodes. `EditSession` (open files/maps, save, new mapgen, overmap_terrain
  stubs, a building's new level tiles and new buildings with their city list entry), `MapDocument` (one mapgen: paint, new symbol, placements, undo/redo, writes straight
  into the BnJson object), `JsonFile` (a parsed file; untouched top-level objects are written back as their
  original text), `Workspace` (workspace folder + manifest.json, never inside BN), `WorkspaceSync`
  (workspace vs BN status, object summary, push into BN), `MapTool`
  (Paint/Erase/Line/Rect/Fill/Pick on press/move/release; Erase paints `blank_key`, an undefined " " or "."), `PlacementTool` (Place: select/move/resize/add
  placements, kept inside one OMT), `Shapes`, `PaletteDocument` (one palette: a
  key's terrain/furniture and computer, includes, its own undo), `PaletteImpact` (which maps an edit changes,
  including maps placing a changed chunk, "via" it; where using maps paint a palette's console),
  `ObjectMembers` (member snapshots for undo). `PaletteImpact.plan_rename`: a palette key rename's
  repainted and changed maps.
- `src/app/app_settings.gd` (`AppSettings`): settings in user://settings.cfg.
- `src/mcp/`: the MCP server, no nodes. `McpServer` (JSON-RPC 2.0 over stdio lines: initialize,
  tools/list, tools/call), `McpTools` (tool name -> schema -> handler, loading the session on first use).
- `src/view/`: display logic without nodes, testable headless. `AsciiMap` (what each cell looks like,
  wall joining, hover text), `BnColors` (BN color names -> RGB), `LevelNav` (the rest of a
  map's level drawn around it, and the ghost level under it: each piece turned as placed, a
  turned multi-tile map split per tile; `placed()`, the map itself as placed, for View as placed), `ConsoleReachView` (what the canvas
  draws for a selected computer: stand cells, reach outline, doors reached; where a new door
  console could go), `RoofHints` (where a roof and the ghost level under it disagree).
- `src/ui/`: controls built in code (`MapCanvas`, `LegendPanel` (its fill_ter row: `MapDocument.set_fill_ter`, blank removes it), `MapBrowser`, `ModsDialog`,
  `NewSymbolDialog`, `NewMapDialog`, `NewBuildingDialog`, `SyncDialog`, `PaletteEditor`, `PlacementsPanel`,
  `ProblemsPanel`, `ComputerEditor`, `ComputerDialog`, `IdCompleter`: an id dropdown under a
  LineEdit, `WeightedIdList`: rows of id + weight for "chunks" and monster lists, `PieceEditor`:
  one piece's fields, used by PlacementsPanel and `SymbolPieces`: a symbol's "nested", "monster", "items", ...
  mappings (Placement.MAPPING_KINDS) in the Legend and PaletteEditor). `main.gd`
  builds the window;
  `godot --path . -- --open <id> [--bn <path>] [--workspace <path>]` opens a map at startup.
- `tests/test_*.gd`: test files; every `test_*` method runs. They extend
  `tests/support/test_case.gd` (`check`, `check_eq`, `skip`). `tests/support/bn_env.gd` finds BN;
  `tests/support/temp_tree.gd` builds fake BN checkouts in a temp dir.
- `tools/`: shell scripts, and `mcp_server.gd` (the MCP server's `-s` entry point). `build/`: local binaries (gitignored).

## Rules

- Never save with Godot's `JSON` class (it turns ints into floats). Save with
  `BnJson.stringify` and then `JsonFormatter.format`. `JSON.parse_string` is fine for read-only
  indexing, where it is ~20x faster than `BnJson.parse`.
- `check_eq` is type-strict (`1` != `1.0`). Keep it that way; int vs float is what breaks saves.
- Never write into the BN checkout, from tests or from the editor. Use a temp dir or the workspace.
  The one exception is `WorkspaceSync.push`, run only when the user pushes from the Sync window;
  tests push into a temp BN tree. UI tests set `main._workspace_override` to a temp dir (the
  default is the user's real workspace).
- Change a JsonFile object only through code that calls `touch(i)` first (MapDocument and
  PaletteDocument do); otherwise the change is invisible to `compose()` and `is_dirty()`.
- An open palette's `DataIndex.Definition.data` IS the live object in its JsonFile, so resolving
  anything sees unsaved palette edits. EditSession puts the index back from disk on discard.
- Don't bind a document into a callable connected to its own signal (a reference cycle; the runner
  then reports leaked objects). Bind an id or title instead.
- A script error inside a test is a failure (the runner hooks `Logger`), so a test that hits
  `push_error` on purpose will fail.
- Tests run inside `SceneTree._initialize`, before the root enters the tree: `_ready` doesn't fire
  and awaited frames never come. UI tests call `_ready()` directly (see `tests/test_viewer.gd`).
- Core must validate with no errors (BN's CI loads it cleanly): an error `test_validation_bn`
  finds in core is a false positive in the Validator, not a data bug.
- A validation test that loops or recurses forever fills Godot's log in
  `~/.local/share/godot/app_userdata/BN Map Editor/logs` (tens of GB), and every later Godot start
  then hangs rotating it. Delete the huge logs if Godot stops printing even its banner.
- `_draw` never runs in tests, nor under `--headless` at all, so canvas drawing code is untested.
  After changing it, run a scratch `-s` script without `--headless` that adds main.tscn to `root`,
  opens a map, waits a few frames in `_process` and saves `root.get_texture().get_image()`.
- A MapDocument's chunk overlay is built lazily and dropped on every change; EditSession only
  notifies maps whose built overlay drew the changed chunk or palette. Call `chunk_overlay()` in a
  test before expecting `overlay_changed`.
- Inner classes can't call their outer class's static functions unqualified; use
  `BnJson.encode_string(...)`.
- Godot's `JSON.stringify` sorts keys unless its third argument is false; TempTree writes values with
  it, so pass a fixture as text when its key order matters.
- A Range (SpinBox, slider) outside the scene tree doesn't emit `value_changed` when its value is
  set; a UI test emits it itself after setting the value.
- A TabContainer outside the tree ignores `current_tab`. main.gd switches drawer tabs with
  `show_drawer_tab()`, which also sets `drawer_tab`; code and tests read that, not `current_tab`.
- `MapDocument.begin_group()`/`end_group()` make several edits one undo step. `undo()`/`redo()`
  return an error when a step's file part refuses (the overmap_terrain stub, when something was
  appended after it).
- Take an object out of a file only through `EditSession._remove_object` (`JsonFile.remove`, then
  `DataIndex.shift_sources` and the open documents' `object_index`): every later object moves down
  one index, and everything holding an index must follow.
- When an open map changes, EditSession tells the other open maps of its buildings
  (`MapDocument.levels_changed`: their stair/elevator findings are forgotten) and emits `map_edited`;
  main redraws the current tab's neighbour/ghost pieces from it once a frame (`flush_level_views`,
  which tests call directly since `_process` never runs there).
- `OS.execute` joins its arguments into one shell command, so a quoted `sh -c` script gets mangled;
  write a script file and run that (see `tests/test_mcp.gd::test_stdio`).
- `main.settings_file` is where main saves settings (ghost level, Dim); UI tests set it to "" before
  `_ready()` so they never write the user's settings.
- Commit the `*.uid` and `*.import` files Godot generates next to scripts and assets.

Overview:
This project aims to create a map editor for Cataclysm-BN using Godot (4.7, GDScript). Cataclysm-BN can be
found next to this project in ../Cataclysm-BN. The editor must both round-trip existing BN mapgen files and
author new ones. Authoritative format reference: Cataclysm-BN/docs/en/mod/json/reference/map/mapgen.md.


Data sources:
 - Point the editor at a BN checkout. Index data/json plus user-selected mods in data/mods/*
   (mods carry their own mapgen, palettes, terrain and furniture).
 - Mapgen: data/json/mapgen (674 files). Palettes: data/json/mapgen_palettes.
 - Terrain/furniture definitions (id, symbol, color): data/json/furniture_and_terrain.
 - Multi-tile / multi-z linking: data/json/overmap (city_building, overmap_special).
 - A single file holds a JSON array of many objects, and mapgen folders also contain non-mapgen types
   (item_group, overmap_terrain, monstergroup, ...). These must be preserved untouched.


Mapgen format (what the editor models):
 - Top level: "type": "mapgen", "method": "json" (3 lua mapgens exist - out of scope), plus one of:
     - "om_terrain": a string, a list (same map reused for several ids), or a nested list (a multi-tile building).
     - "nested_mapgen_id" (a nested chunk, with "mapgensize") - ~1/3 of all entries.
     - "update_mapgen_id" (mission updates) - out of scope for MVP.
 - "weight" (default 1000) picks between multiple mapgens for the same om_terrain. It is NOT per-cell.
 - "object" contents:
     - "rows": 24x24 chars per overmap tile (OMT). A nested om_terrain of R x C expands rows to (24R) x (24C).
       Space and "." may be undefined when fill_ter is set or in nested mapgen.
     - "fill_ter": default terrain.
     - "terrain" / "furniture": char -> id. The same char can map to both a terrain and a furniture.
       Values may be a plain id, {"distribution": [[id, weight], ...]}, {"param": ...} or a "switch".
     - "palettes": list of palette ids (or distributions of them). Used by ~70% of maps. Later palettes
       override earlier ones, and the map's own definitions override all palettes. Palettes can include palettes.
     - Other char mappings: items, monsters, toilets, vendingmachines, gaspumps, signs, traps, fields,
       nested, etc.
     - Coordinate-based placement. x/y are an int or an inclusive [min, max] range, which must not
       cross a 24x24 block boundary:
         - place_items / items : item GROUP, "chance" is a percentage.
         - place_item / item   : a specific item id, "amount", "repeat", "chance".
         - place_loot          : a specific item or a group.
         - place_monster       : ONE monster (a specific id, or one pick from a "group"), with chance, repeat, pack_size.
         - place_monsters      : spawns the ENTIRE monster group, with chance (one-in-N), repeat, density.
         - place_nested / nested : place nested chunks, optionally conditional on neighbors or joins.
         - set, place_vehicles, place_signs, place_npcs, computers, ... (see the reference doc)
     - "rotation", "parameters", "predecessor_mapgen", "flags".
 - Roofs, upper floors and basements are separate mapgen entries with their own om_terrain ids
   (e.g. abstorefront / abstorefront_roof), linked by city_building/overmap_special.

Size distribution in core data (to prioritise): 1x1 = 2511, nested = 1494, 1x2 = 148, 2x3 = 75, 2x2 = 47,
up to 8x16.


Design constraints:
 - All art bundled with the editor must be open source. Cataclysm-BN art (CC-BY-SA 3.0) can be referenced/loaded.
 - There should be an ASCII mode. ASCII comes first, using each terrain/furniture entry's "symbol" and "color".
 - Starting with an expandable MVP is important.
 - The editor should smoothly handle buildings larger than one overmap tile. Use a 2x2 (48x48 rows) as the
   initial test (e.g. apartments_mod_tower).
 - Saving must match BN's JSON formatter. Unchanged objects stay byte-identical, and unknown keys and "//"
   comments are preserved.


MVP scope:
 1. Load a BN checkout and selected mods. Index terrain, furniture, palettes, item groups, monster groups and
    mapgen entries.
 2. Open any json mapgen (standalone or nested). Show a multi-OMT grid with 24x24 block boundaries.
 3. Resolve palettes (including nested includes, and the override order) to display every char.
 4. Paint rows with terrain and furniture. Show a symbol legend that says where each char is defined
    (which palette, or the map itself).
 5. Palette editor window: create and edit palettes and their includes, and show which maps use a palette.
    New symbols go into a palette by default (the map's last-listed palette, or a new palette if the map
    has none). Defining a symbol inline in the map's own "terrain"/"furniture" is an explicit opt-in.
    Warn when an edit to a shared palette affects other maps.
 6. Item and monster placement: view and edit place_items/item(s), place_loot, place_monster(s) as points or
    rectangles with chance/repeat labels. Enforce the no-crossing-24x24 rule.
 7. Nested chunks: edit nested_mapgen_id entries, and show place_nested/nested placements on the parent map.
 8. Create new mapgen (choose om_terrain grid size) and save round-trip-clean.
 9. Validation: undefined chars, unknown ids, out-of-range coordinates.


Later milestones:
 - Tileset rendering via a BN tileset's tile_config.json.
 - Preview roll: resolve weights, distributions, chances and nested chunks into one sample outcome.
 - Multi-z-level linking (roofs, basements) through city_building/overmap_special.
 - update_mapgen, parameters/switch editing, rotation preview, vehicles/NPCs/computers.


JSON formatting (decided: use BN's own formatter):
 - The editor serializes its JSON, then pipes it through BN's json_formatter and writes the result.
 - json_formatter is small and self-contained: tools/format/format.cpp + src/json.cpp, compiled with -DCATA_IN_TOOL
   (CMake target `json_formatter`).
 - With no arguments it reads stdin and writes the formatted JSON to stdout. With a filename it rewrites that
   file in place and exits 1 if anything changed.
 - Build it with clang/LLVM for portability (Linux/Windows/macOS). Either ship prebuilt binaries with the editor,
   or build it from the user's BN checkout on first run. Fall back to a clear error if it's missing.
   (Only g++ is installed on the dev machine right now; clang needs installing.)
 - Verified 2026-09-27: `g++ -std=c++23 -O2 -DCATA_IN_TOOL -Isrc tools/format/format.cpp src/json.cpp` builds
   in ~4s. All 1757 files in data/json/mapgen + mapgen_palettes + data/mods are already formatted, so
   `json_formatter < f` reproduces them byte-for-byte. A byte-identical round trip is achievable and testable.
 - Godot's OS.execute can't write to a child's stdin, so the editor uses the file mode: write compact JSON to a
   temp file, run `json_formatter <tmp>`, read it back. Exit 0 = unchanged, 1 = reformatted (but also
   "Failed to open"; check the output), anything else = crash.
 - Formatter quirks (verified):
     - Floats are printed with std::to_string, so they're rounded to 6 decimals (0.1234567 -> 0.123457), then
       trailing zeros are stripped. The editor writes floats the same way.
     - A number with an exponent but no '.' (e.g. 1e3) is read as an integer and comes out wrong (1000000).
       The editor never writes exponents.
     - Invalid JSON makes it abort (exit 134) with a JsonError on stderr. The editor must never feed it
       unparsed text.
     - Wrapping: the top level and its direct children always wrap; deeper containers go on one line if they
       fit in 120 chars. "rows" and "blueprint" always wrap. Only the formatter decides layout.


Workspace and sync (decided: the editor never writes into BN directly):
 - All edits are saved to a workspace folder that mirrors BN's relative paths
   (e.g. <workspace>/data/json/mapgen/house.json). New files get a chosen relative path in the same tree.
 - The first time a BN file is edited, the editor copies it into the workspace. It records the base in
   <workspace>/manifest.json: the BN commit plus a sha256 of the original file.
 - The editor shows BN data with workspace files layered on top (a workspace file replaces its BN original).
 - Sync window: lists new and modified files with an object-level summary (objects added/changed/removed,
   keyed by type + id / om_terrain / nested_mapgen_id).
     - Push: copy workspace files into the BN checkout when BN's file still matches the recorded base. If BN
       changed since the base, flag a conflict and offer overwrite / skip / (later) object-level merge.
       After a push, the base is updated.
     - Refresh: if BN changed and the workspace copy was never edited, update the workspace copy.
 - Sync never runs git in the BN checkout. The user reviews and commits there themselves.


UI layout (decided: canvas-first):
 +--------------------------------------------------+
 | File Edit View Sync   [Paint|Rect|Fill|Pick|Sel] |
 +---------------------------------------+----------+
 |  0         23|24     47               |[Brw|Leg|I|P]
 |  |||||||||||||||||||||||               | . floor  |
 |  |..hh....|..[I 50%]..|               | # wall   |
 |  |..tt....|....ee....|                | h chair  |
 |  +--------+----------+                | + door   |
 |  |........|..........|                |          |
 | Layers: [T][F][I][M][N]  (map tabs)   |          |
 +---------------------------------------+----------+
 | x12 y30 OMT(0,1) local(12,6) t_floor + f_chair   2 problems |
 +--------------------------------------------------+
 - Canvas fills the window. Multiple open maps are tabs. 24x24 OMT boundaries are drawn with coordinate
   rulers. Zoom and pan. A layer bar toggles visibility and picks the active layer: Terrain, Furniture,
   Items, Monsters, Nested.
 - Toolbar tools: Paint, Rect, Fill, Line, Pick (eyedropper), Select (rectangle select; copy/paste/move).
 - One side drawer, collapsible and toggled by hotkeys, with tabs:
     - Browser: core + mods tree, search by om_terrain / nested id / file, marks workspace-modified files.
     - Legend/Brush: id-first brush. Choose a terrain and/or furniture from searchable lists. The editor
       reuses a char that already has that combo, or adds a new char to the active palette on the first
       stroke. Legend chars can also be clicked directly as a brush. Each entry shows its source
       (palette name / map).
     - Inspector: the selected cell or placement. Placement fields (group/id, x/y ranges, chance, repeat,
       etc.) are edited here.
     - Placements: a list of all placement entries for the open map. Selecting one highlights it on the canvas.
 - Placements are canvas overlays: markers for points, dashed rectangles for x/y ranges, and labels like
   "I 50%" / "M 1/10". Drag to move or resize. Ranges snap so they never cross a 24x24 boundary.
 - Status bar: global x/y, OMT index + local x/y, the resolved ids under the cursor, and a problems count
   (click it to open the problems list).
 - Separate windows: Palette editor and Sync.


Known pitfalls (verified):
 - Godot's built-in JSON cannot be used for saving. JSON.parse_string turns every int into a float, and
   JSON.stringify writes `1000` back as `1000.0` and sorts keys alphabetically by default. json_formatter keeps
   `1000.0` as is, so this would corrupt every file. The editor needs its own JSON reader/writer that keeps
   int vs float and key order.
   Correction (Stage 0): keeping the original number and string text isn't needed. The formatter
   normalizes numbers itself, and all data uses only the canonical escapes \" and \n, so native Godot values
   (ordered Dictionary, int, float, String) plus a canonical writer round-trip every file. The reader
   warns about the constructs that wouldn't come back identical (non-canonical escapes such as é or \/,
   duplicate keys, exponents, ints beyond 64 bits, a BOM). If user files hit those, Stage 3 can keep the
   original text of untouched top-level objects and write it back verbatim.
 - BnJson.parse (GDScript) is ~20x slower than Godot's native JSON: ~9.5s vs ~0.5s for all 30MB of
   data/json. Stage 1 should index read-only data with JSON.parse_string (int/float doesn't matter there)
   and use BnJson only for files that are opened for editing and saved.
 - class_name globals only resolve under `godot --headless -s` after `godot --headless --import` has built
   .godot/global_script_class_cache.cfg. tools/run_tests.sh does this.
 - A GDScript runtime error just aborts the current function, so a crashing test looks like a pass. The test
   runner registers a Logger (Godot 4.5+) and counts script errors as failures.
 - Terrain/furniture use "copy-from" inheritance (161 uses in furniture_and_terrain). A tile's "symbol"/"color"
   may be inherited, so the index must resolve copy-from (and "abstract" entries) before rendering.
 - "rows" characters can be any non-double-width Unicode, including combining characters. A column is not
   always one code point, so parse rows by grapheme, and never re-encode rows that weren't edited.
 - Never write into the user's BN checkout from tests. Tests work on a temp copy.


Development stages (each ends with a headless-testable acceptance check):
 Stage 0 - Foundations  [DONE 2026-09-27]
   - git init, a Godot 4.7 project skeleton, a headless test runner (`godot --headless`), and a CLAUDE.md.
   - Build script for json_formatter (clang, with a g++ fallback).
   - Custom JSON reader/writer (see pitfalls).
   - Accept: every file in data/json/mapgen, mapgen_palettes and data/mods/*/ goes through
     read -> write -> json_formatter and comes back byte-identical.
   - Result: tools/run_tests.sh passes 16 tests. All 1757 files round-trip byte-identically (~10s), and
     breaking the writer (e.g. writing ints as floats) makes 1490 of them fail. Built with g++, since
     clang still isn't installed. Only a bash build script exists so far. Windows needs a .ps1 or prebuilt
     binaries later.
 Stage 1 - Data index (no UI)  [DONE 2026-09-27]
   - Load core + selected mods in BN's load order. Index terrain/furniture (resolving copy-from), palettes,
     item groups, monster groups, and mapgen entries by om_terrain / nested_mapgen_id, keeping the source
     file for each.
   - Accept: apartments_mod_tower resolves to a 48x48 grid where every char has a terrain + source.
   - Result: tools/run_tests.sh passes 32 tests. Core indexes in ~0.6s (1930 files), all 63 non-obsolete
     mods in ~0.8s. apartments_mod_tower_NW..SE (apartment_mod.json, 2x2, weight 250) resolves to 48x48
     with a known terrain in every cell, sourced from apartment_palette or fill_ter. All 4534 core and
     4835 core+mod json mapgens (om_terrain + nested) resolve with no problems.
   - Code: src/data/mod_catalog.gd (ModCatalog: modinfo scan, load order), data_index.gd (DataIndex),
     mapgen_resolver.gd + resolved_mapgen.gd (palette resolution per map), cell_text.gd (rows -> cells),
     src/app/app_settings.gd (AppSettings: user://settings.cfg, BN_PATH overrides the stored path).
   - Checked against BN source (corrections to the earlier notes):
     - Mod loading (mod_manager.cpp, init.cpp): modinfo.json is searched recursively under data/mods.
       Core is the "bn" mod ("core": true, "path": "../../json"). A mod's data folder is its modinfo folder
       joined with "path". Load order = the world's list with duplicates dropped and core moved first;
       the mod picker has already put dependencies first. Mods sharing an id are all dropped.
     - There is no mod-level "override". Per type: a later terrain/furniture/palette with the same id
       replaces the earlier one; mapgens for the same id accumulate (weighted pick); monstergroup has its
       own "override" flag (merge vs replace), not modelled yet. DataIndex keeps every definition in order.
     - Files load in BFS order: a folder's *.json sorted, then its subfolders sorted. "mod_interactions"
       folders are skipped, and <mod>/mod_interactions/<other mod>/ loads in a second pass only if
       <other mod> is active (Arcana_BN uses this).
     - copy-from copies whatever is loaded under that id (or abstract) at that moment, else the object is
       deferred and retried after everything loads. So a mod overriding a base doesn't change copies made
       before it. looks_like defaults to copy-from. "alias" ids point at the same definition.
     - "symbol" is exactly one ASCII byte or LINE_XOXO (│) / LINE_OXOX (─), optionally 4 seasonal values.
       "color" and "bgcolor" are mutually exclusive; either one replaces an inherited one.
     - t_null and f_null are built into the code (blank, white). Palettes use f_null inside distributions.
     - monstergroup is keyed by "name", not "id".
     - Palettes don't "override": BN appends every piece for a key in order (included palettes, then the
       palette, then the map). For terrain/furniture the last one placed wins, but items, monsters, traps,
       etc. from every palette and the map all apply. The legend must show all of those.
     - A plain "t_null"/"f_null" value is dropped, so it doesn't replace an earlier palette's terrain, but
       any key mentioned in any mapping still counts as defined (speedway, convention_center rely on this).
     - Besides "terrain"/"furniture"/..., palettes and maps can use "mapping": {"X": {"terrain": ...,
       "furniture": ..., "items": ...}} (54 files). Read before the plain member of each kind.
     - Terrain/furniture values: an id; a list of alternatives (ids, objects, [piece, count]); {"ter"/"furn":
       value, "colors"/"palette": paint}; or {"distribution"}, {"param", "fallback"}, {"switch", "cases"}.
       A "palettes" entry can also be a distribution/param. For display the resolver takes the first
       possible id (parameter defaults resolved) and records the alternatives.
     - Rows are split with BN's wcwidth rule (a zero-width code point joins the previous cell); ported in
       CellText. Rows use 110+ combining marks in core.
     - apartment_mod_new.json does not share ids with apartment_mod.json (it uses apartments_mod_tower_110
       etc.), so the "several mapgens for one om_terrain" example was wrong; the case is still common
       (e.g. house variants) and handled.
   - Open for later stages: the resolver reads objects with Godot's JSON (floats). Stage 3 must re-read the
     file with BnJson before editing. Monstergroup merge semantics and palette parameter "scope" aren't
     modelled. Mod conflicts are reported as errors, not blocked.
 Stage 2 - Read-only ASCII viewer  [DONE 2026-09-27]
   - Open a mapgen, resolve palettes, and render the multi-OMT grid with 24x24 boundaries. Legend shows where
     each symbol is defined. Hover shows the resolved ids.
   - Accept: a 1x1 house and the 2x2 apartments_mod_tower render with no undefined chars.
   - Result: tools/run_tests.sh passes 43 tests. house_01 (24x24) and apartments_mod_tower_NW..SE (48x48)
     render with every cell drawn from a known terrain/furniture, no undefined symbols and no problems. All
     4534 core json mapgens render with no undefined, unknown-id or missing-terrain cells, and every color
     name on core terrain/furniture is one BN recognizes. A headless smoke test drives the main scene (open,
     hover, click-to-highlight, toggles, close).
   - Code: src/view/bn_colors.gd (BnColors: BN color names -> fg/bg RGB), ascii_map.gd (AsciiMap: per-cell
     glyph, colors and state, wall joining, status-bar text), src/ui/map_canvas.gd (MapCanvas: zoom/pan,
     culled drawing, rulers, OMT lines, hover/click), legend_panel.gd, map_browser.gd, mods_dialog.gd, and
     main.gd (menus, tabs, side drawer, status bar). `godot --path . -- --open <id> [--bn <path>]` opens a
     map at startup.
   - What BN actually draws (checked against its source; the plan only said "symbol" and "color"):
     - map::draw_maptile shows furniture's symbol and color if there is furniture, else terrain's.
     - Terrain with the AUTO_WALL_SYMBOL flag is drawn as a line joined to its N/E/S/W neighbours whose
       terrain has the same connect group (map::determine_wall_corner), so walls need "flags" and
       "connects_to", not just "symbol". TileDef now keeps flags (copy-from "extend"/"delete" applied) and
       connect_group. connect_group is NOT inherited: BN resets it on every load, then the WALL or
       CONNECT_TO_WALL flag implies "WALL" for terrain, then the object's own "connects_to" wins.
       Neighbours outside the map count as unconnected.
     - Colors are curses pairs over 8 base colors: "c_<fg>[_<bg>]", "h_<fg>" (on blue), "i_<fg>" (black
       on fg), with deprecated "lt"/"dk" spellings. Curses backgrounds are the dim colors, so a "white"
       background is light gray and "yellow" is brown. RGB comes from data/raw/colors.json (hardcoded
       defaults; a user's custom colors aren't read). "bgcolor": X means i_X.
     - Seasonal symbols/colors: the viewer shows spring, with View > Season to switch.
   - Display choices: box-drawing characters are drawn as lines rather than font glyphs, so walls join
     whatever font is present. Other glyphs use a SystemFont (DejaVu Sans Mono, Noto Sans Mono, Consolas,
     Menlo, ... fallbacks), so nothing is bundled yet; bundling an open font (e.g. DejaVu Sans Mono) may be
     needed for consistent looks on Windows/macOS. Undefined symbols, unknown ids and cells with no terrain
     get a red background; cells a nested/update chunk leaves alone get a dark gray one. "Row symbols"
     shows the raw row characters in the resolved colors.
   - Not done yet from the UI sketch: the tool buttons (Stage 3) and the Items/Monsters/Nested layers
     (Stages 5-6); the layer bar has only Furniture and Row symbols toggles. The Inspector and Placements
     tabs come with those stages.
   - Test runner note: nodes added during SceneTree._initialize don't get _ready (the root isn't in the
     tree yet), so UI tests call _ready() themselves and main.gd's `auto_start = false` skips the
     deferred load.
 Stage 3 - Editing core + workspace
   - Paint terrain/furniture, pick symbols, undo/redo, save to the workspace through the formatter, create
     new mapgen (choose om_terrain grid size).
   - Accept: after an edit, a diff of the workspace file against its BN original touches only the edited
     rows and the legend entries.
 Stage 3b - Sync window (push / refresh / conflict detection).
   - Accept: push into a temp copy of BN, and a conflict is detected when the BN file changed after the base
     was recorded.
 Stage 4 - Palette editor window (MVP item 5).
 Stage 5 - Item/monster placement layers (MVP item 6).
 Stage 6 - Nested chunks (MVP item 7).
 Stage 7 - Validation panel (MVP item 9). Basic checks can start earlier.
 Then the "Later milestones" list.

Explicitly out of scope until the later milestones: tilesets, preview rolls, z-level linking, update_mapgen,
lua mapgen, and editing terrain/furniture definitions themselves.

Reference: plan written against Cataclysm-BN commit 39f4883093 (2026-09-26).

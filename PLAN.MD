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
         - place_items / items : item GROUP, "chance" is a percentage (default 1).
         - place_item / item   : a specific item id, "amount", "repeat", "chance" (a percentage, default 100;
                                 BN's mapgen.md wrongly says one-in-N for "item").
         - place_loot          : a specific item or a group, "chance" a percentage (default 100).
         - place_monster       : ONE monster (a specific id, or one pick from a "group"), with chance
                                 (a percentage, default 100), repeat, pack_size.
         - place_monsters      : spawns the ENTIRE monster group, with chance (one-in-N, default 1), repeat, density.
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
    New symbols go into the map's own "terrain"/"furniture" by default (decided 2026-09-27). Putting a
    symbol in a palette is done in the palette editor, or by moving a map symbol into a palette. Warn when
    an edit to a shared palette affects other maps, and name them.
 6. Item and monster placement: view and edit place_items/item(s), place_loot, place_monster(s) as points or
    rectangles with chance/repeat labels. Enforce the no-crossing-24x24 rule.
 7. Nested chunks: edit nested_mapgen_id entries, and show place_nested/nested placements on the parent map.
 8. Create new mapgen (choose om_terrain grid size) and save round-trip-clean. Warn when an om_terrain id
    has no overmap_terrain definition, with an auto-fix that creates them.
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
     - Legend/Brush: the brush is a symbol from the pool the map already has: every symbol defined by
       the map or its palettes, used or not (decided 2026-09-27). Painting a symbol paints exactly what the
       legend shows, extras (items, monsters, ...) and distributions/params included, so nothing is picked
       up by accident. Search works by id: "f_chair" lists the symbols that place it, with their extras.
       A combo that isn't in the pool is added with an explicit "New symbol" action (pick terrain and/or
       furniture from all known ids), which defines it in the map itself. Each entry shows its source
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
   Correction (Stage 3): the formatter normalizes numbers (1.50 -> 1.5) but keeps string escapes exactly as
   written ("é\/" stays), so re-encoding a file with such escapes WOULD change untouched strings.
   JsonFile therefore writes every top-level object that is unchanged as its original text (BnJson
   records each element's byte span), and only re-encodes edited objects.
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
 Checked before Stage 3 (2026-09-27, against BN source and data; these correct or add to the plan above):
   - Coordinate ranges: confirmed. A multi-tile map is loaded as one function per OMT, and each placement
     belongs to the OMT containing its (min x, min y). If its max leaves that OMT, BN throws "coordinate
     range cannot cross grid boundaries". A nested chunk checks against its mapgensize instead.
   - "chance" means different things per placement type (see the corrected list under "Mapgen format").
     The Inspector must label it per type, and BN's doc can't be trusted for "item".
   - DECIDED: new symbols go into the map itself, and palettes are edited in the palette editor
     (MVP item 5). Why: defaulting to "the map's last-listed palette" edits widely shared palettes:
     standard_domestic_palette is used by 443 json mapgens, roof_palette by 478, lab_common_palette by 216.
     Inline definitions are normal practice: 2637 of 4615 json mapgens define terrain/furniture inline, 1504
     of them alongside palettes. Adding a key to a shared palette can also silently change OTHER maps: in
     a map that lists this palette after another palette that already defines the key, the new definition
     now wins for terrain/furniture, and items/monsters etc. add up rather than replace. So the palette
     default needs more than a warning. A new key must be free in every palette of this map. When the
     palette editor adds a key to a palette or moves a map symbol into one, it must check every map using
     that palette (directly or through includes) and warn about each map whose symbols would change.
   - DECIDED: the brush picks from the symbols already defined, not from ids (see Legend/Brush). Why:
     auto-reusing "a char that already has that combo" goes wrong because a symbol is terrain + furniture +
     extras. Reusing '1' (t_floor + f_cupboard) would also bring its "items", and a distribution or
     param only sometimes gives the id. Picking the symbol makes that visible and deliberate.
   - A new key must be one display column (CellText.starts_cell, not a zero-width code point). Undefined
     " " and "." are meaningful in nested chunks and with fill_ter, so don't hand them out as new symbols.
   - New om_terrain mapgen: BN never checks that an om_terrain id exists as an "overmap_terrain", so a map
     with a new id just never generates. Creating one needs overmap_terrain entries (one per grid cell)
     and, to spawn in a world, a city_building / overmap_special. DECIDED: warn, with an auto-fix that
     writes a minimal overmap_terrain per missing id into the workspace (next to the map, or in an
     overmap_terrain file of the same mod). DataIndex indexes overmap_terrain ids (Stage 7 validation
     needs them anyway). Spawning (city_building / overmap_special) stays with z-level linking.
   - Workspace layering needs DataIndex support: load the file list from BN, swap in workspace copies,
     and add new workspace files at their relative path, which decides the mod they belong to (a new file
     outside any mod's data folder won't load in BN). The Stage 1 read path (Godot JSON) stays for
     indexing; files opened for editing are re-read with BnJson.
   - A map without "rows" (fill_ter only) needs rows created on the first paint; multi-tile rows must stay
     (24R) x (24C) with every row the same width in cells.
 Stage 3 - Editing core + workspace  [DONE 2026-09-27]
   - Paint with symbols from the pool, "New symbol" (defined in the map), pick symbols, undo/redo, save to
     the workspace through the formatter, create new mapgen (choose om_terrain grid size) with the
     overmap_terrain warning and auto-fix.
   - Accept: after an edit, a diff of the workspace file against its BN original touches only the edited
     rows and the map's own "terrain"/"furniture" entries. (Palette files change only in Stage 4, and
     their diffs must likewise touch only the edited palette.)
   - Result: tools/run_tests.sh passes 59 tests. tests/test_edit_bn.gd edits apartments_mod_tower (2x2, no
     own terrain/furniture yet) and house_01 (has both), paints rows in several OMTs, adds a symbol, saves
     to a temp workspace and checks `diff -U0` against BN: every changed line is an edited row or inside
     the map's terrain/furniture, every other object is unchanged, and BN's file keeps its sha256. A
     main-scene test drives pick, line, undo/redo, the New symbol and New map dialogs, and save.
   - Code: src/edit/ (EditSession, MapDocument, JsonFile, Workspace, MapTool, Shapes), src/ui/
     new_symbol_dialog.gd, new_map_dialog.gd; MapCanvas drag signals + preview; LegendPanel "New
     symbol..."; MapBrowser marks workspace files. DataIndex layers the workspace over BN (a workspace
     file replaces the BN file at the same path; new files load in BFS order), indexes overmap_terrain ids,
     and has file_path()/mod_for_path().
   - How it works: every edit goes straight into the BnJson object (rows as strings, the map's own
     terrain/furniture), so undo restores the exact object and saving is compose -> formatter -> write.
     Maps from one file share a JsonFile. Tools: Paint (B), Line (L), Rect (R, Shift fills), Fill (F,
     4-connected), Pick (I or Alt+click); Esc cancels a drag, Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z. The brush is
     per map. Closing the last map of a changed file, reloading, switching BN/mods/workspace and quitting
     all ask to save or discard. Workspace: --workspace, File > Workspace folder, else
     <user data>/workspace; it may not be inside BN (or contain it), and Workspace.write_file refuses to.
     manifest.json records base_sha256 + base_commit (read from .git without running git) on the first
     save of a BN file, or {"new": true}.
   - Decisions and checks (against BN source/data):
     - Undefined " " and "." are fine with fill_ter or in a nested chunk (mapgen.cpp setup_common), so a
       map without rows gets rows of spaces on the first paint (undo removes them again), and a new map
       starts as spaces over fill_ter. A new om_terrain map requires fill_ter.
     - A new member ("rows", "terrain", "furniture") is inserted after fill_ter/rows/palettes rather than
       appended, to match how BN files are laid out.
     - New symbol keys: one display column, not wide (CJK), not " "/".", and not defined by the map or ANY
       of its palettes (even a palette key with only items would add its items). The suggestion tries the
       furniture's then the terrain's own symbol, then a-z, A-Z, 0-9, punctuation, then Latin-1 and up. The
       dialog lists existing symbols with the same terrain + furniture so they can be reused instead.
     - om_terrain -> overmap_terrain: mapgen ids match the overmap_terrain id itself (BN adds the
       _north/... rotations), or a LINEAR overmap_terrain's id + _straight/_curved/_end/_tee/_four_way.
       With that rule only 18 of 5544 core om_terrain ids have none (lab_* used by hardcoded mapgen,
       FEMA_be, "null"), so the warning is meaningful and is listed with the map's problems.
     - The auto-fix appends one overmap_terrain with the missing ids to the map's own file: copy-from the
       core abstract generic_city_building, a name from the id, color light_gray. BN's strict loading
       rejects a value equal to the inherited one, so "sym" is inherited ("^") rather than restated.
     - BN ignores fill_ter in nested chunks (setup_internal for nested never reads it); no core or mod
       nested chunk sets one, so the resolver's behaviour there doesn't matter yet.
   - Not done / open: the Select tool (copy/paste/move) from the UI sketch; removing or renaming symbols;
     the auto-fix isn't undoable (it marks the file changed; discarding drops it); edits to a file with
     several open maps can only be discarded all together; a file saved while a workspace copy was
     edited outside the editor is overwritten without warning (Stage 3b's sync compares against BN, not
     the workspace). New files outside every loaded mod's data folder are refused; new mods aren't
     supported. Stroke end re-resolves the map (opening the 16x8 nuclear plant, file read included, takes ~30 ms)
     but skips the full redraw unless symbols changed (that was 130 ms there); painting itself
     updates only the touched cells and their wall neighbours.
 Checked before Stage 3b (2026-09-27, against BN 39f4883093 source and core + mod data):
   - Sync, line endings: BN's .gitattributes forces `* text=auto eol=lf`, and no data file has CRLF, so
     byte comparison and sha256 bases also hold on Windows checkouts.
   - Sync, object summary: "type + id / om_terrain / nested_mapgen_id" is NOT a unique key. In 248
     files, objects share it: 898 mapgens (weighted variants of one om_terrain, several chunks under one
     nested id), plus speech/snippet/recipe/dream objects with no id at all. The summary (and a later
     object-level merge) must pair objects by key AND occurrence order (the 2nd "house_01" mapgen with
     the 2nd), falling back to position; objects with no key get a position-only label.
   - Sync, after a push: the workspace copy still shadows BN in the index. If BN later changes that
     file (git pull), the editor keeps showing the stale workspace copy and a later push reports a
     conflict for a file the user never touched again. "Refresh ... if the workspace copy was never
     edited" also can't be decided from the manifest alone: a copy only exists because it was saved.
     DECIDED (2026-09-27): after a successful push, the workspace copy and its manifest entry are
     deleted, so BN is the source again and nothing can go stale. Why: the alternative (also recording
     the pushed sha256 so Refresh can update untouched copies) keeps a working set but adds bookkeeping
     for little gain. Refresh then only matters for copies not pushed yet: when BN changed since the
     base, it is a conflict (offer overwrite / skip / later merge), never a silent update. Also: BN
     deleting or renaming a file since the base is a conflict of its own.
   - Palettes (Stage 4): 46 of 200 palettes are defined outside data/json/mapgen_palettes, often inside
     a mapgen file, so palette edits can touch a file that also holds open maps; the palette editor must
     go through EditSession's shared JsonFile, never a second copy. One palette is replaced by a mod
     (stream_palette in innawoods): editing the core one while that mod is loaded changes nothing
     visible, so warn and name the overriding definition. "Which maps use a palette" must count every
     option of a palette distribution/param (only 2 maps and 1 palette choose palettes that way; the
     resolver only follows the first option). Parameter scopes in use: omt (17) and nest (7).
   - Placements (Stage 5): x/y (and repeat) are an int, [min, max], or a one-element [n] (60 uses); BN
     reads [n] as n. chance is always an int. Keys by count: place_items 4279, place_loot 3342,
     place_nested 2269, place_monster 1794, place_vehicles 1504, place_monsters 1293, set 1024,
     place_item 953, then signs/npcs/terrain/furniture/... The Inspector needs per-type fields
     (place_monster: group or monster, pack_size, one_or_none; place_monsters: density; place_loot: group
     or item, ammo, magazine; place_vehicles: rotation, status, fuel).
   - Placements: BN loads the whole placement list once per OMT, subtracts that OMT's offset, and keeps
     an entry only if its (min x, min y) is inside that OMT. So an entry whose min lies outside the whole
     map is silently dropped (no error). Validation should report it.
   - "set" is different (mapgen.cpp setup_setmap / generate): its coordinates never get the OMT offset.
     In a multi-tile map a "set" entry with coordinates 0..23 runs in EVERY OMT of the building, and one
     with any coordinate > 23 is silently dropped in all of them. 209 entries in 58 multi-tile maps are
     dropped this way today. The editor must draw BN's behaviour (repeat each set entry in every OMT,
     mark the dropped ones), not the documented one. "set" line/square also check x2/y2 the same way.
   - Nested chunks (Stage 6): mapgensize ranges from 1x1 to 24x24 (5x5, 1x1, 3x3 most common).
     place_nested "chunks" entries are ids or [id, weight] pairs; also else_chunks, neighbors (north/
     east/south/west, and "above" 3 times), joins, connections, rotation. 165 maps place chunks through a
     "nested" symbol mapping rather than place_nested. In 325 place_nested entries the chunk runs past
     the edge of its OMT. The anchor rule still holds, but the overhang isn't clipped per OMT in the
     source: map::ter_set/furn_set write through the global mapbuffer by absolute position and only
     reject points outside the pocket dimension, so the overhang may land in the neighbouring OMT.
     Unverified in game; the overlay should draw the overhang and mark it until that's checked.
   - Validation (Stage 7): DataIndex only indexes item groups and monster groups. Checking place_item /
     place_loot item ids, place_monster monster ids, vehicles, traps, fields, npc templates and "set" ids
     needs those types indexed too (items come in many "type"s: GENERIC, TOOL, ARMOR, COMESTIBLE, ...).
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

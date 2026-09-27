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
         - place_items / items : item GROUP (or an item id: 4 uses), "chance" is a percentage (default 1),
                                 which must be 1..100 or BN places nothing (map::place_items).
         - place_item / item   : a specific item id, "amount", "repeat", "chance" (a percentage, default 100;
                                 BN's mapgen.md wrongly says one-in-N for "item").
         - place_loot          : a specific item or a group, "chance" a percentage (default 100), a plain
                                 int (no range); scaled by the item spawn rate unless it is 100.
         - place_monster       : ONE monster (a specific id, one pick from a weighted list of ids, or one
                                 pick from a "group"), with chance (a percentage scaled by spawn density,
                                 default 100), repeat, pack_size.
         - place_vehicles      : a vehicle GROUP id (every vehicle prototype is also a group of its own
                                 id), "chance" a percentage scaled by the vehicle spawn rate, DEFAULT 1.
         - place_monsters      : spawns a monster GROUP (about density x 10-50 picks from it over the
                                 area, map::place_spawns, not the "entire" group), with chance (one-in-N,
                                 default 1), repeat, density (default: the map's monster density).
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
 - update_mapgen, parameters/switch editing, rotation preview, dedicated editors for vehicles/NPCs/
   computers (since Stage 5 every place_* list is shown, moved and edited as fields; what's left are
   id pickers and structured editors, e.g. computer options).
 - The Select tool (copy/paste/move a block of rows, from the UI sketch) is still open from Stage 3;
   when it's built, moving a block should offer to carry the placements anchored in it.
 - A preview roll can take each kind's chance meaning and default from Placement.KINDS, and must
   scale by BN's spawn-rate options the way each placement class does (see the field hints).


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
     (Corrected after Stage 4: the anchor is the FIRST value of each range, not the minimum, and only
     the second value is checked against the OMT's far edge. A reversed range such as [31, 16] passes
     and, since rng swaps its bounds, spans back into the previous OMT: 103 reversed ranges in core +
     mods, 54 spanning an OMT boundary, mostly place_vehicles and place_items. Also, a nested chunk's
     place_* entries are checked against 24x24, not its mapgensize: jmapgen_objects copies the size
     before mapgensize is read. Only "set" uses the real mapgensize. 8 chunks rely on this.)
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
     reads x/y [n] as n. (Corrected after Stage 3b: repeat, chance, amount and pack_size are read with a
     default, so [n] means n..default, and rng swaps the bounds: "repeat": [3] is 1-3, not 3. All 5 uses
     in data are [1], so it's harmless today, but the Inspector must not treat [n] as n there.) chance is always an int. Keys by count: place_items 4279, place_loot 3342,
     place_nested 2269, place_monster 1794, place_vehicles 1504, place_monsters 1293, set 1024,
     place_item 953, then signs/npcs/terrain/furniture/... The Inspector needs per-type fields
     (place_monster: group or monster, pack_size, one_or_none; place_monsters: density; place_loot: group
     or item, ammo, magazine; place_vehicles: rotation, status, fuel).
   - Placements: BN loads the whole placement list once per OMT, subtracts that OMT's offset, and keeps
     an entry only if its (min x, min y) is inside that OMT. So an entry whose min lies outside the whole
     map is silently dropped (no error). Validation should report it. (After Stage 4: "min" is the first
     value, see the correction above; 24 entries in core + mods are dropped this way.)
   - "set" is different (mapgen.cpp setup_setmap / generate): its coordinates never get the OMT offset.
     In a multi-tile map a "set" entry with coordinates 0..23 runs in EVERY OMT of the building, and one
     with any coordinate > 23 is silently dropped in all of them. 209 entries in 44 multi-tile mapgens are
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
 Stage 3b - Sync window (push / refresh / conflict detection).  [DONE 2026-09-27]
   - Accept: push into a temp copy of BN, and a conflict is detected when the BN file changed after the base
     was recorded.
   - Result: tools/run_tests.sh passes 69 tests. tests/test_sync.gd edits real house_01, saves it to a temp
     workspace, pushes into a temp BN holding a byte copy of its file (real BN keeps its sha256), sees one
     changed object ("mapgen house_01"), saves again on the new base, then appends to the copy and gets
     CHANGED_IN_BN, and push refuses. Fake-BN tests cover every state, overwrite, new files, unsafe
     manifest paths, the object pairing, the dialog and the main-scene wiring. Disabling the base check
     fails both acceptance tests.
   - Code: src/edit/workspace_sync.gd (WorkspaceSync: scan/status, summary, push, remove_copy),
     src/ui/sync_dialog.gd (SyncDialog, Sync > Sync with BN..., Ctrl+Shift+P). EditSession.mark_pushed and
     JsonFile.is_new/mark_pushed keep open files consistent after a push.
   - How it works: per file, one state: new (BN has none), modified (BN still matches the base), same as
     BN (push only drops the copy), and the conflicts: BN changed since the base, BN deleted it, BN added a
     file where ours was new, or untracked (a workspace file with no manifest entry where BN has one: no
     base to check). "Missing" is a manifest entry whose file is gone; Discard forgets it. Conflicts start
     unchecked; pushing a checked conflict asks, then overwrites (the "overwrite" option; "skip" is leaving
     it unchecked). push() re-checks the state itself, so a stale window can't overwrite an unseen change.
     BN is written through <file>.bnme-tmp + rename and read back. After a push the workspace copy, its
     manifest entry and empty folders are deleted (decided above). "Discard workspace copy" throws a
     copy's edits away; it asks first.
   - Decisions and checks:
     - Refresh is a rescan. With copies deleted after a push, "update an untouched workspace copy" can't
       happen: a copy exists only because it was saved, so BN changing under it is always a conflict.
     - The summary compares the workspace file with BN's file as it is NOW (what push would do), not with
       the base: only the base's sha256 is stored, not its text. For a CHANGED_IN_BN conflict the list
       therefore includes BN's own changes, reversed; the details pane says so. Storing base text for a
       real three-way view belongs with the object-level merge.
     - Objects pair by type + id (id, abstract, om_terrain, nested_mapgen_id, update_mapgen_id, or a
       string "name" for monstergroup) and occurrence; keyless objects by type and occurrence, labelled
       "speech #12" by position. Unchanged objects are compared by their bytes, which works because both
       sides come out of json_formatter. Inserting a new variant before an existing one of the same
       om_terrain shifts the pairing, so later variants show as changed; acceptable for a summary, not for
       a merge.
     - The index layers every workspace file, manifest or not, so the window lists untracked files too.
     - Found in Stage 3 code: after a push, an open JsonFile still claimed to be in the workspace with no
       base, so its next save would have been recorded as a NEW file and the next push reported a false
       conflict; and a pushed newly-created file counted as dirty again. mark_pushed fixes both.
     - A file with unsaved editor changes can't be pushed (save first); a file open in the editor can't
       be discarded (the open copy would be stale). A push leaves the index valid (BN now has the same
       bytes); a discard doesn't, so the editor reloads if no map is open, else asks for F5.
     - Manifest paths are not trusted: push refuses absolute paths, "..", backslashes, ":" and empty parts.
   - Not done / open: object-level merge; a pushed file isn't checked with json_formatter again (it was
     formatted when saved, and push copies bytes); the window doesn't watch the disk (press Refresh).
 Checked after Stage 3b (2026-09-27, against BN 39f4883093 source and core + mod data; reviews Stages 4-7):
   - Stages 4-7 had no acceptance checks. Proposed ones are listed under each stage below.
   - Palettes (Stage 4):
     - The resolver reads palettes from DataIndex.Definition.data, parsed once with Godot's JSON at load.
       An edited palette must be read from the live BnJson object in EditSession's JsonFile instead, and
       every open map that uses it (directly, through an include, or as any option of a distribution) must
       be re-resolved and redrawn. Undo for a palette edit belongs to the palette, not to a map.
     - "Which maps use a palette" needs a reverse index. Resolving every map to find out takes ~3 s, but
       DataIndex already sees each mapgen object while loading, so recording the ids in "palettes" (every
       option) there is nearly free. Includes (5 palettes use them) are followed at query time.
     - Palette contents beyond terrain/furniture are common: items 89 of 201 palettes, toilets 84,
       nested 29, vendingmachines 27, liquids 14, plus monster, vehicles, computers, sealed_item, ...,
       and "mapping" in 8. BN's loader (mapgen_palette::load_internal) reads exactly the per-symbol kinds
       the resolver already knows, "parameters" and "palettes"; palettes never hold place_* lists. MVP:
       edit terrain/furniture per key and the includes; show the other kinds read-only (as the legend
       does) until Stage 5's field editors can be reused.
     - Confirmed: a palette distribution/param in "palettes" makes BN add EVERY option, each constrained
       to its choice (mapgen_palette::add), so the "key must be free in every palette of the map" check
       has to look at every option too, not only the one the resolver displays.
   - Placements (Stage 5), from the placement classes in mapgen.cpp:
     - chance, repeat, amount and pack_size are jmapgen_int, so each can be a [min, max] range (none are
       in data yet, but the Inspector must keep one if it's there). (Corrected after Stage 4: ranges are
       in data: place_item "amount" 320 times, place_monster "pack_size" 46, set "amount" 211. None for
       chance. place_loot's chance is a plain int.) place_items' "item" goes through
       load_item_group, so it may be an inline group rather than an id (no uses yet).
     - place_monster "monster" is a weighted list of ids in 89 entries. place_vehicles: 30 entries rely
       on the default chance of 1 (%), and 79 give "rotation" as a list (one is picked).
     - place_item chance: exactly 100 gives exactly one (times amount); anything else is an expected count
       in percent, scaled by the item spawn rate, so chance > 100 can give several (1 use in data). A
       label like "I 150%" is still right; don't clamp it to 100.
     - Symbol mappings also place items/monsters/vehicles/nested (e.g. 89 palettes carry "items"). The
       Items/Monsters layers should mark those cells as well, read-only (edited through the symbol).
   - Nested chunks (Stage 6):
     - Editing a chunk's rows already works (Stage 3 opens nested_mapgen_id entries at their mapgensize).
       What's missing: creating a new chunk (New map only makes om_terrain maps; it needs
       nested_mapgen_id + mapgensize, no fill_ter, no overmap_terrain), and the overlay on parents.
     - Rotation: a chunk's own "rotation" member (656 chunks set it) is read but never used by BN. Only
       the placing entry's "rotation" (place_nested, or a "nested" symbol mapping) turns the chunk, around
       its mapgensize (mapgen_function_json_nested::nest). The overlay should use the placing rotation and
       ignore the chunk's own; validation can point out that the chunk's rotation does nothing.
     - 174 of 1599 nested chunks place nested chunks themselves, so the overlay recurses (and needs a
       loop guard). "null" is a common chunk id (590 entries): "place nothing", not an unknown id.
     - 938 chunks use palettes, so drawing a chunk on its parent resolves the chunk's own palettes, not
       the parent's.
   - Validation (Stage 7): place_vehicles ids must be checked against vehicle groups AND vehicle
     prototypes (91 of 158 ids used are prototypes; veh_type.cpp makes an implicit group for each).
     Unknown-id checks must accept "null" chunks and t_null/f_null. Some basic checks already exist in
     MapDocument.problems() (undefined symbols, unknown terrain/furniture, missing overmap_terrain).
 Stage 4 - Palette editor window (MVP item 5).  [DONE 2026-09-27]
   - Accept: edit a key in a palette defined inside a mapgen file (one of the 46) while a map from that
     file is open. The diff against BN touches only that palette's entry; the open map and every other
     open map using the palette redraw with the change; the warning names the affected maps (checked
     against a brute-force resolve of every map); undo restores both.
   - Result: tools/run_tests.sh passes 81 tests (~43 s). tests/test_palette_bn.gd opens three school
     maps and house_01, edits school_palette 'i' (defined in school_1.json): the warning lists exactly
     the 3 maps a brute-force resolve of all 4615 json mapgens finds changed, the three open schools
     redraw and house_01 doesn't, the saved file differs from BN in one line inside the palette, and
     undo gives BN's text back. A second edit (car_theater 'b') is only reached through an include and
     as the second option of a palette distribution, and also matches the brute force. Fake-BN tests
     cover the reverse index, variants, byte-identical undo, "mapping" entries, discard, impact,
     moving a symbol, a map's palette list, new palettes, a mod-replaced palette and the window.
   - Code: src/edit/palette_document.gd (PaletteDocument: set/remove a key's terrain/furniture, includes,
     its own undo), palette_impact.gd (PaletteImpact: which maps an edit changes), object_members.gd
     (ObjectMembers: member snapshots shared with MapDocument), src/ui/palette_editor.gd (PaletteEditor,
     Edit > Palette editor..., Ctrl+Shift+E, or the Legend's "Palette..." button for the selected
     symbol's palette). DataIndex: MapgenRef.palettes, palette_options(), palette_closure(),
     maps_using(), add/remove_palette(). MapgenResolver.resolve(..., picks) and resolve_variants().
     MapDocument: refresh(), uses_palette(), set/add/remove_palette(), own_keys(), remove_own_symbol().
     EditSession: open/close/create_palette, impact_of, move_symbol(_impact), open_count.
   - How it works: opening a palette points its DataIndex definition's data at the live BnJson object
     in the shared JsonFile, so every map resolved afterwards sees the edit; open maps that use the
     palette (directly, by include, or as any option) re-resolve and redraw when it changes. When the
     last map/palette of a file closes with its changes discarded, palette data and maps' palette lists
     are read back from the file on disk. The window lists every definition (a mod-replaced one is
     marked and says editing it changes nothing in game), the palette's keys with their source (own or
     "from <include>"), pickers for terrain/furniture ("keep" for a distribution etc.), includes
     (add/remove/reorder, loops refused), the maps using it, "Use in <map>" (adds it last to the
     current map's palettes) and "Move into this palette" for the current map's own symbols. Switching
     palettes closes the previous one unless its file has unsaved changes; save/quit/sync treat palette
     files like map files.
   - Decisions and checks:
     - Impact = resolve each candidate map (maps_using) before and after the edit, once per palette
       option (resolve_variants), and compare what each symbol USED IN ITS ROWS places (terrain,
       furniture, extras by value; numbers compared by value so floats from Godot's JSON match ints
       from BnJson). Where a definition comes from doesn't count, nor do symbols a map defines but
       never uses. Cost: ~25 ms for school_palette, ~1.0 s for standard_domestic_palette (443 users),
       ~0.6 s for roof_palette, so it runs when Apply is pressed, not on every picker click.
     - The warning comes before the edit: if maps other than the current one change, a dialog names
       them (first 25) with the symbols that change, and the edit waits for "Apply anyway".
     - Moving a map symbol into a palette only moves the kinds the map defines (the palette keeps its
       other kind for that key, which the map may already get from it). It needs the palette to be
       listed unconditionally by the map and not replaced by a mod. It is two undo steps, one in the
       palette and one in the map, not one linked step: each document only ever changes its own object,
       so each history stays valid on its own. The impact check covers the move (the map itself
       should come out unchanged).
     - Found in Stage 3 code: MapDocument.check_new_key only looked at the displayed palette option,
       so a key defined only by another option of a palette distribution (cabin, drive-in theater)
       could be handed out as new. It now rejects those too.
     - Undo records member order: removing a member (e.g. the last furniture) and putting it back
       would otherwise move it, breaking byte-identical undo.
     - A palette key edit replaces the entry where it's written: the plain member, else "mapping".
       New entries go in the plain "terrain"/"furniture"; members added go after type/id/parameters/
       palettes. Keys in palettes may be " " or "." (palettes define those; school_palette does).
     - New palettes: an id no loaded palette has (a second definition would replace the first), in a
       file inside a loaded mod's data folder; default path data/json/mapgen_palettes/<id>.json, or
       <mod>/mapgen_palettes/<id>.json when the current map is in a mod.
   - Not done / open: editing the other per-key kinds (items, toilets, nested, ...; Stage 5's field
     editors can be reused), editing distributions/params in place (they can only be kept or replaced
     by one id), palette "parameters", renaming or deleting keys and palettes, reordering a map's
     palettes list or choosing a palette distribution for it in the UI (the model's set_palettes can),
     and palette parameter scopes. A move is two undo steps (see above).
 Checked after Stage 4 (2026-09-27, against BN 39f4883093 source and core + mod data; reviews Stages 5-7):
   - Corrections, marked where the claims were made above: the anchor of a range is its FIRST value
     (reversed ranges slip past the boundary check); a chunk's place_* entries are bounded by 24x24,
     not mapgensize; amount/pack_size ranges ARE in data; place_items may name an item id and needs
     chance 1..100; place_loot's chance is a plain int; place_monsters doesn't spawn the entire group;
     the 209 dropped "set" entries are in 44 mapgens, not 58. The other Stage 5-7 counts were recounted
     and hold (they are core + mods): 1599 chunks, 656 with an ignored own rotation, 174 nesting, 938
     with palettes, 165 maps with a "nested" mapping, 89 monster lists, 30 vehicles on the default
     chance, 79 rotation lists, 91 of 158 vehicle ids are prototypes, 60 one-element x/y.
   - Confirmed: the chunk's own "rotation" is never used (nest() takes the placing entry's); BN never
     reads fill_ter for chunks; nested placement doesn't clip the overhang (jmapgen_objects::apply
     only offsets), so "overhang may land in the neighbour" is still unverified in game. place_nested
     picks its position at random within its x/y range (x.get()), like the other placements.
   - Placements (Stage 5):
     - Keep every range in the order written, and treat the first value as the anchor (which OMT owns
       the entry, and whether it's dropped). Drag/resize keeps both values inside the anchor's OMT;
       an existing reversed range is drawn with the span BN really uses (min..max) and marked when it
       crosses into another OMT.
     - Per-type fields, from the classes in mapgen.cpp: place_item (item, amount range, chance 100,
       repeat, active); place_items (item group or id, chance 1..100 default 1, repeat); place_loot
       (group XOR item, chance plain int, ammo, magazine, repeat); place_monster (monster id or weighted
       list, or group; chance 100 scaled by spawn density with a cap; pack_size range; one_or_none,
       whose default is true only without repeat and pack_size; friendly, name, target,
       use_pack_size); place_monsters (group, chance one-in-N, density, target); place_vehicles
       (vehicle, chance 1, rotation int or list, fuel, status, locked, place_beyond_bounds).
     - Reuse from Stage 4: MapDocument's member-snapshot undo (with member order) covers place_*
       members; PaletteImpact already compares extras, so editing a palette's items etc. later only
       needs the field editors in the palette window.
     - "Byte-identical when untouched" is already guaranteed by JsonFile (untouched objects are
       copied as text), so it isn't a useful acceptance check. What needs testing is that the
       placement model reproduces each entry exactly, and that editing one entry changes only its lines.
   - Nested chunks (Stage 6):
     - New chunks need their own path in EditSession.create_mapgen (nested_mapgen_id + mapgensize, no
       fill_ter, no overmap_terrain check); today it only makes om_terrain maps.
     - A reverse index "which maps place chunk X" (place_nested chunks/else_chunks and "nested"
       mappings, also from palettes), like DataIndex.maps_using, for warnings when editing a chunk.
     - Stage 4's refresh and warnings stop at the map level: a palette edit that changes a chunk
       also changes every parent that places it, but PaletteImpact lists only the chunk, and
       EditSession only refreshes maps that use the palette themselves. With overlays, open parents
       must also redraw when a chunk they place, or a palette that chunk uses, changes, and the
       warning should name them ("via chunk X").
   - Validation (Stage 7): besides the indexes already listed (item types come in 17 "type"s:
     GENERIC, ARMOR, COMESTIBLE, TOOL, GUN, AMMO, MAGAZINE, BOOK, GUNMOD, TOOL_ARMOR, BIONIC_ITEM,
     CONTAINER, WHEEL, ENGINE, PET_ARMOR, TOOLMOD, BATTERY), the known findings in core + mods today:
     209 dropped "set" entries, 24 place_* entries anchored outside their map, 54 reversed ranges
     spanning an OMT boundary, 8 chunks with place_* ranges past their mapgensize, 656 ignored chunk
     rotations. A range whose second value leaves the anchor's OMT is a BN load error, so the editor
     should refuse to save it rather than just list it. (After Stage 5: 19 anchors in core, 20 in all
     of data/, not 24; saving already refuses a crossing range, see Stage 5.)
 Stage 5 - Item/monster placement layers (MVP item 6).  [DONE 2026-09-27]
   - Accept: every place_* entry in core + mods converts into the placement model and back to an equal
     value (BnJson.stringify), with ranges kept in the order written. Editing one entry of a real
     multi-tile map and saving changes only that entry's lines (diff against BN). Moving/resizing a
     range never lets it leave its anchor's OMT. The display follows BN's rules for the counted cases:
     the 209 dropped "set" entries and 24 dropped anchors are marked, "set" entries repeat in every OMT,
     and the 54 boundary-spanning reversed ranges are drawn with their real span.
   - Result: tools/run_tests.sh passes 95 tests (~50 s). tests/test_placements_bn.gd reads all 15286
     placement entries of core's json mapgens (BnJson, ~2.8 s): every x/y/x2/y2/repeat/chance/amount/
     pack_size comes back exactly as written, and placing each entry where it already is changes none
     of its values. The editor counts 19 dropped anchors, 54 reversed ranges reaching back into the
     previous tile, 209 dropped "set" entries in 44 mapgens and 0 crossing ranges, the same as an
     independent Python pass over data/json. Editing apartments_mod_tower's NE place_monsters (resize +
     chance) and dragging mall_a_1's first place_loot into the next tile with the Place tool each save
     with exactly one line changed in the diff against BN: the entry's. 300 random drags/resizes on a
     2x2 map leave every entry inside one tile and every other entry byte-identical. Breaking the tile
     clamp, or anchoring at the minimum instead of the first value, fails these tests.
   - Code: src/data/placement.gd (Placement: IntRange = jmapgen_int as written, Geometry, per-kind
     table and fields, BN's anchor/drop/cross rules, labels, values_for, clamping),
     src/edit/placement_tool.gd (PlacementTool: select/move/resize/create), src/ui/placements_panel.gd
     (PlacementsPanel: list + inspector). MapDocument: placements(), placement(), placements_at(),
     check_placement(), add/remove_placement(), set_placement_fields(), place_at(), save_problems().
     MapCanvas draws the overlay, AsciiMap.Look.layers marks symbols that place things themselves,
     EditSession.save refuses crossing ranges, main.gd has the Place tool (P), the layer bar under the
     map and the Placements tab.
   - How it works: the model is a view over the live JSON entry (Placement.entry), rebuilt after every
     change, so nothing is converted until a field is edited and untouched fields keep their exact
     form. Edits snapshot the whole list member (MapDocument's member-snapshot undo, member order
     included), so undo gives back the exact object and the file is written as its original text again.
     A new list goes last in the object; an emptied one is removed. New fields go in a per-kind order
     (what it places, x, y, then the rest); unknown keys are appended. The canvas draws a box for a
     point and a dashed outline for a range, colored by layer (Items, Monsters, Vehicles, Nested,
     Other) with labels like "I 50%", "M 1/10", "V 1% x2-3"; entries BN drops or reads oddly are red
     with "!", where BN puts them (dropped ones where they're written, even outside the map), and
     "set" entries are drawn in every tile. Cells whose symbol itself places items/monsters/... get a
     corner mark in that layer's color (read-only; edited through the symbol). Place tool: click picks
     the smallest visible entry under the cursor, drag moves it, dragging the selected one's
     bottom-right cell (or Shift+drag) resizes it; Add (Placements tab) arms a kind and the next drag
     creates it. Moves keep the size and the tile of the new top-left; resizes and new entries are cut
     at the anchor's tile edge; "set" entries stay in their own tile (tile coordinates). A click without
     a drag changes nothing, so an oddly written entry isn't normalized by selecting it. The inspector
     edits every field as text (ids plain, the rest JSON; "1-3" also works for ranges), parsed with
     BnJson so ints stay ints; an empty field is removed; hints give each kind's default and what its
     chance means. Hover lists the placements under the cursor in the status bar; Delete removes the
     selected one with the Place tool active.
   - Decisions and checks (against BN 39f4883093 mapgen.cpp):
     - Recounted for core only (the proposed acceptance used core + mods): 19 dropped anchors, not 24
       (20 over every folder in data/, so the 24 was a miscount); 54 spanning reversed ranges, 209
       dropped "set" in 44 maps, as stated. 13 place_* entries in 12 chunk/update mapgens reach past
       mapgensize (the "8 chunks" in Stage 7's list needs rechecking there).
     - A chunk's place_* bound is 24x24 (jmapgen_objects keeps the default size), so those 13 load and
       are marked, not dropped; drags in a chunk are kept inside its mapgensize (stricter than BN).
     - "set" chance is one in N (default 1: `chance != 1 && !one_in(chance)`); its x/y ranges pick a
       random cell per repeat; a bad id makes BN skip every later "set" entry of the map (not modelled).
       place_liquids' chance is one in N too. "add" (24 uses) is the old name of place_item and is read.
     - Refused as BN would refuse or drop them: an edit or drag whose range leaves its tile, or whose
       anchor is outside the map. An entry BN already drops can still be edited in place (its chance,
       ...), as long as it isn't moved to another dropped position. Saving refuses a crossing range
       even if it was in the file already (BN wouldn't load it); none exist in data.
     - The Inspector and Placements tabs of the UI sketch are one "Placements" tab (list above,
       fields below): selecting in the list and editing below is one step, not a tab switch. The layer
       bar sits under the map as sketched; Terrain/Furniture stay the toolbar's Furniture toggle.
     - Field checks (not id lookups): place_items chance outside 1-100, place_loot with both or neither
       of item/group or a ranged chance, place_monster without monster/group. They're listed with the
       map's problems; ids are Stage 7 (item/vehicle ids aren't indexed yet).
     - Test fixture pitfall: Godot's JSON.stringify sorts keys by default (TempTree uses it), so a
       fixture whose key order matters must be written as text (JSON.stringify(v, " ", false)).
   - Not done / open: id pickers/autocomplete and id validation (Stage 7); a "set" line is drawn as its
     bounding box, and resizing a line/square sets x/y and x2/y2 to single cells; stacked entries pick
     the smallest (others via the list; no click-cycling); dropped entries outside the map are only
     selectable from the list; labels can overlap on dense maps; no multi-select; "set" and
     place_computers/zones/... can be edited and moved but not added from the panel; place_nested only
     shows its rectangle (the chunk itself is Stage 6); palette per-key items/monsters are still
     read-only in the palette editor (the panel's field text parsing can be reused there).
 Checked after Stage 5 (2026-09-27, against BN 39f4883093 source and core data; reviews Stages 6-7
 and the later milestones):
   - Nested chunks (Stage 6), from jmapgen_nested and mapgen_function_json_nested::nest:
     - "chunks" / "else_chunks" are weighted lists of plain ids or [id, weight] pairs (load_weighted_list
       of strings, default weight 100): 1498 plain, 4290 pairs in core, never a param. "null" or ""
       places nothing; an unknown id is a debugmsg and places nothing (a Stage 7 finding).
     - A picked id is a second weighted pick: 169 of 1035 core nested ids have several mapgens, and
       for 4 of them the variants differ in mapgensize. The overlay shows the first (or heaviest)
       variant and says how many there are, like the resolver does for palette choices.
     - neighbors/joins/connections decide between chunks and else_chunks, and need the overmap
       around the map, which the editor doesn't have. The overlay draws "chunks" (conditions met) and
       names the else_chunks; a toggle to show the else case can come later. Only "chunks" occurs in
       the 445 core "nested" symbol mappings (no conditions, no rotation there).
     - Rotation: the placing entry's "rotation" is a jmapgen_int (a [min, max] range is allowed; data
       only uses 1-3) giving clockwise quarter turns, applied with point::rotate around the chunk's
       mapgensize. For a non-square chunk (34 in core) one or three turns swap the footprint's width and
       height. The chunk's own "rotation" (649 core chunks, 656 with mods) is ignored, as noted.
     - Order: nested pieces run in mapgen_phase::nested_mapgen, after the parent's terrain,
       furniture and other pieces and before transforms/faction ownership; within a chunk, its "set"
       entries run before its objects. So a chunk draws over the parent's rows and place_terrain, and
       later nested entries over earlier ones. Undefined " "/"." chunk cells leave the parent's cell.
     - Footprint: Stage 5's place_nested rectangle is only the anchor range (where the chunk's
       top-left corner is picked). BN only bounds that range, so the Place tool is right to keep only
       the anchor inside one tile; the chunk's footprint (anchor range + rotated mapgensize) may run
       past the tile or map. The overlay must draw the footprint and mark the overhang, not clamp it.
       Overhang: map::ter_set writes by absolute position through the mapbuffer, so whether it survives
       depends on whether the neighbouring tile is generated before or after (it would overwrite).
       Still unverified in game; keep the mark.
     - Parameters: nest() takes the chunk's own parameters with scope "nest"; the resolver's defaults
       are fine for display.
     - Counts (core): 2167 place_nested entries in 735 maps, 157 maps with a "nested" mapping, 1536
       chunks, 170 of them placing chunks themselves, 926 using palettes.
   - From the Stage 5 code, for Stage 6:
     - Placement already lists and moves place_nested entries (Nested layer) and its template adds
       {"chunks": []}; Stage 6 adds a chunk id picker to the inspector (the "chunks" field is JSON
       text today) and the footprint drawing.
     - The Placements panel's field text parsing, and PlacementsPanel/IntRange, can edit a chunk's own
       place_* lists unchanged: a chunk opens as a map already, with the 24x24 bound handled.
     - update_mapgen entries are treated like chunks (24x24 bound, "set" by mapgensize); not checked
       further since update_mapgen is out of scope.
   - Validation (Stage 7):
     - Much of it exists: Placement.problems (dropped anchors, crossing and reversed ranges, entries
       past a chunk's mapgensize, dropped "set", place_items chance, place_loot item/group, place_monster
       without monster/group) plus the resolver's symbol checks feed MapDocument.problems(), and saving
       refuses a crossing range. Stage 7 turns these strings into findings with a severity and a target
       (a cell, a placement or a symbol) so the panel can select what it points at.
     - Severity is needed: real maps now report BN quirks BN accepts (ws_regional_dump_0_2 shows 18
       reversed-range notes), which reads as "18 problems". Proposed: error = BN refuses to load (a
       crossing range, place_loot with both or neither of item/group, unknown terrain in rows);
       warning = BN silently does nothing (dropped anchors and "set", place_items chance outside
       1-100, unknown ids); note = BN does something odd but defined (reversed spans, overhang, an
       ignored chunk rotation). The status bar counts errors and warnings.
     - Core counts to use (the earlier list mixed core and core + mods): 19 dropped anchors, 54
       reversed ranges spanning back, 209 dropped "set" in 44 maps, 13 place_* entries past their
       chunk's mapgensize (the "8 chunks" was wrong), 649 ignored chunk rotations, 0 crossing ranges,
       0 place_items chances outside 1-100, 0 place_loot with both/neither.
     - Found in BN while doing Stage 5: a "set" entry with an unknown terrain/furniture/trap id makes
       setup_setmap return, so every LATER "set" entry of that map is dropped too. Worth its own
       finding once ids are indexed.
 Stage 6 - Nested chunks (MVP item 7).
   - Proposed acceptance: create a new chunk (nested_mapgen_id + mapgensize) and place it in a map
     with the Place tool and a chunk picker. Every place_nested / "nested" mapping in core draws its
     chunk's footprint on its parent without errors: "null" places nothing, recursion has a loop
     guard, the placing rotation is applied (a non-square chunk's footprint swaps), chunks draw in
     BN's order over the parent's cells, and the overhang past the anchor's tile is marked. Editing a
     chunk, or a palette it uses, redraws the open parents that place it (directly or through a
     "nested" mapping in one of their palettes), and the palette warning names those parents.
 Stage 7 - Validation panel (MVP item 9). Basic checks exist since Stage 5.
   - Proposed acceptance: all core json mapgens validate with exactly the core counts under "Checked
     after Stage 5", sorted into error/warning/note, and seeded errors are each caught: unknown item,
     monster, vehicle (group or prototype), trap or chunk id; undefined symbol; out-of-range
     coordinate; crossing range; place_items chance outside 1..100; place_loot with both or neither of
     item/group; a "set" with an unknown id (and the later "set" entries it drops). Selecting a finding
     selects its cell, symbol or placement.
 Then the "Later milestones" list.

Explicitly out of scope until the later milestones: tilesets, preview rolls, z-level linking, update_mapgen,
lua mapgen, and editing terrain/furniture definitions themselves.

Reference: plan written against Cataclysm-BN commit 39f4883093 (2026-09-26).

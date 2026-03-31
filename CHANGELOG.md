# Changelog

## [0.12.0-rc2] - 2026-03-31

### Added
- **EngineDebugger IPC** — runtime tools route through Godot's built-in debugger channel instead of a separate WebSocket. Zero config in the game process, no extra port, no race conditions
- **HTTP daemon mode** — `--http` flag starts persistent HTTP server on port 6506. Multiple AI clients share one Godot WebSocket bridge. Idle auto-shutdown
- **Tool consolidation** — 74 tools consolidated into 22 via action enums (~46% schema token reduction): `file`, `scene`, `script`, `proj`, `git`, `shell`, `rt` + existing consolidated tools
- **Batch scene operations** — `scene` gains `find_by_type`, `set_by_type`, `cross_scene_set` actions
- **Autoload management** — `proj` gains `add_autoload` and `rm_autoload` actions
- **Export tool** — `proj` gains `export_presets`, `export_info`, `export_cmd` actions
- **Runtime tools** — `rt` consolidates 13 runtime actions: screenshot, tree, prop, set_prop, call, metrics, input (+side-effect tracking), sig_watch, prop_watch, ui, cam_spawn/move/capture/restore, nav, log
- **Live signal connections** — `analyze` gains `live_signals` action (scene tree signal audit)
- **AnimationTree improvements** — state/blend node positions in structure output, transition xfade/advance_expression, state validation on add/remove transition
- **Test infrastructure** — headless Godot test runner (115 tests across 4 suites), `make test`

### Changed
- **Runtime IPC architecture** — removed `runtimeConn`, `acceptRuntime`, `runtimeReadLoop` from Go bridge. Runtime tools share editor's pending request map via `runtime_tool_invoke`
- **Per-connection pending mutex** — `pendingMu` separates tool result resolution from bridge-level connection management
- **Variadic signal callbacks** — Godot 4.5+ rest parameters replace 9 arity-specific callback functions
- **`const PackedStringArray` → `static var`** — fixes engine bug #88753 where `.size()` returns byte count

### Removed
- Direct WebSocket from game to Go server (runtime uses EngineDebugger IPC)
- `runtimeConn` struct and all runtime WebSocket handling in Go bridge
- `debugger_continue` BFS hack
- 52 standalone tool schemas (consolidated into action enums)

## [0.11.0-rc1] - 2026-03-27

### Added
- **Proxy bridge** — second MCP server connects to the first as a WebSocket proxy instead of killing it, enabling Claude Desktop + Zed to share one Godot connection
- **13 new consolidated tools** — `anim` (AnimationPlayer + AnimationTree), `s3d` (3D scene: meshes, lighting, materials, environment, cameras, gridmaps), `phys` (collision shapes, raycasts, physics bodies, layers), `nav` (navigation regions, agents, mesh baking), `tmap` (TileMapLayer editing), `ptcl` (GPU particles with presets), `audio` (bus layout, effects, AudioStreamPlayer), `input` (InputMap management), `shader` (shader files + uniforms), `theme` (UI theme overrides), `res` (resource files), `analyze` (project analysis: unused resources, signal flow, scene complexity, circular deps, statistics), `perf` (performance monitors)
- **Bridge interface** — `Bridge` interface + `ProxyBridge` impl for multi-client support

### Changed
- **Aggressive token optimization** across all tools:
  - `properties` pattern: consolidated tools use `action` + one `properties` object instead of many top-level params
  - Short tool names: `animation_edit` → `anim`, `scene_3d_edit` → `s3d`, etc.
  - Short action names: `setup_collision` → `collision`, `get_actions` → `list`, etc.
  - Short response keys: `error` → `err`, `suggestion` → `sug`, `old_value` → `old`, `matches` → `m`, `track_index` → `ti`, `image_base64` → `img`
  - Minimal returns: mutations return `{}`, reads drop echoed input keys, no derivable counts
  - Go schema descriptions stripped to bare minimum
- **Wire protocol simplified** — removed `success` field, bridge derives success from absence of `err` key in result
- **StringName conversion** — all dict keys and match arms in `mcp_runtime.gd` and `mcp_client.gd` use `&"key"` for interned pointer comparison
- **Tool merges** — `get_input_map` + `configure_input_map` → `input`, `get_collision_layers` + `set_collision_shape` → `phys`

### Removed
- `get_input_map`, `configure_input_map` — use `input` with action `list`/`set`
- `get_collision_layers` — use `phys` with action `get_layers`
- `set_collision_shape` — use `phys` with action `collision`
- `success` field from WebSocket wire protocol
- Verbose response fields: confirmation booleans, echoed input keys, derivable counts

## [0.10.0] - 2026-03-24

### Added
- **Dynamic tool sets** — `GODOT_MCP_LAZY=1` env var starts with only core tools, load categories on demand via `get_godot_status({"enable": [...]})` for clients supporting `tools/list_changed`
- **Tabular response format** — uniform arrays use `_h`/`rows` header+rows format, saving ~26-42% tokens on search results, class introspection, git status, and symbol queries
- **Compact vector serialization** — `V2(x,y)`, `V3(x,y,z)`, `C(r,g,b,a)`, `R2()`, `Q()`, `NP()` string format instead of verbose dicts (~60% savings per value)
- **`tabular()` helper** in `tool_utils.gd` and `mcp_runtime.gd`

### Changed
- **Tool consolidation** — 72 → 59 tools: `git` (7→1 with `action` param), `scene_edit` (7→1 with `edits` array), `inject_input` (4→1 with `type` param), `signal_watch` (3→1 with `action` param)
- **Trimmed all tool and param descriptions** — ~900 tokens/message saved from definition overhead
- **Stripped redundant response fields** — removed computed counts, null values, echoed-back args, mock metadata, `"ok"` key from all tool results
- **Slimmed error responses** — just `{"error":"..."}` instead of including tool name, args, mode, and hint
- **Type safety audit** — `.assign()` for typed arrays, explicit types on all declarations, direct dict access for required args, `.get()` only for optional args
- **Visualizer updated** for consolidated tool names (`scene_edit`, `git`, `inject_input`, `signal_watch`)
- **ReconnectHelper** — extracted shared reconnect-with-backoff logic for WebSocket connections

### Removed
- Individual git tools (`git_status`, `git_commit`, `git_diff`, `git_log`, `git_stash`) — use `git` with `action` param
- Individual scene mutation tools (`add_node`, `remove_node`, `move_node`, `reparent_node`, `rename_node`, `modify_node_property`, `duplicate_node`) — use `scene_edit` with `edits` array
- Individual input injection tools (`inject_action`, `inject_key`, `inject_mouse_click`, `inject_mouse_motion`) — use `inject_input` with `type` param
- Individual signal tools (`watch_signal`, `unwatch_signal`, `get_signal_emissions`) — use `signal_watch` with `action` param
- Mock response metadata (`_mock`, `_note` fields)
- Redundant count fields (`total`, `count`, `file_count`, `total_matches`, `error_count`)

## [0.9.0] - 2026-03-14

### Added
- **Runtime bridge** — new `mcp_runtime.gd` autoload connects the running game to the MCP server via WebSocket, enabling live game inspection and control
- **`capture_screenshot`** — grab the game viewport as a PNG image, returned as MCP `ImageContent`
- **`inspect_runtime_tree`** — walk the live scene tree with configurable depth and root path
- **`get_runtime_property` / `set_runtime_property`** — read and write node properties on running game nodes
- **`call_runtime_method`** — invoke methods on live nodes with serialized arguments
- **`get_runtime_metrics`** — live FPS, frame time, memory usage, object counts, and render stats via `Performance.get_monitor()`
- **`inject_action`** — simulate input actions (e.g. "jump", "ui_accept") with configurable strength
- **`inject_key`** — send keyboard events by Godot key name with modifier support
- **`inject_mouse_click`** — simulate mouse clicks at specific viewport coordinates
- **`inject_mouse_motion`** — simulate mouse movement with relative and absolute positioning
- **`watch_signal` / `unwatch_signal`** — subscribe to signals on live nodes, buffer emissions with serialized args
- **`get_signal_emissions`** — poll buffered signal emissions with optional key filter and clear control
- **`query_class_info`** — ClassDB introspection: methods, properties, signals, enums for any Godot class
- **`query_classes`** — list/filter ClassDB classes by name, category, and instantiability
- **Batch file tools** — `read_files`, `bulk_edit`, `find_references`, `list_resources`
- **Batch script tools** — `validate_scripts`, `get_script_symbols`, `find_class_definition`
- **Git tools** — `git_diff`, `git_log`, `git_stash`
- **`run_shell_command`** — execute shell commands from the editor
- **`get_uid`** — get Godot UID for a resource path

### Changed
- **Dual WebSocket connections** — Go bridge now accepts both editor (`godot_ready`) and runtime (`runtime_ready`) connections on the same port (6505)
- **`Runtime` flag on `ToolDef`** — runtime tools route to the game process instead of the editor; no mock fallback (error if game not running)
- File Operations: 9 → 13, Script Operations: 5 → 8, Project Tools: 16 → 25, total tools: 42 → 72 (including 13 new runtime tools and `get_godot_status`)

## [0.8.2] - 2026-03-13

### Added
- **Bulk `remove_node`** — pass `node_paths` array to remove multiple nodes in a single load/save cycle instead of calling the tool N times. Single `node_path` still works for backward compatibility
- **Stack traces in `get_errors`** — Output panel errors now collect `at:` continuation lines into a `stack` array with file and line info, matching `get_debug_errors` behavior

## [0.8.1] - 2026-03-12

### Fixed
- **`play_project` no longer crashes Godot** — play/stop calls now use `call_deferred()` so the WebSocket tool response is sent before Godot freezes to launch the game
- **Mock fallback no longer triggers on mid-call crash** — Go server captures connection state before invoking a tool; if Godot was connected but crashes during execution, a proper error is returned instead of fake mock data

## [0.8.0] - 2026-03-11

### Added
- **Auto-clear zombie port** — MCP server auto-kills stale processes occupying port 6505 on startup, then retries. Supports Linux (`fuser`), macOS (`lsof`), and Windows (`netstat`/`taskkill`)

### Changed
- **Reconnect backoff reduced** — Godot plugin max reconnect delay lowered from 30s to 15s
- **GDScript CI workflow** — auto-format on push with commit, lint step removed

## [0.7.3] - 2026-03-11

### Fixed
- **`get_debug_errors` tree lookup fixed** — ancestor walk in `_find_error_tree` stopped too early when the error Tree was a direct child of the `Errors` tab, never matching the name check

## [0.7.2] - 2026-03-10

### Fixed
- **UTF-8 corruption in `read_file`** — replaced `get_buffer().get_string_from_utf8()` with `get_as_text()` to prevent splitting multi-byte characters at byte boundaries. Truncation now uses character count instead of byte count
- **Binary file filter expanded** — `search_project` and `replace_in_files` now skip fonts (`.ttf`, `.otf`), compiled resources (`.res`, `.scn`, `.ctex`), archives (`.zip`, `.pck`), native libraries, and additional asset formats
- **`get_debug_errors` tree lookup fixed** — ancestor walk in `_find_error_tree` stopped too early when the error Tree was a direct child of the `Errors` tab, never matching the name check

## [0.7.1] - 2026-03-10

### Added
- **`configure_input_map` tool** — add, remove, or replace input actions with key/mouse/joypad events. Refreshes editor UI live. Blocks removal of built-in `ui_*` actions

### Changed
- Unified all log prefixes to `[GMCP]` (was mixed `[MCP]` / `[Godot MCP]`)
- Menu item renamed to **GMCP: Map Project**
- Status label renamed to **GMCP: Connected** / **GMCP: Disconnected**
- Project Tools count: 15 → 16, total tools: 41 → 42

## [0.7.0] - 2026-03-10

### Added
- **`set_project_setting` tool** — modify any ProjectSettings value (autoloads, window size, main scene, etc.) with old/new value confirmation
- **`create_file` tool** — create text files in the Godot project with overwrite protection and auto-created parent directories
- **`delete_folder` tool** — delete directories with optional recursive mode and protected path safeguards (`res://`, `res://addons`, `res://addons/godot_mcp`)
- **`git_status` tool** — show working tree status, current branch, and changed/added/deleted/renamed files
- **`git_commit` tool** — stage specific files or all changes and commit, with path traversal protection

### Changed
- File Operations tool count: 6 → 9
- Project Tools count: 13 → 15
- Total tools: 36 → 41
- Collision layer response uses `{index, value}` shape instead of flat map
- Cached `_project_path` in ProjectTools to avoid repeated `globalize_path` calls

### Fixed
- Duplicate `var cls` declaration in `scene_tools.gd` causing parse errors

### Security
- Git commit file paths validated against `..` traversal and absolute path escapes
- Git args use `--` separator to prevent flag injection from filenames starting with `-`

## [0.6.0] - 2026-03-04

### Added
- **`format_script` tool** — format GDScript files using an external formatter (e.g., [gdscript-formatter](https://github.com/GDQuest/gdscript-formatter)). Conditionally registered — only available when the formatter binary is on PATH
- **`get_debug_errors` tool** — read runtime errors and warnings from the Godot Debugger > Errors tab, including stack traces. Scrapes the editor's internal ScriptEditorDebugger Tree widget
- **Auto-format setting** — enable `godot_mcp/auto_format_scripts` in Project Settings to automatically format scripts after every MCP edit (create, edit, modify variable/signal/function)
- **Configurable formatter command** — `godot_mcp/script_formatter_command` Project Setting lets users choose their preferred formatter binary
- **Plugin settings in Project Settings** — settings appear under Godot MCP section without needing Advanced Settings toggle
- **Runtime control tools** — `play_project`, `stop_project`, `is_project_running` for playing/stopping scenes from AI clients

### Security
- **Path traversal fix** — `validate_res_path()` blocks `../` escape sequences in all tool handlers (file, scene, script, project, asset, visualizer)
- **Concurrent write safety** — added `writeMu` mutex for WebSocket writes in Go bridge
- **Crash boundary** — `tool_executor.gd` catches null/non-Dictionary returns from tool handlers
- **Background thread fix** — removed `validate_script` from background-safe list (accesses editor UI)

### Changed
- Script Operations tool count: 4 → 5
- Project Tools count: 9 → 13
- Total tools: 31 → 36
- Go tool schemas: added `Enum` field, fixed `Required` fields, reorganized tool files to match GDScript handlers
- Removed dead code stubs from asset_tools (search_comfyui_nodes, RunningHub tools)

## [0.4.0] - 2026-02-28

### Added
- **Undo/redo system** — Ctrl+Z / Ctrl+Shift+Z across all visualizer edit operations via command pattern
- **Searchable type combobox** — for variable types and signal param types, includes project types and all built-in Godot types
- **Structured signal parameter editor** — name input + type combobox per param, Tab to add more
- **Usage analysis** — detection before deleting or renaming scripts/functions

### Changed
- Unified toolbar layout in visualizer
- Scene tree view improvements

## [0.3.2] - 2026-02-27

### Changed
- **Refactored GDScript addon** — all tool handlers are now `RefCounted` (not Node), shared `ToolUtils` class, unified routing through `tool_executor.gd`

## [0.3.1] - 2026-02-26

### Fixed
- **Moved visualizer to editor button** — accessible via Project → Tools menu
- **Fixed rendering issues** in visualizer

## [0.2.4] - 2026-02-23

### Changed
- **Published to official MCP registry** — `godot-mcp-server` is now listed at `registry.modelcontextprotocol.io` as `io.github.plaught-armor/godot-mcp`
- **Updated npm README** — fully reflects current features, tools, visualizer screenshot, and npx-based install
- **Added `server.json`** — MCP registry manifest for automated discovery
- **Updated `package.json`** — added `mcpName` and `repository` fields required by the MCP registry

## [0.2.3] - 2026-02-23

### Changed
- Minor package metadata update (intermediate release during registry setup)

## [0.2.2] - 2026-02-23

### Fixed
- **`create_scene` schema now valid for strict MCP clients** — added missing `items` field to the `nodes` array property, fixing Windsurf/Cascade rejecting the tool with "array schema missing items"

## [0.2.1] - 2026-02-17

### Changed
- **Moved plugin to repo root** — `addons/godot_mcp/` is now at the repo root instead of nested under `godot-plugin/`, matching the Godot Asset Library expected layout
- **Added `.gitattributes`** — Asset Library downloads now only include the `addons/` folder
- **Updated install instructions** — README and SUMMARY reflect the new path

## [0.2.0] - 2026-02-11

### Fixed
- **Console log and error tools now work reliably** — reads directly from the editor's Output panel instead of the buffered log file on disk, which was returning stale/incomplete data
- **`get_errors` returns newest errors first** — previously returned oldest errors from the start of the log
- **`get_errors` uses proper Godot error patterns** — matches `ERROR:`, `SCRIPT ERROR:`, `WARNING:`, etc. instead of naively matching any line containing the word "error"
- **`clear_console_log` actually clears the Output panel** — previously was a no-op that returned a fake "acknowledged" message
- **`validate_script` bypasses resource cache** — creates a fresh GDScript instance from the file on disk so edits are validated correctly, not stale cached versions
- **`validate_script` returns actual error details** — extracts parse errors from the Output panel instead of just saying "check Godot console"

### Changed
- **Renamed `apply_diff_preview` to `edit_script`** — clearer name for the code editing tool
- **`scene_tree_dump` description corrected** — now accurately says it dumps the scene open in the editor, not a "running" scene
- **Removed dead code** — cleaned up unused `_console_buffer` and `MAX_CONSOLE_LINES`

### Removed
- **Removed `search_comfyui_nodes` tool** — was a non-functional stub that cluttered the tool list
- **Hidden RunningHub tools from MCP** — `inspect_runninghub_workflow` and `customize_and_run_workflow` are not exposed until properly documented (GDScript implementations preserved)

## [0.1.0] - 2025-01-28

### Added
- Initial release
- 32 MCP tools across 6 categories
- Godot editor plugin with WebSocket bridge
- Interactive browser-based project visualizer

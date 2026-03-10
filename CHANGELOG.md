# Changelog

## [0.7.2] - 2026-03-10

### Fixed
- **UTF-8 corruption in `read_file`** — replaced `get_buffer().get_string_from_utf8()` with `get_as_text()` to prevent splitting multi-byte characters at byte boundaries. Truncation now uses character count instead of byte count
- **Binary file filter expanded** — `search_project` and `replace_in_files` now skip fonts (`.ttf`, `.otf`), compiled resources (`.res`, `.scn`, `.ctex`), archives (`.zip`, `.pck`), native libraries, and additional asset formats

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

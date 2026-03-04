# Visual Tree Roadmap

## Completed
- [x] Inline variable/signal editing
- [x] @onready toggle
- [x] Function code editing with syntax highlighting
- [x] Usage detection before delete
- [x] Floating usage panel with navigation
- [x] Right-click context menu
- [x] New script creation
- [x] Draggable/resizable panels
- [x] Function deletion with usage check
- [x] Scene View tab (Phase 4 - Core)
  - Scene overview with cards showing scene info
  - Click scene → expand to full node hierarchy tree
  - Visual node tree with parent-child connections
  - Sibling order indicators (for 2D draw order)
  - Click node → dynamic properties panel
  - Inline editing of all node properties
  - Property controls: toggles, sliders, vectors, colors, enums
  - Back navigation to scene overview
- [x] Right-click context menu on scene nodes (add child, delete, rename, duplicate, reorder)
- [x] Visualizer launched from editor (Project → Tools → MCP: Map Project)
- [x] Minimap with viewport rect, click-to-pan, drag-to-pan
- [x] Folder grouping — scripts cluster by folder with background rects and labels
  - Force-directed layout with folder cohesion/repulsion forces
  - Bounding-box based folder separation (80px gap)
  - Column-major grid snapping within folders (max 4 rows)
  - Cross-folder edge dampening to prevent folder stretching
- [x] Folder dragging — click and drag a folder background to move all its scripts together
- [x] Position persistence — node and camera positions saved to localStorage across sessions
- [x] Delete/rename scripts from visualizer
  - Delete with usage detection and reference listing
  - Rename/move with optional reference updates across files
  - Confirmation modals to prevent accidents
- [x] Root folder grouping — subfolders with same root directory cluster together
  - Root-folder cohesion force in layout
  - Subfolder grid snapping within root folders
  - Grey root folder backgrounds behind colored subfolder groups
- [x] Git integration — modified files indicator
  - Go server runs `git status` and injects per-file status into project data
  - Colored dots on nodes: green (added), yellow (modified), red (deleted), blue (renamed)
  - Stats bar shows count of modified files
- [x] Dependency analysis — circular deps and orphaned scripts
  - DFS cycle detection on extends/preload graph
  - Orphaned script detection (no incoming or outgoing structural edges)
  - Circular dep warning icon on affected nodes
  - Dashed border on orphaned scripts
  - Stats bar shows counts
- [x] Undo/redo system
  - Command pattern with execute/undo closures for all 20 mutation call sites
  - 50-entry history stack with cursor-based navigation
  - Ctrl+Z undo, Ctrl+Shift+Z / Ctrl+Y redo (skipped in text inputs)
  - Toast notifications (bottom-center) showing action/undo/redo/error
  - Covers: variable/signal/function edits, script create/delete/rename, scene node operations, scene property changes
- [x] Searchable type combobox
  - Replaces raw text input for variable types and signal param types
  - Combines project types (classes, enums, resources) with built-in Godot types
  - Filterable search input with keyboard navigation (arrow keys, Enter, Escape)
  - Auto-fills default values when type changes (e.g. int → 0, bool → false, String → "")
- [x] Structured signal parameter editor
  - Each param has a name text input + type combobox + delete button
  - Tab from last param's type adds a new param automatically
  - Click `+` to add params, `×` to remove
  - Serializes to/from raw `"name: Type, name2: Type2"` format for backend
- [x] Unified toolbar
  - Single toolbar row with view tabs (Scripts/Scenes), layout/zoom controls, search
- [x] GDScript formatting via `format_script` MCP tool
  - Conditional tool: only registered when `gdscript-formatter` binary is on PATH
  - Auto-format setting in Project Settings (`godot_mcp/auto_format_scripts`)
  - Configurable formatter command (`godot_mcp/script_formatter_command`)

## In Progress

### Phase 2: Visual Connections
- [ ] Drag signal → function to create `.connect()` code (WIP — scaffolding in place, not yet functional)
  - Drag handle (⊙) on signal items in panel
  - Green dashed bezier wire follows cursor to canvas
  - Function ports appear on target node's left edge during drag
  - Same-script drop targets on panel function items
  - Connection dialog with target reference guess and live code preview
  - Injects `.connect()` into `_ready()` via `edit_script`
  - Optimistic edge update in graph
- Visual signal/function ports on node edges when hovering (without active drag)
- Show existing `.connect()` edges with signal/function labels on hover

### Phase 3: Script Editing
- Create new functions from panel (name, params, return type, body template)
- Edit function signatures (rename, change params/return type)
- Structured function parameter editor (reuse signal param editor pattern)
- Script templates (Node2D, State Machine, Singleton, etc.)
- Add `@export` annotations with type hints from combobox
- Visualizer "Format" button in panel (runs `format_script` on current script)

### Phase 4: Scene View (Enhancements)
- Drag to reorder siblings (change draw order)
- Drag scripts onto scene nodes to attach
- Cross-scene signal visualization
- Scene node creation from script class (instantiate a script's base type)

### Phase 5: Advanced
- Full-text search in function bodies
- Find all references to a variable/function/signal across all scripts
- Batch rename (rename a function and update all call sites)

### Phase 6: Polish
- Documentation generation
- Code snippets library
- Keyboard shortcuts panel / help overlay
- Export visualizer as static image (PNG/SVG)

### Phase 7: Native Editor Integration
- Main screen plugin (`_has_main_screen()`) — visualizer as a tab alongside 2D/3D/Script/AssetLib
- Embed existing HTML/JS visualizer via [godot_wry](https://github.com/kroketio/godot_wry) (Rust-based system webview, MIT, Godot 4.1+)
- Webview loads `localhost:6510` — same URL, same WebSocket, zero JS changes needed
- Go MCP server is always running (it's the Claude↔Godot bridge), so the visualizer URL is always available

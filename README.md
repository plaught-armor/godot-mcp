# Godot MCP

> Forked from [tomyud1/godot-mcp](https://github.com/tomyud1/godot-mcp) — independently maintained with extended features. Actively developed with Claude and tested daily in real Godot projects.

**Give your AI assistant full access to the Godot editor.**

Build games faster with Claude, Cursor, or any MCP-compatible AI — no copy-pasting, no context switching. AI reads, writes, and manipulates your scenes, scripts, nodes, and project settings directly.

> Godot 4.x · 22 consolidated tools · HTTP daemon with idle shutdown · EngineDebugger runtime IPC · Interactive project visualizer · MIT license

---

## Quick Start

### 1. Install the Godot plugin

Inside the Godot editor, click the **AssetLib** tab at the top → search **"mcp"** → find **"Godot AI Assistant tools MCP"** → Install.

That's it — no manual file copying needed.

### 2. Install the MCP server

Download the binary for your platform from [GitHub Releases](https://github.com/plaught-armor/godot-mcp/releases):

| Platform | File |
|----------|------|
| Windows | `godot-mcp-server.exe` |
| macOS (Apple Silicon) | `godot-mcp-server-darwin-arm64` |
| macOS (Intel) | `godot-mcp-server-darwin-amd64` |
| Linux | `godot-mcp-server-linux-amd64` |

#### Windows

1. Create a folder for the binary, e.g. `C:\Tools\`
2. Move `godot-mcp-server.exe` into that folder
3. **Add the folder to your PATH:**
   - Press `Win + R`, type `sysdm.cpl`, press Enter
   - Go to the **Advanced** tab → click **Environment Variables**
   - Under **User variables**, select `Path` and click **Edit**
   - Click **New**, type `C:\Tools\`, click **OK** on every dialog
4. Open a **new** terminal and verify:
   ```
   godot-mcp-server.exe --help
   ```

> If you don't want to touch PATH, skip step 3 and use the full path in your AI client config (see below).

#### macOS / Linux

```bash
mv godot-mcp-server-darwin-arm64 ~/.local/bin/godot-mcp-server
chmod +x ~/.local/bin/godot-mcp-server
```

### 3. Add the server to your AI client

The MCP server runs as an HTTP daemon. AI clients connect via `--client` mode, which auto-starts the daemon if needed and proxies stdio ↔ HTTP. Multiple clients share one daemon — no port conflicts.

**Claude Desktop** — Settings → Developer → Edit Config:

```json
{
  "mcpServers": {
    "godot": {
      "command": "godot-mcp-server",
      "args": ["--client"]
    }
  }
}
```

Windows without PATH — use the full path instead:
```json
{
  "mcpServers": {
    "godot": {
      "command": "C:\\Tools\\godot-mcp-server.exe",
      "args": ["--client"]
    }
  }
}
```

**Claude Code:**
```bash
claude mcp add godot -- godot-mcp-server --client
```

Works with any MCP-compatible client (Cursor, Windsurf, Cline, etc.) — same JSON format.

**Lazy mode (optional)** — starts with only core tools and loads categories on demand via `get_godot_status({"enable": [...]})`. Reduces token usage on clients that support `tools/list_changed` notifications:

```json
{
  "mcpServers": {
    "godot": {
      "command": "godot-mcp-server",
      "args": ["--client"],
      "env": { "GODOT_MCP_LAZY": "1" }
    }
  }
}
```

> **Note:** Claude Code supports `list_changed` since v2.1.0, but newly enabled tools only appear on the **next turn** — not the turn where `enable` is called ([issue #4118](https://github.com/anthropics/claude-code/issues/4118)). Claude Code already defers tool schema loading internally, so eager mode (the default) gives similar token savings without the one-turn delay.

### 4. Restart your AI client

Close and reopen Claude Desktop / Cursor / your client so it picks up the new config.

### 5. Restart your Godot project

Hit **Restart Project** in the Godot editor. Check the **top-right corner** — you should see **GMCP: Connected** in green. You're ready to go.

---

## What Can It Do?

### 22 Consolidated Tools

Every tool uses an `action` enum for multiple operations in one schema, minimizing token overhead.

| Tool | Actions | What it does |
|------|---------|-------------|
| `file` | ls, read, reads, create, search, mkdir, rm, rmdir, rename, replace, bulk_edit, refs, resources | File operations |
| `scene` | create, read, edit, batch, find_by_type, set_by_type, cross_scene_set, attach_script, detach_script, texture | Scene editing |
| `script` | create, edit, validate, validate_batch, list, symbols, find_class, format | GDScript operations |
| `proj` | settings, set_setting, node_props, autoloads, console, errors, debug_errors, clear_console, open, tree, play, stop, running, uid, class_info, classes, export_presets, export_info, export_cmd | Project management |
| `git` | status, commit, diff, log, stash_push, stash_pop, stash_list | Version control |
| `shell` | (direct) | Execute shell commands |
| `rt` | screenshot, tree, prop, set_prop, call, metrics, input, sig_watch, prop_watch, ui, cam_spawn, cam_move, cam_capture, cam_restore, nav, log | Runtime game tools |
| `anim` | list, create, track, keyframe, info, remove, new_tree, tree, add_state, rm_state, add_trans, rm_trans, blend_node, set_param | Animation |
| `s3d` | mesh, lighting, material, environment, camera, gridmap | 3D scene |
| `phys` | collision, layers, get_layers, raycast, body, info | Physics |
| `nav` | region, bake, agent, layers, info | Navigation |
| `tmap` | set_cell, fill_rect, get_cell, clear, info, used_cells | TileMap |
| `ptcl` | create, material, gradient, preset, info | Particles |
| `audio` | list, add, set, effect, player, info | Audio buses |
| `input` | list, set | Input map |
| `shader` | create, read, edit, assign, param, params | Shaders |
| `theme` | create, color, constant, font_size, stylebox, info | UI themes |
| `tres` | read, edit, create, preview | Resources |
| `perf` | monitors, summary | Profiling |
| `analyze` | unused, signals, complexity, references, circular, stats, live_signals | Project analysis |
| `generate_2d_asset` | (direct) | 2D sprite generation |

> `format_script` requires [gdscript-formatter](https://github.com/GDQuest/gdscript-formatter) on PATH. If not found, the tool is hidden from AI clients automatically.
> Runtime tools require the game to be running (`play_project` first). They communicate with the game via EngineDebugger IPC through the editor.

### Interactive Visualizer

Open the visualizer from the Godot editor: **Project → Tools → GMCP: Map Project**. A browser-based explorer opens at `localhost:6510`.

**Script Map**
- Force-directed graph of all scripts and their relationships
- Folder grouping with drag-to-move folders and position persistence
- Git status indicators (green/yellow/red/blue dots) and dependency analysis (circular deps, orphaned scripts)
- Click any script to see variables, functions, signals, and connections
- Minimap with click-to-pan navigation

**Inline Editing**
- Edit variables, signals, and function code directly — changes sync to Godot in real time
- Searchable type combobox with project types and all built-in Godot types
- Structured signal parameter editor (name + type per param, Tab to add more)
- Undo/redo (Ctrl+Z / Ctrl+Shift+Z) across all edit operations
- Usage detection before deleting or renaming scripts/functions
- Create, delete, and rename scripts from the visualizer

**Scene View**
- Browse all scenes, click to expand full node hierarchy tree
- Inline editing of node properties (toggles, sliders, vectors, colors, enums)
- Right-click context menu on nodes (add child, delete, rename, duplicate, reorder)

<img width="1710" height="1107" alt="image" src="https://github.com/user-attachments/assets/a9faf163-8b8b-43da-93ec-c7a651e8ac60" />

### Plugin Settings

The Godot plugin adds settings under **Project → Project Settings → Godot MCP**:

| Setting | Default | Description |
|---------|---------|-------------|
| **Auto Format Scripts** | `false` | Automatically format GDScript files after every MCP script edit |
| **Script Formatter Command** | `gdscript-formatter` | External formatter binary to use (e.g., `gdscript-formatter`, `gdformat`) |

---

## Architecture

```
                                                           ┌──────────────┐
┌─────────────┐  stdio   ┌──────────┐                     │ Godot Editor │
│  AI Client   │◄────────►│ --client │  MCP (HTTP)         │  (Plugin)    │
│  (Claude,    │          │  proxy   │◄──────────┐         │              │
│   Cursor)    │          └──────────┘           │         │  Debugger    │
└─────────────┘                          ┌───────▼───────┐ │  Plugin      │
                                         │  MCP Server   │ │      │       │
┌─────────────┐  stdio   ┌──────────┐   │  (Go daemon)  │ │      │ IPC   │
│  AI Client 2 │◄────────►│ --client │◄─►│  HTTP :6506   │ │      ▼       │
│  (Zed,       │          │  proxy   │   │               │ │ Running Game │
│   Codex)     │          └──────────┘   │  Visualizer   │ │  (Autoload)  │
└─────────────┘                          │  HTTP :6510   │ └──────────────┘
                                         │           WS  │        ▲
                                         │          6505 │────────┘
                                         └───────┬───────┘
                                          ┌──────▼───────┐
                                          │   Browser     │
                                          │  Visualizer   │
                                          └──────────────┘
```

**HTTP daemon** — the server runs as a persistent HTTP daemon on port 6506. AI clients connect via `--client` mode, which proxies stdio ↔ HTTP. Multiple clients share one daemon and one Godot connection. The daemon auto-shuts down after 30s of inactivity (configurable via `GODOT_MCP_IDLE_TIMEOUT_MS`).

**Editor tools** (scene/script/project) go from the daemon to the editor plugin via WebSocket on port 6505.

**Runtime tools** (screenshots, input injection, live inspection) go from the daemon to the editor, then through Godot's built-in **EngineDebugger IPC** channel to the running game. No extra port or connection needed.

---

## Limitations

- **Local only** — runs on localhost, no remote connections
- **No undo for MCP edits** — the visualizer has undo/redo, but AI client tool calls save directly (use version control)
- **AI struggles with complex layouts** — UI composition and some node property setups still need manual work
- **Godot 4.5+ recommended** — runtime tools use rest parameters (`...args`) which require Godot 4.5+. Editor tools work on 4.x

---

## Development

```bash
# Build
cd mcp-server-go
make build

# Test (requires Godot 4.5+ binary — set GODOT= to override path)
cd ..
make test              # GDScript parse check + unit tests + Go build/vet
make test-integration  # Full Go server + headless Godot editor pipeline
```

Binary is at `mcp-server-go/bin/godot-mcp-server`. Cross-compile for all platforms with `make build-all`.

On Windows without `make`:
```
go build -o bin\godot-mcp-server.exe ./cmd/godot-mcp-server
```

---

## License

MIT

---

**[GitHub](https://github.com/plaught-armor/godot-mcp)** · **[Report Issues](https://github.com/plaught-armor/godot-mcp/issues)**

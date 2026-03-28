# Godot MCP

> Forked from [tomyud1/godot-mcp](https://github.com/tomyud1/godot-mcp) — independently maintained with extended features. Actively developed with Claude and tested daily in real Godot projects.

**Give your AI assistant full access to the Godot editor.**

Build games faster with Claude, Cursor, or any MCP-compatible AI — no copy-pasting, no context switching. AI reads, writes, and manipulates your scenes, scripts, nodes, and project settings directly.

> Godot 4.x · 68 tools · Proxy bridge · Runtime bridge · Interactive project visualizer · MIT license

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

**Claude Desktop** — Settings → Developer → Edit Config:

```json
{
  "mcpServers": {
    "godot": {
      "command": "godot-mcp-server"
    }
  }
}
```

Windows without PATH — use the full path instead:
```json
{
  "mcpServers": {
    "godot": {
      "command": "C:\\Tools\\godot-mcp-server.exe"
    }
  }
}
```

**Claude Code:**
```bash
claude mcp add godot godot-mcp-server
```

Works with any MCP-compatible client (Cursor, Windsurf, Cline, etc.) — same JSON format.

**Lazy mode (optional)** — starts with only core tools and loads categories on demand via `get_godot_status({"enable": [...]})`. Reduces token usage on clients that support `tools/list_changed` notifications:

```json
{
  "mcpServers": {
    "godot": {
      "command": "godot-mcp-server",
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

### 59 Tools Across 7 Categories

| Category | Tools | Examples |
|----------|-------|---------|
| **File Operations** | 13 | Browse directories, read/create/search files, bulk read/edit, find references, list resources, rename/delete files and folders |
| **Scene Operations** | 7 | Create/read scenes, batch scene edits (add/remove/move/reparent/rename/set properties), attach/detach scripts, collision shapes, textures |
| **Script Operations** | 7–8 | Create/edit/validate/format scripts, list scripts, get symbols, find class definitions, batch validate |
| **Project Tools** | 21 | Get/set project settings, input map, collision layers, console log, debug errors, scene tree dumps, play/stop project, ClassDB introspection, UID lookup |
| **Git & Shell** | 2 | Consolidated git operations (status/commit/diff/log/stash), shell commands |
| **Runtime Tools** | 8 | Screenshots, live scene tree, get/set properties, call methods, metrics, consolidated input injection, signal watching |
| **Asset Generation** | 1 | Generate 2D sprites from SVG |

> `format_script` requires [gdscript-formatter](https://github.com/GDQuest/gdscript-formatter) on PATH. If not found, the tool is hidden from AI clients automatically.
> Runtime tools require the game to be running (`play_project` first). They operate on the live game process, not the editor.

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
┌─────────────┐    MCP (stdio)    ┌─────────────┐   WebSocket    ┌──────────────┐
│  AI Client   │◄────────────────►│  MCP Server  │◄─────────────►│ Godot Editor │
│  (Claude,    │                  │  (Go binary) │   port 6505   │  (Plugin)    │
│   Cursor)    │                  │              │◄─────────────►│              │
└─────────────┘                  │  Visualizer  │  (same port)  │ Running Game │
                                 │  HTTP :6510  │               │  (Autoload)  │
                                 └──────┬───────┘               └──────────────┘
                                        │
                                 ┌──────▼───────┐
                                 │   Browser     │
                                 │  Visualizer   │
                                 └──────────────┘
```

The Go server maintains two WebSocket connections on port 6505: one to the editor plugin (for scene/script/project tools) and one to the running game's autoload (for runtime tools like screenshots, input injection, and live inspection).

---

## Limitations

- **Local only** — runs on localhost, no remote connections
- **One project at a time** — each server connects to one Godot editor instance
- **No undo for MCP edits** — the visualizer has undo/redo, but AI client tool calls save directly (use version control)
- **AI struggles with complex layouts** — UI composition and some node property setups still need manual work

---

## Development

```bash
cd mcp-server-go
make build
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

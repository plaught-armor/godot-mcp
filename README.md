# Godot MCP

> Forked from [tomyud1/godot-mcp](https://github.com/tomyud1/godot-mcp) — independently maintained with extended features. Actively developed with Claude and tested daily in real Godot projects.

**Give your AI assistant full access to the Godot editor.**

Build games faster with Claude, Cursor, or any MCP-compatible AI — no copy-pasting, no context switching. AI reads, writes, and manipulates your scenes, scripts, nodes, and project settings directly.

> Godot 4.x · 41 tools · Interactive project visualizer · MIT license

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

### 4. Restart your AI client

Close and reopen Claude Desktop / Cursor / your client so it picks up the new config.

### 5. Restart your Godot project

Hit **Restart Project** in the Godot editor. Check the **top-right corner** — you should see **MCP Connected** in green. You're ready to go.

---

## What Can It Do?

### 41 Tools Across 5 Categories

| Category | Tools | Examples |
|----------|-------|---------|
| **File Operations** | 9 | Browse directories, read/create/search files, create folders, rename/delete files and folders, bulk find-and-replace |
| **Scene Operations** | 11 | Create scenes, add/remove/move nodes, set properties, attach scripts, assign collision shapes and textures |
| **Script Operations** | 5 | Create/edit/validate/format scripts, list all scripts |
| **Project Tools** | 15 | Get/set project settings, input map, collision layers, console log, runtime debug errors, scene tree dumps, play/stop project, git status and commits |
| **Asset Generation** | 1 | Generate 2D sprites from SVG |

> `format_script` requires [gdscript-formatter](https://github.com/GDQuest/gdscript-formatter) on PATH. If not found, the tool is hidden from AI clients automatically.

### Interactive Visualizer

Open the visualizer from the Godot editor: **Project → Tools → MCP: Map Project**. A browser-based explorer opens at `localhost:6510`.

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
│   Cursor)    │                  │              │               │              │
└─────────────┘                  │  Visualizer  │               │  41 tool     │
                                 │  HTTP :6510  │               │  handlers    │
                                 └──────┬───────┘               └──────────────┘
                                        │
                                 ┌──────▼───────┐
                                 │   Browser     │
                                 │  Visualizer   │
                                 └──────────────┘
```

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

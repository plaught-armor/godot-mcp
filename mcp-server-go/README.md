# Godot MCP Server (Go)

The recommended MCP server for Godot AI Assistant. Single binary, no runtime dependencies.

## Installation

### Option A: Download a pre-built binary (easiest)

1. Go to [GitHub Releases](https://github.com/tomyud1/godot-mcp/releases)
2. Download the binary for your platform:
   - **Windows:** `godot-mcp-server-windows-amd64.exe`
   - **macOS (Apple Silicon):** `godot-mcp-server-darwin-arm64`
   - **macOS (Intel):** `godot-mcp-server-darwin-amd64`
   - **Linux:** `godot-mcp-server-linux-amd64`

#### Windows setup

1. Create a folder for the binary, for example `C:\Tools\`
2. Move `godot-mcp-server-windows-amd64.exe` into that folder
3. Rename it to `godot-mcp-server.exe` (optional, but makes the config simpler)
4. **Add the folder to your PATH:**
   - Press `Win + R`, type `sysdm.cpl`, press Enter
   - Go to **Advanced** tab → **Environment Variables**
   - Under **User variables**, select `Path` and click **Edit**
   - Click **New** and add `C:\Tools\`
   - Click **OK** on all dialogs
5. **Open a new terminal** (existing ones won't see the PATH change) and verify:
   ```
   godot-mcp-server.exe --help
   ```

If you don't want to add it to PATH, you can use the full path in your AI client config instead (see below).

#### macOS / Linux setup

```bash
# Move to a directory on your PATH
mv godot-mcp-server-darwin-arm64 ~/.local/bin/godot-mcp-server   # macOS Apple Silicon
# or
mv godot-mcp-server-linux-amd64 ~/.local/bin/godot-mcp-server    # Linux

# Make it executable
chmod +x ~/.local/bin/godot-mcp-server
```

### Option B: Build from source

Requires [Go 1.25+](https://go.dev/dl/).

```bash
cd mcp-server-go
make build
```

The binary is at `bin/godot-mcp-server`. Cross-compile for all platforms with `make build-all`.

On Windows without `make`, you can run the Go build command directly:

```
go build -o bin\godot-mcp-server.exe ./cmd/godot-mcp-server
```

---

## AI Client Configuration

### Claude Desktop

Settings → Developer → Edit Config, then add:

**If the binary is on your PATH:**
```json
{
  "mcpServers": {
    "godot": {
      "command": "godot-mcp-server"
    }
  }
}
```

**Windows — if you did NOT add it to PATH, use the full path:**
```json
{
  "mcpServers": {
    "godot": {
      "command": "C:\\Tools\\godot-mcp-server.exe"
    }
  }
}
```

> **Windows users:** Use double backslashes (`\\`) in JSON paths.

### Claude Code

```bash
claude mcp add godot godot-mcp-server
```

Or with a full path on Windows:

```bash
claude mcp add godot "C:\Tools\godot-mcp-server.exe"
```

### Cursor / Windsurf / Other MCP clients

Same JSON format as Claude Desktop above — add the `mcpServers` block to your client's MCP config file.

---

## Verifying It Works

1. **Restart your AI client** after changing the config
2. **Open your Godot project** and make sure the MCP plugin is enabled (Project → Project Settings → Plugins → enable "AI Assistant tools MCP")
3. **Restart the Godot project** (Project → Reload Current Project)
4. Check the **top-right corner** of the Godot editor — you should see **MCP Connected** in green

---

## Troubleshooting

### "godot-mcp-server" is not recognized (Windows)

- You didn't add the folder to PATH, or you didn't open a **new** terminal after editing PATH
- As a workaround, use the full path (`C:\\Tools\\godot-mcp-server.exe`) in your config

### Claude Desktop says the MCP server failed to start

- Open a terminal and run `godot-mcp-server` manually to see the error output
- On Windows, make sure the `.exe` extension is present in the config if using a full path

### Godot says "MCP Disconnected"

- The MCP server communicates with Godot over WebSocket on port **6505**. Make sure nothing else is using that port
- Restart the Godot project after the MCP server is running

### The visualizer doesn't open

- The visualizer runs at `http://localhost:6510`. If that port is taken, it picks the next available port — check the server's stderr output for the actual URL

---

## Architecture

```
AI Client (Claude, Cursor, etc.)
    ↕ stdin/stdout (MCP Protocol)
MCP Server (this binary)
    ↕ WebSocket :6505
Godot Editor (plugin)

MCP Server also serves:
    → Browser visualizer at http://localhost:6510
```

The server runs on **stdio** — your AI client launches it as a subprocess and communicates over stdin/stdout. The server then bridges to the Godot editor plugin over WebSocket.

---

## License

MIT

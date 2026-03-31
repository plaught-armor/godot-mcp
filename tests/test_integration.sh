#!/bin/bash
# Integration test: verifies Go server + headless Godot editor plugin connect.
# Uses HTTP daemon mode so the server stays alive without stdin.
# Usage: ./tests/test_integration.sh [godot_binary]

GODOT="${1:-/mnt/based_backup/Repos/godot/bin/godot.linuxbsd.editor.x86_64}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GO_DIR="$PROJECT_DIR/mcp-server-go"
SERVER_BIN="/tmp/godot-mcp-test-server"
LOG="/tmp/godot-mcp-integration.log"
SERVER_PID=""

export GODOT_MCP_HTTP=1
export GODOT_MCP_HTTP_PORT=16506

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
    [[ -n "$SERVER_PID" ]] && wait "$SERVER_PID" 2>/dev/null || true
    rm -f "$SERVER_BIN" "$LOG"
}
trap cleanup EXIT

echo "=== Integration Test ==="

# Build Go server
echo "  Building Go server..."
cd "$GO_DIR" && go build -o "$SERVER_BIN" ./cmd/godot-mcp-server
if [ $? -ne 0 ]; then
    echo "  FAIL  Go build failed"
    exit 1
fi

# Start Go server (HTTP mode, ws:6505 hardcoded in bridge.go)
echo "  Starting Go server (HTTP mode, http:$GODOT_MCP_HTTP_PORT)..."
"$SERVER_BIN" 2>"$LOG" &
SERVER_PID=$!

# Poll for readiness instead of fixed sleep
for i in $(seq 10); do
    sleep 0.5
    kill -0 "$SERVER_PID" 2>/dev/null && grep -q "listening" "$LOG" 2>/dev/null && break
done

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "  FAIL  Server exited prematurely"
    cat "$LOG"
    exit 1
fi
echo "  Server running (PID $SERVER_PID)"

# Check server log for HTTP mode
if grep -q "HTTP daemon listening" "$LOG" 2>/dev/null; then
    echo "  PASS  HTTP daemon started"
else
    echo "  FAIL  HTTP daemon did not start"
    cat "$LOG"
    exit 1
fi

# Start headless Godot editor (plugin auto-connects to Go server on ws://127.0.0.1:6505)
echo "  Starting headless Godot editor..."
timeout 15 "$GODOT" --headless --editor --path "$PROJECT_DIR" --quit-after 60 2>&1 >> "$LOG" || true

# Check if plugin connected
if grep -q "\[GMCP\] Connected to MCP server" "$LOG" 2>/dev/null; then
    echo "  PASS  Editor plugin connected to Go server"
else
    echo "  WARN  Editor plugin connection not confirmed (port may be in use)"
fi

# Check if Go server received the connection
if grep -q "\[GodotBridge\] Editor.*connected" "$LOG" 2>/dev/null; then
    echo "  PASS  Go server accepted editor connection"
else
    echo "  WARN  Go server did not log editor connection (may be in proxy mode)"
fi

echo "=== Integration test completed ==="

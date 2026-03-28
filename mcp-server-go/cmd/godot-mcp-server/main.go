package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/bridge"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/mcpserver"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/tools"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/visualizer"
)

func main() {
	log.SetOutput(os.Stderr)
	log.SetFlags(0)

	lazy := os.Getenv("GODOT_MCP_LAZY") == "1"

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	log.Printf("[godot-mcp-server] Starting...")

	// Try to own the WebSocket port. If another server already owns it,
	// fall back to proxy mode instead of killing the existing process.
	var br bridge.Bridge

	primary := bridge.New(bridge.DefaultPort, bridge.DefaultTimeout)
	if err := primary.Start(ctx); err != nil {
		log.Printf("[godot-mcp-server] Port %d in use, switching to proxy mode...", bridge.DefaultPort)
		proxy := bridge.NewProxy(bridge.DefaultPort, bridge.DefaultTimeout)
		if err := proxy.Start(ctx); err != nil {
			log.Printf("[godot-mcp-server] Proxy connection failed: %v", err)
			log.Printf("[godot-mcp-server] Continuing in mock-only mode")
			br = primary // use the unstarted bridge — will return mock results
		} else {
			br = proxy
			log.Printf("[godot-mcp-server] Connected as proxy to primary bridge on port %d", bridge.DefaultPort)
		}
	} else {
		br = primary
		log.Printf("[godot-mcp-server] WebSocket server listening on port %d", bridge.DefaultPort)
	}

	// Create visualizer server
	viz := visualizer.New(br)

	// Log connection changes (no-op for proxy mode)
	br.OnConnectionChange(func(connected bool, instanceID string, info *bridge.GodotInfo) {
		if connected {
			log.Printf("[godot-mcp-server] Godot %q connected", instanceID)
		} else {
			log.Printf("[godot-mcp-server] Godot %q disconnected", instanceID)
		}
	})

	// Handle visualizer requests from Godot (no-op for proxy mode)
	br.OnVisualizerRequest(func(_ context.Context, instanceID string, data json.RawMessage) {
		var projectMap any
		if err := json.Unmarshal(data, &projectMap); err != nil {
			log.Printf("[godot-mcp-server] Failed to parse visualizer data: %v", err)
			br.SendNotification("visualizer_status", map[string]any{"err": err.Error()}, instanceID)
			return
		}
		url, err := viz.Serve(projectMap)
		if err != nil {
			log.Printf("[godot-mcp-server] Failed to start visualizer: %v", err)
			br.SendNotification("visualizer_status", map[string]any{"err": err.Error()}, instanceID)
			return
		}
		br.SendNotification("visualizer_status", map[string]any{"url": url}, instanceID)
	})

	if lazy {
		log.Printf("[godot-mcp-server] Lazy mode: %d core tools, %d total available", len(tools.ByCategory("core"))+1, len(tools.AllTools)+1)
	} else {
		log.Printf("[godot-mcp-server] Tools: %d", len(tools.AllTools)+1)
	}
	log.Printf("[godot-mcp-server] Mode: mock (waiting for Godot connection)")

	// Create and run MCP server on stdio
	srv := mcpserver.New(br, lazy)
	if err := srv.Run(ctx, &mcp.StdioTransport{}); err != nil {
		log.Printf("[godot-mcp-server] Fatal error: %v", err)
		os.Exit(1)
	}

	// Cleanup
	viz.Stop()
	br.Stop()
}

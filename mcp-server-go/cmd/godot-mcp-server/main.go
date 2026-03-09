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

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	log.Printf("[godot-mcp-server] Starting...")

	// Create Godot bridge
	b := bridge.New(bridge.DefaultPort, bridge.DefaultTimeout)

	// Create visualizer server
	viz := visualizer.New(b)

	// Start WebSocket server for Godot communication
	if err := b.Start(ctx); err != nil {
		log.Printf("[godot-mcp-server] Failed to start WebSocket server: %v", err)
		log.Printf("[godot-mcp-server] Continuing in mock-only mode")
	} else {
		log.Printf("[godot-mcp-server] WebSocket server listening on port %d", bridge.DefaultPort)
	}

	// Log connection changes
	b.OnConnectionChange(func(connected bool, info *bridge.GodotInfo) {
		if connected {
			log.Printf("[godot-mcp-server] Godot connected")
		} else {
			log.Printf("[godot-mcp-server] Godot disconnected")
		}
	})

	// Handle visualizer requests from Godot (Project → Tools → MCP: Map Project)
	b.OnVisualizerRequest(func(_ context.Context, data json.RawMessage) {
		var projectMap any
		if err := json.Unmarshal(data, &projectMap); err != nil {
			log.Printf("[godot-mcp-server] Failed to parse visualizer data: %v", err)
			b.SendNotification("visualizer_status", map[string]any{"error": err.Error()})
			return
		}
		url, err := viz.Serve(projectMap)
		if err != nil {
			log.Printf("[godot-mcp-server] Failed to start visualizer: %v", err)
			b.SendNotification("visualizer_status", map[string]any{"error": err.Error()})
			return
		}
		b.SendNotification("visualizer_status", map[string]any{"url": url})
	})

	log.Printf("[godot-mcp-server] Available tools: %d", len(tools.AllTools)+1)
	log.Printf("[godot-mcp-server] Mode: mock (waiting for Godot connection)")

	// Create and run MCP server on stdio
	srv := mcpserver.New(b)
	if err := srv.Run(ctx, &mcp.StdioTransport{}); err != nil {
		log.Printf("[godot-mcp-server] Fatal error: %v", err)
		os.Exit(1)
	}

	// Cleanup
	viz.Stop()
	b.Stop()
}

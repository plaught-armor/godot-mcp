package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

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
	httpMode := hasFlag("--http") || os.Getenv("GODOT_MCP_HTTP") == "1"

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

	// Connection logging (HTTP mode overrides this with idle-shutdown callback)
	if !httpMode {
		br.OnConnectionChange(func(connected bool, instanceID string, info *bridge.GodotInfo) {
			if connected {
				log.Printf("[godot-mcp-server] Godot %q connected", instanceID)
			} else {
				log.Printf("[godot-mcp-server] Godot %q disconnected", instanceID)
			}
		})
	}

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

	srv := mcpserver.New(br, lazy)

	if httpMode {
		runHTTP(ctx, cancel, srv, br, viz)
	} else {
		log.Printf("[godot-mcp-server] Running on stdio")
		if err := srv.Run(ctx, &mcp.StdioTransport{}); err != nil {
			log.Printf("[godot-mcp-server] Fatal error: %v", err)
			os.Exit(1)
		}
	}

	viz.Stop()
	br.Stop()
}

func runHTTP(ctx context.Context, cancel context.CancelFunc, srv *mcp.Server, br bridge.Bridge, viz *visualizer.Server) {
	httpPort := 6506
	if v := os.Getenv("GODOT_MCP_HTTP_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			httpPort = p
		}
	}

	idleTimeout := 30 * time.Second
	if v := os.Getenv("GODOT_MCP_IDLE_TIMEOUT_MS"); v != "" {
		if ms, err := strconv.Atoi(v); err == nil {
			idleTimeout = time.Duration(ms) * time.Millisecond
		}
	}

	handler := mcp.NewStreamableHTTPHandler(
		func(_ *http.Request) *mcp.Server { return srv },
		&mcp.StreamableHTTPOptions{},
	)

	httpSrv := &http.Server{
		Addr:    ":" + strconv.Itoa(httpPort),
		Handler: handler,
	}

	// Idle shutdown: when all Godot instances disconnect, start a timer. Cancel if one reconnects.
	// Uses atomic counter to avoid TOCTOU with br.IsConnected().
	var (
		activeCount atomic.Int32
		idleMu      sync.Mutex
		idleTimer   *time.Timer
	)
	br.OnConnectionChange(func(connected bool, instanceID string, info *bridge.GodotInfo) {
		idleMu.Lock()
		defer idleMu.Unlock()
		if connected {
			activeCount.Add(1)
			if idleTimer != nil {
				idleTimer.Stop()
				idleTimer = nil
			}
			log.Printf("[godot-mcp-server] Godot %q connected", instanceID)
		} else {
			log.Printf("[godot-mcp-server] Godot %q disconnected", instanceID)
			if activeCount.Add(-1) == 0 {
				log.Printf("[godot-mcp-server] All Godot instances disconnected, shutting down in %s", idleTimeout)
				idleTimer = time.AfterFunc(idleTimeout, func() {
					log.Printf("[godot-mcp-server] Idle timeout — shutting down")
					cancel()
				})
			}
		}
	})

	go func() {
		log.Printf("[godot-mcp-server] HTTP daemon listening on port %d", httpPort)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("[godot-mcp-server] HTTP server error: %v", err)
			cancel()
		}
	}()

	<-ctx.Done()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		log.Printf("[godot-mcp-server] HTTP shutdown error: %v", err)
	}
}

func hasFlag(flag string) bool {
	for _, arg := range os.Args[1:] {
		if arg == flag {
			return true
		}
	}
	return false
}

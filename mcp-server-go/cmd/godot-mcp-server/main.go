package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"sync"
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

	// Client mode: proxy stdio ↔ HTTP daemon.
	if hasFlag("--client") {
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		if err := runClient(ctx); err != nil {
			log.Printf("[godot-mcp-server] %v", err)
			os.Exit(1)
		}
		return
	}

	lazy := os.Getenv("GODOT_MCP_LAZY") == "1"

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	log.Printf("[godot-mcp-server] Starting...")

	lockFile, err := acquireLock()
	if err != nil {
		log.Printf("[godot-mcp-server] Another instance is already running")
		os.Exit(1)
	}
	defer releaseLock(lockFile)

	br := bridge.New(bridge.DefaultPort, bridge.DefaultTimeout)
	if err := br.Start(ctx); err != nil {
		log.Printf("[godot-mcp-server] Failed to start WebSocket on port %d: %v", bridge.DefaultPort, err)
		os.Exit(1)
	}
	log.Printf("[godot-mcp-server] WebSocket server listening on port %d", bridge.DefaultPort)

	viz := visualizer.New(br)

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

	srv := mcpserver.New(br, lazy)
	runHTTP(ctx, cancel, srv, br, viz)

	viz.Stop()
	br.Stop()
}

// idleTracker manages a unified idle timer that considers both Godot editor
// connections and MCP HTTP request activity. The server shuts down only when
// both are idle for the configured duration.
type idleTracker struct {
	timeout time.Duration
	cancel  context.CancelFunc

	mu         sync.Mutex
	godotCount int
	httpCount  int // active MCP sessions (SSE streams)
	timer       *time.Timer
	hadActivity bool // true once any connection or request has arrived
}

// newIdleTracker creates a tracker. The idle timer only starts after the first
// connection is made and subsequently lost — the daemon stays alive indefinitely
// until something connects, so Godot has time to find it.
func newIdleTracker(timeout time.Duration, cancel context.CancelFunc) *idleTracker {
	t := &idleTracker{timeout: timeout, cancel: cancel}
	log.Printf("[godot-mcp-server] Idle shutdown: %s (after last disconnect)", timeout)
	return t
}

func (t *idleTracker) fire() {
	log.Printf("[godot-mcp-server] Idle timeout — shutting down")
	t.cancel()
}

// godotConnected increments the editor count and cancels any pending idle timer.
func (t *idleTracker) godotConnected() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.godotCount++
	if t.timer != nil {
		t.timer.Stop()
		t.timer = nil
	}
}

// godotDisconnected decrements the editor count. If no editors remain, starts
// the idle timer (MCP requests will reset it if they arrive).
func (t *idleTracker) godotDisconnected() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.godotCount--
	if t.godotCount <= 0 {
		t.godotCount = 0
		t.startTimerLocked()
	}
}

// requestActivity resets the idle timer. Called on every MCP HTTP request.
func (t *idleTracker) requestActivity() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.hadActivity = true
	// Don't reset if Godot editors are connected — no need to track idle.
	if t.godotCount > 0 {
		return
	}
	t.startTimerLocked()
}

func (t *idleTracker) startTimerLocked() {
	// Don't start idle timer if we haven't had any connections yet,
	// or if there are active HTTP sessions (SSE streams).
	if !t.hadActivity || t.httpCount > 0 {
		if t.timer != nil {
			t.timer.Stop()
			t.timer = nil
		}
		return
	}
	if t.timer != nil {
		t.timer.Stop()
	}
	t.timer = time.AfterFunc(t.timeout, t.fire)
}

// wrapHandler returns middleware that resets the idle timer on each HTTP request.
// SSE streams (GET with Accept: text/event-stream) are tracked as active sessions
// that suppress the idle timer for their duration.
func (t *idleTracker) wrapHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		isSSE := r.Method == "GET" && r.Header.Get("Accept") == "text/event-stream"
		if isSSE {
			t.mu.Lock()
			t.httpCount++
			t.hadActivity = true
			if t.timer != nil {
				t.timer.Stop()
				t.timer = nil
			}
			t.mu.Unlock()
		} else {
			t.requestActivity()
		}

		next.ServeHTTP(w, r)

		if isSSE {
			t.mu.Lock()
			t.httpCount--
			if t.httpCount <= 0 {
				t.httpCount = 0
				if t.godotCount <= 0 {
					t.startTimerLocked()
				}
			}
			t.mu.Unlock()
		}
	})
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

	idle := newIdleTracker(idleTimeout, cancel)

	handler := mcp.NewStreamableHTTPHandler(
		func(_ *http.Request) *mcp.Server { return srv },
		&mcp.StreamableHTTPOptions{},
	)

	httpSrv := &http.Server{
		Addr:    ":" + strconv.Itoa(httpPort),
		Handler: idle.wrapHandler(handler),
	}

	br.OnConnectionChange(func(connected bool, instanceID string, info *bridge.GodotInfo) {
		if connected {
			idle.godotConnected()
			log.Printf("[godot-mcp-server] Godot %q connected", instanceID)
		} else {
			log.Printf("[godot-mcp-server] Godot %q disconnected", instanceID)
			idle.godotDisconnected()
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

// lockPath returns a consistent path for the daemon lockfile.
func lockPath() string {
	dir := os.TempDir()
	return dir + "/godot-mcp-server.lock"
}

// acquireLock takes an exclusive flock on the lockfile. Returns the file
// (caller must defer releaseLock) or an error if another daemon holds it.
func acquireLock() (*os.File, error) {
	f, err := os.OpenFile(lockPath(), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := flockExclusiveNB(f); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

// releaseLock releases the flock and removes the lockfile.
func releaseLock(f *os.File) {
	flockUnlock(f)
	os.Remove(f.Name())
	f.Close()
}


package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
)

const (
	DefaultPort        = 6505
	DefaultTimeout     = 30 * time.Second
	pingInterval       = 10 * time.Second
	maxPendingRequests = 100
)

var (
	nextID atomic.Int64

	// Sentinel errors — allocated once, reused on every disconnect/shutdown.
	errNotConnected    = errors.New("Godot is not connected")
	errNoRuntime       = errors.New("game is not running (no runtime connection)")
	errShuttingDown    = errors.New("server shutting down")
	errGameStopped     = errors.New("game stopped")
	errGodotDisconnect = errors.New("Godot disconnected")

	// Static ping payload — never changes, no need to marshal each time.
	pingBytes = []byte(`{"type":"ping"}`)

	// WebSocket accept options — shared across all upgrades.
	wsAcceptOpts = &websocket.AcceptOptions{
		OriginPatterns: []string{"localhost:*", "127.0.0.1:*"},
	}
)

// GodotInfo holds metadata about the connected Godot instance.
type GodotInfo struct {
	ProjectPath string
	ConnectedAt time.Time
}

// Status is the connection status snapshot.
type Status struct {
	Connected        bool       `json:"connected"`
	RuntimeConnected bool       `json:"runtime_connected"`
	ProjectPath      string     `json:"project_path,omitempty"`
	ConnectedAt      *time.Time `json:"connected_at,omitempty"`
	PendingRequests  int        `json:"pending_requests"`
	Port             int        `json:"port"`
}

type invokeResult struct {
	Data json.RawMessage
	Err  error
}

type pendingRequest struct {
	ch       chan invokeResult
	toolName string
	start    time.Time
}

type connectionCallback func(connected bool, info *GodotInfo)
type visualizerCallback func(ctx context.Context, data json.RawMessage)

// GodotBridge manages the WebSocket connection to the Godot plugin.
type GodotBridge struct {
	port    int
	timeout time.Duration

	mu         sync.Mutex
	writeMu    sync.Mutex // serializes concurrent WebSocket writes
	conn       *websocket.Conn
	info       *GodotInfo
	pending    map[string]*pendingRequest
	connCb     connectionCallback
	vizCb      visualizerCallback
	httpServer *http.Server
	cancelRead context.CancelFunc

	// Runtime (game process) connection
	runtimeConn    *websocket.Conn
	runtimeWriteMu sync.Mutex
	runtimeCancel  context.CancelFunc
	runtimePending map[string]*pendingRequest
}

// New creates a new GodotBridge.
func New(port int, timeout time.Duration) *GodotBridge {
	return &GodotBridge{
		port:           port,
		timeout:        timeout,
		pending:        make(map[string]*pendingRequest),
		runtimePending: make(map[string]*pendingRequest),
	}
}

// Start begins listening for Godot WebSocket connections.
// If the port is already in use (zombie server), it kills the old process first.
func (b *GodotBridge) Start(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		b.handleUpgrade(ctx, w, r)
	})

	addr := fmt.Sprintf(":%d", b.port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Printf("[GodotBridge] Port %d in use, killing zombie process...", b.port)
		if killErr := killProcessOnPort(b.port); killErr != nil {
			return fmt.Errorf("port %d in use and could not kill owner: %w", b.port, killErr)
		}
		time.Sleep(200 * time.Millisecond)
		ln, err = net.Listen("tcp", addr)
		if err != nil {
			return fmt.Errorf("listen on port %d after kill: %w", b.port, err)
		}
		log.Printf("[GodotBridge] Reclaimed port %d", b.port)
	}

	b.httpServer = &http.Server{Handler: mux}

	go func() {
		if err := b.httpServer.Serve(ln); err != nil && err != http.ErrServerClosed {
			log.Printf("[GodotBridge] HTTP server error: %v", err)
		}
	}()

	return nil
}

// Stop shuts down the bridge and rejects all pending requests.
func (b *GodotBridge) Stop() {
	b.mu.Lock()
	defer b.mu.Unlock()

	for id, p := range b.pending {
		p.ch <- invokeResult{Err: errShuttingDown}
		delete(b.pending, id)
	}
	for id, p := range b.runtimePending {
		p.ch <- invokeResult{Err: errShuttingDown}
		delete(b.runtimePending, id)
	}

	if b.cancelRead != nil {
		b.cancelRead()
		b.cancelRead = nil
	}
	if b.runtimeCancel != nil {
		b.runtimeCancel()
		b.runtimeCancel = nil
	}

	if b.conn != nil {
		b.conn.Close(websocket.StatusGoingAway, "server shutting down")
		b.conn = nil
	}
	if b.runtimeConn != nil {
		b.runtimeConn.Close(websocket.StatusGoingAway, "server shutting down")
		b.runtimeConn = nil
	}

	if b.httpServer != nil {
		b.httpServer.Close()
		b.httpServer = nil
	}

	log.Printf("[GodotBridge] Stopped")
}

// IsConnected returns true if Godot is connected.
func (b *GodotBridge) IsConnected() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.conn != nil
}

// IsRuntimeConnected returns true if the game runtime is connected.
func (b *GodotBridge) IsRuntimeConnected() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.runtimeConn != nil
}

// GetStatus returns a snapshot of the connection status.
func (b *GodotBridge) GetStatus() Status {
	b.mu.Lock()
	defer b.mu.Unlock()
	s := Status{
		Connected:        b.conn != nil,
		RuntimeConnected: b.runtimeConn != nil,
		PendingRequests:  len(b.pending) + len(b.runtimePending),
		Port:             b.port,
	}
	if b.info != nil {
		s.ProjectPath = b.info.ProjectPath
		t := b.info.ConnectedAt
		s.ConnectedAt = &t
	}
	return s
}

// OnConnectionChange registers a callback for connection state changes.
func (b *GodotBridge) OnConnectionChange(fn connectionCallback) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.connCb = fn
}

// OnVisualizerRequest registers a callback for when Godot sends project map data to visualize.
func (b *GodotBridge) OnVisualizerRequest(fn visualizerCallback) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.vizCb = fn
}

// SendNotification sends a one-way message to Godot (no response expected).
func (b *GodotBridge) SendNotification(msgType string, fields map[string]any) error {
	b.mu.Lock()
	conn := b.conn
	b.mu.Unlock()
	if conn == nil {
		return errNotConnected
	}
	msg := map[string]any{"type": msgType}
	for k, v := range fields {
		msg[k] = v
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	b.writeMu.Lock()
	err = conn.Write(context.Background(), websocket.MessageText, data)
	b.writeMu.Unlock()
	return err
}

// InvokeTool sends a tool invocation to Godot and waits for the result.
func (b *GodotBridge) InvokeTool(ctx context.Context, toolName string, args map[string]any) (json.RawMessage, error) {
	b.mu.Lock()
	conn, pending, wmu := b.conn, b.pending, &b.writeMu
	b.mu.Unlock()
	return b.invokeTool(ctx, toolName, args, conn, wmu, pending, errNotConnected, "")
}

// InvokeRuntimeTool sends a tool invocation to the game runtime and waits for the result.
func (b *GodotBridge) InvokeRuntimeTool(ctx context.Context, toolName string, args map[string]any) (json.RawMessage, error) {
	b.mu.Lock()
	conn, pending, wmu := b.runtimeConn, b.runtimePending, &b.runtimeWriteMu
	b.mu.Unlock()
	return b.invokeTool(ctx, toolName, args, conn, wmu, pending, errNoRuntime, "runtime ")
}

func (b *GodotBridge) invokeTool(
	ctx context.Context, toolName string, args map[string]any,
	conn *websocket.Conn, wmu *sync.Mutex,
	pending map[string]*pendingRequest, noConnErr error, label string,
) (json.RawMessage, error) {
	if conn == nil {
		return nil, noConnErr
	}

	id := strconv.FormatInt(nextID.Add(1), 10)
	ch := make(chan invokeResult, 1)

	b.mu.Lock()
	if len(pending) >= maxPendingRequests {
		b.mu.Unlock()
		return nil, fmt.Errorf("too many pending %srequests", label)
	}
	pending[id] = &pendingRequest{ch: ch, toolName: toolName, start: time.Now()}
	b.mu.Unlock()

	data, err := json.Marshal(ToolInvokeMessage{
		Type: "tool_invoke",
		ID:   id,
		Tool: toolName,
		Args: args,
	})
	if err != nil {
		b.mu.Lock()
		delete(pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("marshal invoke message: %w", err)
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, b.timeout)
	defer cancel()

	wmu.Lock()
	writeErr := conn.Write(timeoutCtx, websocket.MessageText, data)
	wmu.Unlock()
	if writeErr != nil {
		b.mu.Lock()
		delete(pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("send to %sGodot: %w", label, writeErr)
	}

	log.Printf("[GodotBridge] Invoking %stool: %s (%s)", label, toolName, id)

	select {
	case result := <-ch:
		return result.Data, result.Err
	case <-timeoutCtx.Done():
		b.mu.Lock()
		delete(pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("%stool %s timed out after %s", label, toolName, b.timeout)
	}
}

func (b *GodotBridge) handleUpgrade(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, wsAcceptOpts)
	if err != nil {
		log.Printf("[GodotBridge] WebSocket accept error: %v", err)
		return
	}

	// Increase read limit for large tool results / screenshots
	conn.SetReadLimit(10 * 1024 * 1024) // 10 MB

	// Read the first message to identify connection type (editor vs runtime).
	helloCtx, helloCancel := context.WithTimeout(ctx, 5*time.Second)
	_, data, err := conn.Read(helloCtx)
	helloCancel()
	if err != nil {
		log.Printf("[GodotBridge] No hello message: %v", err)
		conn.Close(websocket.StatusProtocolError, "expected hello message")
		return
	}

	var msg IncomingMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		conn.Close(websocket.StatusProtocolError, "invalid hello message")
		return
	}

	switch msg.Type {
	case "godot_ready":
		b.acceptEditor(ctx, conn, msg)
	case "runtime_ready":
		b.acceptRuntime(ctx, conn)
	default:
		log.Printf("[GodotBridge] Unknown hello type: %s", msg.Type)
		conn.Close(websocket.StatusProtocolError, "unknown hello type")
	}
}

func (b *GodotBridge) acceptEditor(ctx context.Context, conn *websocket.Conn, hello IncomingMessage) {
	b.mu.Lock()
	if b.conn != nil {
		b.mu.Unlock()
		log.Printf("[GodotBridge] Rejecting editor connection - already connected")
		conn.Close(websocket.StatusCode(4000), "Another Godot editor is already connected")
		return
	}

	readCtx, cancelRead := context.WithCancel(ctx)
	b.conn = conn
	b.info = &GodotInfo{
		ConnectedAt: time.Now(),
		ProjectPath: hello.ProjectPath,
	}
	b.cancelRead = cancelRead
	b.mu.Unlock()

	log.Printf("[GodotBridge] Editor connected (project: %s)", hello.ProjectPath)
	b.notifyConnectionChange(true, nil)

	go b.pingLoop(readCtx, conn, &b.writeMu)
	b.readLoop(readCtx, conn)
	b.handleDisconnect()
}

func (b *GodotBridge) acceptRuntime(ctx context.Context, conn *websocket.Conn) {
	b.mu.Lock()
	if b.runtimeConn != nil {
		b.mu.Unlock()
		log.Printf("[GodotBridge] Rejecting runtime connection - already connected")
		conn.Close(websocket.StatusCode(4001), "Another runtime is already connected")
		return
	}

	readCtx, cancelRead := context.WithCancel(ctx)
	b.runtimeConn = conn
	b.runtimeCancel = cancelRead
	b.mu.Unlock()

	log.Printf("[GodotBridge] Runtime connected")

	go b.pingLoop(readCtx, conn, &b.runtimeWriteMu)
	b.runtimeReadLoop(readCtx, conn)
	b.handleRuntimeDisconnect()
}

func (b *GodotBridge) readLoop(ctx context.Context, conn *websocket.Conn) {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[GodotBridge] Read error: %v", err)
			}
			return
		}

		var msg IncomingMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("[GodotBridge] Failed to parse message: %v", err)
			continue
		}

		b.handleMessage(ctx, msg)
	}
}

func (b *GodotBridge) handleMessage(ctx context.Context, msg IncomingMessage) {
	switch msg.Type {
	case "tool_result":
		b.handleToolResult(msg)
	case "pong":
		// Keepalive response - nothing to do
	case "godot_ready":
		b.mu.Lock()
		if b.info != nil {
			b.info.ProjectPath = msg.ProjectPath
			log.Printf("[GodotBridge] Godot project: %s", msg.ProjectPath)
		}
		b.mu.Unlock()
	case "open_visualizer":
		b.mu.Lock()
		cb := b.vizCb
		b.mu.Unlock()
		if cb != nil {
			go cb(ctx, msg.Result) // Run in goroutine — viz.Serve() blocks; ctx cancels on disconnect
		} else {
			log.Printf("[GodotBridge] Received open_visualizer but no handler registered")
		}
	default:
		log.Printf("[GodotBridge] Unknown message type: %s", msg.Type)
	}
}

func (b *GodotBridge) handleToolResult(msg IncomingMessage) {
	b.resolveResult(b.pending, msg, "")
}

func (b *GodotBridge) runtimeReadLoop(ctx context.Context, conn *websocket.Conn) {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[GodotBridge] Runtime read error: %v", err)
			}
			return
		}

		var msg IncomingMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("[GodotBridge] Failed to parse runtime message: %v", err)
			continue
		}

		switch msg.Type {
		case "tool_result":
			b.handleRuntimeToolResult(msg)
		case "pong":
			// keepalive
		default:
			log.Printf("[GodotBridge] Unknown runtime message type: %s", msg.Type)
		}
	}
}

func (b *GodotBridge) handleRuntimeToolResult(msg IncomingMessage) {
	b.resolveResult(b.runtimePending, msg, "runtime ")
}

func (b *GodotBridge) resolveResult(pending map[string]*pendingRequest, msg IncomingMessage, label string) {
	b.mu.Lock()
	p, ok := pending[msg.ID]
	if ok {
		delete(pending, msg.ID)
	}
	b.mu.Unlock()

	if !ok {
		log.Printf("[GodotBridge] Received %sresult for unknown request: %s", label, msg.ID)
		return
	}

	duration := time.Since(p.start)
	log.Printf("[GodotBridge] %sTool %s completed in %dms", label, p.toolName, duration.Milliseconds())

	if msg.Success != nil && *msg.Success {
		p.ch <- invokeResult{Data: msg.Result}
	} else {
		errMsg := msg.Error
		if errMsg == "" {
			errMsg = label + "tool execution failed"
		}
		p.ch <- invokeResult{Err: errors.New(errMsg)}
	}
}

func (b *GodotBridge) handleRuntimeDisconnect() {
	b.mu.Lock()
	for id, p := range b.runtimePending {
		p.ch <- invokeResult{Err: errGameStopped}
		delete(b.runtimePending, id)
	}
	if b.runtimeCancel != nil {
		b.runtimeCancel()
		b.runtimeCancel = nil
	}
	b.runtimeConn = nil
	b.mu.Unlock()

	log.Printf("[GodotBridge] Runtime disconnected")
}

func (b *GodotBridge) handleDisconnect() {
	b.mu.Lock()
	info := b.info

	// Reject all pending requests
	for id, p := range b.pending {
		p.ch <- invokeResult{Err: errGodotDisconnect}
		delete(b.pending, id)
	}

	if b.cancelRead != nil {
		b.cancelRead()
		b.cancelRead = nil
	}

	b.conn = nil
	b.info = nil
	b.mu.Unlock()

	log.Printf("[GodotBridge] Godot disconnected")
	b.notifyConnectionChange(false, info)
}

func (b *GodotBridge) pingLoop(ctx context.Context, conn *websocket.Conn, wmu *sync.Mutex) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			wmu.Lock()
			err := conn.Write(ctx, websocket.MessageText, pingBytes)
			wmu.Unlock()
			if err != nil {
				return
			}
		}
	}
}

func (b *GodotBridge) notifyConnectionChange(connected bool, info *GodotInfo) {
	b.mu.Lock()
	cb := b.connCb
	b.mu.Unlock()

	if cb == nil {
		return
	}

	func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[GodotBridge] Connection callback panic: %v", r)
			}
		}()
		cb(connected, info)
	}()
}

// killProcessOnPort finds and kills the process occupying the given TCP port.
func killProcessOnPort(port int) error {
	portStr := strconv.Itoa(port)
	switch runtime.GOOS {
	case "linux":
		out, err := exec.Command("fuser", "-k", portStr+"/tcp").CombinedOutput()
		if err != nil {
			return fmt.Errorf("fuser -k %s/tcp: %s (%w)", portStr, out, err)
		}
		return nil
	case "darwin":
		// macOS has no fuser — use lsof to find PID, then kill
		out, err := exec.Command("lsof", "-ti", ":"+portStr).Output()
		if err != nil {
			return fmt.Errorf("lsof -ti :%s: %w", portStr, err)
		}
		pid := strings.TrimSpace(string(out))
		if pid == "" {
			return fmt.Errorf("no process found on port %s", portStr)
		}
		if err := exec.Command("kill", pid).Run(); err != nil {
			return fmt.Errorf("kill %s: %w", pid, err)
		}
		return nil
	case "windows":
		// Find PID via netstat, then taskkill
		out, err := exec.Command("cmd", "/c",
			fmt.Sprintf("for /f \"tokens=5\" %%a in ('netstat -aon ^| findstr :%s') do taskkill /F /PID %%a", portStr),
		).CombinedOutput()
		if err != nil {
			return fmt.Errorf("taskkill for port %s: %s (%w)", portStr, out, err)
		}
		return nil
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
}

package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strconv"
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

var nextID atomic.Int64

// GodotInfo holds metadata about the connected Godot instance.
type GodotInfo struct {
	ProjectPath string
	ConnectedAt time.Time
}

// Status is the connection status snapshot.
type Status struct {
	Connected       bool       `json:"connected"`
	ProjectPath     string     `json:"project_path,omitempty"`
	ConnectedAt     *time.Time `json:"connected_at,omitempty"`
	PendingRequests int        `json:"pending_requests"`
	Port            int        `json:"port"`
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
	pending  map[string]*pendingRequest
	connCb   connectionCallback
	vizCb    visualizerCallback
	httpServer *http.Server
	cancelRead context.CancelFunc
}

// New creates a new GodotBridge.
func New(port int, timeout time.Duration) *GodotBridge {
	return &GodotBridge{
		port:    port,
		timeout: timeout,
		pending: make(map[string]*pendingRequest),
	}
}

// Start begins listening for Godot WebSocket connections.
func (b *GodotBridge) Start(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		b.handleUpgrade(ctx, w, r)
	})

	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", b.port))
	if err != nil {
		return fmt.Errorf("listen on port %d: %w", b.port, err)
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
		p.ch <- invokeResult{Err: fmt.Errorf("server shutting down")}
		delete(b.pending, id)
	}

	if b.cancelRead != nil {
		b.cancelRead()
		b.cancelRead = nil
	}

	if b.conn != nil {
		b.conn.Close(websocket.StatusGoingAway, "server shutting down")
		b.conn = nil
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

// GetStatus returns a snapshot of the connection status.
func (b *GodotBridge) GetStatus() Status {
	b.mu.Lock()
	defer b.mu.Unlock()
	s := Status{
		Connected:       b.conn != nil,
		PendingRequests: len(b.pending),
		Port:            b.port,
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
		return fmt.Errorf("Godot is not connected")
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
	id := strconv.FormatInt(nextID.Add(1), 10)
	ch := make(chan invokeResult, 1)

	b.mu.Lock()
	conn := b.conn
	if conn == nil {
		b.mu.Unlock()
		return nil, fmt.Errorf("Godot is not connected")
	}
	if len(b.pending) >= maxPendingRequests {
		b.mu.Unlock()
		return nil, fmt.Errorf("too many pending requests (%d), try again later", maxPendingRequests)
	}
	b.pending[id] = &pendingRequest{ch: ch, toolName: toolName, start: time.Now()}
	b.mu.Unlock()

	msg := ToolInvokeMessage{
		Type: "tool_invoke",
		ID:   id,
		Tool: toolName,
		Args: args,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		b.mu.Lock()
		delete(b.pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("marshal invoke message: %w", err)
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, b.timeout)
	defer cancel()

	b.writeMu.Lock()
	writeErr := conn.Write(timeoutCtx, websocket.MessageText, data)
	b.writeMu.Unlock()
	if writeErr != nil {
		b.mu.Lock()
		delete(b.pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("send to Godot: %w", writeErr)
	}

	log.Printf("[GodotBridge] Invoking tool: %s (%s)", toolName, id)

	select {
	case result := <-ch:
		return result.Data, result.Err
	case <-timeoutCtx.Done():
		b.mu.Lock()
		delete(b.pending, id)
		b.mu.Unlock()
		return nil, fmt.Errorf("tool %s timed out after %s", toolName, b.timeout)
	}
}

func (b *GodotBridge) handleUpgrade(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	b.mu.Lock()
	hasConn := b.conn != nil
	b.mu.Unlock()

	// Godot's WebSocketPeer doesn't send an Origin header (it's not a browser),
	// so origin checking is not applicable here. The single-connection limit
	// already prevents hijacking — if Godot is connected, all others are rejected.
	if hasConn {
		log.Printf("[GodotBridge] Rejecting connection - Godot already connected")
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		conn.Close(websocket.StatusCode(4000), "Another Godot instance is already connected")
		return
	}

	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		log.Printf("[GodotBridge] WebSocket accept error: %v", err)
		return
	}

	// Increase read limit for large tool results
	conn.SetReadLimit(10 * 1024 * 1024) // 10 MB

	readCtx, cancelRead := context.WithCancel(ctx)

	b.mu.Lock()
	b.conn = conn
	b.info = &GodotInfo{ConnectedAt: time.Now()}
	b.cancelRead = cancelRead
	b.mu.Unlock()

	log.Printf("[GodotBridge] Godot connected")
	b.notifyConnectionChange(true)

	// Start ping goroutine
	go b.pingLoop(readCtx, conn)

	// Read loop (blocks until disconnect)
	b.readLoop(readCtx, conn)

	// Cleanup on disconnect
	b.handleDisconnect()
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
	b.mu.Lock()
	p, ok := b.pending[msg.ID]
	if ok {
		delete(b.pending, msg.ID)
	}
	b.mu.Unlock()

	if !ok {
		log.Printf("[GodotBridge] Received result for unknown request: %s", msg.ID)
		return
	}

	duration := time.Since(p.start)
	log.Printf("[GodotBridge] Tool %s completed in %dms", p.toolName, duration.Milliseconds())

	if msg.Success != nil && *msg.Success {
		p.ch <- invokeResult{Data: msg.Result}
	} else {
		errMsg := msg.Error
		if errMsg == "" {
			errMsg = "Tool execution failed"
		}
		p.ch <- invokeResult{Err: fmt.Errorf("%s", errMsg)}
	}
}

func (b *GodotBridge) handleDisconnect() {
	b.mu.Lock()
	info := b.info

	// Reject all pending requests
	for id, p := range b.pending {
		p.ch <- invokeResult{Err: fmt.Errorf("Godot disconnected")}
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

func (b *GodotBridge) pingLoop(ctx context.Context, conn *websocket.Conn) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	ping, _ := json.Marshal(PingMessage{Type: "ping"})

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			b.writeMu.Lock()
			err := conn.Write(ctx, websocket.MessageText, ping)
			b.writeMu.Unlock()
			if err != nil {
				return
			}
		}
	}
}

func (b *GodotBridge) notifyConnectionChange(connected bool, info ...*GodotInfo) {
	b.mu.Lock()
	cb := b.connCb
	b.mu.Unlock()

	if cb == nil {
		return
	}

	var gi *GodotInfo
	if len(info) > 0 {
		gi = info[0]
	}

	func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[GodotBridge] Connection callback panic: %v", r)
			}
		}()
		cb(connected, gi)
	}()
}

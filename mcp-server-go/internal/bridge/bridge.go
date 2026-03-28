package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"path/filepath"
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

// InstanceStatus is the per-instance connection snapshot.
// RuntimeStatus is the per-runtime connection snapshot.
type RuntimeStatus struct {
	PID             int `json:"pid"`
	PendingRequests int `json:"pending_requests"`
}

// InstanceStatus is the per-instance connection snapshot.
type InstanceStatus struct {
	InstanceID       string          `json:"instance_id"`
	Connected        bool            `json:"connected"`
	RuntimeConnected bool            `json:"runtime_connected"`
	Runtimes         []RuntimeStatus `json:"runtimes,omitempty"`
	ProjectPath      string          `json:"project_path,omitempty"`
	ConnectedAt      *time.Time      `json:"connected_at,omitempty"`
	PendingRequests  int             `json:"pending_requests"`
	Primary          bool            `json:"primary"`
}

// Status is the connection status snapshot.
type Status struct {
	Connected        bool             `json:"connected"`
	RuntimeConnected bool             `json:"runtime_connected"`
	Instances        []InstanceStatus `json:"instances"`
	PrimaryID        string           `json:"primary_id,omitempty"`
	Port             int              `json:"port"`
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

// runtimeConn holds per-runtime-process state.
type runtimeConn struct {
	pid     int
	conn    *websocket.Conn
	writeMu sync.Mutex
	cancel  context.CancelFunc
	pending map[string]*pendingRequest
}

// editorConn holds per-instance state for one Godot editor connection.
type editorConn struct {
	conn       *websocket.Conn
	writeMu    sync.Mutex
	info       *GodotInfo
	pending    map[string]*pendingRequest
	cancelRead context.CancelFunc

	// Runtime (game process) sub-connections, keyed by PID
	runtimes map[int]*runtimeConn
}

// Unexported aliases kept for internal use — the exported types live in iface.go.
type connectionCallback = ConnectionCallback
type visualizerCallback = VisualizerCallback

// GodotBridge manages WebSocket connections to Godot editor instances.
type GodotBridge struct {
	port    int
	timeout time.Duration

	mu         sync.Mutex
	instances  map[string]*editorConn
	primaryID  string
	connCb     connectionCallback
	vizCb      visualizerCallback
	httpServer *http.Server
}

// New creates a new GodotBridge.
func New(port int, timeout time.Duration) *GodotBridge {
	return &GodotBridge{
		port:      port,
		timeout:   timeout,
		instances: make(map[string]*editorConn),
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
		return fmt.Errorf("port %d in use: %w", b.port, err)
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

	for id, inst := range b.instances {
		for reqID, p := range inst.pending {
			p.ch <- invokeResult{Err: errShuttingDown}
			delete(inst.pending, reqID)
		}
		for _, rt := range inst.runtimes {
			for reqID, p := range rt.pending {
				p.ch <- invokeResult{Err: errShuttingDown}
				delete(rt.pending, reqID)
			}
			if rt.cancel != nil {
				rt.cancel()
			}
			if rt.conn != nil {
				rt.conn.Close(websocket.StatusGoingAway, "server shutting down")
			}
		}
		if inst.cancelRead != nil {
			inst.cancelRead()
		}
		if inst.conn != nil {
			inst.conn.Close(websocket.StatusGoingAway, "server shutting down")
		}
		delete(b.instances, id)
	}
	b.primaryID = ""

	if b.httpServer != nil {
		b.httpServer.Close()
		b.httpServer = nil
	}

	log.Printf("[GodotBridge] Stopped")
}

// IsConnected returns true if any Godot instance is connected.
func (b *GodotBridge) IsConnected() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.instances) > 0
}

// IsRuntimeConnected returns true if any instance has at least one runtime connection.
func (b *GodotBridge) IsRuntimeConnected() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, inst := range b.instances {
		if len(inst.runtimes) > 0 {
			return true
		}
	}
	return false
}

// GetStatus returns a snapshot of the connection status.
func (b *GodotBridge) GetStatus() Status {
	b.mu.Lock()
	defer b.mu.Unlock()

	s := Status{
		Connected: len(b.instances) > 0,
		PrimaryID: b.primaryID,
		Port:      b.port,
	}

	for id, inst := range b.instances {
		is := InstanceStatus{
			InstanceID:       id,
			Connected:        true,
			RuntimeConnected: len(inst.runtimes) > 0,
			PendingRequests:  len(inst.pending),
			Primary:          id == b.primaryID,
		}
		for _, rt := range inst.runtimes {
			is.Runtimes = append(is.Runtimes, RuntimeStatus{
				PID:             rt.pid,
				PendingRequests: len(rt.pending),
			})
			is.PendingRequests += len(rt.pending)
		}
		if inst.info != nil {
			is.ProjectPath = inst.info.ProjectPath
			t := inst.info.ConnectedAt
			is.ConnectedAt = &t
		}
		if is.RuntimeConnected {
			s.RuntimeConnected = true
		}
		s.Instances = append(s.Instances, is)
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

// SendNotification sends a one-way message to a Godot instance.
// If instanceID is empty, sends to the primary instance.
func (b *GodotBridge) SendNotification(msgType string, fields map[string]any, instanceID string) error {
	b.mu.Lock()
	inst, err := b.resolveInstance(instanceID)
	b.mu.Unlock()
	if err != nil {
		return err
	}

	msg := map[string]any{"type": msgType}
	for k, v := range fields {
		msg[k] = v
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	inst.writeMu.Lock()
	err = inst.conn.Write(context.Background(), websocket.MessageText, data)
	inst.writeMu.Unlock()
	return err
}

// InvokeTool sends a tool invocation to a Godot editor and waits for the result.
// If instanceID is empty, routes to the primary instance.
func (b *GodotBridge) InvokeTool(ctx context.Context, toolName string, args map[string]any, instanceID string) (json.RawMessage, error) {
	b.mu.Lock()
	inst, err := b.resolveInstance(instanceID)
	b.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return b.invokeTool(ctx, toolName, args, inst.conn, &inst.writeMu, inst.pending, errNotConnected, "")
}

// InvokeRuntimeTool sends a tool invocation to a game runtime and waits for the result.
// If instanceID is empty, routes to the primary instance. If runtimePID is 0, uses the first runtime.
func (b *GodotBridge) InvokeRuntimeTool(ctx context.Context, toolName string, args map[string]any, instanceID string, runtimePID int) (json.RawMessage, error) {
	b.mu.Lock()
	inst, err := b.resolveInstance(instanceID)
	if err != nil {
		b.mu.Unlock()
		return nil, err
	}
	rt, err := resolveRuntime(inst, runtimePID)
	b.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return b.invokeTool(ctx, toolName, args, rt.conn, &rt.writeMu, rt.pending, errNoRuntime, fmt.Sprintf("runtime[%d] ", rt.pid))
}

// resolveRuntime finds a runtime by PID or returns the first one. Caller must hold b.mu.
func resolveRuntime(inst *editorConn, pid int) (*runtimeConn, error) {
	if len(inst.runtimes) == 0 {
		return nil, errNoRuntime
	}
	if pid != 0 {
		rt, ok := inst.runtimes[pid]
		if !ok {
			pids := make([]string, 0, len(inst.runtimes))
			for p := range inst.runtimes {
				pids = append(pids, strconv.Itoa(p))
			}
			return nil, fmt.Errorf("runtime PID %d not found (available: %s)", pid, strings.Join(pids, ", "))
		}
		return rt, nil
	}
	// Return first runtime
	for _, rt := range inst.runtimes {
		return rt, nil
	}
	return nil, errNoRuntime // unreachable
}

// SetPrimary changes the primary instance.
func (b *GodotBridge) SetPrimary(instanceID string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if _, ok := b.instances[instanceID]; !ok {
		return fmt.Errorf("instance %q not found (available: %s)", instanceID, b.listInstanceIDs())
	}
	b.primaryID = instanceID
	return nil
}

// resolveInstance looks up an instance by ID, falling back to primary. Caller must hold b.mu.
func (b *GodotBridge) resolveInstance(instanceID string) (*editorConn, error) {
	if len(b.instances) == 0 {
		return nil, errNotConnected
	}
	if instanceID == "" {
		instanceID = b.primaryID
	}
	inst, ok := b.instances[instanceID]
	if !ok {
		return nil, fmt.Errorf("instance %q not found (available: %s)", instanceID, b.listInstanceIDs())
	}
	return inst, nil
}

// listInstanceIDs returns a comma-separated list. Caller must hold b.mu.
func (b *GodotBridge) listInstanceIDs() string {
	ids := make([]string, 0, len(b.instances))
	for id := range b.instances {
		ids = append(ids, id)
	}
	return strings.Join(ids, ", ")
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
		b.acceptRuntime(ctx, conn, msg)
	case "proxy_ready":
		b.acceptProxy(ctx, conn)
	default:
		log.Printf("[GodotBridge] Unknown hello type: %s", msg.Type)
		conn.Close(websocket.StatusProtocolError, "unknown hello type")
	}
}

// deriveInstanceID computes an instance ID from the hello message.
func deriveInstanceID(msg IncomingMessage) string {
	if msg.InstanceID != "" {
		return msg.InstanceID
	}
	// Fall back to last segment of project path
	if msg.ProjectPath != "" {
		return filepath.Base(msg.ProjectPath)
	}
	return "default"
}

func (b *GodotBridge) acceptEditor(ctx context.Context, conn *websocket.Conn, hello IncomingMessage) {
	instanceID := deriveInstanceID(hello)

	b.mu.Lock()
	if _, exists := b.instances[instanceID]; exists {
		b.mu.Unlock()
		log.Printf("[GodotBridge] Rejecting editor %q - already connected", instanceID)
		conn.Close(websocket.StatusCode(4000), "Instance already connected: "+instanceID)
		return
	}

	readCtx, cancelRead := context.WithCancel(ctx)
	inst := &editorConn{
		conn: conn,
		info: &GodotInfo{
			ConnectedAt: time.Now(),
			ProjectPath: hello.ProjectPath,
		},
		pending:    make(map[string]*pendingRequest),
		runtimes:   make(map[int]*runtimeConn),
		cancelRead: cancelRead,
	}
	b.instances[instanceID] = inst

	// First connection becomes primary
	if b.primaryID == "" {
		b.primaryID = instanceID
	}
	isPrimary := b.primaryID == instanceID
	b.mu.Unlock()

	primaryLabel := ""
	if isPrimary {
		primaryLabel = " [primary]"
	}
	log.Printf("[GodotBridge] Editor %q connected (project: %s)%s", instanceID, hello.ProjectPath, primaryLabel)
	b.notifyConnectionChange(true, instanceID, inst.info)

	go b.pingLoop(readCtx, conn, &inst.writeMu)
	b.readLoop(readCtx, conn, inst)
	b.handleDisconnect(instanceID)
}

func (b *GodotBridge) acceptRuntime(ctx context.Context, conn *websocket.Conn, hello IncomingMessage) {
	instanceID := deriveInstanceID(hello)
	pid := hello.PID

	b.mu.Lock()
	inst, ok := b.instances[instanceID]
	if !ok {
		b.mu.Unlock()
		log.Printf("[GodotBridge] Rejecting runtime PID %d for %q - no editor connection", pid, instanceID)
		conn.Close(websocket.StatusCode(4002), "No editor connected for instance: "+instanceID)
		return
	}
	if _, exists := inst.runtimes[pid]; exists {
		b.mu.Unlock()
		log.Printf("[GodotBridge] Rejecting runtime PID %d for %q - already connected", pid, instanceID)
		conn.Close(websocket.StatusCode(4001), fmt.Sprintf("Runtime PID %d already connected for: %s", pid, instanceID))
		return
	}

	readCtx, cancelRead := context.WithCancel(ctx)
	rt := &runtimeConn{
		pid:     pid,
		conn:    conn,
		cancel:  cancelRead,
		pending: make(map[string]*pendingRequest),
	}
	inst.runtimes[pid] = rt
	b.mu.Unlock()

	log.Printf("[GodotBridge] Runtime PID %d connected for %q (%d runtimes)", pid, instanceID, len(inst.runtimes))

	go b.pingLoop(readCtx, conn, &rt.writeMu)
	b.runtimeReadLoop(readCtx, conn, rt)
	b.handleRuntimeDisconnect(instanceID, pid)
}

func (b *GodotBridge) readLoop(ctx context.Context, conn *websocket.Conn, inst *editorConn) {
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

		b.handleMessage(ctx, msg, inst)
	}
}

func (b *GodotBridge) handleMessage(ctx context.Context, msg IncomingMessage, inst *editorConn) {
	switch msg.Type {
	case "tool_result":
		b.resolveResult(inst.pending, msg, "")
	case "pong":
		// Keepalive response - nothing to do
	case "godot_ready":
		b.mu.Lock()
		if inst.info != nil {
			inst.info.ProjectPath = msg.ProjectPath
			log.Printf("[GodotBridge] Godot project: %s", msg.ProjectPath)
		}
		b.mu.Unlock()
	case "open_visualizer":
		b.mu.Lock()
		cb := b.vizCb
		// Find the instance ID for the callback
		var instID string
		for id, i := range b.instances {
			if i == inst {
				instID = id
				break
			}
		}
		b.mu.Unlock()
		if cb != nil {
			go cb(ctx, instID, msg.Result)
		} else {
			log.Printf("[GodotBridge] Received open_visualizer but no handler registered")
		}
	default:
		log.Printf("[GodotBridge] Unknown message type: %s", msg.Type)
	}
}

func (b *GodotBridge) runtimeReadLoop(ctx context.Context, conn *websocket.Conn, rt *runtimeConn) {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[GodotBridge] Runtime[%d] read error: %v", rt.pid, err)
			}
			return
		}

		var msg IncomingMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("[GodotBridge] Failed to parse runtime[%d] message: %v", rt.pid, err)
			continue
		}

		switch msg.Type {
		case "tool_result":
			b.resolveResult(rt.pending, msg, fmt.Sprintf("runtime[%d] ", rt.pid))
		case "pong":
			// keepalive
		default:
			log.Printf("[GodotBridge] Unknown runtime[%d] message type: %s", rt.pid, msg.Type)
		}
	}
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
	} else if len(msg.Result) > 0 {
		// Error with full result dict (may contain "suggestion" etc.) —
		// pass through as raw data so the server can forward all fields.
		p.ch <- invokeResult{Data: msg.Result}
	} else {
		errMsg := msg.Error
		if errMsg == "" {
			errMsg = label + "tool execution failed"
		}
		p.ch <- invokeResult{Err: errors.New(errMsg)}
	}
}

func (b *GodotBridge) handleRuntimeDisconnect(instanceID string, pid int) {
	b.mu.Lock()
	inst, ok := b.instances[instanceID]
	if ok {
		if rt, exists := inst.runtimes[pid]; exists {
			for id, p := range rt.pending {
				p.ch <- invokeResult{Err: errGameStopped}
				delete(rt.pending, id)
			}
			if rt.cancel != nil {
				rt.cancel()
			}
			delete(inst.runtimes, pid)
		}
	}
	b.mu.Unlock()

	log.Printf("[GodotBridge] Runtime PID %d disconnected for %q", pid, instanceID)
}

func (b *GodotBridge) handleDisconnect(instanceID string) {
	b.mu.Lock()
	inst, ok := b.instances[instanceID]
	var info *GodotInfo
	if ok {
		info = inst.info
		// Reject all pending editor requests
		for id, p := range inst.pending {
			p.ch <- invokeResult{Err: errGodotDisconnect}
			delete(inst.pending, id)
		}
		// Tear down all runtime connections
		for pid, rt := range inst.runtimes {
			for id, p := range rt.pending {
				p.ch <- invokeResult{Err: errGodotDisconnect}
				delete(rt.pending, id)
			}
			if rt.cancel != nil {
				rt.cancel()
			}
			if rt.conn != nil {
				rt.conn.Close(websocket.StatusGoingAway, "editor disconnected")
			}
			delete(inst.runtimes, pid)
		}
		if inst.cancelRead != nil {
			inst.cancelRead()
		}
		delete(b.instances, instanceID)

		// Promote next instance if primary disconnected
		if b.primaryID == instanceID {
			b.primaryID = ""
			for id := range b.instances {
				b.primaryID = id
				break
			}
		}
	}
	b.mu.Unlock()

	log.Printf("[GodotBridge] Editor %q disconnected", instanceID)
	b.notifyConnectionChange(false, instanceID, info)
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

func (b *GodotBridge) notifyConnectionChange(connected bool, instanceID string, info *GodotInfo) {
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
		cb(connected, instanceID, info)
	}()
}

// acceptProxy handles a proxy client connection.
// The proxy sends tool_invoke / status_request / set_primary messages;
// the primary bridge executes them and writes back the result.
func (b *GodotBridge) acceptProxy(ctx context.Context, conn *websocket.Conn) {
	log.Printf("[GodotBridge] Proxy client connected")

	readCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	go b.pingLoop(readCtx, conn, &sync.Mutex{})

	var writeMu sync.Mutex

	for {
		_, data, err := conn.Read(readCtx)
		if err != nil {
			if readCtx.Err() == nil {
				log.Printf("[GodotBridge] Proxy read error: %v", err)
			}
			break
		}

		var msg ProxyRequest
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("[GodotBridge] Invalid proxy message: %v", err)
			continue
		}

		switch msg.Type {
		case "tool_invoke":
			go func() {
				var raw json.RawMessage
				var invokeErr error
				if msg.RuntimePID != 0 {
					raw, invokeErr = b.InvokeRuntimeTool(readCtx, msg.Tool, msg.Args, msg.Instance, msg.RuntimePID)
				} else {
					raw, invokeErr = b.InvokeTool(readCtx, msg.Tool, msg.Args, msg.Instance)
				}

				resp := ProxyResponse{Type: "tool_result", ID: msg.ID}
				if invokeErr != nil {
					resp.Error = invokeErr.Error()
				} else {
					resp.Result = raw
					t := true
					resp.Success = &t
				}

				out, _ := json.Marshal(resp)
				writeMu.Lock()
				conn.Write(readCtx, websocket.MessageText, out)
				writeMu.Unlock()
			}()

		case "status_request":
			status := b.GetStatus()
			raw, _ := json.Marshal(status)
			resp := ProxyResponse{Type: "status_response", ID: msg.ID, Result: raw}
			out, _ := json.Marshal(resp)
			writeMu.Lock()
			conn.Write(readCtx, websocket.MessageText, out)
			writeMu.Unlock()

		case "set_primary":
			var errStr string
			if err := b.SetPrimary(msg.Instance); err != nil {
				errStr = err.Error()
			}
			resp := ProxyResponse{Type: "set_primary_response", ID: msg.ID, Error: errStr}
			t := errStr == ""
			resp.Success = &t
			out, _ := json.Marshal(resp)
			writeMu.Lock()
			conn.Write(readCtx, websocket.MessageText, out)
			writeMu.Unlock()

		case "notification":
			b.SendNotification(msg.NotificationType, msg.Fields, msg.Instance)

		default:
			log.Printf("[GodotBridge] Unknown proxy message type: %s", msg.Type)
		}
	}

	log.Printf("[GodotBridge] Proxy client disconnected")
}

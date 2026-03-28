package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// ProxyBridge implements Bridge by forwarding calls over WebSocket
// to an existing GodotBridge that owns the port.
type ProxyBridge struct {
	port    int
	timeout time.Duration

	conn    *websocket.Conn
	writeMu sync.Mutex
	mu      sync.Mutex
	pending map[string]chan ProxyResponse
	cancel  context.CancelFunc
}

// NewProxy creates a ProxyBridge that will connect to the primary bridge.
func NewProxy(port int, timeout time.Duration) *ProxyBridge {
	return &ProxyBridge{
		port:    port,
		timeout: timeout,
		pending: make(map[string]chan ProxyResponse),
	}
}

// Start dials the primary bridge and begins reading responses.
func (p *ProxyBridge) Start(ctx context.Context) error {
	url := fmt.Sprintf("ws://localhost:%d/", p.port)
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		return fmt.Errorf("proxy dial %s: %w", url, err)
	}
	conn.SetReadLimit(10 * 1024 * 1024)

	// Send hello
	hello, _ := json.Marshal(map[string]string{"type": "proxy_ready"})
	if err := conn.Write(ctx, websocket.MessageText, hello); err != nil {
		conn.Close(websocket.StatusGoingAway, "hello failed")
		return fmt.Errorf("proxy hello: %w", err)
	}

	readCtx, cancel := context.WithCancel(ctx)
	p.conn = conn
	p.cancel = cancel

	go p.readLoop(readCtx)

	return nil
}

// Stop closes the proxy connection.
func (p *ProxyBridge) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cancel != nil {
		p.cancel()
	}
	if p.conn != nil {
		p.conn.Close(websocket.StatusGoingAway, "proxy shutting down")
		p.conn = nil
	}
	for id, ch := range p.pending {
		ch <- ProxyResponse{Error: "proxy shutting down"}
		delete(p.pending, id)
	}
}

// IsConnected returns true if the proxy connection to the primary is alive.
func (p *ProxyBridge) IsConnected() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.conn != nil
}

// IsRuntimeConnected queries the primary bridge for runtime status.
func (p *ProxyBridge) IsRuntimeConnected() bool {
	status := p.GetStatus()
	return status.RuntimeConnected
}

// GetStatus queries the primary bridge for its full status.
func (p *ProxyBridge) GetStatus() Status {
	resp, err := p.roundTrip("status_request", ProxyRequest{Type: "status_request"})
	if err != nil {
		return Status{Port: p.port}
	}
	var status Status
	if err := json.Unmarshal(resp.Result, &status); err != nil {
		return Status{Port: p.port}
	}
	return status
}

// InvokeTool forwards a tool invocation to the primary bridge.
func (p *ProxyBridge) InvokeTool(ctx context.Context, toolName string, args map[string]any, instanceID string) (json.RawMessage, error) {
	resp, err := p.roundTripCtx(ctx, ProxyRequest{
		Type:     "tool_invoke",
		Tool:     toolName,
		Args:     args,
		Instance: instanceID,
	})
	if err != nil {
		return nil, err
	}
	if resp.Error != "" {
		return nil, errors.New(resp.Error)
	}
	return resp.Result, nil
}

// InvokeRuntimeTool forwards a runtime tool invocation to the primary bridge.
func (p *ProxyBridge) InvokeRuntimeTool(ctx context.Context, toolName string, args map[string]any, instanceID string, runtimePID int) (json.RawMessage, error) {
	resp, err := p.roundTripCtx(ctx, ProxyRequest{
		Type:       "tool_invoke",
		Tool:       toolName,
		Args:       args,
		Instance:   instanceID,
		RuntimePID: runtimePID,
	})
	if err != nil {
		return nil, err
	}
	if resp.Error != "" {
		return nil, errors.New(resp.Error)
	}
	return resp.Result, nil
}

// OnConnectionChange is a no-op for proxies — the primary handles this.
func (p *ProxyBridge) OnConnectionChange(fn ConnectionCallback) {}

// OnVisualizerRequest is a no-op for proxies — visualizer events go to the primary.
func (p *ProxyBridge) OnVisualizerRequest(fn VisualizerCallback) {}

// SendNotification forwards a notification to the primary bridge.
func (p *ProxyBridge) SendNotification(msgType string, fields map[string]any, instanceID string) error {
	req := ProxyRequest{
		Type:             "notification",
		NotificationType: msgType,
		Fields:           fields,
		Instance:         instanceID,
	}
	data, _ := json.Marshal(req)
	p.writeMu.Lock()
	defer p.writeMu.Unlock()
	if p.conn == nil {
		return errNotConnected
	}
	return p.conn.Write(context.Background(), websocket.MessageText, data)
}

// SetPrimary forwards a set_primary request to the primary bridge.
func (p *ProxyBridge) SetPrimary(instanceID string) error {
	resp, err := p.roundTrip("set_primary_response", ProxyRequest{
		Type:     "set_primary",
		Instance: instanceID,
	})
	if err != nil {
		return err
	}
	if resp.Error != "" {
		return errors.New(resp.Error)
	}
	return nil
}

// roundTrip sends a request and waits for the matching response with the default timeout.
func (p *ProxyBridge) roundTrip(expectedType string, req ProxyRequest) (ProxyResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()
	return p.roundTripCtx(ctx, req)
}

// roundTripCtx sends a request and waits for the matching response.
func (p *ProxyBridge) roundTripCtx(ctx context.Context, req ProxyRequest) (ProxyResponse, error) {
	id := strconv.FormatInt(nextID.Add(1), 10)
	req.ID = id

	ch := make(chan ProxyResponse, 1)

	p.mu.Lock()
	if p.conn == nil {
		p.mu.Unlock()
		return ProxyResponse{}, errNotConnected
	}
	p.pending[id] = ch
	p.mu.Unlock()

	data, _ := json.Marshal(req)

	p.writeMu.Lock()
	writeErr := p.conn.Write(ctx, websocket.MessageText, data)
	p.writeMu.Unlock()
	if writeErr != nil {
		p.mu.Lock()
		delete(p.pending, id)
		p.mu.Unlock()
		return ProxyResponse{}, fmt.Errorf("proxy write: %w", writeErr)
	}

	select {
	case resp := <-ch:
		return resp, nil
	case <-ctx.Done():
		p.mu.Lock()
		delete(p.pending, id)
		p.mu.Unlock()
		return ProxyResponse{}, fmt.Errorf("proxy request timed out")
	}
}

// readLoop reads responses from the primary bridge and dispatches them.
func (p *ProxyBridge) readLoop(ctx context.Context) {
	defer func() {
		p.mu.Lock()
		p.conn = nil
		for id, ch := range p.pending {
			ch <- ProxyResponse{Error: "proxy disconnected"}
			delete(p.pending, id)
		}
		p.mu.Unlock()
		log.Printf("[ProxyBridge] Disconnected from primary")
	}()

	for {
		_, data, err := p.conn.Read(ctx)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[ProxyBridge] Read error: %v", err)
			}
			return
		}

		var resp ProxyResponse
		if err := json.Unmarshal(data, &resp); err != nil {
			log.Printf("[ProxyBridge] Invalid response: %v", err)
			continue
		}

		// Dispatch pings
		if resp.Type == "ping" {
			p.writeMu.Lock()
			p.conn.Write(ctx, websocket.MessageText, []byte(`{"type":"pong"}`))
			p.writeMu.Unlock()
			continue
		}

		p.mu.Lock()
		ch, ok := p.pending[resp.ID]
		if ok {
			delete(p.pending, resp.ID)
		}
		p.mu.Unlock()

		if ok {
			ch <- resp
		}
	}
}

// Compile-time interface check.
var _ Bridge = (*ProxyBridge)(nil)

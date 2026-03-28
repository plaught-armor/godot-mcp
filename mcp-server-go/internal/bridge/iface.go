package bridge

import (
	"context"
	"encoding/json"
)

// ConnectionCallback is called when a Godot instance connects or disconnects.
type ConnectionCallback func(connected bool, instanceID string, info *GodotInfo)

// VisualizerCallback is called when Godot sends project map data to visualize.
type VisualizerCallback func(ctx context.Context, instanceID string, data json.RawMessage)

// Compile-time interface check.
var _ Bridge = (*GodotBridge)(nil)

// Bridge is the interface consumed by the MCP server and visualizer.
// GodotBridge implements it directly; ProxyBridge forwards calls to
// an existing GodotBridge over WebSocket.
type Bridge interface {
	Start(ctx context.Context) error
	Stop()
	IsConnected() bool
	IsRuntimeConnected() bool
	GetStatus() Status
	InvokeTool(ctx context.Context, toolName string, args map[string]any, instanceID string) (json.RawMessage, error)
	InvokeRuntimeTool(ctx context.Context, toolName string, args map[string]any, instanceID string, runtimePID int) (json.RawMessage, error)
	OnConnectionChange(fn ConnectionCallback)
	OnVisualizerRequest(fn VisualizerCallback)
	SendNotification(msgType string, fields map[string]any, instanceID string) error
	SetPrimary(instanceID string) error
}

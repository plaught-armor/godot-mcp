package bridge

import "encoding/json"

// IncomingMessage is the envelope for all messages from Godot.
type IncomingMessage struct {
	Type        string          `json:"type"`
	ID          string          `json:"id,omitempty"`
	Result      json.RawMessage `json:"result,omitempty"`
	ProjectPath string          `json:"project_path,omitempty"`
	InstanceID  string          `json:"instance_id,omitempty"`
	PID         int             `json:"pid,omitempty"`
}

// ToolInvokeMessage is sent to Godot to execute a tool.
// Type is "tool_invoke" for editor tools, "runtime_tool_invoke" for runtime tools.
type ToolInvokeMessage struct {
	Type string         `json:"type"`
	ID   string         `json:"id"`
	Tool string         `json:"tool"`
	Args map[string]any `json:"args"`
}

// ProxyRequest is sent from a ProxyBridge client to the primary GodotBridge.
type ProxyRequest struct {
	Type             string         `json:"type"`
	ID               string         `json:"id,omitempty"`
	Tool             string         `json:"tool,omitempty"`
	Args             map[string]any `json:"args,omitempty"`
	Instance         string         `json:"instance,omitempty"`
	RuntimePID       int            `json:"runtime_pid,omitempty"`
	NotificationType string         `json:"notification_type,omitempty"`
	Fields           map[string]any `json:"fields,omitempty"`
}

// ProxyResponse is sent from the primary GodotBridge back to a proxy client.
type ProxyResponse struct {
	Type   string          `json:"type"`
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  string          `json:"err,omitempty"`
}
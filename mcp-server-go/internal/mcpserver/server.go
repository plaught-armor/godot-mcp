package mcpserver

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/bridge"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/tools"
)

const (
	serverName    = "godot-mcp-server"
	serverVersion = "0.6.1"
)

// New creates and configures the MCP server with all tools registered.
func New(b *bridge.GodotBridge) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    serverName,
		Version: serverVersion,
	}, nil)

	// Register dynamic status tool
	server.AddTool(
		&mcp.Tool{
			Name:        "get_godot_status",
			Description: "Check if Godot editor is connected to the MCP server. Use this before attempting Godot operations to see if you'll get real or mock data.",
			InputSchema: emptyObjectSchema(),
		},
		statusHandler(b),
	)

	// Register all tools with a generic handler that routes to Godot or returns mocks
	for i := range tools.AllTools {
		td := &tools.AllTools[i]
		server.AddTool(
			&mcp.Tool{
				Name:        td.Name,
				Description: td.Description,
				InputSchema: td.InputSchema,
			},
			toolHandler(b, td),
		)
	}

	return server
}

type statusResponse struct {
	Connected        bool   `json:"connected"`
	RuntimeConnected bool   `json:"runtime_connected"`
	ServerVersion    string `json:"server_version"`
	WebSocketPort    int    `json:"websocket_port"`
	Mode             string `json:"mode"`
	ProjectPath      string `json:"project_path"`
	ConnectedAt      string `json:"connected_at,omitempty"`
	PendingRequests  int    `json:"pending_requests"`
	Message          string `json:"message"`
}

func statusHandler(b *bridge.GodotBridge) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		status := b.GetStatus()
		mode := "mock"
		msg := "Godot is not connected. Tools will return mock data. Open a Godot project with the MCP plugin enabled to connect."
		if status.Connected {
			mode = "live"
			msg = "Godot is connected"
			if status.ProjectPath != "" {
				msg += fmt.Sprintf(" (%s)", status.ProjectPath)
			}
			msg += ". Tools will execute in the Godot editor."
		}

		result := statusResponse{
			Connected:        status.Connected,
			RuntimeConnected: status.RuntimeConnected,
			ServerVersion:    serverVersion,
			WebSocketPort:    status.Port,
			Mode:             mode,
			ProjectPath:      status.ProjectPath,
			PendingRequests:  status.PendingRequests,
			Message:          msg,
		}
		if status.ConnectedAt != nil {
			result.ConnectedAt = status.ConnectedAt.Format("2006-01-02T15:04:05.000Z")
		}

		return textResult(result)
	}
}

func toolHandler(b *bridge.GodotBridge, td *tools.ToolDef) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args map[string]any
		if req.Params.Arguments != nil {
			if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
				return errorResult(td.Name, nil, fmt.Errorf("invalid arguments: %w", err), "parse")
			}
		} else {
			args = make(map[string]any)
		}

		if td.Runtime {
			return runtimeToolHandler(b, td, ctx, args)
		}

		// Check connection before invoking — only use mocks when Godot
		// was never connected, not when it crashes mid-invocation.
		wasConnected := b.IsConnected()
		raw, err := b.InvokeTool(ctx, td.Name, args)
		if err != nil {
			if !wasConnected && !b.IsConnected() {
				// Godot was not connected before the call — fall back to mock
				return textResult(td.MockFn(args))
			}
			return errorResult(td.Name, args, err, "live")
		}

		// raw is already valid JSON from Godot — pass through without re-marshaling
		return rawTextResult(raw), nil
	}
}

func runtimeToolHandler(b *bridge.GodotBridge, td *tools.ToolDef, ctx context.Context, args map[string]any) (*mcp.CallToolResult, error) {
	if !b.IsRuntimeConnected() {
		return errorResult(td.Name, args,
			fmt.Errorf("game is not running — use play_project first"), "runtime")
	}

	raw, err := b.InvokeRuntimeTool(ctx, td.Name, args)
	if err != nil {
		return errorResult(td.Name, args, err, "runtime")
	}

	// Special case: capture_screenshot returns image data
	if td.Name == "capture_screenshot" {
		return screenshotResult(raw)
	}

	return rawTextResult(raw), nil
}

func screenshotResult(raw json.RawMessage) (*mcp.CallToolResult, error) {
	var img struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
		Image string `json:"image_base64"`
		Width int    `json:"width"`
		Height int   `json:"height"`
	}
	if err := json.Unmarshal(raw, &img); err != nil {
		return rawTextResult(raw), nil // fallback to text
	}
	if !img.OK {
		return rawTextResult(raw), nil
	}
	// Decode base64 string from GDScript into raw bytes.
	// Go's json.Marshal will re-encode []byte as base64 for the MCP wire format.
	pngData, err := base64.StdEncoding.DecodeString(img.Image)
	if err != nil {
		return rawTextResult(raw), nil
	}
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: fmt.Sprintf("Screenshot captured: %dx%d", img.Width, img.Height)},
			&mcp.ImageContent{
				MIMEType: "image/png",
				Data:     pngData,
			},
		},
	}, nil
}

func textResult(v any) (*mcp.CallToolResult, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return nil, fmt.Errorf("marshal result: %w", err)
	}
	return rawTextResult(data), nil
}

func rawTextResult(data []byte) *mcp.CallToolResult {
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(data)},
		},
	}
}

func errorResult(toolName string, args map[string]any, err error, mode string) (*mcp.CallToolResult, error) {
	data, _ := json.Marshal(map[string]any{
		"error": err.Error(),
		"tool":  toolName,
		"args":  args,
		"mode":  mode,
		"hint":  "The tool call was sent to Godot but failed. Check Godot editor for details.",
	})
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(data)},
		},
		IsError: true,
	}, nil
}

func emptyObjectSchema() *tools.Schema {
	return &tools.Schema{
		Type:       "object",
		Properties: map[string]*tools.Schema{},
	}
}

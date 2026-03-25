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

// New creates and configures the MCP server.
// If lazy is true, only core tools are registered initially; other categories
// are activated on demand via get_godot_status (for clients that support listChanged).
// If lazy is false, all tools are registered upfront (for Claude Desktop).
func New(b *bridge.GodotBridge, lazy bool) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    serverName,
		Version: serverVersion,
	}, nil)

	if lazy {
		return newLazy(server, b)
	}
	return newEager(server, b)
}

func newEager(server *mcp.Server, b *bridge.GodotBridge) *mcp.Server {
	server.AddTool(
		&mcp.Tool{
			Name:        "get_godot_status",
			Description: "Check Godot connection status.",
			InputSchema: &tools.Schema{Type: "object"},
		},
		eagerStatusHandler(b),
	)

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

func newLazy(server *mcp.Server, b *bridge.GodotBridge) *mcp.Server {
	tsm := newToolSetManager(server, b)

	server.AddTool(
		&mcp.Tool{
			Name:        "get_godot_status",
			Description: "Check Godot connection. Enable/disable tool categories: scene, script, file, project, git, runtime, asset.",
			InputSchema: &tools.Schema{
				Type: "object",
				Properties: map[string]*tools.Schema{
					"enable":  {Type: "array", Description: "Categories to enable", Items: &tools.Schema{Type: "string"}},
					"disable": {Type: "array", Description: "Categories to disable", Items: &tools.Schema{Type: "string"}},
				},
			},
		},
		lazyStatusHandler(b, tsm),
	)

	// Register core tools only
	for _, td := range tools.ByCategory("core") {
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

func eagerStatusHandler(b *bridge.GodotBridge) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		status := b.GetStatus()
		mode := "mock"
		if status.Connected {
			mode = "live"
		}
		return textResult(map[string]any{
			"connected":         status.Connected,
			"runtime_connected": status.RuntimeConnected,
			"mode":              mode,
			"project_path":      status.ProjectPath,
		})
	}
}

func lazyStatusHandler(b *bridge.GodotBridge, tsm *ToolSetManager) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args struct {
			Enable  []string `json:"enable"`
			Disable []string `json:"disable"`
		}
		if req.Params.Arguments != nil {
			json.Unmarshal(req.Params.Arguments, &args)
		}
		if len(args.Disable) > 0 {
			tsm.DisableCategories(args.Disable...)
		}
		if len(args.Enable) > 0 {
			tsm.EnableCategories(args.Enable...)
		}

		status := b.GetStatus()
		mode := "mock"
		if status.Connected {
			mode = "live"
		}
		return textResult(map[string]any{
			"connected":           status.Connected,
			"runtime_connected":   status.RuntimeConnected,
			"mode":                mode,
			"project_path":        status.ProjectPath,
			"active_categories":   tsm.ActiveCategories(),
			"available_categories": tools.Categories,
		})
	}
}

func toolHandler(b *bridge.GodotBridge, td *tools.ToolDef) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args map[string]any
		if req.Params.Arguments != nil {
			if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
				return errorResult(fmt.Errorf("invalid arguments: %w", err))
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
			return errorResult(err)
		}

		// raw is already valid JSON from Godot — pass through without re-marshaling
		return rawTextResult(raw), nil
	}
}

func runtimeToolHandler(b *bridge.GodotBridge, td *tools.ToolDef, ctx context.Context, args map[string]any) (*mcp.CallToolResult, error) {
	if !b.IsRuntimeConnected() {
		return errorResult(fmt.Errorf("game is not running — use play_project first"))
	}

	raw, err := b.InvokeRuntimeTool(ctx, td.Name, args)
	if err != nil {
		return errorResult(err)
	}

	// Special case: capture_screenshot returns image data
	if td.Name == "capture_screenshot" {
		return screenshotResult(raw)
	}

	return rawTextResult(raw), nil
}

func screenshotResult(raw json.RawMessage) (*mcp.CallToolResult, error) {
	var img struct {
		Error string `json:"error"`
		Image string `json:"image_base64"`
		Width int    `json:"width"`
		Height int   `json:"height"`
	}
	if err := json.Unmarshal(raw, &img); err != nil {
		return rawTextResult(raw), nil // fallback to text
	}
	if img.Error != "" {
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

func errorResult(err error) (*mcp.CallToolResult, error) {
	data, _ := json.Marshal(map[string]any{
		"error": err.Error(),
	})
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(data)},
		},
		IsError: true,
	}, nil
}

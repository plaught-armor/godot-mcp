package mcpserver

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/bridge"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/docs"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/tools"
)

const (
	serverName    = "godot-mcp-server"
	serverVersion = "0.12.0-rc2"
)

// New creates and configures the MCP server.
// If lazy is true, only core tools are registered initially; other categories
// are activated on demand via get_godot_status (for clients that support listChanged).
// If lazy is false, all tools are registered upfront (for Claude Desktop).
func New(b bridge.Bridge, lazy bool) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    serverName,
		Version: serverVersion,
	}, nil)

	if lazy {
		return newLazy(server, b)
	}
	return newEager(server, b)
}

func newEager(server *mcp.Server, b bridge.Bridge) *mcp.Server {
	server.AddTool(
		&mcp.Tool{
			Name:        "get_godot_status",
			Description: "Check Godot connection status. Pass set_primary to change primary instance.",
			InputSchema: &tools.Schema{
				Type: "object",
				Properties: map[string]*tools.Schema{
					"set_primary": {Type: "string"},
				},
			},
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

func newLazy(server *mcp.Server, b bridge.Bridge) *mcp.Server {
	tsm := newToolSetManager(server, b)

	server.AddTool(
		&mcp.Tool{
			Name:        "get_godot_status",
			Description: "Check Godot connection. Enable/disable tool categories: scene, script, file, project, git, runtime, asset. Pass instance/set_primary for multi-instance.",
			InputSchema: &tools.Schema{
				Type: "object",
				Properties: map[string]*tools.Schema{
					"enable":      {Type: "array", Items: &tools.Schema{Type: "string"}},
					"disable":     {Type: "array", Items: &tools.Schema{Type: "string"}},
					"set_primary": {Type: "string"},
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

func eagerStatusHandler(b bridge.Bridge) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args struct {
			SetPrimary string `json:"set_primary"`
		}
		if req.Params.Arguments != nil {
			json.Unmarshal(req.Params.Arguments, &args)
		}
		if args.SetPrimary != "" {
			if err := b.SetPrimary(args.SetPrimary); err != nil {
				return errorResult(err)
			}
		}

		status := b.GetStatus()
		mode := "mock"
		if status.Connected {
			mode = "live"
		}
		result := map[string]any{
			"connected":         status.Connected,
			"runtime_connected": status.RuntimeConnected,
			"mode":              mode,
		}
		if len(status.Instances) > 0 {
			result["instances"] = status.Instances
			result["primary"] = status.PrimaryID
		}
		return textResult(result)
	}
}

func lazyStatusHandler(b bridge.Bridge, tsm *ToolSetManager) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args struct {
			Enable     []string `json:"enable"`
			Disable    []string `json:"disable"`
			SetPrimary string   `json:"set_primary"`
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
		if args.SetPrimary != "" {
			if err := b.SetPrimary(args.SetPrimary); err != nil {
				return errorResult(err)
			}
		}

		status := b.GetStatus()
		mode := "mock"
		if status.Connected {
			mode = "live"
		}
		result := map[string]any{
			"connected":            status.Connected,
			"runtime_connected":    status.RuntimeConnected,
			"mode":                 mode,
			"active_categories":    tsm.ActiveCategories(),
			"available_categories": tools.Categories,
		}
		if len(status.Instances) > 0 {
			result["instances"] = status.Instances
			result["primary"] = status.PrimaryID
		}
		return textResult(result)
	}
}

// extractInstance removes and returns the "instance" key from args.
func extractInstance(args map[string]any) string {
	v, ok := args["instance"]
	if !ok {
		return ""
	}
	delete(args, "instance")
	s, _ := v.(string)
	return s
}

// extractRuntime removes and returns the "runtime" key from args as a PID int.
func extractRuntime(args map[string]any) int {
	v, ok := args["runtime"]
	if !ok {
		return 0
	}
	delete(args, "runtime")
	// JSON numbers come as float64
	f, _ := v.(float64)
	return int(f)
}

func toolHandler(b bridge.Bridge, td *tools.ToolDef) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args map[string]any
		if req.Params.Arguments != nil {
			if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
				return errorResult(fmt.Errorf("invalid arguments: %w", err))
			}
		} else {
			args = make(map[string]any)
		}

		instanceID := extractInstance(args)
		runtimePID := extractRuntime(args)

		if td.Runtime {
			return runtimeToolHandler(b, td, ctx, args, instanceID, runtimePID)
		}

		// Docs tool runs locally in Go — no Godot connection needed
		if td.Name == "docs" {
			return docsHandler(args)
		}

		// Check connection before invoking — only use mocks when Godot
		// was never connected, not when it crashes mid-invocation.
		wasConnected := b.IsConnected()
		raw, err := b.InvokeTool(ctx, td.Name, args, instanceID)
		if err != nil {
			if !wasConnected && !b.IsConnected() {
				// Godot was not connected before the call — fall back to mock
				return textResult(td.MockFn(args))
			}
			return errorResultWithSuggestion(err, "Use get_godot_status to check connection")
		}

		// raw is already valid JSON from Godot — pass through.
		// Check if the response contains "err" key and set IsError.
		result := rawTextResult(raw)
		if isErrorJSON(raw) {
			result.IsError = true
		}
		return result, nil
	}
}

func runtimeToolHandler(b bridge.Bridge, td *tools.ToolDef, ctx context.Context, args map[string]any, instanceID string, runtimePID int) (*mcp.CallToolResult, error) {
	if !b.IsRuntimeConnected() {
		return errorResultWithSuggestion(
			fmt.Errorf("game is not running"),
			"Use proj(action:play) to start the game first",
		)
	}

	raw, err := b.InvokeRuntimeTool(ctx, td.Name, args, instanceID, runtimePID)
	if err != nil {
		return errorResult(err)
	}

	// Runtime actions that return image data (screenshot, camera capture)
	if hasImageJSON(raw) {
		return screenshotResult(raw)
	}

	result := rawTextResult(raw)
	if isErrorJSON(raw) {
		result.IsError = true
	}
	return result, nil
}

func screenshotResult(raw json.RawMessage) (*mcp.CallToolResult, error) {
	var img struct {
		Error string `json:"err"`
		Image string `json:"img"`
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
		"err": err.Error(),
	})
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(data)},
		},
		IsError: true,
	}, nil
}

func errorResultWithSuggestion(err error, suggestion string) (*mcp.CallToolResult, error) {
	data, _ := json.Marshal(map[string]any{
		"err": err.Error(),
		"sug": suggestion,
	})
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(data)},
		},
		IsError: true,
	}, nil
}

func hasImageJSON(data json.RawMessage) bool {
	var probe struct {
		Image *string `json:"img"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return false
	}
	return probe.Image != nil
}

func isErrorJSON(data json.RawMessage) bool {
	var probe struct {
		Error *string `json:"err"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return false
	}
	return probe.Error != nil
}

func docsHandler(args map[string]any) (*mcp.CallToolResult, error) {
	// Flatten properties
	if props, ok := args["properties"].(map[string]any); ok {
		for k, v := range props {
			if _, exists := args[k]; !exists {
				args[k] = v
			}
		}
	}

	action, _ := args["action"].(string)
	switch action {
	case "class":
		name, _ := args["name"].(string)
		if name == "" {
			return errorResult(fmt.Errorf("missing class name"))
		}
		c := docs.LookupClass(name)
		if c == nil {
			matches := docs.SearchClasses(name, 5)
			if len(matches) == 0 {
				return errorResult(fmt.Errorf("class not found: %s", name))
			}
			raw, _ := json.Marshal(matches)
			return errorResultWithSuggestion(fmt.Errorf("class not found: %s", name), string(raw))
		}
		return textResult(classToMap(c))

	case "search":
		query, _ := args["query"].(string)
		if query == "" {
			return errorResult(fmt.Errorf("missing query"))
		}
		limit := 20
		if l, ok := args["limit"].(float64); ok {
			limit = int(l)
		}
		return textResult(map[string]any{"classes": docs.SearchClasses(query, limit)})

	case "method":
		query, _ := args["query"].(string)
		if query == "" {
			return errorResult(fmt.Errorf("missing query"))
		}
		limit := 20
		if l, ok := args["limit"].(float64); ok {
			limit = int(l)
		}
		return textResult(map[string]any{"methods": docs.SearchMethods(query, limit)})
	}

	return errorResult(fmt.Errorf("unknown docs action: %s", action))
}

func classToMap(c *docs.GodotClass) map[string]any {
	result := map[string]any{
		"name":    c.Name,
		"brief":   c.BriefDescription,
		"desc":    c.Description,
	}
	if c.Inherits != "" {
		result["inherits"] = c.Inherits
	}
	if len(c.Methods) > 0 {
		methods := make([]map[string]any, 0, len(c.Methods))
		for _, m := range c.Methods {
			md := map[string]any{"name": m.Name, "return": m.Return.Type}
			if len(m.Arguments) > 0 {
				argStrs := make([]string, len(m.Arguments))
				for i, a := range m.Arguments {
					s := a.Name + ": " + a.Type
					if a.Default != "" {
						s += " = " + a.Default
					}
					argStrs[i] = s
				}
				md["args"] = argStrs
			}
			if m.Description != "" {
				md["desc"] = m.Description
			}
			methods = append(methods, md)
		}
		result["methods"] = methods
	}
	if len(c.Members) > 0 {
		members := make([]map[string]string, 0, len(c.Members))
		for _, m := range c.Members {
			entry := map[string]string{"name": m.Name, "type": m.Type}
			if m.Default != "" {
				entry["default"] = m.Default
			}
			if m.Description != "" {
				entry["desc"] = m.Description
			}
			members = append(members, entry)
		}
		result["members"] = members
	}
	if len(c.Signals) > 0 {
		signals := make([]map[string]any, 0, len(c.Signals))
		for _, s := range c.Signals {
			sig := map[string]any{"name": s.Name}
			if len(s.Arguments) > 0 {
				argStrs := make([]string, len(s.Arguments))
				for i, a := range s.Arguments {
					argStrs[i] = a.Name + ": " + a.Type
				}
				sig["args"] = argStrs
			}
			signals = append(signals, sig)
		}
		result["signals"] = signals
	}
	if len(c.Constants) > 0 {
		consts := make([]map[string]string, 0, len(c.Constants))
		for _, k := range c.Constants {
			entry := map[string]string{"name": k.Name, "value": k.Value}
			if k.Enum != "" {
				entry["enum"] = k.Enum
			}
			consts = append(consts, entry)
		}
		result["consts"] = consts
	}
	return result
}

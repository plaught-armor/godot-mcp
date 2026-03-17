package tools

var runtimeTools = []ToolDef{
	{
		Name:        "capture_screenshot",
		Description: "Capture a screenshot of the running game's viewport. Returns the image as a PNG. The game must be running (use play_project first).",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "inspect_runtime_tree",
		Description: "Walk the live game's scene tree and return node names, types, scripts, and paths. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root_path": {Type: "string", Description: `NodePath to start from (default: "/root")`},
				"max_depth": {Type: "number", Description: "Maximum depth to traverse (default: 3)"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_property",
		Description: "Read a property value from a node in the running game. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string", Description: `Absolute node path (e.g. "/root/Main/Player")`},
				"property":  {Type: "string", Description: `Property name (e.g. "position", "health", "velocity")`},
			},
			Required: []string{"node_path", "property"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "set_runtime_property",
		Description: "Set a property value on a node in the running game. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string", Description: "Absolute node path"},
				"property":  {Type: "string", Description: "Property name"},
				"value":     {Description: `New value to set. For Godot types use {"_type": "Vector3", "x": 1, "y": 2, "z": 3} etc.`},
			},
			Required: []string{"node_path", "property", "value"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "call_runtime_method",
		Description: "Call a method on a node in the running game. The game must be running. For typed args use {\"_type\": \"<T>\", ...} objects. Supported types: Vector2{x,y}, Vector2i, Vector3{x,y,z}, Vector3i, Vector4{x,y,z,w}, Quaternion{x,y,z,w}, Color{r,g,b,a}, Basis{x,y,z}, Transform2D{x,y,origin}, Transform3D{basis,origin}, Rect2{x,y,w,h}, AABB{position,size}, Plane{normal,d}, NodePath{path}.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string", Description: "Absolute node path"},
				"method":    {Type: "string", Description: "Method name to call"},
				"args":      {Type: "array", Description: `Arguments to pass. Use typed objects for Godot types, e.g. {"_type": "Quaternion", "x": 0, "y": 0, "z": 0.707, "w": 0.707}`, Items: &Schema{}},
			},
			Required: []string{"node_path", "method"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_metrics",
		Description: "Get live performance metrics from the running game: FPS, frame time, memory usage, object counts, and render stats. The game must be running.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "inject_action",
		Description: "Simulate a Godot input action (e.g. 'jump', 'ui_accept') in the running game. The action must exist in the project's Input Map. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":   {Type: "string", Description: `Action name from the Input Map (e.g. "jump", "ui_accept")`},
				"pressed":  {Type: "boolean", Description: "true to press, false to release (default: true)"},
				"strength": {Type: "number", Description: "Action strength from 0.0 to 1.0 (default: 1.0)"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "inject_key",
		Description: "Send a keyboard input event to the running game. Uses Godot keycode names (e.g. 'Space', 'A', 'Escape', 'F1'). The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"keycode": {Type: "string", Description: `Godot key name (e.g. "Space", "A", "Escape", "Enter", "F1")`},
				"pressed": {Type: "boolean", Description: "true for key down, false for key up (default: true)"},
				"shift":   {Type: "boolean", Description: "Shift modifier (default: false)"},
				"ctrl":    {Type: "boolean", Description: "Ctrl modifier (default: false)"},
				"alt":     {Type: "boolean", Description: "Alt modifier (default: false)"},
				"meta":    {Type: "boolean", Description: "Meta/Super modifier (default: false)"},
			},
			Required: []string{"keycode"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "inject_mouse_click",
		Description: "Simulate a mouse click at specific coordinates in the running game. Sends both press and release events. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"x":      {Type: "number", Description: "X coordinate in viewport pixels"},
				"y":      {Type: "number", Description: "Y coordinate in viewport pixels"},
				"button": {Type: "string", Description: `Mouse button: "left", "right", or "middle" (default: "left")`},
			},
			Required: []string{"x", "y"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "inject_mouse_motion",
		Description: "Simulate mouse movement in the running game. Specify relative motion (delta) and/or absolute position. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"relative_x": {Type: "number", Description: "Relative X movement (pixels)"},
				"relative_y": {Type: "number", Description: "Relative Y movement (pixels)"},
				"position_x": {Type: "number", Description: "Absolute X position in viewport"},
				"position_y": {Type: "number", Description: "Absolute Y position in viewport"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "watch_signal",
		Description: "Subscribe to a signal on a node in the running game. Emissions are buffered and can be retrieved with get_signal_emissions. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path":   {Type: "string", Description: `Absolute node path (e.g. "/root/Main/Player")`},
				"signal_name": {Type: "string", Description: `Signal name to watch (e.g. "health_changed", "body_entered")`},
			},
			Required: []string{"node_path", "signal_name"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "unwatch_signal",
		Description: "Stop watching a signal previously subscribed with watch_signal. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path":   {Type: "string", Description: "Absolute node path"},
				"signal_name": {Type: "string", Description: "Signal name to stop watching"},
			},
			Required: []string{"node_path", "signal_name"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
	{
		Name:        "get_signal_emissions",
		Description: "Retrieve buffered signal emissions from watched signals. Returns and clears the buffer by default. The game must be running.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"key":   {Type: "string", Description: `Filter by watch key ("node_path::signal_name"). Omit to get all.`},
				"clear": {Type: "boolean", Description: "Clear returned emissions from buffer (default: true)"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"ok": false, "error": "Game is not running"}
		},
	},
}

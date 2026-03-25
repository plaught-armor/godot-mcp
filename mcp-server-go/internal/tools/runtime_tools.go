package tools

var runtimeTools = []ToolDef{
	{
		Name:        "capture_screenshot",
		Description: "Capture a screenshot of the running game viewport.",
		InputSchema: &Schema{
			Type:       "object",
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "inspect_runtime_tree",
		Description: "Walk the running game's scene tree.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root_path": {Type: "string", Description: `Start path (default: "/root")`},
				"max_depth": {Type: "number", Description: "Max depth (default: 3)"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_property",
		Description: "Read a property from a running game node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string", Description: "Absolute node path"},
				"property":  {Type: "string", Description: "Property name"},
			},
			Required: []string{"node_path", "property"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "set_runtime_property",
		Description: "Set a property on a running game node.",
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
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "call_runtime_method",
		Description: "Call a method on a running game node.",
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
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_metrics",
		Description: "Get live perf metrics: FPS, frame time, memory, objects, render.",
		InputSchema: &Schema{
			Type:       "object",
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"error": "Game is not running"}
		},
	},
	{
		Name:        "inject_input",
		Description: "Simulate input in the running game: action, key, mouse click, or mouse motion.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"type": {Type: "string", Description: "Input type", Enum: []string{"action", "key", "mouse_click", "mouse_motion"}},
				// action params
				"action":   {Type: "string", Description: "Input Map action name (type=action)"},
				"pressed":  {Type: "boolean", Description: "true=press, false=release (type=action,key)"},
				"strength": {Type: "number", Description: "Strength 0.0-1.0, default 1.0 (type=action)"},
				// key params
				"keycode": {Type: "string", Description: "Godot key name: Space, A, Escape, Enter, F1, etc. (type=key)"},
				"shift":   {Type: "boolean", Description: "Shift modifier (type=key)"},
				"ctrl":    {Type: "boolean", Description: "Ctrl modifier (type=key)"},
				"alt":     {Type: "boolean", Description: "Alt modifier (type=key)"},
				"meta":    {Type: "boolean", Description: "Meta/Super modifier (type=key)"},
				// mouse_click params
				"x":      {Type: "number", Description: "X in viewport pixels (type=mouse_click)"},
				"y":      {Type: "number", Description: "Y in viewport pixels (type=mouse_click)"},
				"button": {Type: "string", Description: `"left", "right", or "middle", default "left" (type=mouse_click)`},
				// mouse_motion params
				"relative_x": {Type: "number", Description: "Relative X movement (type=mouse_motion)"},
				"relative_y": {Type: "number", Description: "Relative Y movement (type=mouse_motion)"},
				"position_x": {Type: "number", Description: "Absolute X position (type=mouse_motion)"},
				"position_y": {Type: "number", Description: "Absolute Y position (type=mouse_motion)"},
			},
			Required: []string{"type"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "signal_watch",
		Description: "Watch/unwatch signals and get emissions from the running game.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":      {Type: "string", Description: "Action to perform", Enum: []string{"watch", "unwatch", "get_emissions"}},
				"node_path":   {Type: "string", Description: "Absolute node path (action=watch,unwatch)"},
				"signal_name": {Type: "string", Description: "Signal name (action=watch,unwatch)"},
				"key":         {Type: "string", Description: `Filter by "node_path::signal_name" (action=get_emissions)`},
				"clear":       {Type: "boolean", Description: "Clear returned emissions, default true (action=get_emissions)"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
}

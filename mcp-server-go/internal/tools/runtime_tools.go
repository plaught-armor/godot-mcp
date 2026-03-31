package tools

var runtimeTools = []ToolDef{
	{
		Name:        "capture_screenshot",
		Description: "Capture a screenshot of the running game viewport.",
		InputSchema: &Schema{Type: "object"},
		Runtime:     true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "inspect_runtime_tree",
		Description: "Walk the running game's scene tree.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root_path": {Type: "string"},
				"max_depth": {Type: "number"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_property",
		Description: "Read a property from a running game node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string"},
				"property":  {Type: "string"},
			},
			Required: []string{"node_path", "property"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "set_runtime_property",
		Description: "Set a property on a running game node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string"},
				"property":  {Type: "string"},
				"value":     {},
			},
			Required: []string{"node_path", "property", "value"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "call_runtime_method",
		Description: "Call a method on a running game node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_path": {Type: "string"},
				"method":    {Type: "string"},
				"args":      {Type: "array", Items: &Schema{}},
			},
			Required: []string{"node_path", "method"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "get_runtime_metrics",
		Description: "Live perf metrics: FPS, frame time, memory, objects, render.",
		InputSchema: &Schema{Type: "object"},
		Runtime:     true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "inject_input",
		Description: "Simulate input in the running game.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"type":       {Type: "string", Enum: []string{"action", "key", "mouse_click", "mouse_motion"}},
				"properties": {Type: "object"},
				"track":      {Type: "array", Items: &Schema{Type: "object"}},
			},
			Required: []string{"type"},
		},
		Runtime: true,
		MockFn:  mockOK(),
	},
	{
		Name:        "signal_watch",
		Description: "Watch/unwatch signals and get emissions from running game.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"watch", "unwatch", "get_emissions"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn:  mockOK(),
	},
	{
		Name:        "runtime_watch",
		Description: "Watch node properties for changes over time.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"watch", "unwatch", "list", "get_changes"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn:  mockOK(),
	},
	{
		Name:        "map_ui",
		Description: "Walk Control tree: layout, visibility, text content.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root_path": {Type: "string"},
				"max_depth": {Type: "number"},
			},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "explore_camera",
		Description: "Spawn/move/capture/restore a temporary Camera3D for scene exploration.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"spawn", "move", "capture", "restore"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn:  mockOK(),
	},
	{
		Name:        "runtime_nav",
		Description: "Query NavigationServer: pathfinding, distance, snapping.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"get_path", "get_distance", "snap"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
	{
		Name:        "runtime_log",
		Description: "Retrieve game print output, warnings, and errors.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"get", "clear"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		Runtime: true,
		MockFn: func(args map[string]any) any {
			return map[string]any{"err": "Game is not running"}
		},
	},
}

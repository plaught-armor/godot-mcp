package tools

var runtimeTools = []ToolDef{
	{
		Name:        "rt",
		Description: "Runtime game tools: screenshot, tree, properties, input, signals, metrics.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"screenshot", "tree", "prop", "set_prop", "call", "metrics", "input", "sig_watch", "prop_watch", "ui", "cam_spawn", "cam_move", "cam_capture", "cam_restore", "nav", "log"}},
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

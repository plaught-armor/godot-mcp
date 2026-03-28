package tools

var profilingTools = []ToolDef{
	{
		Name:        "perf",
		Description: "Editor performance monitors and summary.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":   {Type: "string", Enum: []string{"monitors", "summary"}},
				"category": {Type: "string", Enum: []string{"time", "memory", "object", "render", "physics_2d", "physics_3d", "navigation"}},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

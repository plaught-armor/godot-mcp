package tools

var navigationTools = []ToolDef{
	{
		Name:        "nav",
		Description: "Navigation regions, agents, mesh baking.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"region", "bake", "agent", "layers", "info"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "scene_path", "node_path"},
		},
		MockFn: mockOK(),
	},
}

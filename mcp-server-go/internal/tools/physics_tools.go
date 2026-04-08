package tools

var physicsTools = []ToolDef{
	{
		Name:        "phys",
		Description: "Physics bodies, collision shapes, raycasts, layers.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":          {Type: "string", Enum: []string{"collision", "layers", "get_layers", "raycast", "body", "info"}},
				"scene_path":      {Type: "string"},
				"node_path":       {Type: "string"},
				"shape_type":      {Type: "string"},
				"target_position": {Type: "object"},
				"properties":      {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

package tools

var particleTools = []ToolDef{
	{
		Name:        "ptcl",
		Description: "GPUParticles2D/3D creation and configuration.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"create", "material", "gradient", "preset", "info"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"colors":     {Type: "array", Items: &Schema{Type: "string"}},
				"preset":     {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

package tools

var shaderTools = []ToolDef{
	{
		Name:        "shader",
		Description: "Shader files and ShaderMaterial uniforms.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":      {Type: "string", Enum: []string{"create", "read", "edit", "assign", "param", "params"}},
				"scene_path":  {Type: "string"},
				"node_path":   {Type: "string"},
				"path":        {Type: "string"},
				"shader_path": {Type: "string"},
				"param":       {Type: "string"},
				"value":       {},
				"properties":  {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

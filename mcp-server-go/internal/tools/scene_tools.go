package tools

var sceneTools = []ToolDef{
	{
		Name:        "scene",
		Description: "Scene operations: create, read, edit nodes, find/set by type, attach scripts, textures.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"create", "read", "edit", "batch", "find_by_type", "set_by_type", "cross_scene_set", "attach_script", "detach_script", "texture"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
				"ops":        {Type: "array", Items: &Schema{Type: "object"}},
				"type":       {Type: "string"},
				"property":   {Type: "string"},
				"value":      {},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

func mockOK() func(map[string]any) any {
	return func(map[string]any) any {
		return map[string]any{}
	}
}

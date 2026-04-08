package tools

var sceneTools = []ToolDef{
	{
		Name:        "scene",
		Description: "Scene operations: create, read, add/remove/edit nodes, find/set by type, attach scripts, textures.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":         {Type: "string", Enum: []string{"create", "read", "add_node", "remove_node", "set_property", "rename", "move", "duplicate", "reorder", "batch", "find_by_type", "set_by_type", "cross_scene_set", "attach_script", "detach_script", "texture"}},
				"scene_path":     {Type: "string"},
				"node_path":      {Type: "string"},
				"root_node_type": {Type: "string"},
				"root_node_name": {Type: "string"},
				"node_name":      {Type: "string"},
				"node_type":      {Type: "string"},
				"property_name":  {Type: "string"},
				"new_name":       {Type: "string"},
				"new_parent_path": {Type: "string"},
				"script_path":    {Type: "string"},
				"shape_type":     {Type: "string"},
				"texture_type":   {Type: "string"},
				"nodes":          {Type: "array", Items: &Schema{Type: "object"}},
				"attach_script":  {Type: "string"},
				"properties":     {Type: "object"},
				"ops":            {Type: "array", Items: &Schema{Type: "object"}},
				"type":           {Type: "string"},
				"property":       {Type: "string"},
				"value":          {},
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

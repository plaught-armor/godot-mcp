package tools

var themeTools = []ToolDef{
	{
		Name:        "theme",
		Description: "UI theme overrides on Control nodes.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"create", "color", "constant", "font_size", "stylebox", "info"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"path":       {Type: "string"},
				"name":       {Type: "string"},
				"color":      {Type: "string"},
				"value":      {},
				"size":       {Type: "integer"},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

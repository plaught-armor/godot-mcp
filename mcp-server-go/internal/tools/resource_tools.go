package tools

var resourceTools = []ToolDef{
	{
		Name:        "tres",
		Description: "Resource (.tres) files: read, edit, create, preview.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"read", "edit", "create", "preview"}},
				"path":       {Type: "string"},
				"type":       {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "path"},
		},
		MockFn: mockOK(),
	},
}

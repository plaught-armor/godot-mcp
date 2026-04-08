package tools

var scriptTools = []ToolDef{
	{
		Name:        "script",
		Description: "GDScript operations: create, edit, validate, list, symbols, find class.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"create", "edit", "validate", "validate_batch", "list", "symbols", "find_class", "format"}},
				"path":       {Type: "string"},
				"paths":      {Type: "array", Items: &Schema{Type: "string"}},
				"content":    {Type: "string"},
				"edit":       {Type: "object"},
				"class_name": {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

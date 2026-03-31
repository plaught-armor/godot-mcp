package tools

var scriptTools = []ToolDef{
	{
		Name:        "script",
		Description: "GDScript operations: create, edit, validate, list, symbols, find class.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"create", "edit", "validate", "validate_batch", "list", "symbols", "find_class", "format"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

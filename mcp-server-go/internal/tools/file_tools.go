package tools

var fileTools = []ToolDef{
	{
		Name:        "file",
		Description: "File operations: list, read, create, search, edit, delete, rename.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"ls", "read", "reads", "create", "search", "mkdir", "rm", "rmdir", "rename", "replace", "bulk_edit", "refs", "resources"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

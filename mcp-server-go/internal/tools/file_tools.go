package tools

var fileTools = []ToolDef{
	{
		Name:        "file",
		Description: "File operations: list, read, create, search, edit, delete, rename.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"ls", "read", "reads", "create", "search", "mkdir", "rm", "rmdir", "rename", "replace", "bulk_edit", "refs", "resources"}},
				"root":       {Type: "string"},
				"path":       {Type: "string"},
				"paths":      {Type: "array", Items: &Schema{Type: "string"}},
				"content":    {Type: "string"},
				"query":      {Type: "string"},
				"confirm":    {Type: "boolean"},
				"old_path":   {Type: "string"},
				"new_path":   {Type: "string"},
				"search":     {Type: "string"},
				"replace":    {Type: "string"},
				"edits":      {Type: "array", Items: &Schema{Type: "object"}},
				"symbol":     {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

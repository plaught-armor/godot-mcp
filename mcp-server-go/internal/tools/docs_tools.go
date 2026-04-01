package tools

var docsTools = []ToolDef{
	{
		Name:        "docs",
		Description: "Godot class reference: lookup classes, search methods, browse API.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"class", "search", "method"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
}

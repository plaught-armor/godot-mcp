package tools

var docsTools = []ToolDef{
	{
		Name:        "docs",
		Description: "Look up a Godot class method's docs from GitHub.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class":  {Type: "string"},
				"method": {Type: "string"},
			},
			Required: []string{"class", "method"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
}

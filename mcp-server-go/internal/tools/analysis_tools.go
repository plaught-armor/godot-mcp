package tools

var analysisTools = []ToolDef{
	{
		Name:        "analyze",
		Description: "Project analysis: unused assets, signals, complexity, references.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"unused", "signals", "complexity", "references", "circular", "stats"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

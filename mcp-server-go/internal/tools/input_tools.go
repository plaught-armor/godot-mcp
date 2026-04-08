package tools

var inputTools = []ToolDef{
	{
		Name:        "input",
		Description: "InputMap actions: list and configure.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":       {Type: "string", Enum: []string{"list", "set"}},
				"input_action": {Type: "string"},
				"operation":    {Type: "string"},
				"properties":   {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

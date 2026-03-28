package tools

var audioTools = []ToolDef{
	{
		Name:        "audio",
		Description: "Audio buses, effects, and StreamPlayer nodes.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"list", "add", "set", "effect", "player", "info"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
}

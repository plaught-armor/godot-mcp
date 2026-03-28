package tools

var assetTools = []ToolDef{
	{
		Name:        "generate_2d_asset",
		Description: "Generate a PNG sprite from SVG code.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"svg_code":  {Type: "string"},
				"filename":  {Type: "string"},
				"save_path": {Type: "string"},
			},
			Required: []string{"svg_code", "filename"},
		},
		MockFn: mockOK(),
	},
}

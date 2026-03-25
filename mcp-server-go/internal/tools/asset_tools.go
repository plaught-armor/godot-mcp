package tools



var assetTools = []ToolDef{
	{
		Name:        "generate_2d_asset",
		Description: "Generate a PNG sprite from SVG code.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"svg_code":  {Type: "string", Description: "SVG code with <svg> tags including width/height"},
				"filename":  {Type: "string", Description: "Output .png filename"},
				"save_path": {Type: "string", Description: "Save directory (default: res://assets/generated/)"},
			},
			Required: []string{"svg_code", "filename"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"dimensions": map[string]any{"width": 64, "height": 64},
			}
		},
	},
}

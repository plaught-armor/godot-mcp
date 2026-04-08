package tools

var tilemapTools = []ToolDef{
	{
		Name:        "tmap",
		Description: "TileMapLayer cell editing.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"set_cell", "fill_rect", "get_cell", "clear", "info", "used_cells"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"x":          {Type: "integer"},
				"y":          {Type: "integer"},
				"x1":         {Type: "integer"},
				"y1":         {Type: "integer"},
				"x2":         {Type: "integer"},
				"y2":         {Type: "integer"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "scene_path", "node_path"},
		},
		MockFn: mockOK(),
	},
}

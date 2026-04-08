package tools

var animationTools = []ToolDef{
	{
		Name:        "anim",
		Description: "AnimationPlayer and AnimationTree operations.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":           {Type: "string", Enum: []string{"list", "create", "track", "keyframe", "info", "remove", "new_tree", "tree", "add_state", "rm_state", "add_trans", "rm_trans", "blend_node", "set_param"}},
				"scene_path":       {Type: "string"},
				"node_path":        {Type: "string"},
				"name":             {Type: "string"},
				"animation":        {Type: "string"},
				"track_path":       {Type: "string"},
				"track_index":      {Type: "integer"},
				"time":             {Type: "number"},
				"value":            {},
				"state_name":       {Type: "string"},
				"from_state":       {Type: "string"},
				"to_state":         {Type: "string"},
				"blend_tree_state": {Type: "string"},
				"bt_node_name":     {Type: "string"},
				"bt_node_type":     {Type: "string"},
				"parameter":        {Type: "string"},
				"properties":       {Type: "object"},
			},
			Required: []string{"action", "scene_path", "node_path"},
		},
		MockFn: mockOK(),
	},
}

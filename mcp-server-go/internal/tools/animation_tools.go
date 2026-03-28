package tools

var animationTools = []ToolDef{
	{
		Name:        "anim",
		Description: "AnimationPlayer and AnimationTree operations.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"list", "create", "track", "keyframe", "info", "remove", "new_tree", "tree", "add_state", "rm_state", "add_trans", "rm_trans", "blend_node", "set_param"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "scene_path", "node_path"},
		},
		MockFn: mockOK(),
	},
}

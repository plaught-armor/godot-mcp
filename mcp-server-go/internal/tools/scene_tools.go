package tools

var sceneTools = []ToolDef{
	{
		Name:        "create_scene",
		Description: "Create a .tscn scene file with nodes.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":     {Type: "string"},
				"root_node_type": {Type: "string"},
				"root_node_name": {Type: "string"},
				"nodes":          {Type: "array", Items: &Schema{Type: "object"}},
				"attach_script":  {Type: "string"},
			},
			Required: []string{"scene_path", "root_node_type"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "read_scene",
		Description: "Read a .tscn file's node structure.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":         {Type: "string"},
				"include_properties": {Type: "boolean"},
			},
			Required: []string{"scene_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "scene_edit",
		Description: "Edit scene nodes: add, remove, set_property, rename, move, duplicate, reorder.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"add_node", "remove_node", "set_property", "rename", "move", "duplicate", "reorder"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "scene_path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "attach_script",
		Description: "Attach a script to a scene node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":  {Type: "string"},
				"node_path":   {Type: "string"},
				"script_path": {Type: "string"},
			},
			Required: []string{"scene_path", "script_path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "detach_script",
		Description: "Remove a script from a scene node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
			},
			Required: []string{"scene_path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "set_sprite_texture",
		Description: "Assign a texture to Sprite2D/Sprite3D/TextureRect.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":     {Type: "string"},
				"node_path":      {Type: "string"},
				"texture_type":   {Type: "string", Enum: []string{"ImageTexture", "PlaceholderTexture2D", "GradientTexture2D", "NoiseTexture2D"}},
				"texture_params": {Type: "object"},
			},
			Required: []string{"scene_path", "node_path", "texture_type"},
		},
		MockFn: mockOK(),
	},
}

func mockOK() func(map[string]any) any {
	return func(map[string]any) any {
		return map[string]any{}
	}
}

package tools

var sceneTools = []ToolDef{
	{
		Name:        "create_scene",
		Description: "Create a .tscn scene file with nodes.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":     {Type: "string", Description: "res:// scene path"},
				"root_node_name": {Type: "string", Description: "Root node name (default: derived from filename)"},
				"root_node_type": {Type: "string", Description: "Root node type"},
				"nodes": {
					Type:        "array",
					Items:       &Schema{Type: "object", Description: "A node: {name, type, properties, script, children}"},
					Description: "Child nodes: [{name, type, properties, script, children}]",
				},
				"attach_script": {Type: "string", Description: "Script to attach to root node (res:// path)"},
			},
			Required: []string{"scene_path", "root_node_type"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "read_scene",
		Description: "Read a .tscn file's node structure and properties.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":         {Type: "string", Description: "res:// scene path"},
				"include_properties": {Type: "boolean", Description: "Include node properties"},
			},
			Required: []string{"scene_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"root": map[string]any{"name": "Root", "type": "Node2D", "children": []map[string]any{{"name": "Sprite2D", "type": "Sprite2D"}}},
			}
		},
	},
	{
		Name:        "scene_edit",
		Description: "Edit scene nodes: add, remove, rename, move, duplicate, reorder, set property.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":          {Type: "string", Description: "Edit action", Enum: []string{"add_node", "remove_node", "set_property", "rename", "move", "duplicate", "reorder"}},
				"scene_path":      {Type: "string", Description: "res:// scene path"},
				"node_path":       {Type: "string", Description: "Target node (. for root)"},
				"node_paths":      {Type: "array", Description: "Nodes to remove (bulk)", Items: &Schema{Type: "string"}},
				"node_name":       {Type: "string", Description: "New node name (add_node)"},
				"node_type":       {Type: "string", Description: "Node type (add_node)"},
				"parent_path":     {Type: "string", Description: "Parent node (add_node, move)"},
				"properties":      {Type: "object", Description: "Properties to set (add_node)"},
				"property_name":   {Type: "string", Description: "Property to modify (set_property)"},
				"value":           {Description: "Value for set_property. Vector2/Vector3/Color: {type:'Vector2',x:100,y:200}"},
				"new_name":        {Type: "string", Description: "New name (rename, duplicate)"},
				"new_parent_path": {Type: "string", Description: "New parent (move)"},
				"sibling_index":   {Type: "number", Description: "Position among siblings (move, reorder)"},
				"new_index":       {Type: "number", Description: "New sibling index (reorder)"},
			},
			Required: []string{"action", "scene_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "attach_script",
		Description: "Attach or change a script on a node in a scene.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":  {Type: "string", Description: "res:// scene path"},
				"node_path":   {Type: "string", Description: "Node path (. for root)"},
				"script_path": {Type: "string", Description: "res:// script path"},
			},
			Required: []string{"scene_path", "script_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "detach_script",
		Description: "Remove a script from a node in a scene.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path": {Type: "string", Description: "res:// scene path"},
				"node_path":  {Type: "string", Description: "Node path (. for root)"},
			},
			Required: []string{"scene_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "set_collision_shape",
		Description: "Assign a collision shape to a CollisionShape2D/3D node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":   {Type: "string", Description: "res:// scene path"},
				"node_path":    {Type: "string", Description: "CollisionShape2D/3D node path"},
				"shape_type":   {Type: "string", Description: "Shape class (CircleShape2D, RectangleShape2D, BoxShape3D, etc.)"},
				"shape_params": {Type: "object", Description: "Shape params: {radius: 32}, {size: {x: 64, y: 64}}, etc."},
			},
			Required: []string{"scene_path", "node_path", "shape_type"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "set_sprite_texture",
		Description: "Assign a texture to a Sprite2D/Sprite3D/TextureRect node.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path":     {Type: "string", Description: "res:// scene path"},
				"node_path":      {Type: "string", Description: "Sprite2D/Sprite3D/TextureRect node path"},
				"texture_type":   {Type: "string", Description: "Texture type", Enum: []string{"ImageTexture", "PlaceholderTexture2D", "GradientTexture2D", "NoiseTexture2D"}},
				"texture_params": {Type: "object", Description: `ImageTexture: {path: "res://..."}. PlaceholderTexture2D: {size: {x: 64, y: 64}}.`},
			},
			Required: []string{"scene_path", "node_path", "texture_type"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
}

func mockOK() func(map[string]any) any {
	return func(map[string]any) any {
		return map[string]any{}
	}
}

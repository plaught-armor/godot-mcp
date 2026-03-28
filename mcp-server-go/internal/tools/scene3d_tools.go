package tools

var scene3dTools = []ToolDef{
	{
		Name:        "s3d",
		Description: "3D scene: mesh, lighting, material, environment, camera, gridmap.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"mesh", "lighting", "material", "environment", "camera", "gridmap"}},
				"scene_path": {Type: "string"},
				"node_path":  {Type: "string"},
				"properties": {Type: "object"},
			},
			Required: []string{"action", "scene_path"},
		},
		MockFn: mockOK(),
	},
}

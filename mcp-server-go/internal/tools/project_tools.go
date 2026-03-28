package tools

var projectTools = []ToolDef{
	{
		Name:        "get_project_settings",
		Description: "Get project settings: main_scene, window, physics, render.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"include_render":  {Type: "boolean"},
				"include_physics": {Type: "boolean"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "set_project_setting",
		Description: "Set a project setting. null to remove.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"setting": {Type: "string"},
				"value":   {},
			},
			Required: []string{"setting", "value"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "get_node_properties",
		Description: "Get editable properties for a node type.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_type": {Type: "string"},
			},
			Required: []string{"node_type"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"properties": []string{}}
		},
	},
	{
		Name:        "get_autoloads",
		Description: "List registered autoloads.",
		InputSchema: &Schema{Type: "object"},
		MockFn: func(args map[string]any) any {
			return map[string]any{"autoloads": []any{}}
		},
	},
	{
		Name:        "get_console_log",
		Description: "Get editor output log lines.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_lines": {Type: "number"},
				"filter":    {Type: "string"},
				"severity":  {Type: "string", Enum: []string{"all", "error", "warning", "info"}},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"lines": []string{}}
		},
	},
	{
		Name:        "get_errors",
		Description: "Get editor errors and warnings.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_errors":       {Type: "number"},
				"include_warnings": {Type: "boolean"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"errors": []any{}}
		},
	},
	{
		Name:        "get_debug_errors",
		Description: "Get runtime debugger errors.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_errors":       {Type: "number"},
				"include_warnings": {Type: "boolean"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"errors": []any{}}
		},
	},
	{
		Name:        "clear_console_log",
		Description: "Clear console log.",
		InputSchema: &Schema{Type: "object"},
		MockFn:      mockOK(),
	},
	{
		Name:        "open_in_godot",
		Description: "Open a file in the Godot editor.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string"},
				"line": {Type: "number"},
			},
			Required: []string{"path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "scene_tree_dump",
		Description: "Dump editor scene tree (design-time).",
		InputSchema: &Schema{Type: "object"},
		MockFn: func(args map[string]any) any {
			return map[string]any{"tree": ""}
		},
	},
	{
		Name:        "play_project",
		Description: "Play the project, optionally a specific scene.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path": {Type: "string"},
			},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "stop_project",
		Description: "Stop the running scene.",
		InputSchema: &Schema{Type: "object"},
		MockFn:      mockOK(),
	},
	{
		Name:        "is_project_running",
		Description: "Check if a scene is running.",
		InputSchema: &Schema{Type: "object"},
		MockFn: func(args map[string]any) any {
			return map[string]any{"running": false}
		},
	},
	{
		Name:        "git",
		Description: "Git: status, commit, diff, log, stash.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"status", "commit", "diff", "log", "stash_push", "stash_pop", "stash_list"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "run_shell_command",
		Description: "Execute a shell command in the project directory.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"command": {Type: "string"},
				"args":    {Type: "array", Items: &Schema{Type: "string"}},
			},
			Required: []string{"command"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"exit_code": 0, "stdout": ""}
		},
	},
	{
		Name:        "get_uid",
		Description: "Get Godot UID for a resource path.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"uid": ""}
		},
	},
	{
		Name:        "query_class_info",
		Description: "Get ClassDB info: methods, properties, signals, enums, parent.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class_name":        {Type: "string"},
				"include_inherited": {Type: "boolean"},
			},
			Required: []string{"class_name"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "query_classes",
		Description: "List ClassDB classes with optional filter.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"filter":            {Type: "string"},
				"category":          {Type: "string", Enum: []string{"node", "node2d", "node3d", "control", "resource", "physics2d", "physics3d", "audio", "animation"}},
				"instantiable_only": {Type: "boolean"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"classes": []string{}}
		},
	},
}

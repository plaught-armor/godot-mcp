package tools



var projectTools = []ToolDef{
	{
		Name:        "get_project_settings",
		Description: "Get project settings: main_scene, window, physics, render.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"include_render":  {Type: "boolean", Description: "Include render settings"},
				"include_physics": {Type: "boolean", Description: "Include physics settings"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"settings": map[string]any{"main_scene": "res://scenes/main.tscn", "window": map[string]any{"width": 1152, "height": 648}},
			}
		},
	},
	{
		Name:        "set_project_setting",
		Description: "Set a project setting by path. null to remove.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"setting": {Type: "string", Description: `Full setting path`},
				"value":   {Description: `Value to set, or null to remove`},
			},
			Required: []string{"setting", "value"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"old_value": nil,
				"new_value": args["value"],
			}
		},
	},
	{
		Name:        "get_input_map",
		Description: "Get InputMap actions and their events.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"include_deadzones": {Type: "boolean", Description: "Include joypad axis values/deadzones"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"actions": map[string]any{"ui_accept": []string{"Enter", "Space"}, "ui_cancel": []string{"Escape"}, "move_left": []string{"A", "Left"}},
			}
		},
	},
	{
		Name:        "configure_input_map",
		Description: "Add/remove/replace InputMap actions.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":    {Type: "string", Description: `Action name`},
				"operation": {Type: "string", Description: `"add", "remove", or "set"`, Enum: []string{"add", "remove", "set"}},
				"events": {Type: "array", Description: `Event objects: key={key:"Space"}, mouse_button={button_index:1}, joypad_button={button_index:0}, joypad_motion={axis:0, axis_value:1.0}`, Items: &Schema{Type: "object"}},
				"deadzone": {Type: "number", Description: "Action deadzone (default: 0.5)"},
			},
			Required: []string{"action", "operation"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "get_collision_layers",
		Description: "Get named 2D/3D physics collision layers.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"layers_2d": []map[string]any{{"index": 1, "value": "Player"}, {"index": 2, "value": "Enemies"}, {"index": 3, "value": "World"}},
				"layers_3d": []map[string]any{},
			}
		},
	},
	{
		Name:        "get_node_properties",
		Description: "Get properties for a node type.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_type": {Type: "string", Description: `Node class name`},
			},
			Required: []string{"node_type"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"properties": []string{"position", "rotation", "scale", "visible", "modulate"},
			}
		},
	},
	{
		Name:        "get_autoloads",
		Description: "List registered autoloads.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"autoloads": []any{}}
		},
	},
	{
		Name:        "get_console_log",
		Description: "Get editor output log lines. Supports filtering.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_lines": {Type: "number", Description: "Max lines (default: 50)"},
				"filter":    {Type: "string", Description: "Substring filter (case-insensitive)"},
				"severity":  {Type: "string", Description: "Severity filter (default: all)", Enum: []string{"all", "error", "warning", "info"}},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"lines": []string{"[Godot] Project loaded", "[Godot] Scene ready"},
			}
		},
	},
	{
		Name:        "get_errors",
		Description: "Get editor errors and warnings.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_errors":       {Type: "number", Description: "Max errors (default: 50)"},
				"include_warnings": {Type: "boolean", Description: "Include warnings (default: true)"},
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
				"max_errors":       {Type: "number", Description: "Max errors (default: 50)"},
				"include_warnings": {Type: "boolean", Description: "Include warnings (default: true)"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"errors": []any{}}
		},
	},
	{
		Name:        "clear_console_log",
		Description: "Clear console log. Subsequent calls return only new output.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: mockOK(),
	},
	{
		Name:        "open_in_godot",
		Description: "Open a file in the Godot editor at a specific line (side-effect only).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "res:// path to open"},
				"line": {Type: "number", Description: "1-based line number"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "scene_tree_dump",
		Description: "Dump editor scene tree (design-time).",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"tree": "Root (Node2D)\n  Player (CharacterBody2D)\n    Sprite2D\n    CollisionShape2D",
			}
		},
	},
	{
		Name:        "play_project",
		Description: "Play the project. Pass scene_path to override main scene.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path": {Type: "string", Description: `res:// scene path, or "current" for active scene. Omit for main scene.`},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "stop_project",
		Description: "Stop the running scene.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "is_project_running",
		Description: "Check if a scene is running.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"running": false}
		},
	},
	{
		Name:        "git",
		Description: "Git operations: status, commit, diff, log, stash.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":    {Type: "string", Description: "Git action", Enum: []string{"status", "commit", "diff", "log", "stash_push", "stash_pop", "stash_list"}},
				"message":   {Type: "string", Description: "Commit message (commit) or stash message (stash_push)"},
				"files":     {Type: "array", Description: "Files to stage (commit). Omit with all=true to stage everything.", Items: &Schema{Type: "string"}},
				"all":       {Type: "boolean", Description: "Stage all changes (commit)"},
				"file":      {Type: "string", Description: "File to diff or filter log by"},
				"staged":    {Type: "boolean", Description: "Show staged diff"},
				"max_count": {Type: "number", Description: "Commits to show (log, default: 10)"},
			},
			Required: []string{"action"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "run_shell_command",
		Description: "Execute a shell command in the project directory.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"command": {Type: "string", Description: "Command to execute"},
				"args":    {Type: "array", Description: "Command arguments", Items: &Schema{Type: "string"}},
			},
			Required: []string{"command"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"exit_code": 0, "stdout": "Mock: command output"}
		},
	},
	{
		Name:        "get_uid",
		Description: "Get Godot UID for a resource path.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "res:// resource path"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"uid": "uid://abc123def456"}
		},
	},
	{
		Name:        "query_class_info",
		Description: "Get ClassDB info: methods, properties, signals, enums, parent.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class_name":        {Type: "string", Description: `Godot class name`},
				"include_inherited": {Type: "boolean", Description: "Include inherited members"},
			},
			Required: []string{"class_name"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"parent_class": "Node",
				"methods":      []any{},
				"properties":   []any{},
				"signals":      []any{},
				"enums":        map[string]any{},
			}
		},
	},
	{
		Name:        "query_classes",
		Description: "List ClassDB classes, optionally filtered by name or category.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"filter":            {Type: "string", Description: "Substring filter on class name (case-insensitive)"},
				"category":          {Type: "string", Description: `Category filter`, Enum: []string{"node", "node2d", "node3d", "control", "resource", "physics2d", "physics3d", "audio", "animation"}},
				"instantiable_only": {Type: "boolean", Description: "Only instantiable classes"},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"classes": []string{"Node", "Node2D", "Node3D"}}
		},
	},
}

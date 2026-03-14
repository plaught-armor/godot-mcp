package tools



var projectTools = []ToolDef{
	{
		Name:        "get_project_settings",
		Description: "Concise project settings summary: main_scene, window size/stretch, physics tick rate, and render basics.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"include_render":  {Type: "boolean", Description: "Include render settings"},
				"include_physics": {Type: "boolean", Description: "Include physics settings"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":       true,
				"settings": map[string]any{"main_scene": "res://scenes/main.tscn", "window": map[string]any{"width": 1152, "height": 648}},
			})
		},
	},
	{
		Name:        "set_project_setting",
		Description: "Set a Godot project setting. Use the full setting path (e.g. \"application/run/main_scene\", \"autoload/MyAutoload\", \"display/window/size/viewport_width\"). For autoloads, prefix the path with * for non-singleton (e.g. \"*res://scripts/my_autoload.gd\"). Set value to null to remove a setting.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"setting": {Type: "string", Description: `Full setting path (e.g. "application/run/main_scene", "autoload/GameManager")`},
				"value":   {Description: `New value to set. Type depends on the setting (string, number, boolean, etc.). Use null to remove.`},
			},
			Required: []string{"setting", "value"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":        true,
				"setting":   args["setting"],
				"old_value": nil,
				"new_value": args["value"],
			})
		},
	},
	{
		Name:        "get_input_map",
		Description: "Return the InputMap: action names mapped to events (keys, mouse, gamepad).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"include_deadzones": {Type: "boolean", Description: "Include axis values/deadzones for joypad motion"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":      true,
				"actions": map[string]any{"ui_accept": []string{"Enter", "Space"}, "ui_cancel": []string{"Escape"}, "move_left": []string{"A", "Left"}},
			})
		},
	},
	{
		Name:        "configure_input_map",
		Description: "Add, remove, or replace input actions in the Godot InputMap. Operations: 'add' (create action or append events), 'remove' (delete action entirely), 'set' (replace action with new events). Events are objects with type ('key', 'mouse_button', 'joypad_button', 'joypad_motion') and type-specific fields.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":    {Type: "string", Description: `Action name (e.g. "move_left", "jump")`},
				"operation": {Type: "string", Description: `Operation: "add", "remove", or "set"`, Enum: []string{"add", "remove", "set"}},
				"events": {Type: "array", Description: `Array of event objects. Each has "type" plus type-specific fields: key={key:"Space"}, mouse_button={button_index:1}, joypad_button={button_index:0}, joypad_motion={axis:0, axis_value:1.0}`, Items: &Schema{Type: "object"}},
				"deadzone": {Type: "number", Description: "Deadzone for the action (default: 0.5)"},
			},
			Required: []string{"action", "operation"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":      true,
				"message": "Mock: Would configure input action " + str(args["action"]),
			})
		},
	},
	{
		Name:        "get_collision_layers",
		Description: "Return named 2D/3D physics collision layers from ProjectSettings.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":        true,
				"layers_2d": []map[string]any{{"index": 1, "value": "Player"}, {"index": 2, "value": "Enemies"}, {"index": 3, "value": "World"}},
				"layers_3d": []map[string]any{},
			})
		},
	},
	{
		Name:        "get_node_properties",
		Description: "Get available properties for a Godot node type. Use this to discover what properties exist on a node type (e.g., anchors_preset for Control, position for Node2D).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"node_type": {Type: "string", Description: `Node class name (e.g., "Sprite2D", "Control", "Label", "Button")`},
			},
			Required: []string{"node_type"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":         true,
				"node_type":  args["node_type"],
				"properties": []string{"position", "rotation", "scale", "visible", "modulate"},
			})
		},
	},
	{
		Name:        "get_autoloads",
		Description: "List all registered autoloads in the Godot project with their paths and singleton status.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "autoloads": []any{}, "count": 0})
		},
	},
	{
		Name:        "get_console_log",
		Description: "Return the latest lines from the Godot editor output log. Supports filtering by substring and severity level.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_lines": {Type: "number", Description: "Maximum number of lines to include (default: 50)"},
				"filter":    {Type: "string", Description: "Only include lines containing this substring (case-insensitive)"},
				"severity":  {Type: "string", Description: "Filter by severity: all, error, warning, info (default: all)", Enum: []string{"all", "error", "warning", "info"}},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":    true,
				"lines": []string{"[Godot] Project loaded", "[Godot] Scene ready"},
			})
		},
	},
	{
		Name:        "get_errors",
		Description: "Get errors and warnings from the Godot editor log with file paths, line numbers, and severity. Returns the most recent errors first.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_errors":       {Type: "number", Description: "Maximum number of errors to return (default: 50)"},
				"include_warnings": {Type: "boolean", Description: "Include warnings in addition to errors (default: true)"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "errors": []any{}, "count": 0})
		},
	},
	{
		Name:        "get_debug_errors",
		Description: "Get runtime errors and warnings from the Godot Debugger > Errors tab. Includes stack traces. Only available when the game has been run.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_errors":       {Type: "number", Description: "Maximum number of errors to return (default: 50)"},
				"include_warnings": {Type: "boolean", Description: "Include warnings in addition to errors (default: true)"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "errors": []any{}, "error_count": 0})
		},
	},
	{
		Name:        "clear_console_log",
		Description: "Mark the current position in the Godot editor log. Subsequent get_console_log and get_errors calls will only return output after this point.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: mockOK("Console would be cleared"),
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
			return mockNote(map[string]any{"ok": true, "message": "Mock: Would open " + str(args["path"])})
		},
	},
	{
		Name:        "scene_tree_dump",
		Description: "Dump the scene tree of the scene currently open in the Godot editor (node names, types, and attached scripts).",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":   true,
				"tree": "Root (Node2D)\n  Player (CharacterBody2D)\n    Sprite2D\n    CollisionShape2D",
			})
		},
	},
	{
		Name:        "play_project",
		Description: "Play the project in the Godot editor. By default plays the main scene. Pass scene_path for a specific scene, or \"current\" to play the scene currently open in the editor.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"scene_path": {Type: "string", Description: `Optional: res:// path to a specific scene, or "current" to play the currently edited scene. Omit to play the main scene.`},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "message": "Mock: Would play project"})
		},
	},
	{
		Name:        "stop_project",
		Description: "Stop the currently running scene in the Godot editor.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "message": "Mock: Would stop project"})
		},
	},
	{
		Name:        "is_project_running",
		Description: "Check if a scene is currently running in the Godot editor.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "running": false})
		},
	},
	{
		Name:        "git_status",
		Description: "Show git working tree status for the Godot project. Returns changed/added/deleted files, current branch, and whether the tree is clean.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":     true,
				"branch": "main",
				"files":  []map[string]any{{"path": "scripts/player.gd", "status": "modified"}},
				"clean":  false,
			})
		},
	},
	{
		Name:        "git_commit",
		Description: "Stage files and create a git commit in the Godot project. Provide specific files to stage, or set all=true to stage everything. Does NOT push.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"message": {Type: "string", Description: "Commit message"},
				"files":   {Type: "array", Description: "Files to stage (res:// paths or relative paths). Omit and set all=true to stage everything.", Items: &Schema{Type: "string"}},
				"all":     {Type: "boolean", Description: "Stage all changes (git add -A). Default: false"},
			},
			Required: []string{"message"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":      true,
				"message": args["message"],
				"commit":  "abc1234",
			})
		},
	},
	{
		Name:        "git_diff",
		Description: "Show git diff output for the Godot project. Shows unstaged changes by default, or staged changes with staged=true.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"file":   {Type: "string", Description: "Optional: specific file to diff (res:// or relative path)"},
				"staged": {Type: "boolean", Description: "Show staged changes instead of unstaged (default: false)"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "diff": "diff --git a/scripts/player.gd ...", "files_changed": 1, "staged": false})
		},
	},
	{
		Name:        "git_log",
		Description: "Show recent git commit history for the Godot project.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"max_count": {Type: "number", Description: "Number of commits to show (default: 10, max: 100)"},
				"file":      {Type: "string", Description: "Optional: show only commits affecting this file"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":      true,
				"commits": []map[string]any{{"hash": "abc1234", "message": "Initial commit"}},
				"count":   1,
			})
		},
	},
	{
		Name:        "git_stash",
		Description: "Git stash management. Push current changes, pop the latest stash, or list all stashes.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":  {Type: "string", Description: `Stash operation: "push", "pop", or "list"`, Enum: []string{"push", "pop", "list"}},
				"message": {Type: "string", Description: "Optional message for push (e.g. \"checkpoint before refactor\")"},
			},
			Required: []string{"action"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "action": args["action"], "output": "Mock: stash operation"})
		},
	},
	{
		Name:        "run_shell_command",
		Description: "Execute a shell command in the Godot project directory. Uses OS.execute() with separate args (no shell injection). Dangerous commands (rm, sudo, etc.) are blocked.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"command": {Type: "string", Description: "Command to execute (e.g. spacetime, cargo, npm)"},
				"args":    {Type: "array", Description: "Array of command arguments", Items: &Schema{Type: "string"}},
			},
			Required: []string{"command"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "command": args["command"], "exit_code": 0, "stdout": "Mock: command output"})
		},
	},
	{
		Name:        "get_uid",
		Description: "Get the Godot UID (unique identifier) for a resource path. Useful for understanding UID references in .tscn and .tres files.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "Resource path (e.g. res://scripts/player.gd, res://scenes/main.tscn)"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "uid": "uid://abc123def456"})
		},
	},
	{
		Name:        "query_class_info",
		Description: "Get full ClassDB info for a Godot class: methods, properties, signals, enums, parent class, and instantiability. Use this to look up what a node type can do.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class_name":        {Type: "string", Description: `Godot class name (e.g. "CharacterBody2D", "AnimationPlayer", "Control")`},
				"include_inherited": {Type: "boolean", Description: "Include inherited members from parent classes (default: false)"},
			},
			Required: []string{"class_name"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":         true,
				"class_name": args["class_name"],
				"parent_class": "Node",
				"methods":    []any{},
				"properties": []any{},
				"signals":    []any{},
				"enums":      map[string]any{},
			})
		},
	},
	{
		Name:        "query_classes",
		Description: "List Godot classes from ClassDB, optionally filtered by name substring or category (node, node2d, node3d, control, resource, physics2d, physics3d, audio, animation).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"filter":            {Type: "string", Description: "Case-insensitive substring filter on class name"},
				"category":          {Type: "string", Description: `Filter by category: "node", "node2d", "node3d", "control", "resource", "physics2d", "physics3d", "audio", "animation"`, Enum: []string{"node", "node2d", "node3d", "control", "resource", "physics2d", "physics3d", "audio", "animation"}},
				"instantiable_only": {Type: "boolean", Description: "Only include classes that can be instantiated (default: false)"},
			},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "classes": []string{"Node", "Node2D", "Node3D"}, "count": 3})
		},
	},
}

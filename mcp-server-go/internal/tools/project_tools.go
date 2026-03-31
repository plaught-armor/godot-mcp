package tools

var projectTools = []ToolDef{
	{
		Name:        "proj",
		Description: "Project settings, console, debug, playback, ClassDB, export.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"action":     {Type: "string", Enum: []string{"settings", "set_setting", "node_props", "autoloads", "add_autoload", "rm_autoload", "console", "errors", "debug_errors", "clear_console", "open", "tree", "play", "stop", "running", "uid", "class_info", "classes", "export_presets", "export_info", "export_cmd"}},
				"properties": {Type: "object"},
			},
			Required: []string{"action"},
		},
		MockFn: mockOK(),
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
		Name:        "shell",
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
			return map[string]any{}
		},
	},
}

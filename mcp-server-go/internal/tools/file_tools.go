package tools

var fileTools = []ToolDef{
	{
		Name:        "list_dir",
		Description: "List files and folders under a Godot project path (e.g., res://). Returns arrays of files and folders in the specified directory.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root":           {Type: "string", Description: "Starting path like res://addons/ai_assistant or res://"},
				"include_hidden": {Type: "boolean", Description: "Include hidden files/folders (default: false)"},
			},
			Required: []string{"root"},
		},
		MockFn: func(args map[string]any) any {
			root, _ := args["root"].(string)
			if root == "" {
				root = "res://"
			}
			return map[string]any{
				"path":    root,
				"files":   []string{"project.godot", "icon.svg", "default_env.tres"},
				"folders": []string{"scenes", "scripts", "assets", "addons"},
				"_mock":   true,
				"_note":   "This is mock data. Connect Godot for real results.",
			}
		},
	},
	{
		Name:        "read_file",
		Description: "Read a text file from the Godot project, optionally a specific line range. Useful for reading GDScript files, scene files, or any text-based content.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":       {Type: "string", Description: "res:// path to the file (e.g., res://scripts/player.gd)"},
				"start_line": {Type: "number", Description: "1-based inclusive start line (optional)"},
				"end_line":   {Type: "number", Description: "Inclusive end line; 0 or missing means to end of file (optional)"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"path":       args["path"],
				"content":    "# Mock file content\nextends Node\n\nfunc _ready():\n    print(\"Hello from mock!\")",
				"line_count": 5,
				"_mock":      true,
				"_note":      "Connect Godot for real results.",
			}
		},
	},
	{
		Name:        "create_file",
		Description: "Create a new text file in the Godot project. Use for config files, shaders, data files, etc. For GDScript files, prefer create_script_file instead.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string", Description: "res:// path for the new file (e.g., res://data/config.json)"},
				"content":   {Type: "string", Description: "File content to write"},
				"overwrite": {Type: "boolean", Description: "Overwrite if file exists (default: false)"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: File would be created"})
		},
	},
	{
		Name:        "search_project",
		Description: "Search the Godot project for a substring and return file hits with line numbers. Useful for finding usages of functions, variables, or any text pattern.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"query":          {Type: "string", Description: "Substring to find"},
				"glob":           {Type: "string", Description: "Optional glob filter like **/*.gd to search only GDScript files"},
				"max_results":    {Type: "number", Description: "Maximum number of results to return (default: 200)"},
				"case_sensitive": {Type: "boolean", Description: "Case-sensitive search (default: false)"},
			},
			Required: []string{"query"},
		},
		MockFn: func(args map[string]any) any {
			query, _ := args["query"].(string)
			return map[string]any{
				"query": query,
				"matches": []map[string]any{
					{"file": "res://scripts/player.gd", "line": 10, "content": "    # Mock match for \"" + query + "\""},
				},
				"total_matches": 1,
				"_mock":         true,
				"_note":         "Connect Godot for real results.",
			}
		},
	},
	{
		Name:        "create_folder",
		Description: "Create a directory (with parent directories if needed).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "Directory path (res://path/to/folder)"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: Folder would be created"})
		},
	},
	{
		Name:        "delete_file",
		Description: "Delete a file permanently. ONLY use when explicitly requested. NEVER use to \"edit\" a file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":          {Type: "string", Description: "File to delete"},
				"confirm":       {Type: "boolean", Description: "Must be true to proceed"},
				"create_backup": {Type: "boolean", Description: "Create backup before deleting (default: true)"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: File would be deleted"})
		},
	},
	{
		Name:        "delete_folder",
		Description: "Delete a directory. By default only removes empty directories. Use recursive=true to delete a directory and all its contents. ONLY use when explicitly requested.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string", Description: "Directory path to delete (res://path/to/folder)"},
				"confirm":   {Type: "boolean", Description: "Must be true to proceed"},
				"recursive": {Type: "boolean", Description: "Delete directory and all contents (default: false)"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: Folder would be deleted"})
		},
	},
	{
		Name:        "rename_file",
		Description: "Rename or move a file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"old_path": {Type: "string", Description: "Current file path"},
				"new_path": {Type: "string", Description: "New file path"},
			},
			Required: []string{"old_path", "new_path"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "old_path": args["old_path"], "new_path": args["new_path"], "message": "Mock: File would be renamed"})
		},
	},
	{
		Name:        "replace_in_files",
		Description: "Bulk find-and-replace text across project files. Like Godot's Ctrl+Shift+R. Use preview mode first to verify scope before applying.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"search":         {Type: "string", Description: "Text to find"},
				"replace":        {Type: "string", Description: "Replacement text"},
				"glob":           {Type: "string", Description: "Glob filter (e.g. **/*.gd). Default: all text files"},
				"exclude":        {Type: "array", Description: "Glob patterns to skip (e.g. [\"**/addons/**\"])", Items: &Schema{Type: "string"}},
				"case_sensitive":  {Type: "boolean", Description: "Case-sensitive search (default: true)"},
				"preview":        {Type: "boolean", Description: "Dry-run — show what would change without writing (default: false)"},
			},
			Required: []string{"search", "replace"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{
				"ok":                 true,
				"search":            args["search"],
				"replace":           args["replace"],
				"files_modified":    3,
				"total_replacements": 7,
				"files":             []string{"res://scripts/a.gd", "res://scripts/b.gd", "res://scenes/c.tscn"},
				"preview":           args["preview"],
				"message":           "Mock: Would replace across files",
			})
		},
	},
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

package tools

var fileTools = []ToolDef{
	{
		Name:        "list_dir",
		Description: "List files and folders under a project path.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root":           {Type: "string", Description: "res:// starting path"},
				"include_hidden": {Type: "boolean", Description: "Include hidden files/folders"},
				"recursive":      {Type: "boolean", Description: "Flat recursive listing"},
				"glob":           {Type: "string", Description: "Glob filter (e.g. *.gd, **/*.tscn)"},
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
			}
		},
	},
	{
		Name:        "read_file",
		Description: "Read a text file, optionally a specific line range.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":       {Type: "string", Description: "res:// file path"},
				"start_line": {Type: "number", Description: "1-based start line"},
				"end_line":   {Type: "number", Description: "End line (0 = end of file)"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"content":    "# Mock file content\nextends Node\n\nfunc _ready():\n    print(\"Hello from mock!\")",
				"line_count": 5,
			}
		},
	},
	{
		Name:        "create_file",
		Description: "Create a text file. For .gd files, use create_script instead.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string", Description: "res:// path for the new file"},
				"content":   {Type: "string", Description: "File content"},
				"overwrite": {Type: "boolean", Description: "Overwrite if exists"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "search_project",
		Description: "Search project for a substring with line numbers.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"query":          {Type: "string", Description: "Substring to find"},
				"glob":           {Type: "string", Description: "Glob filter (e.g. **/*.gd)"},
				"max_results":    {Type: "number", Description: "Max results (default: 200)"},
				"case_sensitive": {Type: "boolean", Description: "Case-sensitive search"},
				"regex":          {Type: "boolean", Description: "Treat query as regex"},
				"exclude_dirs":   {Type: "array", Description: "Directory names to skip", Items: &Schema{Type: "string"}},
			},
			Required: []string{"query"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"matches":   []any{},
				"truncated": false,
			}
		},
	},
	{
		Name:        "create_folder",
		Description: "Create a directory (with parent directories if needed).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "res:// directory path"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "delete_file",
		Description: "Delete a file permanently.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":          {Type: "string", Description: "res:// file path"},
				"confirm":       {Type: "boolean", Description: "Must be true"},
				"create_backup": {Type: "boolean", Description: "Backup before deleting (default: true)"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "delete_folder",
		Description: "Delete a directory. recursive=true for non-empty.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string", Description: "res:// directory path"},
				"confirm":   {Type: "boolean", Description: "Must be true"},
				"recursive": {Type: "boolean", Description: "Delete all contents"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "rename_file",
		Description: "Rename or move a file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"old_path": {Type: "string", Description: "Current path"},
				"new_path": {Type: "string", Description: "New path"},
			},
			Required: []string{"old_path", "new_path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "replace_in_files",
		Description: "Bulk find-and-replace across files. Use preview=true first.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"search":         {Type: "string", Description: "Text to find"},
				"replace":        {Type: "string", Description: "Replacement text"},
				"glob":           {Type: "string", Description: "Glob filter (default: all text files)"},
				"exclude":        {Type: "array", Description: "Glob patterns to skip", Items: &Schema{Type: "string"}},
				"case_sensitive":  {Type: "boolean", Description: "Case-sensitive (default: true)"},
				"preview":        {Type: "boolean", Description: "Dry-run only"},
				"exclude_dirs":   {Type: "array", Description: "Directory names to skip", Items: &Schema{Type: "string"}},
			},
			Required: []string{"search", "replace"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"files":        []string{},
				"replacements": 0,
				"preview":      true,
			}
		},
	},
	{
		Name:        "read_files",
		Description: "Read multiple text files in a single call.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"paths":     {Type: "array", Description: "res:// paths to read", Items: &Schema{Type: "string"}},
				"max_bytes": {Type: "number", Description: "Max bytes per file (default: 200000)"},
			},
			Required: []string{"paths"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"files": []map[string]any{{"path": "res://scripts/player.gd", "content": "# mock", "line_count": 1}},
			}
		},
	},
	{
		Name:        "bulk_edit",
		Description: "Apply multiple text replacements across files in one call.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"edits": {Type: "array", Description: `Array of edit objects: [{file: "res://path", old: "old text", new: "new text"}]`, Items: &Schema{
					Type: "object",
					Properties: map[string]*Schema{
						"file": {Type: "string", Description: "res:// path to the file"},
						"old":  {Type: "string", Description: "Exact text to find and replace"},
						"new":  {Type: "string", Description: "Replacement text"},
					},
					Required: []string{"file", "old", "new"},
				}},
			},
			Required: []string{"edits"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"success_count": 1, "error_count": 0}
		},
	},
	{
		Name:        "find_references",
		Description: "Find references to a symbol (word-boundary matching).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"symbol":       {Type: "string", Description: "Symbol to find"},
				"glob":         {Type: "string", Description: "Glob filter"},
				"max_results":  {Type: "number", Description: "Max results (default: 200)"},
				"exclude_dirs": {Type: "array", Description: "Directory names to skip", Items: &Schema{Type: "string"}},
			},
			Required: []string{"symbol"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"matches": []any{}, "truncated": false}
		},
	},
	{
		Name:        "list_resources",
		Description: "Find .tres resource files, optionally filtered by type.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"type":         {Type: "string", Description: "Filter by resource class name"},
				"glob":         {Type: "string", Description: "Glob filter"},
				"exclude_dirs": {Type: "array", Description: "Directory names to skip", Items: &Schema{Type: "string"}},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"resources": []any{}}
		},
	},
}

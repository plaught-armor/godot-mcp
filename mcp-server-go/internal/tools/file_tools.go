package tools

var fileTools = []ToolDef{
	{
		Name:        "list_dir",
		Description: "List files and folders under a project path.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"root":           {Type: "string"},
				"include_hidden": {Type: "boolean"},
				"recursive":      {Type: "boolean"},
				"glob":           {Type: "string"},
			},
			Required: []string{"root"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"files": []string{}, "folders": []string{}}
		},
	},
	{
		Name:        "read_file",
		Description: "Read a text file, optionally a line range.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":       {Type: "string"},
				"start_line": {Type: "number"},
				"end_line":   {Type: "number", Description: "0 = EOF"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"content": ""}
		},
	},
	{
		Name:        "create_file",
		Description: "Create a text file. For .gd use create_script.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string"},
				"content":   {Type: "string"},
				"overwrite": {Type: "boolean"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "search_project",
		Description: "Search project files for a substring.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"query":          {Type: "string"},
				"glob":           {Type: "string"},
				"max_results":    {Type: "number"},
				"case_sensitive": {Type: "boolean"},
				"regex":          {Type: "boolean"},
				"exclude_dirs":   {Type: "array", Items: &Schema{Type: "string"}},
			},
			Required: []string{"query"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"m": []any{}, "trunc": false}
		},
	},
	{
		Name:        "create_folder",
		Description: "Create a directory with parents.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string"},
			},
			Required: []string{"path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "delete_file",
		Description: "Delete a file permanently.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":          {Type: "string"},
				"confirm":       {Type: "boolean"},
				"create_backup": {Type: "boolean"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "delete_folder",
		Description: "Delete a directory. recursive=true for non-empty.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":      {Type: "string"},
				"confirm":   {Type: "boolean"},
				"recursive": {Type: "boolean"},
			},
			Required: []string{"path", "confirm"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "rename_file",
		Description: "Rename or move a file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"old_path": {Type: "string"},
				"new_path": {Type: "string"},
			},
			Required: []string{"old_path", "new_path"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "replace_in_files",
		Description: "Bulk find-and-replace across files. preview=true for dry-run.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"search":         {Type: "string"},
				"replace":        {Type: "string"},
				"glob":           {Type: "string"},
				"exclude":        {Type: "array", Items: &Schema{Type: "string"}},
				"case_sensitive": {Type: "boolean"},
				"preview":        {Type: "boolean"},
				"exclude_dirs":   {Type: "array", Items: &Schema{Type: "string"}},
			},
			Required: []string{"search", "replace"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"replacements": 0, "preview": true}
		},
	},
	{
		Name:        "read_files",
		Description: "Read multiple text files in one call.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"paths":     {Type: "array", Items: &Schema{Type: "string"}},
				"max_bytes": {Type: "number"},
			},
			Required: []string{"paths"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"files": []any{}}
		},
	},
	{
		Name:        "bulk_edit",
		Description: "Apply multiple text replacements across files.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"edits": {Type: "array", Items: &Schema{
					Type:     "object",
					Required: []string{"file", "old", "new"},
				}},
			},
			Required: []string{"edits"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"results": []any{}}
		},
	},
	{
		Name:        "find_references",
		Description: "Find references to a symbol (word-boundary match).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"symbol":       {Type: "string"},
				"glob":         {Type: "string"},
				"max_results":  {Type: "number"},
				"exclude_dirs": {Type: "array", Items: &Schema{Type: "string"}},
			},
			Required: []string{"symbol"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"m": []any{}, "trunc": false}
		},
	},
	{
		Name:        "list_resources",
		Description: "Find .tres resource files, optionally by type.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"type":         {Type: "string"},
				"glob":         {Type: "string"},
				"exclude_dirs": {Type: "array", Items: &Schema{Type: "string"}},
			},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"resources": []any{}}
		},
	},
}

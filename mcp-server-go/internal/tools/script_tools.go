package tools

import "os/exec"

var scriptTools = []ToolDef{
	{
		Name:        "create_script",
		Description: "Create a NEW GDScript file (.gd) that does not exist yet. Use this for creating new scripts, NOT for editing existing files (use edit_script for edits).",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":    {Type: "string", Description: "Script file path (res://scripts/player.gd) - must not exist yet"},
				"content": {Type: "string", Description: "Full GDScript content to write to the file"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: Would create script"})
		},
	},
	{
		Name:        "edit_script",
		Description: `Apply a SMALL, SURGICAL code edit (1-10 lines) to GDScript files. Auto-applies changes. For large changes, call multiple times. ONLY for .gd files - NEVER for .tscn scene files.`,
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"edit": {Type: "object", Description: `Edit spec: {type: "snippet_replace", file: "res://path.gd", old_snippet: "old code", new_snippet: "new code", context_before: "line above", context_after: "line below"}. Keep old_snippet SMALL (1-10 lines).`},
			},
			Required: []string{"edit"},
		},
		MockFn: mockOK("Diff would be applied"),
	},
	{
		Name:        "validate_script",
		Description: "Validate a GDScript file for syntax errors using Godot's built-in parser. Call after creating or modifying scripts to ensure they are error-free.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "Path to the GDScript file to validate (e.g., res://scripts/player.gd)"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "path": args["path"], "valid": true, "errors": []any{}})
		},
	},
	{
		Name:        "list_scripts",
		Description: "List all GDScript files in the project with basic metadata.",
		InputSchema: &Schema{
			Type:       "object",
			Properties: map[string]*Schema{},
		},
		MockFn: func(args map[string]any) any {
			return mockNote(map[string]any{"ok": true, "scripts": []string{"res://scripts/player.gd", "res://scripts/enemy.gd"}, "count": 2})
		},
	},
}

// optionalScriptTools returns tools that depend on external binaries.
func optionalScriptTools() []ToolDef {
	var out []ToolDef
	if _, err := exec.LookPath("gdscript-formatter"); err == nil {
		out = append(out, ToolDef{
			Name:        "format_script",
			Description: "Format a GDScript file using gdscript-formatter.",
			InputSchema: &Schema{
				Type: "object",
				Properties: map[string]*Schema{
					"path": {Type: "string", Description: "Path to the GDScript file to format (e.g., res://scripts/player.gd)"},
				},
				Required: []string{"path"},
			},
			MockFn: func(args map[string]any) any {
				return mockNote(map[string]any{"ok": true, "path": args["path"], "message": "Mock: File would be formatted"})
			},
		})
	}
	return out
}

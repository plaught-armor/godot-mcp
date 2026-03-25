package tools

import "os/exec"

var scriptTools = []ToolDef{
	{
		Name:        "create_script",
		Description: "Create a new .gd file. Use edit_script for existing files.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":    {Type: "string", Description: "res:// path (must not exist yet)"},
				"content": {Type: "string", Description: "Full GDScript content"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{}
		},
	},
	{
		Name:        "edit_script",
		Description: "Apply a surgical edit (1-10 lines) to a .gd file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"edit": {Type: "object", Description: `Edit spec: {type: "snippet_replace", file: "res://path.gd", old_snippet: "old code", new_snippet: "new code", context_before: "line above", context_after: "line below"}. Keep old_snippet SMALL (1-10 lines).`},
			},
			Required: []string{"edit"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "validate_script",
		Description: "Validate a .gd file for syntax errors.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "res:// path to validate"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"valid": true, "errors": []any{}}
		},
	},
	{
		Name:        "list_scripts",
		Description: "List all .gd files in the project.",
		InputSchema: &Schema{
			Type:       "object",
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"scripts": []string{"res://scripts/player.gd", "res://scripts/enemy.gd"}}
		},
	},
	{
		Name:        "validate_scripts",
		Description: "Validate multiple .gd files in one call.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"paths": {Type: "array", Description: "res:// paths to validate", Items: &Schema{Type: "string"}},
			},
			Required: []string{"paths"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"results": []any{}}
		},
	},
	{
		Name:        "get_script_symbols",
		Description: "Extract methods, variables, and signals from a .gd file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path": {Type: "string", Description: "res:// script path"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{
				"methods":   []any{},
				"variables": []any{},
				"signals":   []any{},
			}
		},
	},
	{
		Name:        "find_class_definition",
		Description: "Find the file that defines a class_name.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class_name": {Type: "string", Description: "Class name to find"},
			},
			Required: []string{"class_name"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"file": ""}
		},
	},
}

// optionalScriptTools returns tools that depend on external binaries.
func optionalScriptTools() []ToolDef {
	var out []ToolDef
	if _, err := exec.LookPath("gdscript-formatter"); err == nil {
		out = append(out, ToolDef{
			Name:        "format_script",
			Description: "Format a .gd file with gdscript-formatter.",
			InputSchema: &Schema{
				Type: "object",
				Properties: map[string]*Schema{
					"path": {Type: "string", Description: "res:// script path"},
				},
				Required: []string{"path"},
			},
			MockFn: func(args map[string]any) any {
				return map[string]any{"changed": false}
			},
		})
	}
	return out
}

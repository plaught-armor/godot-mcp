package tools

import "os/exec"

var scriptTools = []ToolDef{
	{
		Name:        "create_script",
		Description: "Create a .gd file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"path":    {Type: "string"},
				"content": {Type: "string"},
			},
			Required: []string{"path", "content"},
		},
		MockFn: mockOK(),
	},
	{
		Name:        "edit_script",
		Description: "Apply a surgical edit (1-10 lines) to a .gd file.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"edit": {Type: "object"},
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
				"path": {Type: "string"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"valid": true, "errs": []any{}}
		},
	},
	{
		Name:        "list_scripts",
		Description: "List all .gd files in the project.",
		InputSchema: &Schema{Type: "object"},
		MockFn: func(args map[string]any) any {
			return map[string]any{"scripts": []string{}}
		},
	},
	{
		Name:        "validate_scripts",
		Description: "Validate multiple .gd files in one call.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"paths": {Type: "array", Items: &Schema{Type: "string"}},
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
				"path": {Type: "string"},
			},
			Required: []string{"path"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"methods": []any{}, "variables": []any{}, "signals": []any{}}
		},
	},
	{
		Name:        "find_class_definition",
		Description: "Find the file that defines a class_name.",
		InputSchema: &Schema{
			Type: "object",
			Properties: map[string]*Schema{
				"class_name": {Type: "string"},
			},
			Required: []string{"class_name"},
		},
		MockFn: func(args map[string]any) any {
			return map[string]any{"file": ""}
		},
	},
}

func optionalScriptTools() []ToolDef {
	var out []ToolDef
	if _, err := exec.LookPath("gdscript-formatter"); err == nil {
		out = append(out, ToolDef{
			Name:        "format_script",
			Description: "Format a .gd file with gdscript-formatter.",
			InputSchema: &Schema{
				Type: "object",
				Properties: map[string]*Schema{
					"path": {Type: "string"},
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

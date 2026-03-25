package tools

var AllTools []ToolDef

var toolIndex map[string]*ToolDef

// Categories available for dynamic tool registration.
var Categories = []string{"file", "scene", "script", "project", "git", "runtime", "asset"}

// coreTools are always registered regardless of category activation.
var coreTools = map[string]bool{
	"list_dir":        true,
	"read_file":       true,
	"read_files":      true,
	"search_project":  true,
	"create_file":     true,
	"create_script":   true,
	"edit_script":     true,
	"get_console_log": true,
	"get_errors":      true,
}

// categoryAssignment maps tool names to their category.
// Tools not listed here default to "core" if in coreTools, otherwise "project".
var categoryAssignment = map[string]string{
	// file
	"create_folder":    "file",
	"delete_file":      "file",
	"delete_folder":    "file",
	"rename_file":      "file",
	"replace_in_files": "file",
	"bulk_edit":        "file",
	"find_references":  "file",
	"list_resources":   "file",
	// scene
	"create_scene":         "scene",
	"read_scene":           "scene",
	"scene_edit": "scene",
	"attach_script":        "scene",
	"detach_script":        "scene",
	"set_collision_shape":  "scene",
	"set_sprite_texture":   "scene",
	"set_typed_property":   "scene",
	"get_scene_hierarchy":  "scene",
	// script
	"validate_script":       "script",
	"validate_scripts":      "script",
	"list_scripts":          "script",
	"get_script_symbols":    "script",
	"find_class_definition": "script",
	"format_script":         "script",
	// project
	"get_project_settings":  "project",
	"set_project_setting":   "project",
	"get_autoloads":         "project",
	"get_input_map":         "project",
	"configure_input_map":   "project",
	"get_collision_layers":  "project",
	"get_node_properties":   "project",
	"get_debug_errors":      "project",
	"clear_console_log":     "project",
	"open_in_godot":         "project",
	"scene_tree_dump":       "project",
	"play_project":          "project",
	"stop_project":          "project",
	"is_project_running":    "project",
	"get_uid":               "project",
	"query_class_info":      "project",
	"query_classes":         "project",
	"map_project":           "project",
	"map_scenes":            "project",
	// git
	"git":              "git",
	"run_shell_command": "git",
	// runtime
	"capture_screenshot":     "runtime",
	"inspect_runtime_tree":   "runtime",
	"get_runtime_property":   "runtime",
	"set_runtime_property":   "runtime",
	"call_runtime_method":    "runtime",
	"get_runtime_metrics":    "runtime",
	"inject_input":  "runtime",
	"signal_watch":  "runtime",
	// asset
	"generate_2d_asset": "asset",
}

func init() {
	opt := optionalScriptTools()
	total := len(fileTools) + len(sceneTools) + len(scriptTools) + len(opt) + len(projectTools) + len(assetTools) + len(runtimeTools)
	AllTools = make([]ToolDef, 0, total)
	AllTools = append(AllTools, fileTools...)
	AllTools = append(AllTools, sceneTools...)
	AllTools = append(AllTools, scriptTools...)
	AllTools = append(AllTools, opt...)
	AllTools = append(AllTools, projectTools...)
	AllTools = append(AllTools, assetTools...)
	AllTools = append(AllTools, runtimeTools...)

	// Assign categories
	for i := range AllTools {
		name := AllTools[i].Name
		if coreTools[name] {
			AllTools[i].Category = "core"
		} else if cat, ok := categoryAssignment[name]; ok {
			AllTools[i].Category = cat
		} else {
			AllTools[i].Category = "project" // default
		}
	}

	toolIndex = make(map[string]*ToolDef, len(AllTools))
	for i := range AllTools {
		toolIndex[AllTools[i].Name] = &AllTools[i]
	}
}

// IsCore returns true if the tool is always-on.
func IsCore(name string) bool {
	return coreTools[name]
}

// ByCategory returns all tool defs for a given category.
func ByCategory(cat string) []*ToolDef {
	var out []*ToolDef
	for i := range AllTools {
		if AllTools[i].Category == cat {
			out = append(out, &AllTools[i])
		}
	}
	return out
}

// Exists returns true if a tool with the given name is registered.
func Exists(name string) bool {
	_, ok := toolIndex[name]
	return ok
}

// Get returns the tool definition for the given name, or nil.
func Get(name string) *ToolDef {
	return toolIndex[name]
}

// GetMockResponse returns the mock response for a tool.
func GetMockResponse(name string, args map[string]any) any {
	td := toolIndex[name]
	if td == nil {
		return map[string]any{"error": "Unknown tool: " + name}
	}
	return td.MockFn(args)
}

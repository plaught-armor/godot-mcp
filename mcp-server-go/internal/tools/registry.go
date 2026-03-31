package tools

var AllTools []ToolDef

var toolIndex map[string]*ToolDef

// Categories available for dynamic tool registration.
var Categories = []string{"file", "scene", "script", "project", "git", "runtime", "asset", "physics", "tilemap", "theme", "resource", "profiling", "input", "animation", "shader", "scene3d", "navigation", "audio", "particle", "analysis"}

// coreTools are always registered regardless of category activation.
var coreTools = map[string]bool{
	"file":   true,
	"script": true,
	"proj":   true,
}

// categoryAssignment maps tool names to their category.
// Tools not listed here default to "core" if in coreTools, otherwise "project".
var categoryAssignment = map[string]string{
	// file
	"file": "file",
	// scene
	"scene": "scene",
	// script
	"script": "script",
	// project
	"proj": "project",
	// git
	"git":   "git",
	"shell": "git",
	// runtime
	"rt": "runtime",
	// asset
	"generate_2d_asset": "asset",
	// consolidated
	"phys":    "physics",
	"tmap":    "tilemap",
	"theme":   "theme",
	"tres":    "resource",
	"perf":    "profiling",
	"input":   "input",
	"anim":    "animation",
	"shader":  "shader",
	"s3d":     "scene3d",
	"nav":     "navigation",
	"audio":   "audio",
	"ptcl":    "particle",
	"analyze": "analysis",
}

func init() {
	AllTools = make([]ToolDef, 0, 30)
	AllTools = append(AllTools, fileTools...)
	AllTools = append(AllTools, sceneTools...)
	AllTools = append(AllTools, scriptTools...)
	AllTools = append(AllTools, projectTools...)
	AllTools = append(AllTools, assetTools...)
	AllTools = append(AllTools, runtimeTools...)
	AllTools = append(AllTools, physicsTools...)
	AllTools = append(AllTools, tilemapTools...)
	AllTools = append(AllTools, themeTools...)
	AllTools = append(AllTools, resourceTools...)
	AllTools = append(AllTools, profilingTools...)
	AllTools = append(AllTools, inputTools...)
	AllTools = append(AllTools, animationTools...)
	AllTools = append(AllTools, shaderTools...)
	AllTools = append(AllTools, scene3dTools...)
	AllTools = append(AllTools, navigationTools...)
	AllTools = append(AllTools, audioTools...)
	AllTools = append(AllTools, particleTools...)
	AllTools = append(AllTools, analysisTools...)

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
		return map[string]any{"err": "Unknown tool: " + name}
	}
	return td.MockFn(args)
}

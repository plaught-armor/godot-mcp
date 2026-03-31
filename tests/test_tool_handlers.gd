extends RefCounted
## Tests that core addon scripts load correctly in headless mode.
## Note: @tool scripts that depend on class_names (ToolUtils, etc.) cannot be
## instantiated outside --editor context. These tests verify the non-@tool scripts
## and the runtime/debugger/client scripts which don't have class_name dependencies.


func test_mcp_runtime_load_and_instantiate() -> String:
	var script: GDScript = load("res://addons/godot_mcp/mcp_runtime.gd")
	if script == null:
		return "Failed to load mcp_runtime.gd"
	var instance: Node = script.new()
	if instance == null:
		return "Failed to instantiate mcp_runtime"
	instance.free()
	return ""


func test_mcp_debugger_load() -> String:
	var script: GDScript = load("res://addons/godot_mcp/mcp_debugger.gd")
	if script == null:
		return "Failed to load mcp_debugger.gd"
	return ""


func test_reconnect_helper_load() -> String:
	var script: GDScript = load("res://addons/godot_mcp/reconnect_helper.gd")
	if script == null:
		return "Failed to load reconnect_helper.gd"
	return ""


func test_tool_scripts_exist() -> String:
	var expected: PackedStringArray = [
		"file_tools.gd", "scene_tools.gd", "script_tools.gd", "project_tools.gd",
		"analysis_tools.gd", "profiling_tools.gd", "animation_tools.gd",
		"physics_tools.gd", "tilemap_tools.gd", "theme_tools.gd",
		"resource_tools.gd", "input_tools.gd", "shader_tools.gd",
		"scene3d_tools.gd", "navigation_tools.gd", "audio_tools.gd",
		"particle_tools.gd", "asset_tools.gd", "visualizer_tools.gd",
		"tool_utils.gd",
	]
	for file: String in expected:
		if not FileAccess.file_exists("res://addons/godot_mcp/tools/" + file):
			return "Missing tool file: " + file
	return ""

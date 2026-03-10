@tool
extends RefCounted
class_name ToolExecutor
## Routes tool invocations to the appropriate handler.

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils
var _file_tools: FileTools
var _scene_tools: SceneTools
var _script_tools: ScriptTools
var _project_tools: ProjectTools
var _asset_tools: AssetTools
var _visualizer_tools: VisualizerTools
var _initialized := false


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

	# Initialize tools first (must be done synchronously)
	_init_tools()

	# Pass shared utils and editor plugin reference to all tool handlers
	_utils.set_editor_plugin(plugin)
	for tool_node: RefCounted in [_file_tools, _scene_tools, _script_tools, _project_tools, _asset_tools, _visualizer_tools]:
		if tool_node:
			tool_node.set_utils(_utils)
			tool_node.set_editor_plugin(plugin)


func execute_tool(tool_name: StringName, args: Dictionary) -> Dictionary:
	"""Execute a tool by name with the given arguments."""
	var handler := _get_handler(tool_name)
	if handler == null:
		return {&"ok": false, &"error": "Unknown tool: " + tool_name}

	if not handler.has_method(tool_name):
		push_error("[MCP] Handler has no method '%s'" % tool_name)
		return {&"ok": false, &"error": "Handler missing method: " + tool_name}

	var result = handler.call(tool_name, args)

	# GDScript runtime errors (null deref, bad type) print to console but
	# don't throw — they return null. Catch that here so the Go bridge
	# gets a proper error response instead of a 30s timeout.
	if result == null:
		push_error("[MCP] Tool '%s' returned null (likely a runtime error — check console above)" % tool_name)
		return {&"ok": false, &"error": "Tool crashed or returned null: " + tool_name}
	if result is not Dictionary:
		push_error("[MCP] Tool '%s' returned non-Dictionary: %s" % [tool_name, typeof(result)])
		return {&"ok": false, &"error": "Tool returned invalid type: " + tool_name}
	return result


func _get_handler(tool_name: StringName) -> RefCounted:
	"""Match a tool name to its handler."""
	match tool_name:
		# File tools
		&"list_dir", &"read_file", &"create_file", &"search_project", \
		&"create_folder", &"delete_file", &"delete_folder", \
		&"rename_file", &"replace_in_files":
			return _file_tools

		# Scene tools
		&"create_scene", &"read_scene", &"add_node", &"remove_node", \
		&"modify_node_property", &"rename_node", &"move_node", \
		&"attach_script", &"detach_script", \
		&"set_collision_shape", &"set_sprite_texture", \
		&"get_scene_hierarchy", &"get_scene_node_properties", \
		&"set_scene_node_property", \
		&"duplicate_node", &"reorder_node":
			return _scene_tools

		# Script tools
		&"create_script", &"edit_script", &"validate_script", &"list_scripts", \
		&"create_script_file", &"modify_variable", &"modify_signal", \
		&"modify_function", &"modify_function_delete", \
		&"delete_script", &"rename_script", &"format_script":
			return _script_tools

		# Project/debug tools
		&"get_project_settings", &"set_project_setting", \
		&"get_input_map", &"configure_input_map", &"get_collision_layers", \
		&"get_node_properties", &"get_console_log", &"get_errors", \
		&"get_debug_errors", &"clear_console_log", &"open_in_godot", \
		&"scene_tree_dump", \
		&"play_project", &"stop_project", &"is_project_running", \
		&"git_status", &"git_commit":
			return _project_tools

		# Asset tools
		&"generate_2d_asset":
			return _asset_tools

		# Visualizer tools
		&"map_project", &"map_scenes":
			return _visualizer_tools

	return null


func _init_tools() -> void:
	"""Initialize all tool handlers. Called from set_editor_plugin."""
	if _initialized:
		return
	_initialized = true

	_utils = ToolUtils.new()

	_file_tools = preload("res://addons/godot_mcp/tools/file_tools.gd").new()
	_scene_tools = preload("res://addons/godot_mcp/tools/scene_tools.gd").new()
	_script_tools = preload("res://addons/godot_mcp/tools/script_tools.gd").new()
	_project_tools = preload("res://addons/godot_mcp/tools/project_tools.gd").new()
	_asset_tools = preload("res://addons/godot_mcp/tools/asset_tools.gd").new()
	_visualizer_tools = preload("res://addons/godot_mcp/tools/visualizer_tools.gd").new()

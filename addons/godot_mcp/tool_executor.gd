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
var _profiling_tools: ProfilingTools
var _theme_tools: ThemeTools
var _tilemap_tools: TilemapTools
var _resource_tools: ResourceTools
var _input_tools: InputTools
var _physics_tools: PhysicsTools
var _animation_tools: AnimationTools
var _shader_tools: ShaderTools
var _scene3d_tools: Scene3DTools
var _navigation_tools: NavigationTools
var _audio_tools: AudioTools
var _particle_tools: ParticleTools
var _analysis_tools: AnalysisTools
var _initialized: bool = false


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

	# Initialize tools first (must be done synchronously)
	_init_tools()

	# Pass shared utils and editor plugin reference to all tool handlers
	_utils.set_editor_plugin(plugin)
	for tool_node: RefCounted in [_file_tools, _scene_tools, _script_tools, _project_tools, _asset_tools, _visualizer_tools, _profiling_tools, _theme_tools, _tilemap_tools, _resource_tools, _input_tools, _physics_tools, _animation_tools, _shader_tools, _scene3d_tools, _navigation_tools, _audio_tools, _particle_tools, _analysis_tools]:
		if tool_node:
			tool_node.set_utils(_utils)
			tool_node.set_editor_plugin(plugin)


## Execute a tool by name with the given arguments.
func execute_tool(tool_name: StringName, args: Dictionary) -> Dictionary:
	var handler: RefCounted = _get_handler(tool_name)
	if handler == null:
		return { &"err": "Unknown tool: " + tool_name, &"sug": "Use get_godot_status to see available tools and categories" }

	if not handler.has_method(tool_name):
		push_error("[GMCP] Handler has no method '%s'" % tool_name)
		return { &"err": "Handler missing method: " + tool_name }

	var result: Variant = handler.call(tool_name, args)

	# GDScript runtime errors (null deref, bad type) print to console but
	# don't throw — they return null. Catch that here so the Go bridge
	# gets a proper error response instead of a 30s timeout.
	if result == null:
		push_error("[GMCP] Tool '%s' returned null (likely a runtime error — check console above)" % tool_name)
		return { &"err": "Tool crashed or returned null: " + tool_name, &"sug": "Check the Godot console for details with get_console_log" }
	if result is not Dictionary:
		push_error("[GMCP] Tool '%s' returned non-Dictionary: %s" % [tool_name, typeof(result)])
		return { &"err": "Tool returned invalid type: " + tool_name }
	return result


## Match a tool name to its handler.
func _get_handler(tool_name: StringName) -> RefCounted:
	match tool_name:
		# File tools
		&"list_dir", &"read_file", &"read_files", &"create_file", &"search_project", &"create_folder", &"delete_file", &"delete_folder", &"rename_file", &"replace_in_files", &"bulk_edit", &"find_references", &"list_resources":
			return _file_tools

		# Scene tools
		&"scene_edit", &"create_scene", &"read_scene", &"attach_script", &"detach_script", &"set_sprite_texture", &"get_scene_hierarchy", &"get_scene_node_properties", &"set_scene_node_property":
			return _scene_tools

		# Script tools
		&"create_script", &"edit_script", &"validate_script", &"validate_scripts", &"list_scripts", &"create_script_file", &"modify_variable", &"modify_signal", &"modify_function", &"modify_function_delete", &"delete_script", &"rename_script", &"format_script", &"get_script_symbols", &"find_class_definition":
			return _script_tools

		# Project/debug tools
		&"get_project_settings", &"set_project_setting", &"get_autoloads", &"get_node_properties", &"get_console_log", &"get_errors", &"get_debug_errors", &"clear_console_log", &"open_in_godot", &"scene_tree_dump", &"play_project", &"stop_project", &"is_project_running", &"git", &"run_shell_command", &"get_uid", &"query_class_info", &"query_classes":
			return _project_tools

		# Asset tools
		&"generate_2d_asset":
			return _asset_tools

		# Visualizer tools
		&"map_project", &"map_scenes":
			return _visualizer_tools

		# Consolidated tools
		&"perf":
			return _profiling_tools
		&"theme":
			return _theme_tools
		&"tmap":
			return _tilemap_tools
		&"res":
			return _resource_tools
		&"input":
			return _input_tools
		&"phys":
			return _physics_tools
		&"anim":
			return _animation_tools
		&"shader":
			return _shader_tools
		&"s3d":
			return _scene3d_tools
		&"nav":
			return _navigation_tools
		&"audio":
			return _audio_tools
		&"ptcl":
			return _particle_tools
		&"analyze":
			return _analysis_tools

	return null


## Initialize all tool handlers. Called from [method set_editor_plugin].
func _init_tools() -> void:
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
	_profiling_tools = preload("res://addons/godot_mcp/tools/profiling_tools.gd").new()
	_theme_tools = preload("res://addons/godot_mcp/tools/theme_tools.gd").new()
	_tilemap_tools = preload("res://addons/godot_mcp/tools/tilemap_tools.gd").new()
	_resource_tools = preload("res://addons/godot_mcp/tools/resource_tools.gd").new()
	_input_tools = preload("res://addons/godot_mcp/tools/input_tools.gd").new()
	_physics_tools = preload("res://addons/godot_mcp/tools/physics_tools.gd").new()
	_animation_tools = preload("res://addons/godot_mcp/tools/animation_tools.gd").new()
	_shader_tools = preload("res://addons/godot_mcp/tools/shader_tools.gd").new()
	_scene3d_tools = preload("res://addons/godot_mcp/tools/scene3d_tools.gd").new()
	_navigation_tools = preload("res://addons/godot_mcp/tools/navigation_tools.gd").new()
	_audio_tools = preload("res://addons/godot_mcp/tools/audio_tools.gd").new()
	_particle_tools = preload("res://addons/godot_mcp/tools/particle_tools.gd").new()
	_analysis_tools = preload("res://addons/godot_mcp/tools/analysis_tools.gd").new()

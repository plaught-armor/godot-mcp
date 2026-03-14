@tool
extends EditorPlugin
## Godot MCP Plugin
## Connects to the godot-mcp-server via WebSocket and executes tools.

const MCPClientScript = preload("res://addons/godot_mcp/mcp_client.gd")
const ToolExecutorScript = preload("res://addons/godot_mcp/tool_executor.gd")


# Tools safe to run on a background thread (pure read, no editor API calls).
# Everything else runs on the main thread (filesystem refresh, editor UI, etc.).
func _is_background_safe(tool_name: StringName) -> bool:
	match tool_name:
		&"list_dir", &"read_file", &"read_files", &"search_project", &"find_references", &"list_resources", &"list_scripts", &"get_script_symbols", &"find_class_definition", &"get_autoloads", &"get_uid", &"query_class_info", &"query_classes", &"map_scenes", &"git_status", &"git_diff", &"git_log":
			return true
	return false


var _mcp_client: MCPClient # MCPClient
var _tool_executor: ToolExecutor # ToolExecutor
var _status_label: Label
var _thread: Thread
var _mutex: Mutex
var _pending_requests: Array = [] # [{id, tool, args}]
var _thread_running := false


func _enter_tree() -> void:
	print("[GMCP] Plugin loading...")

	_register_settings()
	_mutex = Mutex.new()

	# Create MCP client
	_mcp_client = MCPClientScript.new()
	_mcp_client.name = "MCPClient"
	add_child(_mcp_client)

	# Create tool executor
	_tool_executor = ToolExecutorScript.new()
	_tool_executor.set_editor_plugin(self)

	# Connect signals
	_mcp_client.connected.connect(_on_connected)
	_mcp_client.disconnected.connect(_on_disconnected)
	_mcp_client.tool_requested.connect(_on_tool_requested)
	_mcp_client.visualizer_opened.connect(
		func(url: String):
			print_rich("[GMCP] Project visualizer available at [url]%s[/url]" % url)
	)
	_mcp_client.visualizer_failed.connect(
		func(err: String):
			push_error("[GMCP] Visualizer failed: ", err)
	)

	# Add status indicator and menu items to editor
	_setup_status_indicator()
	add_tool_menu_item("GMCP: Map Project", _on_map_project_pressed)

	# Register runtime autoload (persists in project.godot)
	add_autoload_singleton("MCPRuntime", "res://addons/godot_mcp/mcp_runtime.gd")

	# Start connection
	_mcp_client.connect_to_server()

	print("[GMCP] Plugin loaded - connecting to MCP server...")


func _exit_tree() -> void:
	print("[GMCP] Plugin unloading...")

	# Stop accepting new work and wait for the background thread to finish
	_thread_running = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

	if _mcp_client:
		_mcp_client.disconnect_from_server()
		_mcp_client.queue_free()

	_tool_executor = null

	if _status_label:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
		_status_label.queue_free()

	remove_tool_menu_item("GMCP: Map Project")
	remove_autoload_singleton("MCPRuntime")
	_unregister_settings()

	print("[GMCP] Plugin unloaded")


const SETTINGS := {
	&"godot_mcp/auto_format_scripts": {
		&"type": TYPE_BOOL,
		&"default": false,
		&"hint": PROPERTY_HINT_NONE,
		&"hint_string": "",
		&"description": "Automatically format GDScript files after MCP tool edits.",
	},
	&"godot_mcp/script_formatter_command": {
		&"type": TYPE_STRING,
		&"default": "gdscript-formatter",
		&"hint": PROPERTY_HINT_NONE,
		&"hint_string": "",
		&"description": "Command to run for GDScript formatting (e.g., gdscript-formatter, gdformat).",
	},
}


func _register_settings() -> void:
	for path: StringName in SETTINGS:
		var info: Dictionary = SETTINGS[path]
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, info[&"default"])
		ProjectSettings.set_initial_value(path, info[&"default"])
		ProjectSettings.set_as_basic(path, true)
		ProjectSettings.add_property_info(
			{
				&"name": path,
				&"type": info[&"type"],
				&"hint": info[&"hint"],
				&"hint_string": info[&"hint_string"],
			},
		)


func _unregister_settings() -> void:
	for path: StringName in SETTINGS:
		if ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, null)


## Add a small status label to the editor toolbar.
func _setup_status_indicator() -> void:
	_status_label = Label.new()
	_status_label.text = "GMCP: Connecting..."
	_status_label.add_theme_color_override(&"font_color", Color.YELLOW)
	_status_label.add_theme_font_size_override(&"font_size", 12)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)


func _on_connected() -> void:
	print("[GMCP] Connected to MCP server")
	if _status_label:
		_status_label.text = "GMCP: Connected"
		_status_label.add_theme_color_override(&"font_color", Color.GREEN)


func _on_disconnected() -> void:
	print("[GMCP] Disconnected from MCP server")
	if _status_label:
		_status_label.text = "GMCP: Disconnected"
		_status_label.add_theme_color_override(&"font_color", Color.RED)


## Handle incoming tool request from MCP server.
func _on_tool_requested(request_id: String, tool_name: String, args: Dictionary) -> void:
	print("[GMCP] Executing tool: ", tool_name)

	# Only pure-read tools go to the background thread; everything else
	# stays on the main thread (filesystem refresh, editor UI, etc.).
	if not _is_background_safe(tool_name):
		var result: Dictionary = _tool_executor.execute_tool(tool_name, args)
		_send_result(request_id, result)
		return

	# Queue for background execution
	_mutex.lock()
	_pending_requests.append({ &"id": request_id, &"tool": tool_name, &"args": args })
	_mutex.unlock()

	_ensure_thread_running()


func _ensure_thread_running() -> void:
	# Use our own flag — Thread.is_started() stays true until wait_to_finish()
	if _thread_running:
		return
	# Previous thread finished — clean it up before starting a new one
	if _thread:
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread_running = true
	_thread.start(_thread_loop)


func _thread_loop() -> void:
	while _thread_running:
		# Swap the whole queue out under the lock — O(1) instead of O(n) pop_front
		_mutex.lock()
		if _pending_requests.is_empty():
			_mutex.unlock()
			_thread_running = false
			return
		var batch: Array = _pending_requests
		_pending_requests = []
		_mutex.unlock()

		for req: Dictionary in batch:
			var result: Dictionary = _tool_executor.execute_tool(req[&"tool"], req[&"args"])
			_send_result.call_deferred(req[&"id"], result)


func _send_result(request_id: String, result: Dictionary) -> void:
	if result[&"ok"]:
		result.erase(&"ok")
		_mcp_client.send_tool_result(request_id, true, result)
	else:
		_mcp_client.send_tool_result(request_id, false, null, result[&"error"])


func _on_map_project_pressed() -> void:
	if not _mcp_client.is_connected_to_server():
		push_warning("[GMCP] Cannot map project — not connected to MCP server")
		return
	# Run map_project on a background thread to avoid blocking the editor
	var thread := Thread.new()
	thread.start(
		func():
			var result: Dictionary = _tool_executor.execute_tool(&"map_project", { })
			if result[&"ok"]:
				_send_visualizer_data.call_deferred(result[&"project_map"], thread)
			else:
				push_error("[GMCP] Map project failed: ", result[&"error"])
				_cleanup_thread.call_deferred(thread)
	)


func _send_visualizer_data(project_map: Dictionary, thread: Thread) -> void:
	_mcp_client.send_visualizer_request(project_map)
	thread.wait_to_finish()


func _cleanup_thread(thread: Thread) -> void:
	thread.wait_to_finish()

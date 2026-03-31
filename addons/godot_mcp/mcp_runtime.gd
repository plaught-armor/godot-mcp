extends Node
## MCP Runtime Bridge — runs as an autoload inside the game process.
## Communicates with the editor via Godot's EngineDebugger IPC channel.
## No networking — messages flow through the debugger protocol automatically.

const MAX_DEPTH_DEFAULT: int = 3
const MAX_DEPTH_LIMIT: int = 10
const MAX_EMISSIONS: int = 500
const MAX_LOG_ENTRIES: int = 1000

# Signal watching: key = "node_path::signal_name", value = callable used to connect
var _watched_signals: Dictionary = {} # {String: Callable}
var _signal_emissions: Array[Dictionary] = [] # [{node_path, signal_name, args, timestamp}]

# Property watching
var _watched_properties: Dictionary = {} # {String: Dictionary} key = "node_path::property"
var _property_changes: Array[Dictionary] = []

# Explore camera
var _explore_camera: Camera3D = null
var _original_camera: Camera3D = null

# Runtime logger
var _log_buffer: Array[Dictionary] = []


func _ready() -> void:
	# Prevent game window from stealing focus when launched via MCP play_project.
	# The editor plugin sets this meta before calling play — cleared after read.
	if ProjectSettings.has_setting("godot_mcp/mcp_launched"):
		ProjectSettings.set_setting("godot_mcp/mcp_launched", false)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)

	if not EngineDebugger.is_active():
		print("[MCPRuntime] No debugger attached — runtime tools disabled")
		return

	set_physics_process(false)
	EngineDebugger.register_message_capture(&"mcp", _on_debug_message)
	# Defer runtime_ready so the editor's EditorDebuggerPlugin has time to register
	_send_ready.call_deferred()
	print("[MCPRuntime] EngineDebugger capture registered")


func _send_ready() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message(&"mcp:runtime_ready", [])


func _exit_tree() -> void:
	_restore_explore_camera()
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture(&"mcp")


## EngineDebugger message callback. Called from debugger thread — prefix "mcp:" is stripped.
## Defers to main thread since tool handlers need SceneTree access.
func _on_debug_message(message: String, data: Array) -> bool:
	match message:
		&"invoke_tool":
			var request_id: String = data[0]
			var tool_name: String = data[1]
			var args_json: String = data[2]
			_dispatch_tool.call_deferred(request_id, tool_name, args_json)
			return true
	return false


func _dispatch_tool(request_id: String, tool_name: String, args_json: String) -> void:
	var parsed: Variant = JSON.parse_string(args_json) if not args_json.is_empty() else {}
	var args: Dictionary = parsed if parsed is Dictionary else {}
	args.merge(args.get(&"properties", {}))
	var action: String = args.get(&"action", tool_name)
	# Async actions
	if action == &"screenshot" or action == &"cam_capture":
		if action == &"cam_capture" and _explore_camera == null:
			_send_result(request_id, {&"err": "No explore camera — spawn first"})
			return
		_capture_screenshot_async(request_id)
		return
	if action == &"input" and args.has(&"track"):
		_inject_input_tracked_async(request_id, args)
		return
	_send_result(request_id, _execute(action, args))


func _execute(action: String, args: Dictionary) -> Dictionary:
	match action:
		&"tree":
			return _inspect_tree(args)
		&"prop":
			return _get_property(args)
		&"set_prop":
			return _set_property(args)
		&"call":
			return _call_method(args)
		&"metrics":
			return _get_metrics()
		&"input":
			return _dispatch_inject_input(args)
		&"sig_watch":
			return _dispatch_signal_watch(args)
		&"prop_watch":
			return _dispatch_runtime_watch(args)
		&"ui":
			return _map_ui(args)
		&"cam_spawn":
			return _explore_spawn(args)
		&"cam_move":
			return _explore_move(args)
		&"cam_restore":
			_restore_explore_camera()
			return {}
		&"nav":
			return _dispatch_runtime_nav(args)
		&"log":
			return _dispatch_runtime_log(args)
	return {&"err": "Unknown rt action: " + action}


# =============================================================================
# capture_screenshot
# =============================================================================
func _capture_screenshot_async(id: String) -> void:
	_send_result(id, await _capture_viewport())


func _capture_viewport() -> Dictionary:
	await RenderingServer.frame_post_draw
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return {&"err": "No viewport available"}
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {&"err": "Failed to capture viewport image"}
	var png_data: PackedByteArray = img.save_png_to_buffer()
	if png_data.is_empty():
		return {&"err": "Failed to encode PNG"}
	return {&"img": Marshalls.raw_to_base64(png_data), &"width": img.get_width(), &"height": img.get_height()}


# =============================================================================
# inspect_runtime_tree
# =============================================================================
func _inspect_tree(args: Dictionary) -> Dictionary:
	var root_path: String = args.get(&"root_path", "/root")
	var max_depth: int = clampi(args.get(&"max_depth", MAX_DEPTH_DEFAULT), 1, MAX_DEPTH_LIMIT)

	var root: Node = get_tree().root.get_node_or_null(root_path)
	if root == null:
		return {&"err": "Node not found: " + root_path}

	return {&"tree": _serialize_node_tree(root, 0, max_depth)}


func _serialize_node_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result: Dictionary = _serialize_node(node)
	if depth < max_depth and node.get_child_count() > 0:
		var children: Array[Dictionary] = []
		for child: Node in node.get_children():
			children.append(_serialize_node_tree(child, depth + 1, max_depth))
		result[&"children"] = children
	elif depth >= max_depth:
		var child_count: int = node.get_child_count()
		if child_count > 0:
			result[&"child_count"] = child_count
	return result


func _serialize_node(node: Node) -> Dictionary:
	var result: Dictionary = {
		&"name": node.name,
		&"type": node.get_class(),
		&"path": str(node.get_path()),
	}
	var script: Variant = node.get_script()
	if script:
		result[&"script"] = script.resource_path
	return result


# =============================================================================
# get_runtime_property
# =============================================================================
func _get_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return {&"err": "Node not found: " + node_path}

	var value: Variant = node.get(property)
	return {&"value": _serialize_value(value)}


# =============================================================================
# set_runtime_property
# =============================================================================
func _set_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return {&"err": "Node not found: " + node_path}

	var old_value: Variant = node.get(property)
	node.set(property, _deserialize_value(args[&"value"]))

	return {&"old": _serialize_value(old_value)}


# =============================================================================
# call_runtime_method
# =============================================================================
func _call_method(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var method: String = args[&"method"]
	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return {&"err": "Node not found: " + node_path}

	if not node.has_method(method):
		return {&"err": "Method not found: " + method + " on " + node_path}

	var deserialized: Array = []
	for arg: Variant in args.get(&"args", []):
		deserialized.append(_deserialize_value(arg))

	var result: Variant = node.callv(method, deserialized)
	return {&"result": _serialize_value(result)}


# =============================================================================
# get_runtime_metrics
# =============================================================================
func _get_metrics() -> Dictionary:
	return {
		&"fps": Performance.get_monitor(Performance.TIME_FPS),
		&"frame_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		&"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		&"memory": {
			&"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			&"static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		},
		&"objects": {
			&"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			&"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
			&"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			&"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		},
		&"render": {
			&"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			&"total_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			&"total_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			&"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		},
		&"physics": {
			&"active_2d": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
			&"pairs_2d": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
			&"islands_2d": Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
			&"active_3d": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			&"pairs_3d": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			&"islands_3d": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		},
		&"navigation": {
			&"maps": Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS),
			&"regions": Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT),
			&"agents": Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT),
			&"links": Performance.get_monitor(Performance.NAVIGATION_LINK_COUNT),
		},
	}


# =============================================================================
# inject_input dispatcher
# =============================================================================
func _dispatch_inject_input(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var input_type: String = args[&"type"]
	match input_type:
		&"action":
			return _inject_action(args)
		&"key":
			return _inject_key(args)
		&"mouse_click":
			return _inject_mouse_click(args)
		&"mouse_motion":
			return _inject_mouse_motion(args)
	return {&"err": "Unknown input type: " + input_type + " (use action, key, mouse_click, or mouse_motion)"}


# =============================================================================
# signal_watch dispatcher
# =============================================================================
func _dispatch_signal_watch(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var sig_action: String = args[&"action"]
	match sig_action:
		&"watch":
			return _watch_signal(args)
		&"unwatch":
			return _unwatch_signal(args)
		&"get_emissions":
			return _get_signal_emissions(args)
	return {&"err": "Unknown signal_watch action: " + sig_action + " (use watch, unwatch, or get_emissions)"}


# =============================================================================
# inject_action
# =============================================================================
func _inject_action(args: Dictionary) -> Dictionary:
	var action: String = args[&"action"]
	var pressed: bool = args.get(&"pressed", true)
	var strength: float = args.get(&"strength", 1.0)

	if not InputMap.has_action(action):
		return {&"err": "Unknown action: " + action}

	if pressed:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

	return {}


# =============================================================================
# inject_key
# =============================================================================
func _inject_key(args: Dictionary) -> Dictionary:
	var keycode_str: String = args[&"keycode"]
	var keycode: int = OS.find_keycode_from_string(keycode_str)
	if keycode == KEY_NONE:
		return {&"err": "Unknown keycode: " + keycode_str}

	var pressed: bool = args.get(&"pressed", true)
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	ev.shift_pressed = args.get(&"shift", false)
	ev.ctrl_pressed = args.get(&"ctrl", false)
	ev.alt_pressed = args.get(&"alt", false)
	ev.meta_pressed = args.get(&"meta", false)
	Input.parse_input_event(ev)

	return {}


# =============================================================================
# inject_mouse_click
# =============================================================================
func _inject_mouse_click(args: Dictionary) -> Dictionary:
	var x: float = args[&"x"]
	var y: float = args[&"y"]
	var button: String = args.get(&"button", "left")

	var button_index: int
	match button:
		&"left":
			button_index = MOUSE_BUTTON_LEFT
		&"right":
			button_index = MOUSE_BUTTON_RIGHT
		&"middle":
			button_index = MOUSE_BUTTON_MIDDLE
		_:
			return {&"err": "Unknown button: " + button + " (use left, right, or middle)"}

	var pos: Vector2 = Vector2(x, y)

	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = button_index
	ev.pressed = true
	Input.parse_input_event(ev)
	var release: InputEventMouseButton = ev.duplicate()
	release.pressed = false
	Input.parse_input_event(release)

	return {}


# =============================================================================
# inject_mouse_motion
# =============================================================================
func _inject_mouse_motion(args: Dictionary) -> Dictionary:
	var rel_x: float = args.get(&"relative_x", 0.0)
	var rel_y: float = args.get(&"relative_y", 0.0)
	var pos_x: float = args.get(&"position_x", 0.0)
	var pos_y: float = args.get(&"position_y", 0.0)

	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(rel_x, rel_y)
	ev.position = Vector2(pos_x, pos_y)
	ev.global_position = Vector2(pos_x, pos_y)
	Input.parse_input_event(ev)

	return {}


# =============================================================================
# watch_signal
# =============================================================================
func _watch_signal(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var signal_name: String = args[&"signal_name"]
	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return {&"err": "Node not found: " + node_path}

	if not node.has_signal(signal_name):
		return {&"err": "Signal not found: " + signal_name + " on " + node_path}

	var key: String = node_path + "::" + signal_name
	if _watched_signals.has(key):
		return {}

	var sig: Signal = Signal(node, signal_name)
	var cb: Callable = _on_sig_variadic.bind(node_path, signal_name)
	sig.connect(cb)
	_watched_signals[key] = cb

	return {}


# =============================================================================
# unwatch_signal
# =============================================================================
func _unwatch_signal(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var signal_name: String = args[&"signal_name"]
	var key: String = node_path + "::" + signal_name
	if not _watched_signals.has(key):
		return {&"err": "Not watching: " + key}

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node != null:
		var cb: Callable = _watched_signals[key]
		var sig: Signal = Signal(node, signal_name)
		if sig.is_connected(cb):
			sig.disconnect(cb)

	_watched_signals.erase(key)
	return {}


# =============================================================================
# get_signal_emissions
# =============================================================================
func _get_signal_emissions(args: Dictionary) -> Dictionary:
	var clear: bool = args.get(&"clear", true)
	var out: Array[Dictionary]
	if not args.has(&"key"):
		out.assign(_signal_emissions.duplicate())
		if clear:
			_signal_emissions.clear()
	else:
		var filter_key: String = args[&"key"]
		out = []
		var remaining: Array[Dictionary] = []
		for e: Dictionary in _signal_emissions:
			var k: String = e[&"node_path"] + "::" + e[&"signal_name"]
			if k == filter_key:
				out.append(e)
			else:
				remaining.append(e)
		if clear:
			_signal_emissions = remaining

	return {&"emissions": _tabular(out, [&"node_path", &"signal_name", &"args", &"timestamp"]), &"watching": _watched_signals.keys()}


## Variadic signal callback. .bind(node_path, signal_name) appends after signal args.
## Requires Godot 4.5+ rest parameters (PR #82808).
func _on_sig_variadic(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	var node_path: String = args.pop_back()
	_on_signal_fired(node_path, signal_name, args)


func _on_signal_fired(node_path: String, signal_name: String, sig_args: Array) -> void:
	if _signal_emissions.size() >= MAX_EMISSIONS:
		_signal_emissions.pop_front()
	var serialized_args: Array = []
	for arg: Variant in sig_args:
		serialized_args.append(_serialize_value(arg))
	_signal_emissions.append(
		{
			&"node_path": node_path,
			&"signal_name": signal_name,
			&"args": serialized_args,
			&"timestamp": Time.get_ticks_msec(),
		},
	)


# =============================================================================
# Value serialization
# =============================================================================
func _serialize_value(value: Variant) -> Variant:
	if value == null:
		return null
	if value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return "V2(%s,%s)" % [value.x, value.y]
	if value is Vector2i:
		return "V2i(%s,%s)" % [value.x, value.y]
	if value is Vector3:
		return "V3(%s,%s,%s)" % [value.x, value.y, value.z]
	if value is Vector3i:
		return "V3i(%s,%s,%s)" % [value.x, value.y, value.z]
	if value is Color:
		return "C(%s,%s,%s,%s)" % [value.r, value.g, value.b, value.a]
	if value is Rect2:
		return "R2(%s,%s,%s,%s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Vector4:
		return "V4(%s,%s,%s,%s)" % [value.x, value.y, value.z, value.w]
	if value is Quaternion:
		return "Q(%s,%s,%s,%s)" % [value.x, value.y, value.z, value.w]
	if value is Basis:
		return "Bas(%s,%s,%s)" % [_serialize_value(value.x), _serialize_value(value.y), _serialize_value(value.z)]
	if value is Transform2D:
		return "T2D(%s,%s,%s)" % [_serialize_value(value.x), _serialize_value(value.y), _serialize_value(value.origin)]
	if value is Transform3D:
		return "T3D(%s,%s)" % [_serialize_value(value.basis), _serialize_value(value.origin)]
	if value is AABB:
		return "AB(%s,%s)" % [_serialize_value(value.position), _serialize_value(value.size)]
	if value is Plane:
		return "Pl(%s,%s)" % [_serialize_value(value.normal), value.d]
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_serialize_value(item))
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			out[str(key)] = _serialize_value(value[key])
		return out
	if value is NodePath:
		return "NP(%s)" % str(value)
	# Fallback: convert to string
	return str(value)


func _deserialize_value(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float:
		return value
	if value is String:
		return _parse_compact_type(value)
	if value is Dictionary:
		# Legacy dict format fallback + plain dicts
		var t: String = value.get(&"_type", "")
		if t.is_empty():
			return value
		match t:
			&"Vector2":
				return Vector2(value.get(&"x", 0.0), value.get(&"y", 0.0))
			&"Vector2i":
				return Vector2i(int(value.get(&"x", 0)), int(value.get(&"y", 0)))
			&"Vector3":
				return Vector3(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0))
			&"Vector3i":
				return Vector3i(int(value.get(&"x", 0)), int(value.get(&"y", 0)), int(value.get(&"z", 0)))
			&"Vector4":
				return Vector4(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0), value.get(&"w", 0.0))
			&"Quaternion":
				return Quaternion(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0), value.get(&"w", 1.0))
			&"Color":
				return Color(value.get(&"r", 0.0), value.get(&"g", 0.0), value.get(&"b", 0.0), value.get(&"a", 1.0))
			&"Rect2":
				return Rect2(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"w", 0.0), value.get(&"h", 0.0))
			&"NodePath":
				return NodePath(value.get(&"path", ""))
		return value
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_deserialize_value(item))
		return out
	return value


func _parse_compact_type(s: String) -> Variant:
	if s.begins_with("V2i(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(4, s.length() - 5).split(",")
		return Vector2i(int(parts[0].to_float()), int(parts[1].to_float()))
	if s.begins_with("V2(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(3, s.length() - 4).split(",")
		return Vector2(parts[0].to_float(), parts[1].to_float())
	if s.begins_with("V3i(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(4, s.length() - 5).split(",")
		return Vector3i(int(parts[0].to_float()), int(parts[1].to_float()), int(parts[2].to_float()))
	if s.begins_with("V3(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(3, s.length() - 4).split(",")
		return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	if s.begins_with("V4(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(3, s.length() - 4).split(",")
		return Vector4(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
	if s.begins_with("C(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(2, s.length() - 3).split(",")
		return Color(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
	if s.begins_with("R2(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(3, s.length() - 4).split(",")
		return Rect2(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
	if s.begins_with("Q(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(2, s.length() - 3).split(",")
		return Quaternion(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
	if s.begins_with("NP(") and s.ends_with(")"):
		return NodePath(s.substr(3, s.length() - 4))
	# Not a compact type string — return as plain string
	return s


## Convert an array of uniform dicts to header + rows format.
func _tabular(items: Array, keys: Array) -> Dictionary:
	var rows: Array[Array] = []
	for item: Dictionary in items:
		var row: Array = []
		for k: Variant in keys:
			row.append(item.get(k))
		rows.append(row)
	return {&"_h": keys, &"rows": rows}


# =============================================================================
# EngineDebugger IPC
# =============================================================================
func _send_result(id: String, result: Dictionary) -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message(&"mcp:tool_result", [id, JSON.stringify(result)])


# =============================================================================
# Enhanced metrics (Feature 5)
# =============================================================================
# (Integrated directly into _get_metrics below — no separate handler needed)


# =============================================================================
# Property watch system (Feature 1)
# =============================================================================
func _dispatch_runtime_watch(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	match args[&"action"]:
		&"watch":
			return _watch_property(args)
		&"unwatch":
			return _unwatch_property(args)
		&"list":
			return {&"watches": _watched_properties.keys()}
		&"get_changes":
			return _get_property_changes(args)
	return {&"err": "Unknown action (use watch, unwatch, list, get_changes)"}


func _watch_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return {&"err": "Node not found: " + node_path}
	var key: String = node_path + "::" + property
	_watched_properties[key] = {
		&"node_path": node_path,
		&"property": property,
		&"interval_ms": args.get(&"interval_ms", 100),
		&"last_value": _serialize_value(node.get(property)),
		&"last_sample_ms": Time.get_ticks_msec(),
	}
	set_physics_process(true)
	return {}


func _unwatch_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	var key: String = node_path + "::" + property
	if not _watched_properties.has(key):
		return {&"err": "Not watching: " + key}
	_watched_properties.erase(key)
	if _watched_properties.is_empty():
		set_physics_process(false)
	return {}


func _get_property_changes(args: Dictionary) -> Dictionary:
	var clear: bool = args.get(&"clear", true)
	var out: Array[Dictionary]
	if not args.has(&"key"):
		out.assign(_property_changes.duplicate())
		if clear:
			_property_changes.clear()
	else:
		var filter_key: String = args[&"key"]
		out = []
		var remaining: Array[Dictionary] = []
		for e: Dictionary in _property_changes:
			if e[&"key"] == filter_key:
				out.append(e)
			else:
				remaining.append(e)
		if clear:
			_property_changes = remaining
	return {&"changes": _tabular(out, [&"key", &"old", &"new", &"timestamp"])}


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for key: String in _watched_properties:
		var w: Dictionary = _watched_properties[key]
		if now - int(w[&"last_sample_ms"]) < int(w[&"interval_ms"]):
			continue
		var node: Node = get_tree().root.get_node_or_null(w[&"node_path"])
		if node == null:
			continue
		var current: Variant = _serialize_value(node.get(w[&"property"]))
		if current != w[&"last_value"]:
			if _property_changes.size() >= MAX_EMISSIONS:
				_property_changes.pop_front()
			_property_changes.append({&"key": key, &"old": w[&"last_value"], &"new": current, &"timestamp": now})
			w[&"last_value"] = current
		w[&"last_sample_ms"] = now


# =============================================================================
# UI mapping (Feature 2)
# =============================================================================
func _map_ui(args: Dictionary) -> Dictionary:
	var root_path: String = args.get(&"root_path", "/root")
	var max_depth: int = clampi(args.get(&"max_depth", 5), 1, 10)
	var root: Node = get_tree().root.get_node_or_null(root_path)
	if root == null:
		return {&"err": "Node not found: " + root_path}
	var rows: Array[Dictionary] = []
	_collect_controls(root, 0, max_depth, rows)
	return {&"controls": _tabular(rows, [&"name", &"type", &"path", &"pos", &"size", &"visible", &"extra"])}


func _collect_controls(node: Node, depth: int, max_depth: int, rows: Array[Dictionary]) -> void:
	if node is Control:
		var entry: Dictionary = {
			&"name": node.name,
			&"type": node.get_class(),
			&"path": str(node.get_path()),
			&"pos": _serialize_value(node.global_position),
			&"size": _serialize_value(node.size),
			&"visible": node.visible,
			&"extra": _control_extra(node),
		}
		rows.append(entry)
	if depth < max_depth:
		for child: Node in node.get_children():
			_collect_controls(child, depth + 1, max_depth, rows)


func _control_extra(node: Node) -> Variant:
	if node is BaseButton:
		return {&"disabled": node.disabled, &"pressed": node.button_pressed}
	if node is Label:
		return {&"text": node.text.left(200)}
	if node is RichTextLabel:
		return {&"text": node.get_parsed_text().left(200)}
	if node is LineEdit:
		return {&"text": node.text.left(200)}
	if node is TextEdit:
		return {&"text": node.text.left(200)}
	return null


# =============================================================================
# Explore camera (Feature 3) — cam_spawn/cam_move/cam_capture/cam_restore routed directly from _execute
# =============================================================================

func _explore_spawn(args: Dictionary) -> Dictionary:
	if _explore_camera != null:
		return {&"err": "Explore camera already spawned — restore first"}
	_original_camera = get_viewport().get_camera_3d()
	_explore_camera = Camera3D.new()
	if _original_camera:
		_explore_camera.global_transform = _original_camera.global_transform
	get_tree().root.add_child(_explore_camera)
	_explore_camera.make_current()
	if args.has(&"position"):
		_explore_camera.global_position = _deserialize_value(args[&"position"])
	if args.has(&"rotation"):
		_explore_camera.rotation_degrees = _deserialize_value(args[&"rotation"])
	if args.has(&"look_at"):
		_explore_camera.look_at(_deserialize_value(args[&"look_at"]))
	return {}


func _explore_move(args: Dictionary) -> Dictionary:
	if _explore_camera == null:
		return {&"err": "No explore camera — spawn first"}
	if args.has(&"position"):
		_explore_camera.global_position = _deserialize_value(args[&"position"])
	if args.has(&"rotation"):
		_explore_camera.rotation_degrees = _deserialize_value(args[&"rotation"])
	if args.has(&"look_at"):
		_explore_camera.look_at(_deserialize_value(args[&"look_at"]))
	return {}


func _explore_camera_capture_async(id: String) -> void:
	if _explore_camera == null:
		_send_result(id, {&"err": "No explore camera — spawn first"})
		return
	_send_result(id, await _capture_viewport())


func _restore_explore_camera() -> void:
	if _explore_camera == null:
		return
	if _original_camera and is_instance_valid(_original_camera):
		_original_camera.make_current()
	_explore_camera.queue_free()
	_explore_camera = null
	_original_camera = null


# =============================================================================
# Input side-effect tracking (Feature 4)
# =============================================================================
func _inject_input_tracked_async(id: String, args: Dictionary) -> void:
	var track: Array = args[&"track"]
	# Snapshot before
	var snapshots: Array[Dictionary] = []
	for entry: Dictionary in track:
		var node: Node = get_tree().root.get_node_or_null(entry[&"node_path"])
		var before: Variant = node.get(entry[&"property"]) if node else null
		snapshots.append({&"node_path": entry[&"node_path"], &"property": entry[&"property"], &"before": _serialize_value(before)})
	# Perform injection
	args.erase(&"track")
	_dispatch_inject_input(args)
	# Wait one physics frame for side effects
	await get_tree().physics_frame
	# Snapshot after and diff
	var diff: Array[Dictionary] = []
	for i: int in snapshots.size():
		var s: Dictionary = snapshots[i]
		var node: Node = get_tree().root.get_node_or_null(s[&"node_path"])
		var after: Variant = _serialize_value(node.get(s[&"property"])) if node else null
		if after != s[&"before"]:
			diff.append({&"node_path": s[&"node_path"], &"property": s[&"property"], &"before": s[&"before"], &"after": after})
	_send_result(id, {&"diff": diff})


# =============================================================================
# Runtime nav queries (Feature 6)
# =============================================================================
func _dispatch_runtime_nav(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var use_2d: bool = args.get(&"use_2d", false)
	match args[&"action"]:
		&"get_path":
			return _nav_get_path(args, use_2d)
		&"get_distance":
			return _nav_get_distance(args, use_2d)
		&"snap":
			return _nav_snap(args, use_2d)
	return {&"err": "Unknown action (use get_path, get_distance, snap)"}


func _nav_get_path(args: Dictionary, use_2d: bool) -> Dictionary:
	var from: Variant = _deserialize_value(args[&"from"])
	var to: Variant = _deserialize_value(args[&"to"])
	if use_2d:
		var maps: Array[RID] = NavigationServer2D.get_maps()
		if maps.is_empty():
			return {&"err": "No 2D navigation maps active"}
		var path: PackedVector2Array = NavigationServer2D.map_get_path(maps[0], from, to, true)
		var points: Array = []
		for p: Vector2 in path:
			points.append(_serialize_value(p))
		return {&"path": points}
	var maps: Array[RID] = NavigationServer3D.get_maps()
	if maps.is_empty():
		return {&"err": "No 3D navigation maps active"}
	var path: PackedVector3Array = NavigationServer3D.map_get_path(maps[0], from, to, true)
	var points: Array = []
	for p: Vector3 in path:
		points.append(_serialize_value(p))
	return {&"path": points}


func _nav_get_distance(args: Dictionary, use_2d: bool) -> Dictionary:
	var result: Dictionary = _nav_get_path(args, use_2d)
	if result.has(&"err"):
		return result
	var path: Array = result[&"path"]
	if path.size() < 2:
		return {&"distance": 0.0}
	var total: float = 0.0
	for i: int in range(1, path.size()):
		var a: Variant = _deserialize_value(path[i - 1])
		var b: Variant = _deserialize_value(path[i])
		total += a.distance_to(b)
	return {&"distance": total}


func _nav_snap(args: Dictionary, use_2d: bool) -> Dictionary:
	var point: Variant = _deserialize_value(args[&"point"])
	if use_2d:
		var maps: Array[RID] = NavigationServer2D.get_maps()
		if maps.is_empty():
			return {&"err": "No 2D navigation maps active"}
		return {&"snapped": _serialize_value(NavigationServer2D.map_get_closest_point(maps[0], point))}
	var maps: Array[RID] = NavigationServer3D.get_maps()
	if maps.is_empty():
		return {&"err": "No 3D navigation maps active"}
	return {&"snapped": _serialize_value(NavigationServer3D.map_get_closest_point(maps[0], point))}


# =============================================================================
# Runtime logger (Feature 7)
# =============================================================================
func _dispatch_runtime_log(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	match args[&"action"]:
		&"get":
			return _get_runtime_log(args)
		&"clear":
			_log_buffer.clear()
			return {}
	return {&"err": "Unknown action (use get, clear)"}


func _get_runtime_log(args: Dictionary) -> Dictionary:
	var count: int = args[&"count"] if args.has(&"count") else _log_buffer.size()
	var has_level: bool = args.has(&"level")
	var filter_level: String = args[&"level"] if has_level else ""
	var clear: bool = args.get(&"clear", true)
	var out: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for e: Dictionary in _log_buffer:
		if has_level and e[&"level"] != filter_level:
			remaining.append(e)
			continue
		if out.size() < count:
			out.append(e)
		else:
			remaining.append(e)
	if clear:
		_log_buffer = remaining if has_level else []
	return {&"log": _tabular(out, [&"msg", &"level", &"timestamp"])}

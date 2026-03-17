extends Node
## MCP Runtime Bridge — runs as an autoload inside the game process.
## Connects to the Go MCP server and handles runtime inspection tools:
## capture_screenshot, inspect_runtime_tree, get/set_runtime_property, call_runtime_method.

const SERVER_URL := "ws://127.0.0.1:6505"
const MAX_DEPTH_DEFAULT := 3
const MAX_DEPTH_LIMIT := 10

var _socket := WebSocketPeer.new()
var _connected := false
const WS_OUTBOUND_BUFFER := 10 * 1024 * 1024 # 10 MB — screenshots are large
const WS_INBOUND_BUFFER := 1 * 1024 * 1024 # 1 MB

# Signal watching: key = "node_path::signal_name", value = callable used to connect
var _watched_signals: Dictionary = { } # {String: Callable}
var _signal_emissions: Array = [] # [{node_path, signal_name, args, timestamp}]
const MAX_EMISSIONS := 500


func _ready() -> void:
	# Prevent game window from stealing focus when launched via MCP play_project.
	# The editor plugin sets this meta before calling play — cleared after read.
	if ProjectSettings.has_setting("godot_mcp/mcp_launched"):
		ProjectSettings.set_setting("godot_mcp/mcp_launched", false)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_socket.inbound_buffer_size = WS_INBOUND_BUFFER
	_socket.outbound_buffer_size = WS_OUTBOUND_BUFFER
	_socket.connect_to_url(SERVER_URL)


func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_send({ "type": "runtime_ready" })
			print("[MCPRuntime] Connected to MCP server")
		while _socket.get_available_packet_count() > 0:
			_handle_message(_socket.get_packet().get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			print("[MCPRuntime] Disconnected from MCP server")
		set_process(false)


func _handle_message(json_string: String) -> void:
	var msg: Variant = JSON.parse_string(json_string)
	if msg == null or msg is not Dictionary:
		return

	match msg.get("type", ""):
		"ping":
			_send({ "type": "pong" })
		"tool_invoke":
			var id: String = str(msg.get("id", ""))
			var tool_name: String = str(msg.get("tool", ""))
			var args: Dictionary = msg.get("args", { }) if msg.get("args") is Dictionary else { }
			if tool_name == "capture_screenshot":
				_capture_screenshot_async(id)
			else:
				var result := _execute(tool_name, args)
				_send_result(id, result)


func _execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"inspect_runtime_tree":
			return _inspect_tree(args)
		"get_runtime_property":
			return _get_property(args)
		"set_runtime_property":
			return _set_property(args)
		"call_runtime_method":
			return _call_method(args)
		"get_runtime_metrics":
			return _get_metrics()
		"inject_action":
			return _inject_action(args)
		"inject_key":
			return _inject_key(args)
		"inject_mouse_click":
			return _inject_mouse_click(args)
		"inject_mouse_motion":
			return _inject_mouse_motion(args)
		"watch_signal":
			return _watch_signal(args)
		"unwatch_signal":
			return _unwatch_signal(args)
		"get_signal_emissions":
			return _get_signal_emissions(args)
	return { "ok": false, "error": "Unknown runtime tool: " + tool_name }


# =============================================================================
# capture_screenshot
# =============================================================================
func _capture_screenshot_async(id: String) -> void:
	await RenderingServer.frame_post_draw
	var viewport := get_viewport()
	if viewport == null:
		_send_result(id, { "ok": false, "error": "No viewport available" })
		return

	var img := viewport.get_texture().get_image()
	if img == null:
		_send_result(id, { "ok": false, "error": "Failed to capture viewport image" })
		return

	var png_data := img.save_png_to_buffer()
	if png_data.is_empty():
		_send_result(id, { "ok": false, "error": "Failed to encode PNG" })
		return

	var b64 := Marshalls.raw_to_base64(png_data)
	_send_result(
		id,
		{
			"ok": true,
			"image_base64": b64,
			"width": img.get_width(),
			"height": img.get_height(),
		},
	)


# =============================================================================
# inspect_runtime_tree
# =============================================================================
func _inspect_tree(args: Dictionary) -> Dictionary:
	var root_path: String = str(args.get("root_path", "/root"))
	var max_depth: int = clampi(int(args.get("max_depth", MAX_DEPTH_DEFAULT)), 1, MAX_DEPTH_LIMIT)

	var root := get_tree().root.get_node_or_null(root_path)
	if root == null:
		return { "ok": false, "error": "Node not found: " + root_path }

	return { "ok": true, "tree": _serialize_node_tree(root, 0, max_depth) }


func _serialize_node_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result := _serialize_node(node)
	if depth < max_depth:
		var children: Array = []
		for child: Node in node.get_children():
			children.append(_serialize_node_tree(child, depth + 1, max_depth))
		result["children"] = children
	else:
		var child_count := node.get_child_count()
		if child_count > 0:
			result["child_count"] = child_count
	return result


func _serialize_node(node: Node) -> Dictionary:
	var result: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}
	if node.get_script():
		result["script"] = node.get_script().resource_path
	return result


# =============================================================================
# get_runtime_property
# =============================================================================
func _get_property(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", ""))
	var property: String = str(args.get("property", ""))
	if node_path.is_empty() or property.is_empty():
		return { "ok": false, "error": "Missing node_path or property" }

	var node := get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { "ok": false, "error": "Node not found: " + node_path }

	var value: Variant = node.get(property)
	return { "ok": true, "node_path": node_path, "property": property, "value": _serialize_value(value) }


# =============================================================================
# set_runtime_property
# =============================================================================
func _set_property(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", ""))
	var property: String = str(args.get("property", ""))
	if node_path.is_empty() or property.is_empty():
		return { "ok": false, "error": "Missing node_path or property" }

	var node := get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { "ok": false, "error": "Node not found: " + node_path }

	var old_value: Variant = node.get(property)
	var new_value: Variant = _deserialize_value(args.get("value"))
	node.set(property, new_value)

	return {
		"ok": true,
		"node_path": node_path,
		"property": property,
		"old_value": _serialize_value(old_value),
		"new_value": _serialize_value(node.get(property)),
	}


# =============================================================================
# call_runtime_method
# =============================================================================
func _call_method(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", ""))
	var method: String = str(args.get("method", ""))
	if node_path.is_empty() or method.is_empty():
		return { "ok": false, "error": "Missing node_path or method" }

	var node := get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { "ok": false, "error": "Node not found: " + node_path }

	if not node.has_method(method):
		return { "ok": false, "error": "Method not found: " + method + " on " + node_path }

	var call_args: Array = args.get("args", []) if args.get("args") is Array else []
	var deserialized: Array = []
	for arg: Variant in call_args:
		deserialized.append(_deserialize_value(arg))

	var result: Variant = node.callv(method, deserialized)
	return { "ok": true, "result": _serialize_value(result) }


# =============================================================================
# get_runtime_metrics
# =============================================================================
func _get_metrics() -> Dictionary:
	return {
		"ok": true,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"memory": {
			"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		},
		"objects": {
			"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
			"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		},
		"render": {
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"total_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"total_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		},
	}


# =============================================================================
# inject_action
# =============================================================================
func _inject_action(args: Dictionary) -> Dictionary:
	var action: String = str(args.get("action", ""))
	if action.is_empty():
		return { "ok": false, "error": "Missing action" }

	var pressed: bool = args.get("pressed", true)
	var strength: float = float(args.get("strength", 1.0))

	if not InputMap.has_action(action):
		return { "ok": false, "error": "Unknown action: " + action }

	if pressed:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

	return { "ok": true, "action": action, "pressed": pressed, "strength": strength }


# =============================================================================
# inject_key
# =============================================================================
func _inject_key(args: Dictionary) -> Dictionary:
	var keycode_str: String = str(args.get("keycode", ""))
	if keycode_str.is_empty():
		return { "ok": false, "error": "Missing keycode" }

	var keycode: int = OS.find_keycode_from_string(keycode_str)
	if keycode == KEY_NONE:
		return { "ok": false, "error": "Unknown keycode: " + keycode_str }

	var pressed: bool = args.get("pressed", true)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	ev.shift_pressed = args.get("shift", false)
	ev.ctrl_pressed = args.get("ctrl", false)
	ev.alt_pressed = args.get("alt", false)
	ev.meta_pressed = args.get("meta", false)
	Input.parse_input_event(ev)

	return { "ok": true, "keycode": keycode_str, "pressed": pressed }


# =============================================================================
# inject_mouse_click
# =============================================================================
func _inject_mouse_click(args: Dictionary) -> Dictionary:
	var x: float = float(args.get("x", 0.0))
	var y: float = float(args.get("y", 0.0))
	var button: String = str(args.get("button", "left"))

	var button_index: int
	match button:
		"left":
			button_index = MOUSE_BUTTON_LEFT
		"right":
			button_index = MOUSE_BUTTON_RIGHT
		"middle":
			button_index = MOUSE_BUTTON_MIDDLE
		_:
			return { "ok": false, "error": "Unknown button: " + button + " (use left, right, or middle)" }

	var pos := Vector2(x, y)

	# Press
	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = button_index
	press.pressed = true
	Input.parse_input_event(press)

	# Release
	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = button_index
	release.pressed = false
	Input.parse_input_event(release)

	return { "ok": true, "x": x, "y": y, "button": button }


# =============================================================================
# inject_mouse_motion
# =============================================================================
func _inject_mouse_motion(args: Dictionary) -> Dictionary:
	var rel_x: float = float(args.get("relative_x", 0.0))
	var rel_y: float = float(args.get("relative_y", 0.0))
	var pos_x: float = float(args.get("position_x", 0.0))
	var pos_y: float = float(args.get("position_y", 0.0))

	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(rel_x, rel_y)
	ev.position = Vector2(pos_x, pos_y)
	ev.global_position = Vector2(pos_x, pos_y)
	Input.parse_input_event(ev)

	return { "ok": true, "relative": { "x": rel_x, "y": rel_y }, "position": { "x": pos_x, "y": pos_y } }


# =============================================================================
# watch_signal
# =============================================================================
func _watch_signal(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", ""))
	var signal_name: String = str(args.get("signal_name", ""))
	if node_path.is_empty() or signal_name.is_empty():
		return { "ok": false, "error": "Missing node_path or signal_name" }

	var node := get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { "ok": false, "error": "Node not found: " + node_path }

	if not node.has_signal(signal_name):
		return { "ok": false, "error": "Signal not found: " + signal_name + " on " + node_path }

	var key := node_path + "::" + signal_name
	if _watched_signals.has(key):
		return { "ok": true, "already_watching": true, "key": key }

	# We need a closure that captures node_path and signal_name,
	# while accepting any number of signal arguments via a lambda.
	var sig := Signal(node, signal_name)
	var arg_count: int = 0
	for s: Dictionary in node.get_signal_list():
		if s["name"] == signal_name:
			arg_count = s["args"].size()
			break

	# Build a callable matching the exact signal arity.
	var cb: Callable
	match arg_count:
		0:
			cb = func() -> void: _on_signal_fired(node_path, signal_name, [])
		1:
			cb = func(a: Variant) -> void: _on_signal_fired(node_path, signal_name, [a])
		2:
			cb = func(a: Variant, b: Variant) -> void: _on_signal_fired(node_path, signal_name, [a, b])
		3:
			cb = func(a: Variant, b: Variant, c: Variant) -> void: _on_signal_fired(node_path, signal_name, [a, b, c])
		4:
			cb = func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: _on_signal_fired(node_path, signal_name, [a, b, c, d])
		_:
			cb = func() -> void: _on_signal_fired(node_path, signal_name, [])

	sig.connect(cb)
	_watched_signals[key] = cb

	return { "ok": true, "watching": key }


# =============================================================================
# unwatch_signal
# =============================================================================
func _unwatch_signal(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", ""))
	var signal_name: String = str(args.get("signal_name", ""))
	if node_path.is_empty() or signal_name.is_empty():
		return { "ok": false, "error": "Missing node_path or signal_name" }

	var key := node_path + "::" + signal_name
	if not _watched_signals.has(key):
		return { "ok": false, "error": "Not watching: " + key }

	var node := get_tree().root.get_node_or_null(node_path)
	if node != null:
		var cb: Callable = _watched_signals[key]
		var sig := Signal(node, signal_name)
		if sig.is_connected(cb):
			sig.disconnect(cb)

	_watched_signals.erase(key)
	return { "ok": true, "unwatched": key }


# =============================================================================
# get_signal_emissions
# =============================================================================
func _get_signal_emissions(args: Dictionary) -> Dictionary:
	var filter_key: String = str(args.get("key", ""))
	var clear: bool = args.get("clear", true)

	var out: Array
	if filter_key.is_empty():
		out = _signal_emissions.duplicate()
		if clear:
			_signal_emissions.clear()
	else:
		out = []
		var remaining: Array = []
		for e: Dictionary in _signal_emissions:
			var k: String = str(e.get("node_path", "")) + "::" + str(e.get("signal_name", ""))
			if k == filter_key:
				out.append(e)
			else:
				remaining.append(e)
		if clear:
			_signal_emissions = remaining

	return { "ok": true, "emissions": out, "count": out.size(), "watching": _watched_signals.keys() }


func _on_signal_fired(node_path: String, signal_name: String, sig_args: Array) -> void:
	if _signal_emissions.size() >= MAX_EMISSIONS:
		_signal_emissions.pop_front()
	var serialized_args: Array = []
	for arg: Variant in sig_args:
		serialized_args.append(_serialize_value(arg))
	_signal_emissions.append(
		{
			"node_path": node_path,
			"signal_name": signal_name,
			"args": serialized_args,
			"timestamp": Time.get_ticks_msec(),
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
		return { "_type": "Vector2", "x": value.x, "y": value.y }
	if value is Vector2i:
		return { "_type": "Vector2i", "x": value.x, "y": value.y }
	if value is Vector3:
		return { "_type": "Vector3", "x": value.x, "y": value.y, "z": value.z }
	if value is Vector3i:
		return { "_type": "Vector3i", "x": value.x, "y": value.y, "z": value.z }
	if value is Color:
		return { "_type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a }
	if value is Rect2:
		return { "_type": "Rect2", "x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y }
	if value is Vector4:
		return { "_type": "Vector4", "x": value.x, "y": value.y, "z": value.z, "w": value.w }
	if value is Quaternion:
		return { "_type": "Quaternion", "x": value.x, "y": value.y, "z": value.z, "w": value.w }
	if value is Basis:
		return { "_type": "Basis", "x": _serialize_value(value.x), "y": _serialize_value(value.y), "z": _serialize_value(value.z) }
	if value is Transform2D:
		return { "_type": "Transform2D", "origin": _serialize_value(value.origin), "x": _serialize_value(value.x), "y": _serialize_value(value.y) }
	if value is Transform3D:
		return { "_type": "Transform3D", "basis": _serialize_value(value.basis), "origin": _serialize_value(value.origin) }
	if value is AABB:
		return { "_type": "AABB", "position": _serialize_value(value.position), "size": _serialize_value(value.size) }
	if value is Plane:
		return { "_type": "Plane", "normal": _serialize_value(value.normal), "d": value.d }
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_serialize_value(item))
		return out
	if value is Dictionary:
		var out: Dictionary = { }
		for key: Variant in value:
			out[str(key)] = _serialize_value(value[key])
		return out
	if value is NodePath:
		return { "_type": "NodePath", "path": str(value) }
	# Fallback: convert to string
	return str(value)


func _deserialize_value(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Dictionary:
		var t: String = str(value.get("_type", ""))
		match t:
			"Vector2":
				return Vector2(value.get("x", 0.0), value.get("y", 0.0))
			"Vector2i":
				return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
			"Vector3":
				return Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
			"Vector3i":
				return Vector3i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("z", 0)))
			"Vector4":
				return Vector4(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0), value.get("w", 0.0))
			"Quaternion":
				return Quaternion(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0), value.get("w", 1.0))
			"Color":
				return Color(value.get("r", 0.0), value.get("g", 0.0), value.get("b", 0.0), value.get("a", 1.0))
			"Basis":
				return Basis(_deserialize_value(value.get("x", { })), _deserialize_value(value.get("y", { })), _deserialize_value(value.get("z", { })))
			"Transform3D":
				return Transform3D(_deserialize_value(value.get("basis", { })), _deserialize_value(value.get("origin", { })))
			"Transform2D":
				return Transform2D(0.0, _deserialize_value(value.get("origin", { }))) if not value.has("x") else Transform2D(_deserialize_value(value.get("x", { })), _deserialize_value(value.get("y", { })), _deserialize_value(value.get("origin", { })))
			"Rect2":
				return Rect2(value.get("x", 0.0), value.get("y", 0.0), value.get("w", 0.0), value.get("h", 0.0))
			"AABB":
				return AABB(_deserialize_value(value.get("position", { })), _deserialize_value(value.get("size", { })))
			"Plane":
				return Plane(_deserialize_value(value.get("normal", { })), value.get("d", 0.0))
			"NodePath":
				return NodePath(str(value.get("path", "")))
		# No _type — treat as plain dictionary
		return value
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_deserialize_value(item))
		return out
	return value


# =============================================================================
# WebSocket helpers
# =============================================================================
func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func _send_result(id: String, result: Dictionary) -> void:
	_send(
		{
			"type": "tool_result",
			"id": id,
			"success": result.get("ok", false),
			"result": result,
		},
	)

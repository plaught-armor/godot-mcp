extends Node
## MCP Runtime Bridge — runs as an autoload inside the game process.
## Connects to the Go MCP server and handles runtime inspection tools:
## capture_screenshot, inspect_runtime_tree, get/set_runtime_property, call_runtime_method.

const SERVER_URL: String = "ws://127.0.0.1:6505"
const MAX_DEPTH_DEFAULT: int = 3
const MAX_DEPTH_LIMIT: int = 10
const WS_OUTBOUND_BUFFER: int = 10 * 1024 * 1024 # 10 MB — screenshots are large
const WS_INBOUND_BUFFER: int = 1 * 1024 * 1024 # 1 MB
const MAX_EMISSIONS: int = 500

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false
var _reconnect: ReconnectHelper = ReconnectHelper.new()
var _instance_id: String = ""
# Signal watching: key = "node_path::signal_name", value = callable used to connect
var _watched_signals: Dictionary = { } # {String: Callable}
var _signal_emissions: Array[Dictionary] = [] # [{node_path, signal_name, args, timestamp}]


func _ready() -> void:
	# Prevent game window from stealing focus when launched via MCP play_project.
	# The editor plugin sets this meta before calling play — cleared after read.
	if ProjectSettings.has_setting("godot_mcp/mcp_launched"):
		ProjectSettings.set_setting("godot_mcp/mcp_launched", false)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	# Compute instance ID to match editor plugin
	var custom_id: String = ProjectSettings.get_setting("godot_mcp/instance_id", "")
	if custom_id.is_empty():
		_instance_id = ProjectSettings.globalize_path("res://").get_base_dir().get_file()
	else:
		_instance_id = custom_id
	_reconnect.setup(self)
	_reconnect.should_connect.connect(_attempt_connection)
	_attempt_connection()


func _process(_delta: float) -> void:
	_socket.poll()
	var state: WebSocketPeer.State = _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_reconnect.reset()
			_send({ &"type": &"runtime_ready", &"instance_id": _instance_id, &"pid": OS.get_process_id() })
			print("[MCPRuntime] Connected to MCP server")
		while _socket.get_available_packet_count() > 0:
			_handle_message(_socket.get_packet().get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			print("[MCPRuntime] Disconnected from MCP server")
		_reconnect.schedule()
		set_process(false)


func _attempt_connection() -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	_socket.inbound_buffer_size = WS_INBOUND_BUFFER
	_socket.outbound_buffer_size = WS_OUTBOUND_BUFFER
	_socket.connect_to_url(SERVER_URL)
	set_process(true)


func _handle_message(json_string: String) -> void:
	var msg: Variant = JSON.parse_string(json_string)
	if msg == null or msg is not Dictionary:
		return

	match msg.get(&"type", ""):
		&"ping":
			_send({ &"type": &"pong" })
		&"tool_invoke":
			var id: String = msg[&"id"]
			var tool_name: String = msg[&"tool"]
			if tool_name == &"capture_screenshot":
				_capture_screenshot_async(id)
			else:
				var result: Dictionary = _execute(tool_name, msg.get(&"args", { }))
				_send_result(id, result)


func _execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		&"inspect_runtime_tree":
			return _inspect_tree(args)
		&"get_runtime_property":
			return _get_property(args)
		&"set_runtime_property":
			return _set_property(args)
		&"call_runtime_method":
			return _call_method(args)
		&"get_runtime_metrics":
			return _get_metrics()
		&"inject_input":
			return _dispatch_inject_input(args)
		&"signal_watch":
			return _dispatch_signal_watch(args)
	return { &"err": "Unknown runtime tool: " + tool_name }


# =============================================================================
# capture_screenshot
# =============================================================================
func _capture_screenshot_async(id: String) -> void:
	await RenderingServer.frame_post_draw
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_send_result(id, { &"err": "No viewport available" })
		return

	var img: Image = viewport.get_texture().get_image()
	if img == null:
		_send_result(id, { &"err": "Failed to capture viewport image" })
		return

	var png_data: PackedByteArray = img.save_png_to_buffer()
	if png_data.is_empty():
		_send_result(id, { &"err": "Failed to encode PNG" })
		return

	var b64: String = Marshalls.raw_to_base64(png_data)
	_send_result(id, { &"img": b64, &"width": img.get_width(), &"height": img.get_height() })


# =============================================================================
# inspect_runtime_tree
# =============================================================================
func _inspect_tree(args: Dictionary) -> Dictionary:
	var root_path: String = args.get(&"root_path", "/root")
	var max_depth: int = clampi(args.get(&"max_depth", MAX_DEPTH_DEFAULT), 1, MAX_DEPTH_LIMIT)

	var root: Node = get_tree().root.get_node_or_null(root_path)
	if root == null:
		return { &"err": "Node not found: " + root_path }

	return { &"tree": _serialize_node_tree(root, 0, max_depth) }


func _serialize_node_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result: Dictionary = _serialize_node(node)
	if depth < max_depth and node.get_child_count() > 0:
		var children: Array[Dictionary] = []
		for child: Node in node.get_children():
			children.append(_serialize_node_tree(child, depth + 1, max_depth))
		result[&"children"] = children
	elif depth < max_depth:
		pass # leaf node — omit children key to save allocation
	else:
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
	var script := node.get_script()
	if script:
		result[&"script"] = script.resource_path
	return result


# =============================================================================
# get_runtime_property
# =============================================================================
func _get_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	if node_path.is_empty() or property.is_empty():
		return { &"err": "Missing node_path or property" }

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { &"err": "Node not found: " + node_path }

	var value: Variant = node.get(property)
	return { &"node_path": node_path,&"property": property,&"value": _serialize_value(value) }


# =============================================================================
# set_runtime_property
# =============================================================================
func _set_property(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var property: String = args[&"property"]
	if node_path.is_empty() or property.is_empty():
		return { &"err": "Missing node_path or property" }

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { &"err": "Node not found: " + node_path }

	var old_value: Variant = node.get(property)
	var new_value: Variant = _deserialize_value(args.get(&"value"))
	node.set(property, new_value)

	return { &"old": _serialize_value(old_value) }


# =============================================================================
# call_runtime_method
# =============================================================================
func _call_method(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var method: String = args[&"method"]
	if node_path.is_empty() or method.is_empty():
		return { &"err": "Missing node_path or method" }

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { &"err": "Node not found: " + node_path }

	if not node.has_method(method):
		return { &"err": "Method not found: " + method + " on " + node_path }

	var deserialized: Array = []
	for arg: Variant in args.get(&"args", []):
		deserialized.append(_deserialize_value(arg))

	var result: Variant = node.callv(method, deserialized)
	return { &"result": _serialize_value(result) }


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
		},
	}


# =============================================================================
# inject_input dispatcher
# =============================================================================
func _dispatch_inject_input(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var input_type: String = args.get(&"type", "")
	match input_type:
		&"action":
			return _inject_action(args)
		&"key":
			return _inject_key(args)
		&"mouse_click":
			return _inject_mouse_click(args)
		&"mouse_motion":
			return _inject_mouse_motion(args)
	return { &"err": "Unknown input type: " + input_type + " (use action, key, mouse_click, or mouse_motion)" }


# =============================================================================
# signal_watch dispatcher
# =============================================================================
func _dispatch_signal_watch(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var sig_action: String = args.get(&"action", "")
	match sig_action:
		&"watch":
			return _watch_signal(args)
		&"unwatch":
			return _unwatch_signal(args)
		&"get_emissions":
			return _get_signal_emissions(args)
	return { &"err": "Unknown signal_watch action: " + sig_action + " (use watch, unwatch, or get_emissions)" }


# =============================================================================
# inject_action
# =============================================================================
func _inject_action(args: Dictionary) -> Dictionary:
	var action: String = args[&"action"]
	if action.is_empty():
		return { &"err": "Missing action" }

	var pressed: bool = args.get(&"pressed", true)
	var strength: float = args.get(&"strength", 1.0)

	if not InputMap.has_action(action):
		return { &"err": "Unknown action: " + action }

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
	if keycode_str.is_empty():
		return { &"err": "Missing keycode" }

	var keycode: int = OS.find_keycode_from_string(keycode_str)
	if keycode == KEY_NONE:
		return { &"err": "Unknown keycode: " + keycode_str }

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
			return { &"err": "Unknown button: " + button + " (use left, right, or middle)" }

	var pos: Vector2 = Vector2(x, y)

	# Press
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = button_index
	press.pressed = true
	Input.parse_input_event(press)

	# Release
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = button_index
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
	if node_path.is_empty() or signal_name.is_empty():
		return { &"err": "Missing node_path or signal_name" }

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node == null:
		return { &"err": "Node not found: " + node_path }

	if not node.has_signal(signal_name):
		return { &"err": "Signal not found: " + signal_name + " on " + node_path }

	var key: String = node_path + "::" + signal_name
	if _watched_signals.has(key):
		return { &"already_watching": true,&"key": key }

	# We need a closure that captures node_path and signal_name,
	# while accepting any number of signal arguments via a lambda.
	var sig: Signal = Signal(node, signal_name)
	var arg_count: int = 0
	for s: Dictionary in node.get_signal_list():
		if s[&"name"] == signal_name:
			arg_count = s[&"args"].size()
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

	return { &"watching": key }


# =============================================================================
# unwatch_signal
# =============================================================================
func _unwatch_signal(args: Dictionary) -> Dictionary:
	var node_path: String = args[&"node_path"]
	var signal_name: String = args[&"signal_name"]
	if node_path.is_empty() or signal_name.is_empty():
		return { &"err": "Missing node_path or signal_name" }

	var key: String = node_path + "::" + signal_name
	if not _watched_signals.has(key):
		return { &"err": "Not watching: " + key }

	var node: Node = get_tree().root.get_node_or_null(node_path)
	if node != null:
		var cb: Callable = _watched_signals[key]
		var sig: Signal = Signal(node, signal_name)
		if sig.is_connected(cb):
			sig.disconnect(cb)

	_watched_signals.erase(key)
	return { &"unwatched": key }


# =============================================================================
# get_signal_emissions
# =============================================================================
func _get_signal_emissions(args: Dictionary) -> Dictionary:
	var filter_key: String = args.get(&"key", "")
	var clear: bool = args.get(&"clear", true)

	var out: Array[Dictionary]
	if filter_key.is_empty():
		out.assign(_signal_emissions.duplicate())
		if clear:
			_signal_emissions.clear()
	else:
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

	return { &"emissions": _tabular(out, [&"node_path", &"signal_name", &"args", &"timestamp"]), &"watching": _watched_signals.keys() }


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
		var out: Dictionary = { }
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
			"Vector2":
				return Vector2(value.get(&"x", 0.0), value.get(&"y", 0.0))
			"Vector2i":
				return Vector2i(int(value.get(&"x", 0)), int(value.get(&"y", 0)))
			"Vector3":
				return Vector3(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0))
			"Vector3i":
				return Vector3i(int(value.get(&"x", 0)), int(value.get(&"y", 0)), int(value.get(&"z", 0)))
			"Vector4":
				return Vector4(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0), value.get(&"w", 0.0))
			"Quaternion":
				return Quaternion(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"z", 0.0), value.get(&"w", 1.0))
			"Color":
				return Color(value.get(&"r", 0.0), value.get(&"g", 0.0), value.get(&"b", 0.0), value.get(&"a", 1.0))
			"Rect2":
				return Rect2(value.get(&"x", 0.0), value.get(&"y", 0.0), value.get(&"w", 0.0), value.get(&"h", 0.0))
			"NodePath":
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
		for k: String in keys:
			row.append(item.get(k))
		rows.append(row)
	return { &"_h": keys, &"rows": rows }


# =============================================================================
# WebSocket helpers
# =============================================================================
func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func _send_result(id: String, result: Dictionary) -> void:
	_send({ &"type": &"tool_result", &"id": id, &"result": result })

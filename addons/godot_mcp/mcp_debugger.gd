@tool
extends EditorDebuggerPlugin
## Bridges runtime tool invocations between the editor plugin and running game
## instances via Godot's built-in EngineDebugger IPC channel.
##
## Flow: Go server -> mcp_client -> plugin -> THIS -> EngineDebugger -> mcp_runtime
##       Go server <- mcp_client <- plugin <- THIS <- EngineDebugger <- mcp_runtime

signal runtime_started(session_id: int)
signal runtime_stopped(session_id: int)
signal tool_result_received(request_id: String, result_json: String)

## Active debugger session IDs (game instances currently running).
var _active_sessions: Array[int] = []


## Send a tool invocation to a running game instance.
## If session_id is -1, sends to the first active session.
func invoke_tool(request_id: String, tool_name: String, args_json: String, session_id: int = -1) -> bool:
	var session: EditorDebuggerSession = _resolve_session(session_id)
	if session == null:
		return false
	session.send_message(&"mcp:invoke_tool", [request_id, tool_name, args_json])
	return true


## Returns true if any game instance is connected via the debugger.
func is_runtime_connected() -> bool:
	return not _active_sessions.is_empty()


func _has_capture(capture: String) -> bool:
	return capture == "mcp"


func _capture(message: String, data: Array, session_id: int) -> bool:
	# NOTE: engine strips the "mcp:" prefix — we receive only the suffix.
	match message:
		&"tool_result":
			tool_result_received.emit(data[0], data[1])
			return true
		&"runtime_ready":
			print("[GMCP] Runtime ready via EngineDebugger (session %d)" % session_id)
			return true
	return false


func _setup_session(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	if session == null:
		return
	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))


func _on_session_started(session_id: int) -> void:
	_active_sessions.append(session_id)
	print("[GMCP] Debugger session %d started" % session_id)
	runtime_started.emit(session_id)


func _on_session_stopped(session_id: int) -> void:
	var idx: int = _active_sessions.find(session_id)
	if idx >= 0:
		_active_sessions.remove_at(idx)
	print("[GMCP] Debugger session %d stopped" % session_id)
	runtime_stopped.emit(session_id)


func _resolve_session(session_id: int) -> EditorDebuggerSession:
	if session_id >= 0:
		var session: EditorDebuggerSession = get_session(session_id)
		if session != null and session.is_active():
			return session
		return null
	for i: int in _active_sessions.size():
		var session: EditorDebuggerSession = get_session(_active_sessions[i])
		if session != null and session.is_active():
			return session
	return null

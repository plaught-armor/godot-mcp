class_name ReconnectHelper
extends RefCounted
## Shared reconnect logic with exponential backoff.
## Used by both the editor client (mcp_client.gd) and the runtime bridge (mcp_runtime.gd).

signal should_connect
signal gave_up

const INITIAL_DELAY := 0.5
const MAX_DELAY := 2.0
const MAX_RETRIES := 5

var _retry_count: int = 0
var _delay: float = INITIAL_DELAY
var _timer: Timer


func setup(parent: Node) -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(func() -> void: should_connect.emit())
	parent.add_child(_timer)


func reset() -> void:
	_retry_count = 0
	_delay = INITIAL_DELAY
	if _timer:
		_timer.stop()


func schedule() -> void:
	_retry_count += 1
	if _retry_count > MAX_RETRIES:
		push_warning("[MCP] Max retries (%d) reached, giving up" % MAX_RETRIES)
		gave_up.emit()
		return
	print("[MCP] Reconnecting in ", _delay, "s (attempt ", _retry_count, "/", MAX_RETRIES, ")...")
	_timer.start(_delay)
	_delay = minf(_delay * 2.0, MAX_DELAY)

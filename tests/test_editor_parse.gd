extends SceneTree
## Validates all @tool GDScript files parse correctly in editor context.
## Must be run with: godot --headless --editor --path . --script tests/test_editor_parse.gd
## This catches errors that headless non-editor mode misses (class_name resolution, etc.)

var _fail_count: int = 0
var _pass_count: int = 0


func _init() -> void:
	print("=== Editor parse validation ===")

	# Core addon files
	_check("res://addons/godot_mcp/plugin.gd")
	_check("res://addons/godot_mcp/mcp_client.gd")
	_check("res://addons/godot_mcp/mcp_debugger.gd")
	_check("res://addons/godot_mcp/mcp_runtime.gd")
	_check("res://addons/godot_mcp/reconnect_helper.gd")
	_check("res://addons/godot_mcp/tool_executor.gd")

	# All tool handlers
	var tools_dir: String = "res://addons/godot_mcp/tools/"
	var dir: DirAccess = DirAccess.open(tools_dir)
	if dir:
		dir.list_dir_begin()
		var file: String = dir.get_next()
		while not file.is_empty():
			if file.ends_with(".gd"):
				_check(tools_dir + file)
			file = dir.get_next()
		dir.list_dir_end()

	print("\n=== Editor parse: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func _check(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_fail_count += 1
		printerr("  FAIL  %s — failed to load" % path)
		return
	# Force recompilation to catch parse errors
	if not script.can_instantiate():
		_fail_count += 1
		printerr("  FAIL  %s — cannot instantiate (parse/compile error)" % path)
		return
	_pass_count += 1
	print("  PASS  %s" % path)

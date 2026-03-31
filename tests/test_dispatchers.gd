extends SceneTree
## Tests consolidated tool dispatcher routing.
## Must be run with: godot --headless --editor --path . --script tests/test_dispatchers.gd
## Verifies that every action in every consolidated tool routes correctly.

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("=== Dispatcher routing tests ===")

	_test_runtime_dispatch()
	_test_unknown_actions()
	_test_valid_action_routing()

	print("\n=== Dispatchers: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


# =============================================================================
# Runtime dispatcher — can instantiate without editor context
# =============================================================================
func _test_runtime_dispatch() -> void:
	var rt: Node = load("res://addons/godot_mcp/mcp_runtime.gd").new()

	# Test that _execute routes all actions without crashing
	# Most will fail gracefully (no SceneTree) but dispatch itself works
	var actions: PackedStringArray = [
		"tree", "prop", "set_prop", "call", "metrics",
		"input", "sig_watch", "prop_watch", "ui",
		"cam_spawn", "cam_move", "cam_restore",
		"nav", "log",
	]
	for action: String in actions:
		var result: Dictionary = rt._execute(action, {})
		# Should either return a dict with err (expected — no scene tree) or {}
		_assert(result is Dictionary, "rt action '%s' should return Dictionary, got %s" % [action, typeof(result)])

	# Unknown action should return err
	var bad: Dictionary = rt._execute("nonexistent", {})
	_assert(bad.has(&"err"), "rt unknown action should return err")

	rt.free()


# =============================================================================
# Tool handler unknown-action tests (editor context)
# These verify the consolidated dispatcher match statements have a default arm
# =============================================================================
func _test_unknown_actions() -> void:
	# file dispatcher
	var file_tools: RefCounted = load("res://addons/godot_mcp/tools/file_tools.gd").new()
	var file_result: Variant = file_tools.call(&"file", {&"action": &"nonexistent"})
	_assert(file_result is Dictionary and file_result.has(&"err"), "file unknown action should return err")

	# scene dispatcher
	var scene_tools: RefCounted = load("res://addons/godot_mcp/tools/scene_tools.gd").new()
	var scene_result: Variant = scene_tools.call(&"scene", {&"action": &"nonexistent"})
	_assert(scene_result is Dictionary and scene_result.has(&"err"), "scene unknown action should return err")

	# script dispatcher
	var script_tools: RefCounted = load("res://addons/godot_mcp/tools/script_tools.gd").new()
	var script_result: Variant = script_tools.call(&"script", {&"action": &"nonexistent"})
	_assert(script_result is Dictionary and script_result.has(&"err"), "script unknown action should return err")

	# proj dispatcher
	var project_tools: RefCounted = load("res://addons/godot_mcp/tools/project_tools.gd").new()
	var proj_result: Variant = project_tools.call(&"proj", {&"action": &"nonexistent"})
	_assert(proj_result is Dictionary and proj_result.has(&"err"), "proj unknown action should return err")

	# anim dispatcher
	var anim_tools: RefCounted = load("res://addons/godot_mcp/tools/animation_tools.gd").new()
	var anim_result: Variant = anim_tools.call(&"anim", {&"action": &"nonexistent"})
	_assert(anim_result is Dictionary and anim_result.has(&"err"), "anim unknown action should return err")

	# phys dispatcher
	var phys_tools: RefCounted = load("res://addons/godot_mcp/tools/physics_tools.gd").new()
	var phys_result: Variant = phys_tools.call(&"phys", {&"action": &"nonexistent"})
	_assert(phys_result is Dictionary and phys_result.has(&"err"), "phys unknown action should return err")

	# analyze dispatcher
	var analysis_tools: RefCounted = load("res://addons/godot_mcp/tools/analysis_tools.gd").new()
	var analyze_result: Variant = analysis_tools.call(&"analyze", {&"action": &"nonexistent"})
	_assert(analyze_result is Dictionary and analyze_result.has(&"err"), "analyze unknown action should return err")

	# nav dispatcher
	var nav_tools: RefCounted = load("res://addons/godot_mcp/tools/navigation_tools.gd").new()
	var nav_result: Variant = nav_tools.call(&"nav", {&"action": &"nonexistent"})
	_assert(nav_result is Dictionary and nav_result.has(&"err"), "nav unknown action should return err")

	# theme dispatcher
	var theme_tools: RefCounted = load("res://addons/godot_mcp/tools/theme_tools.gd").new()
	var theme_result: Variant = theme_tools.call(&"theme", {&"action": &"nonexistent"})
	_assert(theme_result is Dictionary and theme_result.has(&"err"), "theme unknown action should return err")

	# shader dispatcher
	var shader_tools: RefCounted = load("res://addons/godot_mcp/tools/shader_tools.gd").new()
	var shader_result: Variant = shader_tools.call(&"shader", {&"action": &"nonexistent"})
	_assert(shader_result is Dictionary and shader_result.has(&"err"), "shader unknown action should return err")

	# audio dispatcher
	var audio_tools: RefCounted = load("res://addons/godot_mcp/tools/audio_tools.gd").new()
	var audio_result: Variant = audio_tools.call(&"audio", {&"action": &"nonexistent"})
	_assert(audio_result is Dictionary and audio_result.has(&"err"), "audio unknown action should return err")

	# tmap dispatcher
	var tmap_tools: RefCounted = load("res://addons/godot_mcp/tools/tilemap_tools.gd").new()
	var tmap_result: Variant = tmap_tools.call(&"tmap", {&"action": &"nonexistent"})
	_assert(tmap_result is Dictionary and tmap_result.has(&"err"), "tmap unknown action should return err")

	# tres dispatcher
	var tres_tools: RefCounted = load("res://addons/godot_mcp/tools/resource_tools.gd").new()
	var tres_result: Variant = tres_tools.call(&"tres", {&"action": &"nonexistent"})
	_assert(tres_result is Dictionary and tres_result.has(&"err"), "tres unknown action should return err")

	# ptcl dispatcher
	var ptcl_tools: RefCounted = load("res://addons/godot_mcp/tools/particle_tools.gd").new()
	var ptcl_result: Variant = ptcl_tools.call(&"ptcl", {&"action": &"nonexistent"})
	_assert(ptcl_result is Dictionary and ptcl_result.has(&"err"), "ptcl unknown action should return err")

	# perf dispatcher
	var perf_tools: RefCounted = load("res://addons/godot_mcp/tools/profiling_tools.gd").new()
	var perf_result: Variant = perf_tools.call(&"perf", {&"action": &"nonexistent"})
	_assert(perf_result is Dictionary and perf_result.has(&"err"), "perf unknown action should return err")

	# input dispatcher
	var input_tools: RefCounted = load("res://addons/godot_mcp/tools/input_tools.gd").new()
	var input_result: Variant = input_tools.call(&"input", {&"action": &"nonexistent"})
	_assert(input_result is Dictionary and input_result.has(&"err"), "input unknown action should return err")

	# s3d dispatcher
	var s3d_tools: RefCounted = load("res://addons/godot_mcp/tools/scene3d_tools.gd").new()
	var s3d_result: Variant = s3d_tools.call(&"s3d", {&"action": &"nonexistent"})
	_assert(s3d_result is Dictionary and s3d_result.has(&"err"), "s3d unknown action should return err")


# =============================================================================
# Valid action routing — verify known actions don't crash (may return err due to no editor)
# =============================================================================
func _test_valid_action_routing() -> void:
	# file valid actions
	var ft: RefCounted = load("res://addons/godot_mcp/tools/file_tools.gd").new()
	for action: String in ["ls", "read", "reads", "create", "search", "mkdir", "rm", "rmdir", "rename", "replace", "bulk_edit", "refs", "resources"]:
		var result: Variant = ft.call(&"file", {&"action": action})
		_assert(result is Dictionary, "file action '%s' returns Dictionary" % action)

	# proj valid actions (most will fail without editor but shouldn't crash)
	var pt: RefCounted = load("res://addons/godot_mcp/tools/project_tools.gd").new()
	for action: String in ["settings", "autoloads", "clear_console", "tree", "stop", "running", "classes"]:
		var result: Variant = pt.call(&"proj", {&"action": action})
		_assert(result is Dictionary, "proj action '%s' returns Dictionary" % action)

	# scene valid actions
	var st: RefCounted = load("res://addons/godot_mcp/tools/scene_tools.gd").new()
	for action: String in ["find_by_type", "set_by_type"]:
		var result: Variant = st.call(&"scene", {&"action": action, &"scene_path": "res://nonexistent.tscn", &"type": "Node"})
		_assert(result is Dictionary, "scene action '%s' returns Dictionary" % action)

	# script valid actions
	var scr: RefCounted = load("res://addons/godot_mcp/tools/script_tools.gd").new()
	var list_result: Variant = scr.call(&"script", {&"action": &"list"})
	_assert(list_result is Dictionary, "script action 'list' returns Dictionary")


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  %s" % msg.get_slice(" should ", 0))
	else:
		_fail_count += 1
		printerr("  FAIL  %s" % msg)

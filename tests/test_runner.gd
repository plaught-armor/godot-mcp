extends SceneTree
## Headless test runner for godot-mcp.
## Discovers and runs all test_*.gd scripts in res://tests/.
## Exit code 0 = all pass, 1 = failures.
##
## Usage: godot --headless --path . --script tests/test_runner.gd

var _pass_count: int = 0
var _fail_count: int = 0
var _current_suite: String = ""


func _init() -> void:
	var test_dir: String = "res://tests/"
	var dir: DirAccess = DirAccess.open(test_dir)
	if dir == null:
		printerr("Cannot open test directory: ", test_dir)
		quit(1)
		return

	var test_files: PackedStringArray = []
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while not file.is_empty():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_runner.gd":
			test_files.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	test_files.sort()

	if test_files.is_empty():
		print("No test files found in ", test_dir)
		quit(1)
		return

	print("=== godot-mcp test runner ===")
	print("Found %d test suites\n" % test_files.size())

	for test_file: String in test_files:
		_run_suite(test_dir + test_file)

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func _run_suite(path: String) -> void:
	_current_suite = path.get_file().trim_suffix(".gd")
	var script: GDScript = load(path)
	if script == null:
		_fail("Failed to load: " + path)
		return

	var instance: RefCounted = script.new()
	if instance == null:
		_fail("Failed to instantiate: " + path)
		return

	# Call every method starting with "test_"
	var methods: Array[Dictionary] = instance.get_method_list()
	var test_count: int = 0
	for m: Dictionary in methods:
		var method_name: String = m[&"name"]
		if method_name.begins_with("test_"):
			test_count += 1
			_run_test(instance, method_name)

	if test_count == 0:
		print("  [WARN] %s: no test_ methods found" % _current_suite)


func _run_test(instance: RefCounted, method: String) -> void:
	var result: Variant = instance.call(method)
	if result is String and result.is_empty():
		_pass("%s.%s" % [_current_suite, method])
	else:
		_fail("%s.%s: %s" % [_current_suite, method, str(result)])


func _pass(name: String) -> void:
	_pass_count += 1
	print("  PASS  %s" % name)


func _fail(name: String) -> void:
	_fail_count += 1
	printerr("  FAIL  %s" % name)

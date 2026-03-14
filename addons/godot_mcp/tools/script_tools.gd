@tool
extends RefCounted

class_name ScriptTools
## GDScript tools for MCP.
## Handles: create_script, edit_script, validate_script, validate_scripts,
##          list_scripts, get_script_symbols, find_class_definition

var _editor_plugin: EditorPlugin = null

# Cached RegEx patterns for script modification helpers
var _re_helper_var: RegEx
var _re_helper_func: RegEx
var _re_helper_class: RegEx
var _re_helper_signal: RegEx
var _re_identifier: RegEx


func _init() -> void:
	_re_helper_var = RegEx.create_from_string("^(@export)?\\s*(@onready)?\\s*var\\s+")
	_re_helper_func = RegEx.create_from_string("^func\\s+")
	_re_helper_class = RegEx.create_from_string("^(class_name|extends)\\s+")
	_re_helper_signal = RegEx.create_from_string("^signal\\s+")
	_re_identifier = RegEx.create_from_string("^[a-zA-Z_][a-zA-Z0-9_]*$")


## Validate that a name is a legal GDScript identifier (prevents regex injection).
func _is_valid_identifier(name: String) -> bool:
	return not name.is_empty() and _re_identifier.search(name) != null


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


var _utils: ToolUtils


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


## Run the configured formatter on a script file if auto-format is enabled.
func _auto_format(path: String) -> void:
	if not ProjectSettings.get_setting(&"godot_mcp/auto_format_scripts", false):
		return
	var cmd: String = ProjectSettings.get_setting(&"godot_mcp/script_formatter_command", "gdscript-formatter")
	if not _is_safe_command(cmd):
		return
	var abs_path := ProjectSettings.globalize_path(path)
	var output: Array = []
	OS.execute(cmd, [abs_path], output)


## Reject commands with shell metacharacters or path traversal.
static func _is_safe_command(cmd: String) -> bool:
	if cmd.is_empty():
		return false
	# Only allow simple command names or absolute paths to executables.
	# Block shell operators, pipes, backticks, semicolons, etc.
	for c: String in [";", "|", "&", "`", "$", "(", ")", "{", "}", "<", ">", "\n", "\r"]:
		if cmd.find(c) != -1:
			push_warning("[GMCP] Refusing formatter command with shell metacharacter: ", cmd)
			return false
	return true


# =============================================================================
# edit_script - Apply a small surgical code edit to a GDScript file
# =============================================================================
func edit_script(args: Dictionary) -> Dictionary:
	var edit: Dictionary = args.get(&"edit", { })
	if edit.is_empty():
		return { &"ok": false, &"error": "Missing 'edit' payload" }

	var path: String = str(edit.get(&"file", ""))
	if path.is_empty():
		return { &"ok": false, &"error": "Missing 'file' in edit" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	var spec_type: String = str(edit.get(&"type", "snippet_replace"))
	if spec_type != "snippet_replace":
		return { &"ok": false, &"error": "Only 'snippet_replace' type is supported" }

	var old_snippet: String = str(edit.get(&"old_snippet", ""))
	var new_snippet: String = str(edit.get(&"new_snippet", ""))
	var context_before: String = str(edit.get(&"context_before", ""))
	var context_after: String = str(edit.get(&"context_after", ""))

	if old_snippet.is_empty():
		return { &"ok": false, &"error": "Missing 'old_snippet' in edit" }

	# Read current file content
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return { &"ok": false, &"error": "Cannot read file: " + path }
	var content := file.get_as_text()
	file.close()

	# Find and replace the snippet
	var search_text := old_snippet
	var pos := content.find(search_text)

	# If not found directly, try with context
	if pos == -1 and not context_before.is_empty():
		var ctx_pos := content.find(context_before)
		if ctx_pos != -1:
			var after_ctx := ctx_pos + context_before.length()
			var remaining := content.substr(after_ctx)
			var snippet_pos := remaining.find(old_snippet)
			if snippet_pos != -1:
				pos = after_ctx + snippet_pos

	if pos == -1:
		return { &"ok": false, &"error": "Could not find old_snippet in file. Make sure old_snippet matches the file content exactly." }

	# Check for multiple occurrences
	var second_pos := content.find(search_text, pos + 1)
	if second_pos != -1 and context_before.is_empty() and context_after.is_empty():
		return { &"ok": false, &"error": "old_snippet appears multiple times. Add context_before or context_after for disambiguation." }

	# Apply the replacement
	var new_content := content.substr(0, pos) + new_snippet + content.substr(pos + old_snippet.length())

	# Write back
	file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return { &"ok": false, &"error": "Cannot write file: " + path }
	file.store_string(new_content)
	file.close()

	# Count changes
	var old_lines := old_snippet.split("\n")
	var new_lines := new_snippet.split("\n")
	var added := maxi(0, new_lines.size() - old_lines.size())
	var removed := maxi(0, old_lines.size() - new_lines.size())

	_auto_format(path)
	_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"added": added,
		&"removed": removed,
		&"auto_applied": true,
		&"message": "Applied edit to %s (+%d -%d lines)" % [path, added, removed],
	}


# =============================================================================
# validate_script
# =============================================================================
func validate_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	# Read the source text directly from disk so we validate the *current*
	# file contents, not a stale resource-cache entry.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return { &"ok": false, &"error": "Cannot read file: " + path }
	var source_code := file.get_as_text()
	file.close()

	# Create a fresh GDScript instance and assign the source for parsing.
	var script := GDScript.new()
	script.source_code = source_code

	# reload() triggers the parser/compiler and returns OK or an error code.
	var err := script.reload()

	if err != OK:
		# Try to extract useful details from the Godot output log.
		var errors := _collect_recent_script_errors(path)
		return {
			&"ok": true,
			&"valid": false,
			&"path": path,
			&"error_code": err,
			&"errors": errors,
			&"message": "Script has errors." + (" Details: " + "; ".join(errors) if errors.size() > 0 else " Check Godot console for details."),
		}

	if not script.can_instantiate():
		return {
			&"ok": true,
			&"valid": false,
			&"path": path,
			&"message": "Script parsed but cannot be instantiated (may have dependency errors)",
		}

	return {
		&"ok": true,
		&"valid": true,
		&"path": path,
		&"message": "No syntax errors found",
	}


## Grab recent SCRIPT ERROR / Parse Error lines from the editor Output panel
## that mention the given script path. Best-effort — returns [code][][/code] if
## the panel cannot be accessed.
func _collect_recent_script_errors(script_path: String) -> Array:
	var errors: Array = []
	if not _editor_plugin:
		return errors

	# Find the editor's Output panel RichTextLabel
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var editor_log := _utils.find_node_by_class(base, "EditorLog")
	if not editor_log:
		return errors
	var rtl := _utils.find_child_rtl(editor_log)
	if not rtl:
		return errors

	var text: String = rtl.get_parsed_text()
	var short_path := script_path.get_file() # e.g. "player.gd"

	for line: String in text.split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		if short_path in line or script_path in line:
			if line.begins_with("SCRIPT ERROR:") or line.begins_with("Parse Error:") \
			or line.begins_with("ERROR:") or line.begins_with("at:"):
				errors.append(line)

	# Keep only the last 10 relevant lines
	if errors.size() > 10:
		errors = errors.slice(errors.size() - 10)
	return errors


# =============================================================================
# validate_scripts - Batch validate multiple scripts
# =============================================================================
const MAX_VALIDATE_BATCH := 50

## Validate multiple GDScript files in a single call.
func validate_scripts(args: Dictionary) -> Dictionary:
	var paths: Array = args.get(&"paths", [])
	if paths.is_empty():
		return { &"ok": false, &"error": "Missing 'paths' array" }
	if paths.size() > MAX_VALIDATE_BATCH:
		return { &"ok": false, &"error": "Too many paths (%d). Maximum is %d" % [paths.size(), MAX_VALIDATE_BATCH] }

	var results: Array = []
	var valid_count := 0
	var error_count := 0

	for p: Variant in paths:
		var result := validate_script({ &"path": str(p) })
		var entry: Dictionary = { &"path": str(p) }
		if not result[&"ok"]:
			entry[&"valid"] = false
			entry[&"error"] = result[&"error"]
			error_count += 1
		elif result.get(&"valid", false):
			entry[&"valid"] = true
			valid_count += 1
		else:
			entry[&"valid"] = false
			entry[&"errors"] = result.get(&"errors", [result.get(&"message", "Unknown error")])
			error_count += 1
		results.append(entry)

	return {
		&"ok": true,
		&"results": results,
		&"valid_count": valid_count,
		&"error_count": error_count,
	}


# =============================================================================
# get_script_symbols - Extract methods/variables/signals from a script
# =============================================================================
## Return all user-defined methods, variables, and signals from a GDScript file.
func get_script_symbols(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	# Load script to introspect
	var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if script == null or not script is GDScript:
		return { &"ok": false, &"error": "Cannot load script: " + path }

	# Get the base class methods/properties/signals to filter them out
	var base_methods: Dictionary = {}
	var base_properties: Dictionary = {}
	var base_signals: Dictionary = {}
	var base_script = script.get_base_script()
	if base_script == null:
		# Native base class — get its methods to exclude
		var instance = script.new() if script.can_instantiate() else null
		if instance:
			var base_class: String = instance.get_class()
			for m: Dictionary in ClassDB.class_get_method_list(base_class, true):
				base_methods[m[&"name"]] = true
			for p: Dictionary in ClassDB.class_get_property_list(base_class, true):
				base_properties[p[&"name"]] = true
			for s: Dictionary in ClassDB.class_get_signal_list(base_class, true):
				base_signals[s[&"name"]] = true
			if instance is Node:
				instance.queue_free()

	# Methods
	var methods: Array = []
	for m: Dictionary in script.get_script_method_list():
		var mname: String = m[&"name"]
		if mname.begins_with("@") or mname in base_methods:
			continue
		var method_args: Array = []
		for a: Dictionary in m.get(&"args", []):
			method_args.append({
				&"name": a[&"name"],
				&"type": _utils.type_id_to_name(a[&"type"]),
			})
		methods.append({
			&"name": mname,
			&"args": method_args,
			&"return_type": _utils.type_id_to_name(m.get(&"return", {}).get(&"type", TYPE_NIL)),
		})

	# Variables (properties)
	var variables: Array = []
	for p: Dictionary in script.get_script_property_list():
		var pname: String = p[&"name"]
		if pname.begins_with("@") or pname in base_properties:
			continue
		variables.append({
			&"name": pname,
			&"type": _utils.type_id_to_name(p[&"type"]),
		})

	# Signals
	var signals: Array = []
	for s: Dictionary in script.get_script_signal_list():
		var sname: String = s[&"name"]
		if sname in base_signals:
			continue
		var sig_args: Array = []
		for a: Dictionary in s.get(&"args", []):
			sig_args.append({
				&"name": a[&"name"],
				&"type": _utils.type_id_to_name(a[&"type"]),
			})
		signals.append({
			&"name": sname,
			&"args": sig_args,
		})

	return {
		&"ok": true,
		&"path": path,
		&"methods": methods,
		&"variables": variables,
		&"signals": signals,
	}


# =============================================================================
# find_class_definition - Find the file that defines a class
# =============================================================================
## Search all [code].gd[/code] files for [code]class_name ClassName[/code].
func find_class_definition(args: Dictionary) -> Dictionary:
	var cls_name: String = str(args.get(&"class_name", ""))
	if cls_name.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'class_name'" }

	if not _is_valid_identifier(cls_name):
		return { &"ok": false, &"error": "Invalid class name: " + cls_name }

	var regex := RegEx.new()
	regex.compile("^class_name\\s+" + cls_name + "\\b")

	var scripts: PackedStringArray = []
	_collect_scripts("res://", scripts)

	for script_path: String in scripts:
		var file := FileAccess.open(script_path, FileAccess.READ)
		if file == null:
			continue
		var content := file.get_as_text()
		file.close()

		var lines := content.split("\n")
		for i: int in range(lines.size()):
			if regex.search(lines[i]) != null:
				return {
					&"ok": true,
					&"class_name": cls_name,
					&"file": script_path,
					&"line": i + 1,
				}

	return {
		&"ok": true,
		&"class_name": cls_name,
		&"file": "",
		&"message": "Class '%s' not found in any .gd file" % cls_name,
	}


# =============================================================================
# list_scripts
# =============================================================================
func list_scripts(args: Dictionary) -> Dictionary:
	var scripts: PackedStringArray = []
	_collect_scripts("res://", scripts)

	return {
		&"ok": true,
		&"scripts": scripts,
		&"count": scripts.size(),
	}


const MAX_TRAVERSAL_DEPTH := 20


func _collect_scripts(path: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			_collect_scripts(full_path, out, depth + 1)
		elif file_name.ends_with(".gd"):
			out.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# create_script - Create a new GDScript file
# =============================================================================
func create_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var content: String = str(args.get(&"content", ""))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path' parameter" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	# Add .gd extension if missing
	if not "." in path.get_file():
		path += ".gd"

	if FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File already exists: " + path }

	# Ensure parent directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return { &"ok": false, &"error": "Could not create directory: " + dir_path }

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { &"ok": false, &"error": "Could not create file: " + path }

	file.store_string(content)
	file.close()

	_auto_format(path)
	_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"size_bytes": content.length(),
		&"message": "Script created successfully",
	}


# =============================================================================
# format_script - Format a GDScript file using gdscript-formatter
# =============================================================================
func format_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	var abs_path := ProjectSettings.globalize_path(path)

	# Read original content for comparison
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return { &"ok": false, &"error": "Cannot read file: " + path }
	var original := file.get_as_text()
	file.close()

	# Run the configured formatter (formats in-place when given a file path)
	var cmd: String = ProjectSettings.get_setting(&"godot_mcp/script_formatter_command", "gdscript-formatter")
	if not _is_safe_command(cmd):
		return { &"ok": false, &"error": "No formatter command configured or command contains unsafe characters. Set godot_mcp/script_formatter_command in Project Settings." }
	var output: Array = []
	var exit_code := OS.execute(cmd, [abs_path], output)

	if exit_code == -1:
		return { &"ok": false, &"error": "'%s' not found. Install it or update godot_mcp/script_formatter_command in Project Settings." % cmd }

	if exit_code != 0:
		var error_text := ""
		if output.size() > 0:
			error_text = str(output[0]).strip_edges()
		return { &"ok": false, &"error": "Formatter failed (exit %d): %s" % [exit_code, error_text] }

	# Re-read to check if content changed
	file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return { &"ok": false, &"error": "Cannot read formatted file: " + path }
	var formatted := file.get_as_text()
	file.close()

	var changed := original != formatted
	if changed:
		_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"changed": changed,
		&"message": "Formatted " + path if changed else "No changes needed for " + path,
	}

# =============================================================================
# Visualizer script methods (called via WebSocket, not exposed as MCP tools)
# =============================================================================


## Create a new script file with a basic template.
func create_script_file(args: Dictionary) -> Dictionary:
	var script_path: String = args.get(&"path", "")
	var extends_type: String = args.get(&"extends", "Node")
	var class_name_str: String = args.get(&"class_name", "")

	if script_path.is_empty():
		return { &"ok": false, &"error": "No path provided" }

	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not script_path.ends_with(".gd"):
		script_path += ".gd"

	if FileAccess.file_exists(script_path):
		return { &"ok": false, &"error": "File already exists: " + script_path }

	# Create directory if needed
	var dir_path: String = script_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return { &"ok": false, &"error": "Failed to create directory" }

	# Build script content
	var content := ""
	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n"
	content += "extends " + extends_type + "\n"
	content += "\n\n"
	content += "func _ready() -> void:\n"
	content += "\tpass\n"

	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return { &"ok": false, &"error": "Cannot create file: " + script_path }

	file.store_string(content)
	file.close()

	_auto_format(script_path)
	return { &"ok": true, &"path": script_path }


## Add, update, or delete a variable in a script file.
func modify_variable(args: Dictionary) -> Dictionary:
	var script_path: String = args.get(&"path", "")
	var action: String = args.get(&"action", "")
	var old_name: String = args.get(&"old_name", "")
	var new_name: String = args.get(&"name", "")
	var var_type: String = args.get(&"type", "")
	var default_val: String = args.get(&"default", "")
	var exported: bool = args.get(&"exported", false)
	var onready: bool = args.get(&"onready", false)

	if script_path.is_empty():
		return { &"ok": false, &"error": "No script path provided" }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	# Validate identifiers to prevent regex injection
	if not old_name.is_empty() and not _is_valid_identifier(old_name):
		return { &"ok": false, &"error": "Invalid identifier: " + old_name }
	if not new_name.is_empty() and not _is_valid_identifier(new_name):
		return { &"ok": false, &"error": "Invalid identifier: " + new_name }

	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return { &"ok": false, &"error": "Cannot open file: " + script_path }

	var content: String = file.get_as_text()
	file.close()

	var lines: Array = Array(content.split("\n"))
	var modified := false

	if action == "delete":
		var pattern := RegEx.new()
		pattern.compile("^(@export(?:\\([^)]*\\))?\\s+)?(?:@onready\\s+)?var\\s+" + old_name + "\\s*(?::|=|$)")
		for i: int in range(lines.size() - 1, -1, -1):
			if pattern.search(lines[i].strip_edges()):
				lines.remove_at(i)
				modified = true
				break

	elif action == "update":
		var pattern := RegEx.new()
		pattern.compile("^(@export(?:\\([^)]*\\))?\\s+)?(@onready\\s+)?var\\s+" + old_name + "\\s*(?::\\s*\\w+)?(?:\\s*=\\s*.+)?$")
		for i: int in range(lines.size()):
			var m := pattern.search(lines[i].strip_edges())
			if m:
				var new_line := _build_var_line(new_name, var_type, default_val, exported, onready)
				lines[i] = new_line
				modified = true
				break

	elif action == "add":
		var insert_pos := _find_var_insert_position(lines, exported)
		var new_line := _build_var_line(new_name, var_type, default_val, exported, false)
		lines.insert(insert_pos, new_line)
		modified = true

	if modified:
		var new_content := "\n".join(PackedStringArray(lines))
		var write_file := FileAccess.open(script_path, FileAccess.WRITE)
		if write_file == null:
			return { &"ok": false, &"error": "Cannot write to file: " + script_path }
		write_file.store_string(new_content)
		write_file.close()
		_auto_format(script_path)
		return { &"ok": true, &"action": action, &"variable": new_name }

	return { &"ok": false, &"error": "Variable not found: " + old_name }


## Add, update, or delete a signal in a script file.
func modify_signal(args: Dictionary) -> Dictionary:
	var script_path: String = args.get(&"path", "")
	var action: String = args.get(&"action", "")
	var old_name: String = args.get(&"old_name", "")
	var new_name: String = args.get(&"name", "")
	var params: String = args.get(&"params", "")

	if script_path.is_empty():
		return { &"ok": false, &"error": "No script path provided" }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	# Validate identifiers to prevent regex injection
	if not old_name.is_empty() and not _is_valid_identifier(old_name):
		return { &"ok": false, &"error": "Invalid signal name: " + old_name }
	if not new_name.is_empty() and not _is_valid_identifier(new_name):
		return { &"ok": false, &"error": "Invalid signal name: " + new_name }

	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return { &"ok": false, &"error": "Cannot open file: " + script_path }

	var content: String = file.get_as_text()
	file.close()

	var lines: Array = Array(content.split("\n"))
	var modified := false

	if action == "delete":
		var pattern := RegEx.new()
		pattern.compile("^signal\\s+" + old_name + "(?:\\s*\\(|$)")
		for i: int in range(lines.size() - 1, -1, -1):
			if pattern.search(lines[i].strip_edges()):
				lines.remove_at(i)
				modified = true
				break

	elif action == "update":
		var pattern := RegEx.new()
		pattern.compile("^signal\\s+" + old_name + "(?:\\s*\\([^)]*\\))?$")
		for i: int in range(lines.size()):
			if pattern.search(lines[i].strip_edges()):
				var new_line := "signal " + new_name
				if not params.is_empty():
					new_line += "(" + params + ")"
				lines[i] = new_line
				modified = true
				break

	elif action == "add":
		var insert_pos := _find_signal_insert_position(lines)
		var new_line := "signal " + new_name
		if not params.is_empty():
			new_line += "(" + params + ")"
		lines.insert(insert_pos, new_line)
		modified = true

	if modified:
		var new_content := "\n".join(PackedStringArray(lines))
		var write_file := FileAccess.open(script_path, FileAccess.WRITE)
		if write_file == null:
			return { &"ok": false, &"error": "Cannot write to file: " + script_path }
		write_file.store_string(new_content)
		write_file.close()
		_auto_format(script_path)
		return { &"ok": true, &"action": action, &"signal": new_name }

	return { &"ok": false, &"error": "Signal not found: " + old_name }


## Update a function's body in a script file.
func modify_function(args: Dictionary) -> Dictionary:
	var script_path: String = args.get(&"path", "")
	var func_name: String = args.get(&"name", "")
	var new_body: String = args.get(&"body", "")

	if script_path.is_empty() or func_name.is_empty():
		return { &"ok": false, &"error": "Missing path or function name" }
	if not _is_valid_identifier(func_name):
		return { &"ok": false, &"error": "Invalid function name: " + func_name }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return { &"ok": false, &"error": "Cannot open file: " + script_path }

	var content: String = file.get_as_text()
	file.close()

	var lines: Array = Array(content.split("\n"))
	var range_result := _find_function_range(lines, func_name)
	if range_result.is_empty():
		return { &"ok": false, &"error": "Function not found: " + func_name }

	var func_start: int = range_result[0]
	var func_end: int = range_result[1]

	var new_lines := Array(new_body.split("\n"))

	# Splice: keep lines before func_start, insert new body, keep lines after func_end
	var spliced: Array = lines.slice(0, func_start) + new_lines + lines.slice(func_end)

	var new_content := "\n".join(PackedStringArray(spliced))
	var write_file := FileAccess.open(script_path, FileAccess.WRITE)
	if write_file == null:
		return { &"ok": false, &"error": "Cannot write to file: " + script_path }
	write_file.store_string(new_content)
	write_file.close()

	_auto_format(script_path)
	return { &"ok": true, &"function": func_name }


## Delete a function from a script file.
func modify_function_delete(args: Dictionary) -> Dictionary:
	var script_path: String = args.get(&"path", "")
	var func_name: String = args.get(&"name", "")

	if script_path.is_empty() or func_name.is_empty():
		return { &"ok": false, &"error": "Missing path or function name" }
	if not _is_valid_identifier(func_name):
		return { &"ok": false, &"error": "Invalid function name: " + func_name }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return { &"ok": false, &"error": "Cannot open file: " + script_path }

	var content: String = file.get_as_text()
	file.close()

	var lines: Array = Array(content.split("\n"))
	var range_result := _find_function_range(lines, func_name)
	if range_result.is_empty():
		return { &"ok": false, &"error": "Function not found: " + func_name }

	var func_start: int = range_result[0]
	var func_end: int = range_result[1]

	# Splice out the function range
	var spliced: Array = lines.slice(0, func_start) + lines.slice(func_end)

	var new_content := "\n".join(PackedStringArray(spliced))
	var write_file := FileAccess.open(script_path, FileAccess.WRITE)
	if write_file == null:
		return { &"ok": false, &"error": "Cannot write to file: " + script_path }
	write_file.store_string(new_content)
	write_file.close()

	_auto_format(script_path)
	return { &"ok": true, &"deleted": func_name }


## Find the start and end line indices of a function. Returns [code][start, end][/code] or [code][][/code] if not found.
func _find_function_range(lines: Array, func_name: String) -> Array:
	var re_func := RegEx.new()
	re_func.compile("^func\\s+" + func_name + "\\s*\\(")

	var func_start := -1
	var func_end := -1

	for i: int in range(lines.size()):
		if func_start == -1:
			if re_func.search(lines[i].strip_edges()):
				func_start = i
		else:
			var stripped: String = lines[i].strip_edges()
			if not stripped.is_empty() and not lines[i].begins_with("\t") and not lines[i].begins_with(" ") and not stripped.begins_with("#"):
				func_end = i
				break

	if func_start == -1:
		return []

	if func_end == -1:
		func_end = lines.size()

	while func_end > func_start + 1 and lines[func_end - 1].strip_edges().is_empty():
		func_end -= 1

	return [func_start, func_end]


## Delete a script file from the project.
func delete_script(args: Dictionary) -> Dictionary:
	var path: String = args.get(&"path", "")

	if path.is_empty():
		return { &"ok": false, &"error": "No path provided" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to delete: " + str(err) }

	# Also remove .import file if it exists
	var import_path := path + ".import"
	if FileAccess.file_exists(import_path):
		DirAccess.remove_absolute(import_path)

	_utils.refresh_filesystem()
	return { &"ok": true, &"path": path }


## Rename/move a script file, optionally updating references.
func rename_script(args: Dictionary) -> Dictionary:
	var old_path: String = args.get(&"old_path", "")
	var new_path: String = args.get(&"new_path", "")
	var update_refs: bool = args.get(&"update_references", true)

	if old_path.is_empty():
		return { &"ok": false, &"error": "No old_path provided" }
	if new_path.is_empty():
		return { &"ok": false, &"error": "No new_path provided" }

	old_path = _utils.validate_res_path(old_path)
	if old_path.is_empty():
		return { &"ok": false, &"error": "old_path escapes project root" }
	new_path = _utils.validate_res_path(new_path)
	if new_path.is_empty():
		return { &"ok": false, &"error": "new_path escapes project root" }

	if not FileAccess.file_exists(old_path):
		return { &"ok": false, &"error": "File not found: " + old_path }
	if FileAccess.file_exists(new_path):
		return { &"ok": false, &"error": "Target already exists: " + new_path }

	# Ensure target directory exists
	var dir_path := new_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var dir_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if dir_err != OK:
			return { &"ok": false, &"error": "Failed to create directory: " + dir_path }

	# Update references in other files first (before renaming)
	var updated_files: Array = []
	if update_refs:
		updated_files = _update_script_references(old_path, new_path)

	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to rename: " + str(err) }

	_utils.refresh_filesystem()
	return {
		&"ok": true,
		&"old_path": old_path,
		&"new_path": new_path,
		&"updated_references": updated_files.size(),
		&"files": updated_files,
	}

# Helper functions for script modification


func _build_var_line(var_name: String, type: String, default: String, exported: bool, onready: bool) -> String:
	var line := ""
	if exported:
		line += "@export "
	if onready:
		line += "@onready "
	line += "var " + var_name
	if not type.is_empty():
		line += ": " + type
	if not default.is_empty():
		line += " = " + default
	return line


## Find the best position to insert a new variable.
func _find_var_insert_position(lines: Array, exported: bool) -> int:
	var last_var_line := -1
	var first_func_line := -1
	var after_class_decl := 0

	for i: int in range(lines.size()):
		var stripped: String = lines[i].strip_edges()
		if _re_helper_class.search(stripped):
			after_class_decl = i + 1
		if _re_helper_var.search(stripped):
			last_var_line = i
		if _re_helper_func.search(stripped) and first_func_line == -1:
			first_func_line = i
			break

	if last_var_line != -1:
		return last_var_line + 1
	if first_func_line != -1:
		return first_func_line
	return max(after_class_decl, 2)


## Find the best position to insert a new signal.
func _find_signal_insert_position(lines: Array) -> int:
	var last_signal_line := -1
	var first_var_line := -1
	var after_class_decl := 0

	for i: int in range(lines.size()):
		var stripped: String = lines[i].strip_edges()
		if _re_helper_class.search(stripped):
			after_class_decl = i + 1
		if _re_helper_signal.search(stripped):
			last_signal_line = i
		if _re_helper_var.search(stripped) and first_var_line == -1:
			first_var_line = i

	if last_signal_line != -1:
		return last_signal_line + 1
	if first_var_line != -1:
		return first_var_line
	return max(after_class_decl, 2)


## Update all references to [param old_path] in project files.
func _update_script_references(old_path: String, new_path: String) -> Array:
	var updated: Array = []
	var files: Array = []
	_collect_files_by_ext("res://", ["gd", "tscn", "tres"], files)

	for file_path: String in files:
		if file_path == old_path:
			continue

		var content := FileAccess.get_file_as_string(file_path)
		if content.is_empty():
			continue

		if old_path not in content:
			continue

		var new_content := content.replace(old_path, new_path)
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(new_content)
			file.close()
			updated.append(file_path)

	return updated


## Recursively collect files with the given extensions.
func _collect_files_by_ext(root: String, extensions: Array, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if entry != "." and entry != ".." and entry != ".godot":
				_collect_files_by_ext(root.path_join(entry), extensions, out)
		else:
			if entry.get_extension() in extensions:
				out.append(root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()

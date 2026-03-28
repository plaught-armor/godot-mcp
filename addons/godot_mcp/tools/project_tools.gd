@tool
extends RefCounted

class_name ProjectTools
## Project configuration and debug tools for MCP.
## Handles: get_project_settings, set_project_setting, get_autoloads,
##          get_input_map, configure_input_map, get_collision_layers,
##          get_node_properties, get_console_log, get_errors, get_debug_errors,
##          clear_console_log, open_in_godot, scene_tree_dump,
##          play_project, stop_project, is_project_running,
##          git, run_shell_command, get_uid, query_class_info, query_classes

var _editor_plugin: EditorPlugin = null

# Cached reference to the editor Output panel's RichTextLabel.
var _editor_log_rtl: RichTextLabel = null

# Character offset for clear_console_log.
var _clear_char_offset: int = 0

var _utils: ToolUtils
var _project_path: String = ProjectSettings.globalize_path("res://")


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# get_project_settings
# =============================================================================
func get_project_settings(args: Dictionary) -> Dictionary:
	var include_render: bool = args.get(&"include_render", true)
	var include_physics: bool = args.get(&"include_physics", true)

	var out: Dictionary = { }
	out[&"main_scene"] = str(ProjectSettings.get_setting("application/run/main_scene", ""))

	# Window size
	var width: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", null)
	var height: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", null)
	if width != null:
		out[&"window_width"] = int(width)
	if height != null:
		out[&"window_height"] = int(height)

	# Stretch
	var stretch_mode: Variant = ProjectSettings.get_setting("display/window/stretch/mode", null)
	var stretch_aspect: Variant = ProjectSettings.get_setting("display/window/stretch/aspect", null)
	if stretch_mode != null:
		out[&"stretch_mode"] = str(stretch_mode)
	if stretch_aspect != null:
		out[&"stretch_aspect"] = str(stretch_aspect)

	if include_physics:
		var pps: Variant = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", null)
		if pps != null:
			out[&"physics_ticks_per_second"] = int(pps)

	if include_render:
		var method: Variant = ProjectSettings.get_setting("rendering/renderer/rendering_method", null)
		if method != null:
			out[&"rendering_method"] = str(method)
		var vsync: Variant = ProjectSettings.get_setting("display/window/vsync/vsync_mode", null)
		if vsync != null:
			out[&"vsync"] = str(vsync)

	return { &"settings": out }


# =============================================================================
# set_project_setting
# =============================================================================
func set_project_setting(args: Dictionary) -> Dictionary:
	var setting: String = args[&"setting"]
	if setting.strip_edges().is_empty():
		return { &"err": "Missing 'setting'" }
	if not args.has(&"value"):
		return { &"err": "Missing 'value'" }

	var old_value: Variant = ProjectSettings.get_setting(setting) if ProjectSettings.has_setting(setting) else null
	var new_value: Variant = args[&"value"]

	ProjectSettings.set_setting(setting, new_value)
	var save_err: Error = ProjectSettings.save()
	if save_err != OK:
		return { &"err": "Failed to save project settings (error %d)" % save_err }

	return { &"old": _utils.serialize_value(old_value) }


# =============================================================================
# get_autoloads - List all registered autoloads
# =============================================================================
## Return all registered autoloads with their paths and singleton status.
func get_autoloads(_args: Dictionary) -> Dictionary:
	var autoloads: Array[Dictionary] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var name: String = prop[&"name"]
		if not name.begins_with("autoload/"):
			continue
		var value: String = str(ProjectSettings.get_setting(name))
		var autoload_name: String = name.substr(9) # Strip "autoload/"
		var is_singleton: bool = value.begins_with("*")
		var path: String = value.substr(1) if is_singleton else value
		autoloads.append(
			{
				&"name": autoload_name,
				&"path": path,
				&"singleton": is_singleton,
			},
		)
	return { &"autoloads": _utils.tabular(autoloads, [&"name", &"path", &"singleton"]) }


# =============================================================================
# get_node_properties
# =============================================================================
const ENUM_HINTS: Dictionary = {
	"anchors_preset": "0:Top Left,1:Top Right,2:Bottom Right,3:Bottom Left,4:Center Left,5:Center Top,6:Center Right,7:Center Bottom,8:Center,9:Left Wide,10:Top Wide,11:Right Wide,12:Bottom Wide,13:VCenter Wide,14:HCenter Wide,15:Full Rect",
	"grow_horizontal": "0:Begin,1:End,2:Both",
	"grow_vertical": "0:Begin,1:End,2:Both",
	"horizontal_alignment": "0:Left,1:Center,2:Right,3:Fill",
	"vertical_alignment": "0:Top,1:Center,2:Bottom,3:Fill",
}


func get_node_properties(args: Dictionary) -> Dictionary:
	var node_type: String = args[&"node_type"]
	if node_type.strip_edges().is_empty():
		return { &"err": "Missing 'node_type'" }
	if not ClassDB.class_exists(node_type):
		return { &"err": "Unknown node type: " + node_type, &"sug": "Use query_classes to find valid node types" }

	var temp: Variant = ClassDB.instantiate(node_type)
	if not temp:
		return { &"err": "Cannot instantiate: " + node_type }

	var properties: Array[Dictionary] = []
	for prop: Dictionary in temp.get_property_list():
		var prop_name: String = prop[&"name"]
		if prop_name.begins_with("_"):
			continue
		if _utils.SKIP_PROPS.has(prop_name):
			continue
		if not (prop[&"usage"] & PROPERTY_USAGE_EDITOR):
			continue

		var type_name: String = _utils.type_id_to_name(prop[&"type"])
		if prop[&"type"] == TYPE_OBJECT:
			type_name = "Resource"
		var info: Dictionary = {
			&"name": prop_name,
			&"type": type_name,
			&"default": _utils.serialize_value(temp.get(prop_name)),
		}

		# Enum hints — only include when there's actual data
		if prop_name in ENUM_HINTS:
			info[&"enum_values"] = ENUM_HINTS[prop_name]
		elif prop[&"hint"] == PROPERTY_HINT_ENUM and not prop[&"hint_string"].is_empty():
			info[&"enum_values"] = prop[&"hint_string"]

		properties.append(info)

	if temp is Node:
		temp.queue_free()
	else:
		temp.free()

	# Inheritance chain
	var chain: Array[String] = []
	var cls: String = node_type
	while cls != "":
		chain.append(cls)
		cls = ClassDB.get_parent_class(cls)

	return {
		&"inheritance_chain": chain,
		&"properties": properties,
	}

# =============================================================================
# Editor Output Panel access
# =============================================================================
# We read directly from the editor's internal EditorLog RichTextLabel.
# This is real-time and matches exactly what the user sees in the Output panel.
# =============================================================================


## Find (and cache) the [RichTextLabel] inside the editor's Output panel.
func _get_editor_log_rtl() -> RichTextLabel:
	if is_instance_valid(_editor_log_rtl):
		return _editor_log_rtl
	if not _editor_plugin:
		return null
	var base: Control = _editor_plugin.get_editor_interface().get_base_control()
	var editor_log: Node = _utils.find_node_by_class(base, &"EditorLog")
	if editor_log:
		_editor_log_rtl = _utils.find_child_rtl(editor_log)
	return _editor_log_rtl


## Return all non-empty lines from the editor Output panel (after clear offset).
func _read_output_panel_lines() -> Array[String]:
	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return []
	var full_text: String = rtl.get_parsed_text()
	if _clear_char_offset > 0 and _clear_char_offset < full_text.length():
		full_text = full_text.substr(_clear_char_offset)
	elif _clear_char_offset >= full_text.length():
		return []
	var lines: Array[String] = []
	for line: String in full_text.split("\n"):
		if not line.strip_edges().is_empty():
			lines.append(line)
	return lines


# =============================================================================
# get_console_log
# =============================================================================
func get_console_log(args: Dictionary) -> Dictionary:
	var max_lines: int = args.get(&"max_lines", 50)
	var filter_text: String = args.get(&"filter", "")
	var severity: String = args.get(&"severity", "all")

	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return {
			&"err": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	var all_lines: Array[String] = _read_output_panel_lines()

	# Filter by severity
	if severity != "all":
		var filtered: Array[String] = []
		for line: String in all_lines:
			match severity:
				"error":
					if line.containsn("ERROR") or line.containsn("SCRIPT ERROR"):
						filtered.append(line)
				"warning":
					if line.containsn("WARNING"):
						filtered.append(line)
				"info":
					if not line.containsn("ERROR") and not line.containsn("WARNING"):
						filtered.append(line)
		all_lines = filtered

	# Filter by substring
	if not filter_text.is_empty():
		var filtered: Array[String] = []
		for line: String in all_lines:
			if line.containsn(filter_text):
				filtered.append(line)
		all_lines = filtered

	var start: int = maxi(0, all_lines.size() - max_lines)
	var lines: Array[String] = all_lines.slice(start)
	return { &"lines": lines }

# =============================================================================
# get_errors
# =============================================================================
const _ERROR_PREFIXES: PackedStringArray = [
	"ERROR:",
	"SCRIPT ERROR:",
	"USER ERROR:",
	"WARNING:",
	"USER WARNING:",
	"SCRIPT WARNING:",
	"Parse Error:",
	"Invalid",
]


func get_errors(args: Dictionary) -> Dictionary:
	var max_errors: int = args.get(&"max_errors", 50)
	var include_warnings: bool = args.get(&"include_warnings", true)

	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return {
			&"err": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	var all_lines: Array[String] = _read_output_panel_lines()

	var all_errors: Array[Dictionary] = []
	for i: int in range(all_lines.size()):
		var line: String = all_lines[i].strip_edges()
		if line.is_empty():
			continue

		var is_error: bool = false
		var severity: String = "error"
		for prefix: String in _ERROR_PREFIXES:
			if line.begins_with(prefix):
				is_error = true
				if "WARNING" in prefix:
					severity = "warning"
				break

		# Godot continuation lines:  "at: res://path/file.gd:123"
		if not is_error and line.begins_with("at: ") and "res://" in line:
			if all_errors.size() > 0:
				var prev: Dictionary = all_errors[all_errors.size() - 1]
				var loc: Dictionary = _extract_file_line(line)
				if not loc.is_empty():
					# Set file/line from first frame if not already set
					if not prev.has(&"file"):
						prev[&"file"] = loc[&"file"]
						prev[&"line"] = loc.get(&"line", 0)
					# Collect as stack frame
					var frame: Dictionary = { &"text": line }
					frame[&"file"] = loc[&"file"]
					if loc.has(&"line"):
						frame[&"line"] = loc[&"line"]
					if not prev.has(&"stack"):
						prev[&"stack"] = []
					prev[&"stack"].append(frame)
			continue

		if not is_error:
			continue
		if severity == "warning" and not include_warnings:
			continue

		var error_info: Dictionary = { &"msg": line, &"sev": severity }
		var loc: Dictionary = _extract_file_line(line)
		if not loc.is_empty():
			error_info[&"file"] = loc[&"file"]
			error_info[&"line"] = loc.get(&"line", 0)
		all_errors.append(error_info)

	# Return the most recent errors
	var start: int = maxi(0, all_errors.size() - max_errors)
	var errors: Array[Dictionary] = all_errors.slice(start)
	return { &"errs": errors }


func _extract_file_line(text: String) -> Dictionary:
	var idx: int = text.find("res://")
	if idx == -1:
		return { }
	var rest: String = text.substr(idx)
	var colon_idx: int = rest.find(":", 6)
	if colon_idx == -1:
		return { &"file": rest.strip_edges() }
	var file_path: String = rest.substr(0, colon_idx)
	var after_colon: String = rest.substr(colon_idx + 1)
	var end: int = 0
	while end < after_colon.length() and after_colon.unicode_at(end) >= 48 and after_colon.unicode_at(end) <= 57:
		end += 1
	if end > 0:
		return { &"file": file_path, &"line": after_colon.substr(0, end).to_int() }
	return { &"file": file_path }

# =============================================================================
# get_debug_errors - Read errors from the Debugger > Errors tab
# =============================================================================
var _debugger_error_tree: Tree = null


func get_debug_errors(args: Dictionary) -> Dictionary:
	var max_errors: int = args.get(&"max_errors", 50)
	var include_warnings: bool = args.get(&"include_warnings", true)

	var tree: Tree = _get_debugger_error_tree()
	if not tree:
		return { &"errs": [] }

	var errors: Array[Dictionary] = []
	var item: TreeItem = tree.get_root()
	if not item:
		return { &"errs": [] }

	# Root items are errors; children are stack frames
	item = item.get_first_child()
	while item:
		var msg: String = item.get_text(0).strip_edges()
		var detail: String = item.get_text(1).strip_edges() if tree.get_columns() > 1 else ""
		var is_warning: bool = "WARNING" in msg.to_upper() or item.get_icon_modulate(0) == Color.YELLOW

		if not include_warnings and is_warning:
			item = item.get_next()
			continue

		var error_info: Dictionary = {
			&"msg": msg,
			&"detail": detail,
			&"sev": "warning" if is_warning else "error",
		}

		# Extract file:line from item metadata (Godot stores [file, line] array)
		var meta: Variant = item.get_metadata(0)
		if meta is Array and meta.size() >= 2:
			error_info[&"file"] = str(meta[0])
			error_info[&"line"] = int(meta[1])

		# Collect stack frames from child items
		# Children are: <Error> (optional), <Source>, then <Stack Trace> frames
		var stack: Array[Dictionary] = []
		var child: TreeItem = item.get_first_child()
		while child:
			var label: String = child.get_text(0).strip_edges()
			var frame_detail: String = child.get_text(1).strip_edges() if tree.get_columns() > 1 else ""
			# Stack trace items: first has "<Stack Trace>" in col 0, rest have empty col 0
			# Skip <Error> and <Source> children (they have labels like "<GDScript Error>", "<GDScript Source>")
			var child_meta: Variant = child.get_metadata(0)
			var is_stack_frame: bool = label.contains("Stack Trace") or (label.is_empty() and child_meta is Array)
			if is_stack_frame and child_meta is Array and child_meta.size() >= 2:
				var frame: Dictionary = {
					&"function": frame_detail,
					&"file": str(child_meta[0]),
					&"line": int(child_meta[1]),
				}
				stack.append(frame)
			child = child.get_next()
		if not stack.is_empty():
			error_info[&"stack"] = stack

		errors.append(error_info)
		item = item.get_next()

	# Return most recent errors
	var start: int = maxi(0, errors.size() - max_errors)
	errors = errors.slice(start)
	return {
		&"errs": errors,
	}


## Find (and cache) the error [Tree] inside the Debugger panel.
func _get_debugger_error_tree() -> Tree:
	if is_instance_valid(_debugger_error_tree):
		return _debugger_error_tree
	if not _editor_plugin:
		return null
	var base: Control = _editor_plugin.get_editor_interface().get_base_control()
	var debugger: Node = _utils.find_node_by_class(base, &"ScriptEditorDebugger")
	if not debugger:
		return null
	# The error tree is a 2-column Tree inside the debugger
	_debugger_error_tree = _find_error_tree(debugger)
	return _debugger_error_tree


## Find the error [Tree] (2 columns) inside [code]ScriptEditorDebugger[/code].
func _find_error_tree(node: Node) -> Tree:
	for child: Node in node.get_children():
		if child is Tree and child.get_columns() == 2:
			# Check if this tree or any ancestor has "error" in its name
			var ancestor: Node = child.get_parent()
			while ancestor:
				if ancestor.name.containsn("error"):
					return child
				ancestor = ancestor.get_parent()
			# Fallback: first 2-column tree
			if not _debugger_error_tree:
				_debugger_error_tree = child
		var found: Tree = _find_error_tree(child)
		if found:
			return found
	return null


# =============================================================================
# clear_console_log
# =============================================================================
func clear_console_log(_args: Dictionary) -> Dictionary:
	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return {
			&"err": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	# Actually clear the editor Output panel
	rtl.clear()
	_clear_char_offset = 0
	return {}


# =============================================================================
# open_in_godot
# =============================================================================
func open_in_godot(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	var line: int = args.get(&"line", 0)

	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if not _editor_plugin:
		return { &"err": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()

	if path.ends_with(".gd") or path.ends_with(".shader"):
		var script: Resource = load(path)
		if script:
			ei.edit_resource(script)
			if line > 0:
				ei.get_script_editor().goto_line(line - 1)
		else:
			return { &"err": "Could not load: " + path, &"sug": "Use list_dir to verify the file exists" }
	elif path.ends_with(".tscn") or path.ends_with(".scn"):
		ei.open_scene_from_path(path)
	else:
		var res: Resource = load(path)
		if res:
			ei.edit_resource(res)

	return {}


# =============================================================================
# scene_tree_dump
# =============================================================================
func scene_tree_dump(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"err": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var edited_scene: Node = ei.get_edited_scene_root()

	if not edited_scene:
		return { &"tree": "(no scene open)" }

	var lines: PackedStringArray = []
	_dump_node(edited_scene, 0, lines)

	return { &"tree": "\n".join(lines), &"scene_path": edited_scene.scene_file_path }


func _dump_node(node: Node, depth: int, out: PackedStringArray) -> void:
	var indent: String = "  ".repeat(depth)
	var line: String = "%s%s (%s)" % [indent, node.name, node.get_class()]

	var script: Variant = node.get_script()
	if script:
		line += " [%s]" % script.resource_path.get_file()

	out.append(line)
	for child: Node in node.get_children():
		_dump_node(child, depth + 1, out)


# =============================================================================
# play_project
# =============================================================================
func play_project(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"err": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var scene_path: String = args.get(&"scene_path", "")

	# Signal to mcp_runtime.gd that this launch came from MCP (suppress focus grab).
	ProjectSettings.set_setting("godot_mcp/mcp_launched", true)

	# Defer play calls so the tool response is sent via WebSocket before
	# Godot launches the game (which can freeze the editor momentarily).
	if scene_path == "current":
		ei.play_current_scene.call_deferred()
		return {}
	elif not scene_path.is_empty():
		scene_path = _utils.validate_res_path(scene_path)
		if scene_path.is_empty():
			return { &"err": "Path escapes project root" }
		if not FileAccess.file_exists(scene_path):
			return { &"err": "Scene not found: " + scene_path, &"sug": "Use list_dir to find available .tscn files" }
		ei.play_custom_scene.call_deferred(scene_path)
		return {}
	else:
		ei.play_main_scene.call_deferred()
		return {}


# =============================================================================
# stop_project
# =============================================================================
func stop_project(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"err": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if ei.is_playing_scene():
		ei.stop_playing_scene()
	return {}


# =============================================================================
# is_project_running
# =============================================================================
func is_project_running(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"err": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var running: bool = ei.is_playing_scene()
	return { &"running": running }


# =============================================================================
# git - Consolidated git operations
# =============================================================================
func git(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"status":
			return _git_status(args)
		"commit":
			return _git_commit(args)
		"diff":
			return _git_diff(args)
		"log":
			return _git_log(args)
		"stash_push", "stash_pop", "stash_list":
			args[&"action"] = action.substr(6) # strip "stash_" prefix
			return _git_stash(args)
	return { &"err": "Unknown git action: " + action }


func _git_status(_args: Dictionary) -> Dictionary:
	var project_path: String = _project_path
	var output: Array = []
	var exit_code: int = OS.execute("git", ["-C", project_path, "status", "--porcelain"], output)
	if exit_code != 0:
		return { &"err": "git status failed (exit %d). Is this a git repo?" % exit_code, &"sug": "Initialize a git repo with run_shell_command: git init" }

	var raw: String = output[0] if output.size() > 0 else ""
	var files: Array[Dictionary] = []
	for line: String in raw.split("\n"):
		if line.strip_edges().is_empty():
			continue
		if line.length() < 4:
			continue
		var status: String = line.substr(0, 2).strip_edges()
		var file_path: String = line.substr(3).strip_edges()
		# Handle renames (old -> new)
		if " -> " in file_path:
			file_path = file_path.split(" -> ")[1]
		var label: String = "changed"
		match status:
			"??", "A", "AM":
				label = "added"
			"M", "MM":
				label = "modified"
			"D":
				label = "deleted"
			"R", "RM":
				label = "renamed"
		files.append({ &"path": file_path, &"status": label })

	# Also get current branch
	var branch_output: Array[String] = []
	OS.execute("git", ["-C", project_path, "rev-parse", "--abbrev-ref", "HEAD"], branch_output)
	var branch: String = branch_output[0].strip_edges() if branch_output.size() > 0 else "unknown"

	return {
		&"branch": branch,
		&"files": _utils.tabular(files, [&"path", &"status"]),
		&"clean": files.size() == 0,
	}


# =============================================================================
# git_commit - Stage files and commit
# =============================================================================
func _git_commit(args: Dictionary) -> Dictionary:
	var message: String = args[&"message"]
	var files: Array = args.get(&"files", []) # Variant array from JSON
	var stage_all: bool = args.get(&"all", false)

	if message.strip_edges().is_empty():
		return { &"err": "Missing 'message'" }

	var project_path: String = _project_path

	# Stage files
	if stage_all:
		var output: Array = []
		var exit_code: int = OS.execute("git", ["-C", project_path, "add", "-A"], output)
		if exit_code != 0:
			return { &"err": "git add -A failed (exit %d)" % exit_code }
	elif files.size() > 0:
		var git_args: PackedStringArray = ["-C", project_path, "add", "--"]
		for f: String in files:
			# Convert res:// paths to relative paths
			if f.begins_with("res://"):
				f = f.substr(6) # strip "res://"
			# Block path traversal outside project
			if ".." in f or f.begins_with("/"):
				return { &"err": "File path escapes project: " + f }
			git_args.append(f)
		var output: Array = []
		var exit_code: int = OS.execute("git", git_args, output)
		if exit_code != 0:
			return { &"err": "git add failed (exit %d): %s" % [exit_code, output[0] if output.size() > 0 else ""] }
	else:
		return { &"err": "No files specified. Provide 'files' array or set 'all' to true." }

	# Commit
	var commit_output: Array = []
	var commit_code: int = OS.execute("git", ["-C", project_path, "commit", "-m", message], commit_output)
	if commit_code != 0:
		var err_text: String = commit_output[0] if commit_output.size() > 0 else "unknown error"
		return { &"err": "git commit failed (exit %d): %s" % [commit_code, err_text.strip_edges()] }

	# Parse commit hash from output
	var output_text: String = commit_output[0] if commit_output.size() > 0 else ""
	var commit_hash: String = ""
	# Output format: "[branch hash] message"
	var bracket_start: int = output_text.find("[")
	var bracket_end: int = output_text.find("]", bracket_start)
	if bracket_start != -1 and bracket_end > bracket_start:
		var inside: String = output_text.substr(bracket_start + 1, bracket_end - bracket_start - 1)
		var parts: PackedStringArray = inside.split(" ")
		if parts.size() >= 2:
			commit_hash = parts[1]

	return { &"commit": commit_hash }


# =============================================================================
# git_diff - Show uncommitted changes
# =============================================================================
## Show git diff output. Supports single file and staged mode.
func _git_diff(args: Dictionary) -> Dictionary:
	var file_path: String = args.get(&"file", "")
	var staged: bool = args.get(&"staged", false)

	var git_args: PackedStringArray = ["-C", _project_path, "diff"]
	if staged:
		git_args.append("--staged")
	if not file_path.is_empty():
		if file_path.begins_with("res://"):
			file_path = file_path.substr(6)
		if ".." in file_path or file_path.begins_with("/"):
			return { &"err": "File path escapes project: " + file_path }
		git_args.append("--")
		git_args.append(file_path)

	var output: Array = []
	var exit_code: int = OS.execute("git", git_args, output)
	if exit_code != 0:
		return { &"err": "git diff failed (exit %d)" % exit_code }

	var diff_text: String = output[0] if output.size() > 0 else ""
	return { &"diff": diff_text.strip_edges() }


# =============================================================================
# git_log - Recent commit history
# =============================================================================
## Show recent git commit history.
func _git_log(args: Dictionary) -> Dictionary:
	var max_count: int = args.get(&"max_count", 10)
	var file_path: String = args.get(&"file", "")

	max_count = clampi(max_count, 1, 100)

	var git_args: PackedStringArray = ["-C", _project_path, "log", "--oneline", "--no-decorate", "-n", str(max_count)]
	if not file_path.is_empty():
		if file_path.begins_with("res://"):
			file_path = file_path.substr(6)
		if ".." in file_path or file_path.begins_with("/"):
			return { &"err": "File path escapes project: " + file_path }
		git_args.append("--")
		git_args.append(file_path)

	var output: Array = []
	var exit_code: int = OS.execute("git", git_args, output)
	if exit_code != 0:
		return { &"err": "git log failed (exit %d)" % exit_code }

	var raw: String = output[0] if output.size() > 0 else ""
	var commits: Array[Dictionary] = []
	for line: String in raw.split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		var space_idx: int = line.find(" ")
		if space_idx == -1:
			commits.append({ &"hash": line, &"message": "" })
		else:
			commits.append({ &"hash": line.substr(0, space_idx), &"message": line.substr(space_idx + 1) })

	return { &"commits": _utils.tabular(commits, [&"hash", &"message"]) }


# =============================================================================
# git_stash - Stash management
# =============================================================================
## Git stash operations: push, pop, or list.
func _git_stash(args: Dictionary) -> Dictionary:
	var action: String = args[&"action"]
	var message: String = args[&"message"]

	match action:
		"push":
			var git_args: PackedStringArray = ["-C", _project_path, "stash", "push"]
			if not message.is_empty():
				git_args.append("-m")
				git_args.append(message)
			var output: Array = []
			var exit_code: int = OS.execute("git", git_args, output)
			if exit_code != 0:
				return { &"err": "git stash push failed (exit %d)" % exit_code }
			return {}
		"pop":
			var output: Array = []
			var exit_code: int = OS.execute("git", ["-C", _project_path, "stash", "pop"], output)
			if exit_code != 0:
				return { &"err": "git stash pop failed (exit %d): %s" % [exit_code, output[0] if output.size() > 0 else ""] }
			return {}
		"list":
			var output: Array = []
			var exit_code: int = OS.execute("git", ["-C", _project_path, "stash", "list"], output)
			if exit_code != 0:
				return { &"err": "git stash list failed (exit %d)" % exit_code }
			var raw: String = output[0] if output.size() > 0 else ""
			var stashes: Array[String] = []
			for line: String in raw.split("\n"):
				line = line.strip_edges()
				if not line.is_empty():
					stashes.append(line)
			return { &"stashes": stashes }
		_:
			return { &"err": "Invalid action '%s'. Use 'push', 'pop', or 'list'." % action }

# =============================================================================
# run_shell_command - Execute a shell command in the project directory
# =============================================================================
const _BLOCKED_COMMANDS: PackedStringArray = ["rm", "sudo", "chmod", "chown", "mkfs", "dd", "kill", "killall", "pkill", "shutdown", "reboot", "init", "systemctl"]


## Execute a shell command in the project directory.
## Uses [code]OS.execute()[/code] with separate args (no shell injection).
func run_shell_command(args: Dictionary) -> Dictionary:
	var command: String = args[&"command"]
	var cmd_args: Array = args.get(&"args", []) # Variant array from JSON

	if command.strip_edges().is_empty():
		return { &"err": "Missing 'command'" }

	# Block dangerous commands (get_file strips path: /usr/bin/rm → rm)
	var base_cmd: String = command.get_file()
	if base_cmd in _BLOCKED_COMMANDS:
		return { &"err": "Command '%s' is blocked for safety" % base_cmd }

	var exec_args: PackedStringArray = []
	for a: Variant in cmd_args:
		var s: String = str(a)
		if ".." in s or s.begins_with("/"):
			return { &"err": "Arg escapes project directory: " + s }
		exec_args.append(s)

	var output: Array = []
	var exit_code: int = OS.execute(command, exec_args, output)
	var stdout: String = output[0] if output.size() > 0 else ""

	return {
		&"exit_code": exit_code,
		&"stdout": stdout.strip_edges(),
	}


# =============================================================================
# get_uid - Get the UID for a resource path
# =============================================================================
## Return the UID for a given resource path.
func get_uid(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if not ResourceLoader.exists(path):
		return { &"err": "Resource not found: " + path, &"sug": "Use list_dir or search_project to find the correct path" }

	var uid_int: int = ResourceLoader.get_resource_uid(path)
	if uid_int == -1:
		return { &"err": "No UID assigned to: " + path }

	var uid_text: String = ResourceUID.id_to_text(uid_int)
	return { &"uid": uid_text }


# =============================================================================
# query_class_info — Full ClassDB introspection for a single class
# =============================================================================
func query_class_info(args: Dictionary) -> Dictionary:
	var class_name_str: String = args[&"class_name"]
	if class_name_str.is_empty():
		return { &"err": "Missing 'class_name'" }
	if not ClassDB.class_exists(class_name_str):
		return { &"err": "Class not found: " + class_name_str, &"sug": "Use query_classes to search for available classes" }

	var include_inherited: bool = args.get(&"include_inherited", false)
	var no_exclude: bool = not include_inherited # ClassDB uses "no_inheritance" flag

	var result: Dictionary = {
		&"parent_class": ClassDB.get_parent_class(class_name_str),
		&"can_instantiate": ClassDB.can_instantiate(class_name_str),
	}

	# Methods
	var methods: Array[Dictionary] = []
	for m: Dictionary in ClassDB.class_get_method_list(class_name_str, no_exclude):
		var mname: String = m[&"name"]
		if mname.begins_with("_"):
			continue
		var method_args: Array[Dictionary] = []
		for a: Dictionary in m.get(&"args", []):
			method_args.append(
				{
					&"name": a[&"name"],
					&"type": _utils.type_id_to_name(a[&"type"]),
				},
			)
		methods.append(
			{
				&"name": mname,
				&"args": _utils.tabular(method_args, [&"name", &"type"]),
				&"return_type": _utils.type_id_to_name(m.get(&"return", { }).get(&"type", TYPE_NIL)),
			},
		)
	result[&"methods"] = _utils.tabular(methods, [&"name", &"args", &"return_type"])

	# Properties
	var properties: Array[Dictionary] = []
	for p: Dictionary in ClassDB.class_get_property_list(class_name_str, no_exclude):
		var usage: int = p.get(&"usage", 0)
		# Skip category/group headers
		if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			continue
		properties.append(
			{
				&"name": p[&"name"],
				&"type": _utils.type_id_to_name(p[&"type"]),
			},
		)
	result[&"properties"] = _utils.tabular(properties, [&"name", &"type"])

	# Signals
	var signals: Array[Dictionary] = []
	for s: Dictionary in ClassDB.class_get_signal_list(class_name_str, no_exclude):
		var sig_args: Array[Dictionary] = []
		for a: Dictionary in s.get(&"args", []):
			sig_args.append(
				{
					&"name": a[&"name"],
					&"type": _utils.type_id_to_name(a[&"type"]),
				},
			)
		signals.append(
			{
				&"name": s[&"name"],
				&"args": _utils.tabular(sig_args, [&"name", &"type"]),
			},
		)
	result[&"signals"] = _utils.tabular(signals, [&"name", &"args"])

	# Enums
	var enums: Dictionary = { }
	for enum_name: String in ClassDB.class_get_enum_list(class_name_str, no_exclude):
		var constants: Dictionary = { }
		for const_name: String in ClassDB.class_get_enum_constants(class_name_str, enum_name, no_exclude):
			constants[const_name] = ClassDB.class_get_integer_constant(class_name_str, const_name)
		enums[enum_name] = constants
	result[&"enums"] = enums

	return result

# =============================================================================
# query_classes — List/filter classes from ClassDB
# =============================================================================
const _CATEGORY_BASES: Dictionary = {
	"node": "Node",
	"node2d": "Node2D",
	"node3d": "Node3D",
	"control": "Control",
	"resource": "Resource",
	"physics2d": "PhysicsBody2D",
	"physics3d": "PhysicsBody3D",
	"audio": "AudioStream",
	"animation": "AnimationMixer",
}


func query_classes(args: Dictionary) -> Dictionary:
	var filter: String = args.get(&"filter", "")
	var category: String = args.get(&"category", "")
	var instantiable_only: bool = args.get(&"instantiable_only", false)

	var base_class: String = ""
	if not category.is_empty():
		base_class = _CATEGORY_BASES.get(category.to_lower(), "")
		if base_class.is_empty():
			return { &"err": "Unknown category: " + category + ". Valid: " + ", ".join(_CATEGORY_BASES.keys()) }

	var all_classes: PackedStringArray = ClassDB.get_class_list()
	var filter_lower: String = filter.to_lower()
	var filtered: Array[String] = []

	for cls: String in all_classes:
		if instantiable_only and not ClassDB.can_instantiate(cls):
			continue
		if not filter_lower.is_empty() and not cls.to_lower().contains(filter_lower):
			continue
		if not base_class.is_empty():
			if cls != base_class and not ClassDB.is_parent_class(cls, base_class):
				continue
		filtered.append(cls)

	filtered.sort()
	return { &"classes": filtered }

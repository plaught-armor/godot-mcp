@tool
extends RefCounted

class_name ProjectTools
## Project configuration and debug tools for MCP.
## Handles: get_project_settings, set_project_setting, get_autoloads,
##          get_input_map, configure_input_map, get_collision_layers,
##          get_node_properties, get_console_log,
##          get_errors, clear_console_log, open_in_godot, scene_tree_dump,
##          play_project, stop_project, is_project_running,
##          git_status, git_commit, git_diff, git_log, git_stash,
##          run_shell_command, get_uid,
##          query_class_info, query_classes

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
	var include_render: bool = bool(args.get(&"include_render", true))
	var include_physics: bool = bool(args.get(&"include_physics", true))

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

	return { &"ok": true, &"settings": out }


# =============================================================================
# set_project_setting
# =============================================================================
func set_project_setting(args: Dictionary) -> Dictionary:
	var setting: String = str(args.get(&"setting", ""))
	if setting.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'setting'" }
	if not args.has(&"value"):
		return { &"ok": false, &"error": "Missing 'value'" }

	var old_value: Variant = ProjectSettings.get_setting(setting) if ProjectSettings.has_setting(setting) else null
	var new_value: Variant = args[&"value"]

	ProjectSettings.set_setting(setting, new_value)
	var save_err: Error = ProjectSettings.save()
	if save_err != OK:
		return { &"ok": false, &"error": "Failed to save project settings (error %d)" % save_err }

	return {
		&"ok": true,
		&"setting": setting,
		&"old_value": _utils.serialize_value(old_value),
		&"new_value": _utils.serialize_value(new_value),
	}


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
	return {
		&"ok": true,
		&"autoloads": autoloads,
		&"count": autoloads.size(),
	}


# =============================================================================
# get_input_map
# =============================================================================
func get_input_map(args: Dictionary) -> Dictionary:
	var include_deadzones: bool = bool(args.get(&"include_deadzones", true))
	var actions: Array[StringName] = InputMap.get_actions()
	actions.sort()

	var result: Dictionary = { }
	for action: StringName in actions:
		var events: Array[Dictionary] = []
		for e: InputEvent in InputMap.action_get_events(action):
			var item: Dictionary = { &"type": e.get_class() }

			if e is InputEventKey:
				var keycode: Key = e.physical_keycode if e.physical_keycode != 0 else e.keycode
				item[&"keycode"] = keycode
				item[&"key_label"] = OS.get_keycode_string(keycode) if keycode != 0 else ""
			elif e is InputEventMouseButton:
				item[&"button_index"] = e.button_index
			elif e is InputEventJoypadButton:
				item[&"button_index"] = e.button_index
			elif e is InputEventJoypadMotion:
				item[&"axis"] = e.axis
				if include_deadzones:
					item[&"axis_value"] = e.axis_value

			events.append(item)
		result[action] = events

	return { &"ok": true, &"actions": result, &"count": result.size() }


# =============================================================================
# configure_input_map - Add, remove, or replace input actions
# =============================================================================
func configure_input_map(args: Dictionary) -> Dictionary:
	var action: String = str(args.get(&"action", ""))
	var operation: String = str(args.get(&"operation", ""))

	if action.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'action' name" }
	if operation.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'operation'. Use: add, remove, set" }

	match operation:
		"add":
			return _input_map_add(action, args)
		"remove":
			return _input_map_remove(action)
		"set":
			return _input_map_set(action, args)
		_:
			return { &"ok": false, &"error": "Unknown operation: %s. Use: add, remove, set" % operation }


func _input_map_add(action: String, args: Dictionary) -> Dictionary:
	var deadzone: float = float(args.get(&"deadzone", 0.5))
	var events_data: Array = args.get(&"events", [])

	var created: bool = false
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
		created = true

	var added_events: Array[String] = []
	var event_errors: Array[String] = []
	for event_desc: Variant in events_data:
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"error"):
			event_errors.append(result[&"error"])
			continue
		InputMap.action_add_event(action, result[&"event"])
		added_events.append(_describe_event(result[&"event"]))

	_persist_action(action)
	_save_and_refresh()
	_try_refresh_input_map_ui()

	var msg: String = "Action '%s' %s" % [action, "created" if created else "updated"]
	if added_events.size() > 0:
		msg += " with %d event(s)" % added_events.size()

	var out: Dictionary = { &"ok": true, &"message": msg, &"events_added": added_events }
	if event_errors.size() > 0:
		out[&"event_errors"] = event_errors
	return out


func _input_map_remove(action: String) -> Dictionary:
	if not InputMap.has_action(action):
		return { &"ok": false, &"error": "Action not found: " + action }
	if action.begins_with("ui_"):
		return { &"ok": false, &"error": "Refusing to remove built-in action: " + action }

	InputMap.erase_action(action)
	var input_key: String = "input/" + action
	if ProjectSettings.has_setting(input_key):
		ProjectSettings.clear(input_key)
	_save_and_refresh()
	_try_refresh_input_map_ui()

	return { &"ok": true, &"message": "Removed action: " + action }


func _input_map_set(action: String, args: Dictionary) -> Dictionary:
	var deadzone: float = float(args.get(&"deadzone", 0.5))
	var events_data: Array = args.get(&"events", [])

	if InputMap.has_action(action):
		InputMap.erase_action(action)

	InputMap.add_action(action, deadzone)

	var added_events: Array[String] = []
	var event_errors: Array[String] = []
	for event_desc: Variant in events_data:
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"error"):
			event_errors.append(result[&"error"])
			continue
		InputMap.action_add_event(action, result[&"event"])
		added_events.append(_describe_event(result[&"event"]))

	_persist_action(action)
	_save_and_refresh()
	_try_refresh_input_map_ui()

	var out: Dictionary = { &"ok": true, &"message": "Set action '%s' with %d event(s)" % [action, added_events.size()], &"events": added_events }
	if event_errors.size() > 0:
		out[&"event_errors"] = event_errors
	return out


func _create_input_event(desc: Dictionary) -> Dictionary:
	var type: String = str(desc.get(&"type", ""))
	match type:
		"key":
			var key_string: String = str(desc.get(&"key", ""))
			if key_string.is_empty():
				return { &"error": "Missing 'key' for key event" }
			var event: InputEventKey = InputEventKey.new()
			var keycode: Key = OS.find_keycode_from_string(key_string)
			if keycode == 0:
				return { &"error": "Unknown key: " + key_string }
			event.physical_keycode = keycode
			return { &"event": event }
		"mouse_button":
			var button_index: int = int(desc.get(&"button_index", 0))
			if button_index <= 0:
				return { &"error": "Invalid 'button_index' for mouse_button (must be >= 1)" }
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_button":
			var button_index: int = int(desc.get(&"button_index", -1))
			if button_index < 0:
				return { &"error": "Missing or invalid 'button_index' for joypad_button" }
			var event: InputEventJoypadButton = InputEventJoypadButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_motion":
			var axis: int = int(desc.get(&"axis", -1))
			if axis < 0:
				return { &"error": "Missing or invalid 'axis' for joypad_motion" }
			var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			event.axis = axis
			event.axis_value = float(desc.get(&"axis_value", 0.0))
			return { &"event": event }
		_:
			return { &"error": "Unknown event type: '%s'. Use: key, mouse_button, joypad_button, joypad_motion" % type }


func _persist_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	ProjectSettings.set_setting(
		"input/" + action,
		{
			"deadzone": InputMap.action_get_deadzone(action),
			"events": InputMap.action_get_events(action),
		},
	)


func _save_and_refresh() -> void:
	ProjectSettings.save()
	ProjectSettings.notify_property_list_changed()


func _try_refresh_input_map_ui() -> void:
	if not _editor_plugin:
		return
	var base: Control = _editor_plugin.get_editor_interface().get_base_control()
	var pse: Node = _find_node_by_class(base, &"ProjectSettingsEditor")
	if not pse:
		return
	if pse.has_method("_update_action_map_editor"):
		pse.call("_update_action_map_editor")


func _find_node_by_class(node: Node, cls: StringName) -> Node:
	if node.get_class() == cls:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_node_by_class(child, cls)
		if found:
			return found
	return null


func _describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return "Key: " + (OS.get_keycode_string(keycode) if keycode != 0 else "Unknown")
	elif event is InputEventMouseButton:
		return "Mouse Button: " + str(event.button_index)
	elif event is InputEventJoypadButton:
		return "Joypad Button: " + str(event.button_index)
	elif event is InputEventJoypadMotion:
		return "Joypad Axis: %d (%.1f)" % [event.axis, event.axis_value]
	return event.get_class()


# =============================================================================
# get_collision_layers
# =============================================================================
func get_collision_layers(_args: Dictionary) -> Dictionary:
	var layers_2d: Array[Dictionary] = _collect_layers("layer_names/2d_physics")
	var layers_3d: Array[Dictionary] = _collect_layers("layer_names/3d_physics")
	return { &"ok": true, &"layers_2d": layers_2d, &"layers_3d": layers_3d }


func _collect_layers(prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(1, 33):
		var key: String = "%s/layer_%d" % [prefix, i]
		if ProjectSettings.has_setting(key):
			out.append({ &"index": i, &"value": ProjectSettings.get_setting(key) })
	return out

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
	var node_type: String = str(args.get(&"node_type", ""))
	if node_type.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'node_type'" }
	if not ClassDB.class_exists(node_type):
		return { &"ok": false, &"error": "Unknown node type: " + node_type }

	var temp: Variant = ClassDB.instantiate(node_type)
	if not temp:
		return { &"ok": false, &"error": "Cannot instantiate: " + node_type }

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

		# Enum hints
		if prop[&"hint"] == PROPERTY_HINT_ENUM:
			info[&"enum_values"] = prop[&"hint_string"]
		if prop_name in ENUM_HINTS:
			info[&"enum_values"] = ENUM_HINTS[prop_name]

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
		&"ok": true,
		&"node_type": node_type,
		&"inheritance_chain": chain,
		&"property_count": properties.size(),
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
	var max_lines: int = int(args.get(&"max_lines", 50))
	var filter_text: String = str(args.get(&"filter", ""))
	var severity: String = str(args.get(&"severity", "all"))

	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return {
			&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
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
	return {
		&"ok": true,
		&"lines": lines,
		&"line_count": lines.size(),
		&"content": "\n".join(lines),
	}

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
	var max_errors: int = int(args.get(&"max_errors", 50))
	var include_warnings: bool = bool(args.get(&"include_warnings", true))

	var rtl: RichTextLabel = _get_editor_log_rtl()
	if not rtl:
		return {
			&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
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
						prev[&"file"] = loc.get(&"file", "")
						prev[&"line"] = loc.get(&"line", 0)
					# Collect as stack frame
					var frame: Dictionary = { &"text": line }
					frame[&"file"] = loc.get(&"file", "")
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

		var error_info: Dictionary = { &"message": line, &"severity": severity }
		var loc: Dictionary = _extract_file_line(line)
		if not loc.is_empty():
			error_info[&"file"] = loc.get(&"file", "")
			error_info[&"line"] = loc.get(&"line", 0)
		all_errors.append(error_info)

	# Return the most recent errors
	var start: int = maxi(0, all_errors.size() - max_errors)
	var errors: Array[Dictionary] = all_errors.slice(start)
	return {
		&"ok": true,
		&"errors": errors,
		&"error_count": errors.size(),
		&"summary": "%d error(s) found" % errors.size(),
	}


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
	var max_errors: int = int(args.get(&"max_errors", 50))
	var include_warnings: bool = bool(args.get(&"include_warnings", true))

	var tree: Tree = _get_debugger_error_tree()
	if not tree:
		return {
			&"ok": true,
			&"errors": [],
			&"error_count": 0,
			&"summary": "Debugger Errors tab not available (game not running or no errors).",
		}

	var errors: Array[Dictionary] = []
	var item: TreeItem = tree.get_root()
	if not item:
		return {
			&"ok": true,
			&"errors": [],
			&"error_count": 0,
			&"summary": "No errors in debugger.",
		}

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
			&"message": msg,
			&"detail": detail,
			&"severity": "warning" if is_warning else "error",
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
		&"ok": true,
		&"errors": errors,
		&"error_count": errors.size(),
		&"summary": "%d debugger error(s) found" % errors.size(),
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
			&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	# Actually clear the editor Output panel
	rtl.clear()
	_clear_char_offset = 0
	return {
		&"ok": true,
		&"message": "Console log cleared.",
	}


# =============================================================================
# open_in_godot
# =============================================================================
func open_in_godot(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var line: int = int(args.get(&"line", 0))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()

	if path.ends_with(".gd") or path.ends_with(".shader"):
		var script: Resource = load(path)
		if script:
			ei.edit_resource(script)
			if line > 0:
				ei.get_script_editor().goto_line(line - 1)
		else:
			return { &"ok": false, &"error": "Could not load: " + path }
	elif path.ends_with(".tscn") or path.ends_with(".scn"):
		ei.open_scene_from_path(path)
	else:
		var res: Resource = load(path)
		if res:
			ei.edit_resource(res)

	return { &"ok": true, &"message": "Opened %s%s" % [path, " at line %d" % line if line > 0 else ""] }


# =============================================================================
# scene_tree_dump
# =============================================================================
func scene_tree_dump(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var edited_scene: Node = ei.get_edited_scene_root()

	if not edited_scene:
		return { &"ok": true, &"tree": "(no scene open)", &"message": "No scene is currently open in the editor" }

	var lines: PackedStringArray = []
	_dump_node(edited_scene, 0, lines)

	return { &"ok": true, &"tree": "\n".join(lines), &"scene_path": edited_scene.scene_file_path }


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
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var scene_path: String = str(args.get(&"scene_path", ""))

	# Signal to mcp_runtime.gd that this launch came from MCP (suppress focus grab).
	ProjectSettings.set_setting("godot_mcp/mcp_launched", true)

	# Defer play calls so the tool response is sent via WebSocket before
	# Godot launches the game (which can freeze the editor momentarily).
	if scene_path == "current":
		ei.play_current_scene.call_deferred()
		return { &"ok": true, &"message": "Playing current scene" }
	elif not scene_path.is_empty():
		scene_path = _utils.validate_res_path(scene_path)
		if scene_path.is_empty():
			return { &"ok": false, &"error": "Path escapes project root" }
		if not FileAccess.file_exists(scene_path):
			return { &"ok": false, &"error": "Scene not found: " + scene_path }
		ei.play_custom_scene.call_deferred(scene_path)
		return { &"ok": true, &"message": "Playing scene: " + scene_path }
	else:
		ei.play_main_scene.call_deferred()
		return { &"ok": true, &"message": "Playing main scene" }


# =============================================================================
# stop_project
# =============================================================================
func stop_project(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if not ei.is_playing_scene():
		return { &"ok": true, &"message": "No scene is running" }

	ei.stop_playing_scene()
	return { &"ok": true, &"message": "Stopped running scene" }


# =============================================================================
# is_project_running
# =============================================================================
func is_project_running(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var running: bool = ei.is_playing_scene()
	return { &"ok": true, &"running": running }


# =============================================================================
# git_status - Show working tree status
# =============================================================================
func git_status(_args: Dictionary) -> Dictionary:
	var project_path: String = _project_path
	var output: Array = []
	var exit_code: int = OS.execute("git", ["-C", project_path, "status", "--porcelain"], output)
	if exit_code != 0:
		return { &"ok": false, &"error": "git status failed (exit %d). Is this a git repo?" % exit_code }

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
		&"ok": true,
		&"branch": branch,
		&"files": files,
		&"file_count": files.size(),
		&"clean": files.size() == 0,
	}


# =============================================================================
# git_commit - Stage files and commit
# =============================================================================
func git_commit(args: Dictionary) -> Dictionary:
	var message: String = str(args.get(&"message", ""))
	var files: Array = args.get(&"files", [])  # Variant array from JSON
	var stage_all: bool = bool(args.get(&"all", false))

	if message.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'message'" }

	var project_path: String = _project_path

	# Stage files
	if stage_all:
		var output: Array = []
		var exit_code: int = OS.execute("git", ["-C", project_path, "add", "-A"], output)
		if exit_code != 0:
			return { &"ok": false, &"error": "git add -A failed (exit %d)" % exit_code }
	elif files.size() > 0:
		var git_args: PackedStringArray = ["-C", project_path, "add", "--"]
		for f: String in files:
			# Convert res:// paths to relative paths
			if f.begins_with("res://"):
				f = f.substr(6) # strip "res://"
			# Block path traversal outside project
			if ".." in f or f.begins_with("/"):
				return { &"ok": false, &"error": "File path escapes project: " + f }
			git_args.append(f)
		var output: Array = []
		var exit_code: int = OS.execute("git", git_args, output)
		if exit_code != 0:
			return { &"ok": false, &"error": "git add failed (exit %d): %s" % [exit_code, output[0] if output.size() > 0 else ""] }
	else:
		return { &"ok": false, &"error": "No files specified. Provide 'files' array or set 'all' to true." }

	# Commit
	var commit_output: Array = []
	var commit_code: int = OS.execute("git", ["-C", project_path, "commit", "-m", message], commit_output)
	if commit_code != 0:
		var err_text: String = commit_output[0] if commit_output.size() > 0 else "unknown error"
		return { &"ok": false, &"error": "git commit failed (exit %d): %s" % [commit_code, err_text.strip_edges()] }

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

	return {
		&"ok": true,
		&"message": message,
		&"commit": commit_hash,
		&"output": output_text.strip_edges(),
	}


# =============================================================================
# git_diff - Show uncommitted changes
# =============================================================================
## Show git diff output. Supports single file and staged mode.
func git_diff(args: Dictionary) -> Dictionary:
	var file_path: String = str(args.get(&"file", ""))
	var staged: bool = bool(args.get(&"staged", false))

	var git_args: PackedStringArray = ["-C", _project_path, "diff"]
	if staged:
		git_args.append("--staged")
	if not file_path.is_empty():
		if file_path.begins_with("res://"):
			file_path = file_path.substr(6)
		if ".." in file_path or file_path.begins_with("/"):
			return { &"ok": false, &"error": "File path escapes project: " + file_path }
		git_args.append("--")
		git_args.append(file_path)

	var output: Array = []
	var exit_code: int = OS.execute("git", git_args, output)
	if exit_code != 0:
		return { &"ok": false, &"error": "git diff failed (exit %d)" % exit_code }

	var diff_text: String = output[0] if output.size() > 0 else ""

	# Count files changed from "diff --git" lines
	var files_changed: int = 0
	for line: String in diff_text.split("\n"):
		if line.begins_with("diff --git"):
			files_changed += 1

	return {
		&"ok": true,
		&"diff": diff_text.strip_edges(),
		&"files_changed": files_changed,
		&"staged": staged,
	}


# =============================================================================
# git_log - Recent commit history
# =============================================================================
## Show recent git commit history.
func git_log(args: Dictionary) -> Dictionary:
	var max_count: int = int(args.get(&"max_count", 10))
	var file_path: String = str(args.get(&"file", ""))

	max_count = clampi(max_count, 1, 100)

	var git_args: PackedStringArray = ["-C", _project_path, "log", "--oneline", "--no-decorate", "-n", str(max_count)]
	if not file_path.is_empty():
		if file_path.begins_with("res://"):
			file_path = file_path.substr(6)
		if ".." in file_path or file_path.begins_with("/"):
			return { &"ok": false, &"error": "File path escapes project: " + file_path }
		git_args.append("--")
		git_args.append(file_path)

	var output: Array = []
	var exit_code: int = OS.execute("git", git_args, output)
	if exit_code != 0:
		return { &"ok": false, &"error": "git log failed (exit %d)" % exit_code }

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

	return {
		&"ok": true,
		&"commits": commits,
		&"count": commits.size(),
	}


# =============================================================================
# git_stash - Stash management
# =============================================================================
## Git stash operations: push, pop, or list.
func git_stash(args: Dictionary) -> Dictionary:
	var action: String = str(args.get(&"action", ""))
	var message: String = str(args.get(&"message", ""))

	match action:
		"push":
			var git_args: PackedStringArray = ["-C", _project_path, "stash", "push"]
			if not message.is_empty():
				git_args.append("-m")
				git_args.append(message)
			var output: Array = []
			var exit_code: int = OS.execute("git", git_args, output)
			if exit_code != 0:
				return { &"ok": false, &"error": "git stash push failed (exit %d)" % exit_code }
			return { &"ok": true, &"action": "push", &"output": (output[0] if output.size() > 0 else "").strip_edges() }
		"pop":
			var output: Array = []
			var exit_code: int = OS.execute("git", ["-C", _project_path, "stash", "pop"], output)
			if exit_code != 0:
				return { &"ok": false, &"error": "git stash pop failed (exit %d): %s" % [exit_code, output[0] if output.size() > 0 else ""] }
			return { &"ok": true, &"action": "pop", &"output": (output[0] if output.size() > 0 else "").strip_edges() }
		"list":
			var output: Array = []
			var exit_code: int = OS.execute("git", ["-C", _project_path, "stash", "list"], output)
			if exit_code != 0:
				return { &"ok": false, &"error": "git stash list failed (exit %d)" % exit_code }
			var raw: String = output[0] if output.size() > 0 else ""
			var stashes: Array[String] = []
			for line: String in raw.split("\n"):
				line = line.strip_edges()
				if not line.is_empty():
					stashes.append(line)
			return { &"ok": true, &"action": "list", &"stashes": stashes, &"count": stashes.size() }
		_:
			return { &"ok": false, &"error": "Invalid action '%s'. Use 'push', 'pop', or 'list'." % action }

# =============================================================================
# run_shell_command - Execute a shell command in the project directory
# =============================================================================
const _BLOCKED_COMMANDS: PackedStringArray = ["rm", "sudo", "chmod", "chown", "mkfs", "dd", "kill", "killall", "pkill", "shutdown", "reboot", "init", "systemctl"]


## Execute a shell command in the project directory.
## Uses [code]OS.execute()[/code] with separate args (no shell injection).
func run_shell_command(args: Dictionary) -> Dictionary:
	var command: String = str(args.get(&"command", ""))
	var cmd_args: Array = args.get(&"args", [])  # Variant array from JSON

	if command.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'command'" }

	# Block dangerous commands (get_file strips path: /usr/bin/rm → rm)
	var base_cmd: String = command.get_file()
	if base_cmd in _BLOCKED_COMMANDS:
		return { &"ok": false, &"error": "Command '%s' is blocked for safety" % base_cmd }

	var exec_args: PackedStringArray = []
	for a: Variant in cmd_args:
		var s: String = str(a)
		if ".." in s or s.begins_with("/"):
			return { &"ok": false, &"error": "Arg escapes project directory: " + s }
		exec_args.append(s)

	var output: Array = []
	var exit_code: int = OS.execute(command, exec_args, output)
	var stdout: String = output[0] if output.size() > 0 else ""

	return {
		&"ok": true,
		&"command": command,
		&"args": cmd_args,
		&"exit_code": exit_code,
		&"stdout": stdout.strip_edges(),
	}


# =============================================================================
# get_uid - Get the UID for a resource path
# =============================================================================
## Return the UID for a given resource path.
func get_uid(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not ResourceLoader.exists(path):
		return { &"ok": false, &"error": "Resource not found: " + path }

	var uid_int: int = ResourceLoader.get_resource_uid(path)
	if uid_int == -1:
		return { &"ok": false, &"error": "No UID assigned to: " + path }

	var uid_text: String = ResourceUID.id_to_text(uid_int)
	return {
		&"ok": true,
		&"path": path,
		&"uid": uid_text,
	}


# =============================================================================
# query_class_info — Full ClassDB introspection for a single class
# =============================================================================
func query_class_info(args: Dictionary) -> Dictionary:
	var class_name_str: String = str(args.get(&"class_name", ""))
	if class_name_str.is_empty():
		return { &"ok": false, &"error": "Missing 'class_name'" }
	if not ClassDB.class_exists(class_name_str):
		return { &"ok": false, &"error": "Class not found: " + class_name_str }

	var include_inherited: bool = bool(args.get(&"include_inherited", false))
	var no_exclude: bool = not include_inherited # ClassDB uses "no_inheritance" flag

	var result: Dictionary = {
		&"ok": true,
		&"class_name": class_name_str,
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
				&"args": method_args,
				&"return_type": _utils.type_id_to_name(m.get(&"return", { }).get(&"type", TYPE_NIL)),
			},
		)
	result[&"methods"] = methods

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
	result[&"properties"] = properties

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
				&"args": sig_args,
			},
		)
	result[&"signals"] = signals

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
	var filter: String = str(args.get(&"filter", ""))
	var category: String = str(args.get(&"category", ""))
	var instantiable_only: bool = bool(args.get(&"instantiable_only", false))

	var base_class: String = ""
	if not category.is_empty():
		base_class = _CATEGORY_BASES.get(category.to_lower(), "")
		if base_class.is_empty():
			return { &"ok": false, &"error": "Unknown category: " + category + ". Valid: " + ", ".join(_CATEGORY_BASES.keys()) }

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
	return {
		&"ok": true,
		&"classes": filtered,
		&"count": filtered.size(),
	}

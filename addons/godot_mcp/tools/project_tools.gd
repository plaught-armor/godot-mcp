@tool
extends RefCounted

class_name ProjectTools
## Project configuration and debug tools for MCP.
## Handles: get_project_settings, set_project_setting, get_input_map,
##          configure_input_map, get_collision_layers, get_node_properties,
##          get_console_log,
##          get_errors, clear_console_log, open_in_godot, scene_tree_dump,
##          play_project, stop_project, is_project_running,
##          git_status, git_commit

var _editor_plugin: EditorPlugin = null

# Cached reference to the editor Output panel's RichTextLabel.
var _editor_log_rtl: RichTextLabel = null

# Character offset for clear_console_log.
var _clear_char_offset: int = 0

var _utils: ToolUtils
var _project_path := ProjectSettings.globalize_path("res://")


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
	var width = ProjectSettings.get_setting("display/window/size/viewport_width", null)
	var height = ProjectSettings.get_setting("display/window/size/viewport_height", null)
	if width != null:
		out[&"window_width"] = int(width)
	if height != null:
		out[&"window_height"] = int(height)

	# Stretch
	var stretch_mode = ProjectSettings.get_setting("display/window/stretch/mode", null)
	var stretch_aspect = ProjectSettings.get_setting("display/window/stretch/aspect", null)
	if stretch_mode != null:
		out[&"stretch_mode"] = str(stretch_mode)
	if stretch_aspect != null:
		out[&"stretch_aspect"] = str(stretch_aspect)

	if include_physics:
		var pps = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", null)
		if pps != null:
			out[&"physics_ticks_per_second"] = int(pps)

	if include_render:
		var method = ProjectSettings.get_setting("rendering/renderer/rendering_method", null)
		if method != null:
			out[&"rendering_method"] = str(method)
		var vsync = ProjectSettings.get_setting("display/window/vsync/vsync_mode", null)
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

	var old_value = ProjectSettings.get_setting(setting) if ProjectSettings.has_setting(setting) else null
	var new_value = args[&"value"]

	ProjectSettings.set_setting(setting, new_value)
	var save_err := ProjectSettings.save()
	if save_err != OK:
		return { &"ok": false, &"error": "Failed to save project settings (error %d)" % save_err }

	return {
		&"ok": true,
		&"setting": setting,
		&"old_value": _utils.serialize_value(old_value),
		&"new_value": _utils.serialize_value(new_value),
	}


# =============================================================================
# get_input_map
# =============================================================================
func get_input_map(args: Dictionary) -> Dictionary:
	var include_deadzones: bool = bool(args.get(&"include_deadzones", true))
	var actions: Array = InputMap.get_actions()
	actions.sort()

	var result: Dictionary = { }
	for action: StringName in actions:
		var events: Array = []
		for e: InputEvent in InputMap.action_get_events(action):
			var item := { &"type": e.get_class() }

			if e is InputEventKey:
				var keycode = e.physical_keycode if e.physical_keycode != 0 else e.keycode
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

	var created := false
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
		created = true

	var added_events: Array = []
	var event_errors: Array = []
	for event_desc in events_data:
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

	var msg := "Action '%s' %s" % [action, "created" if created else "updated"]
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
	if ProjectSettings.has_setting("input/" + action):
		ProjectSettings.clear("input/" + action)
	_save_and_refresh()
	_try_refresh_input_map_ui()

	return { &"ok": true, &"message": "Removed action: " + action }


func _input_map_set(action: String, args: Dictionary) -> Dictionary:
	var deadzone: float = float(args.get(&"deadzone", 0.5))
	var events_data: Array = args.get(&"events", [])

	if InputMap.has_action(action):
		InputMap.erase_action(action)

	InputMap.add_action(action, deadzone)

	var added_events: Array = []
	var event_errors: Array = []
	for event_desc in events_data:
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
			var event := InputEventKey.new()
			var keycode := OS.find_keycode_from_string(key_string)
			if keycode == 0:
				return { &"error": "Unknown key: " + key_string }
			event.physical_keycode = keycode
			return { &"event": event }
		"mouse_button":
			var button_index: int = int(desc.get(&"button_index", 0))
			if button_index <= 0:
				return { &"error": "Invalid 'button_index' for mouse_button (must be >= 1)" }
			var event := InputEventMouseButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_button":
			var button_index: int = int(desc.get(&"button_index", -1))
			if button_index < 0:
				return { &"error": "Missing or invalid 'button_index' for joypad_button" }
			var event := InputEventJoypadButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_motion":
			var axis: int = int(desc.get(&"axis", -1))
			if axis < 0:
				return { &"error": "Missing or invalid 'axis' for joypad_motion" }
			var event := InputEventJoypadMotion.new()
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
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var pse := _find_node_by_class(base, "ProjectSettingsEditor")
	if not pse:
		return
	if pse.has_method("_update_action_map_editor"):
		pse.call("_update_action_map_editor")


func _find_node_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for child: Node in node.get_children():
		var found := _find_node_by_class(child, cls)
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
	var layers_2d: Array = _collect_layers("layer_names/2d_physics")
	var layers_3d: Array = _collect_layers("layer_names/3d_physics")
	return { &"ok": true, &"layers_2d": layers_2d, &"layers_3d": layers_3d }


func _collect_layers(prefix: String) -> Array:
	var out: Array = []
	for i: int in range(1, 33):
		var key := "%s/layer_%d" % [prefix, i]
		if ProjectSettings.has_setting(key):
			out.append({ &"index": i, &"value": ProjectSettings.get_setting(key) })
	return out

# =============================================================================
# get_node_properties
# =============================================================================
const ENUM_HINTS = {
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

	var temp = ClassDB.instantiate(node_type)
	if not temp:
		return { &"ok": false, &"error": "Cannot instantiate: " + node_type }

	var properties: Array = []
	for prop: Dictionary in temp.get_property_list():
		var prop_name: String = prop[&"name"]
		if prop_name.begins_with("_"):
			continue
		if _utils.SKIP_PROPS.has(prop_name):
			continue
		if not (prop[&"usage"] & PROPERTY_USAGE_EDITOR):
			continue

		var type_name := _utils.type_id_to_name(prop[&"type"])
		if prop[&"type"] == TYPE_OBJECT:
			type_name = "Resource"
		var info := {
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

	temp.queue_free()

	# Inheritance chain
	var chain: Array = []
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


func _get_editor_log_rtl() -> RichTextLabel:
	"""Find (and cache) the RichTextLabel inside the editor's Output panel."""
	if is_instance_valid(_editor_log_rtl):
		return _editor_log_rtl
	if not _editor_plugin:
		return null
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var editor_log := _utils.find_node_by_class(base, "EditorLog")
	if editor_log:
		_editor_log_rtl = _utils.find_child_rtl(editor_log)
	return _editor_log_rtl


func _read_output_panel_lines() -> Array:
	"""Return all non-empty lines from the editor Output panel (after clear offset)."""
	var rtl := _get_editor_log_rtl()
	if not rtl:
		return []
	var full_text: String = rtl.get_parsed_text()
	if _clear_char_offset > 0 and _clear_char_offset < full_text.length():
		full_text = full_text.substr(_clear_char_offset)
	elif _clear_char_offset >= full_text.length():
		return []
	var lines: Array = []
	for line: String in full_text.split("\n"):
		if not line.strip_edges().is_empty():
			lines.append(line)
	return lines


# =============================================================================
# get_console_log
# =============================================================================
func get_console_log(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get(&"max_lines", 50))

	var rtl := _get_editor_log_rtl()
	if not rtl:
		return {
			&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	var all_lines := _read_output_panel_lines()
	var start := maxi(0, all_lines.size() - max_lines)
	var lines := all_lines.slice(start)
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

	var rtl := _get_editor_log_rtl()
	if not rtl:
		return {
			&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor.",
		}

	var all_lines := _read_output_panel_lines()

	var all_errors: Array = []
	for i: int in range(all_lines.size()):
		var line: String = all_lines[i].strip_edges()
		if line.is_empty():
			continue

		var is_error := false
		var severity := "error"
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
				var loc := _extract_file_line(line)
				if not loc.is_empty():
					prev[&"file"] = loc.get(&"file", "")
					prev[&"line"] = loc.get(&"line", 0)
			continue

		if not is_error:
			continue
		if severity == "warning" and not include_warnings:
			continue

		var error_info := { &"message": line, &"severity": severity }
		var loc := _extract_file_line(line)
		if not loc.is_empty():
			error_info[&"file"] = loc.get(&"file", "")
			error_info[&"line"] = loc.get(&"line", 0)
		all_errors.append(error_info)

	# Return the most recent errors
	var start := maxi(0, all_errors.size() - max_errors)
	var errors := all_errors.slice(start)
	return {
		&"ok": true,
		&"errors": errors,
		&"error_count": errors.size(),
		&"summary": "%d error(s) found" % errors.size(),
	}


func _extract_file_line(text: String) -> Dictionary:
	var idx := text.find("res://")
	if idx == -1:
		return { }
	var rest := text.substr(idx)
	var colon_idx := rest.find(":", 6)
	if colon_idx == -1:
		return { &"file": rest.strip_edges() }
	var file_path := rest.substr(0, colon_idx)
	var after_colon := rest.substr(colon_idx + 1)
	var digits: PackedStringArray = []
	for c: String in after_colon:
		if c.is_valid_int():
			digits.append(c)
		else:
			break
	if not digits.is_empty():
		return { &"file": file_path, &"line": int("".join(digits)) }
	return { &"file": file_path }

# =============================================================================
# get_debug_errors - Read errors from the Debugger > Errors tab
# =============================================================================
var _debugger_error_tree: Tree = null


func get_debug_errors(args: Dictionary) -> Dictionary:
	var max_errors: int = int(args.get(&"max_errors", 50))
	var include_warnings: bool = bool(args.get(&"include_warnings", true))

	var tree := _get_debugger_error_tree()
	if not tree:
		return {
			&"ok": true,
			&"errors": [],
			&"error_count": 0,
			&"summary": "Debugger Errors tab not available (game not running or no errors).",
		}

	var errors: Array = []
	var item := tree.get_root()
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
		var is_warning := "WARNING" in msg.to_upper() or item.get_icon_modulate(0) == Color.YELLOW

		if not include_warnings and is_warning:
			item = item.get_next()
			continue

		var error_info: Dictionary = {
			&"message": msg,
			&"detail": detail,
			&"severity": "warning" if is_warning else "error",
		}

		# Extract file:line from detail column (format: "at: res://path.gd:123")
		var loc := _extract_file_line(detail)
		if loc.is_empty():
			loc = _extract_file_line(msg)
		if not loc.is_empty():
			error_info[&"file"] = loc.get(&"file", "")
			if loc.has(&"line"):
				error_info[&"line"] = loc[&"line"]

		# Collect stack frames from child items
		var stack: Array = []
		var child := item.get_first_child()
		while child:
			var frame_text: String = child.get_text(0).strip_edges()
			var frame_detail: String = child.get_text(1).strip_edges() if tree.get_columns() > 1 else ""
			if not frame_text.is_empty() or not frame_detail.is_empty():
				var frame := { &"text": frame_text }
				if not frame_detail.is_empty():
					frame[&"detail"] = frame_detail
				var frame_loc := _extract_file_line(frame_detail)
				if not frame_loc.is_empty():
					frame[&"file"] = frame_loc.get(&"file", "")
					if frame_loc.has(&"line"):
						frame[&"line"] = frame_loc[&"line"]
				stack.append(frame)
			child = child.get_next()
		if not stack.is_empty():
			error_info[&"stack"] = stack

		errors.append(error_info)
		item = item.get_next()

	# Return most recent errors
	var start := maxi(0, errors.size() - max_errors)
	errors = errors.slice(start)
	return {
		&"ok": true,
		&"errors": errors,
		&"error_count": errors.size(),
		&"summary": "%d debugger error(s) found" % errors.size(),
	}


func _get_debugger_error_tree() -> Tree:
	"""Find (and cache) the error Tree inside the Debugger panel."""
	if is_instance_valid(_debugger_error_tree):
		return _debugger_error_tree
	if not _editor_plugin:
		return null
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var debugger := _utils.find_node_by_class(base, "ScriptEditorDebugger")
	if not debugger:
		return null
	# The error tree is a 2-column Tree inside the debugger
	_debugger_error_tree = _find_error_tree(debugger)
	return _debugger_error_tree


func _find_error_tree(node: Node) -> Tree:
	"""Find the error Tree (2 columns) inside ScriptEditorDebugger."""
	for child: Node in node.get_children():
		if child is Tree and child.get_columns() == 2:
			# Check if this tree or any ancestor has "error" in its name
			var ancestor := child.get_parent()
			while ancestor:
				if ancestor.name.containsn("error"):
					return child
				ancestor = ancestor.get_parent()
			# Fallback: first 2-column tree
			if not _debugger_error_tree:
				_debugger_error_tree = child
		var found := _find_error_tree(child)
		if found:
			return found
	return null


# =============================================================================
# clear_console_log
# =============================================================================
func clear_console_log(_args: Dictionary) -> Dictionary:
	var rtl := _get_editor_log_rtl()
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

	var ei = _editor_plugin.get_editor_interface()

	if path.ends_with(".gd") or path.ends_with(".shader"):
		var script = load(path)
		if script:
			ei.edit_resource(script)
			if line > 0:
				ei.get_script_editor().goto_line(line - 1)
		else:
			return { &"ok": false, &"error": "Could not load: " + path }
	elif path.ends_with(".tscn") or path.ends_with(".scn"):
		ei.open_scene_from_path(path)
	else:
		var res = load(path)
		if res:
			ei.edit_resource(res)

	return { &"ok": true, &"message": "Opened %s%s" % [path, " at line %d" % line if line > 0 else ""] }


# =============================================================================
# scene_tree_dump
# =============================================================================
func scene_tree_dump(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei = _editor_plugin.get_editor_interface()
	var edited_scene = ei.get_edited_scene_root()

	if not edited_scene:
		return { &"ok": true, &"tree": "(no scene open)", &"message": "No scene is currently open in the editor" }

	var lines: PackedStringArray = []
	_dump_node(edited_scene, 0, lines)

	return { &"ok": true, &"tree": "\n".join(lines), &"scene_path": edited_scene.scene_file_path }


func _dump_node(node: Node, depth: int, out: PackedStringArray) -> void:
	var indent := "  ".repeat(depth)
	var line := "%s%s (%s)" % [indent, node.name, node.get_class()]

	var script = node.get_script()
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

	var ei = _editor_plugin.get_editor_interface()
	var scene_path: String = str(args.get(&"scene_path", ""))

	if scene_path == "current":
		ei.play_current_scene()
		return { &"ok": true, &"message": "Playing current scene" }
	elif not scene_path.is_empty():
		scene_path = _utils.validate_res_path(scene_path)
		if scene_path.is_empty():
			return { &"ok": false, &"error": "Path escapes project root" }
		if not FileAccess.file_exists(scene_path):
			return { &"ok": false, &"error": "Scene not found: " + scene_path }
		ei.play_custom_scene(scene_path)
		return { &"ok": true, &"message": "Playing scene: " + scene_path }
	else:
		ei.play_main_scene()
		return { &"ok": true, &"message": "Playing main scene" }


# =============================================================================
# stop_project
# =============================================================================
func stop_project(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return { &"ok": false, &"error": "Editor plugin not available" }

	var ei = _editor_plugin.get_editor_interface()
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

	var ei = _editor_plugin.get_editor_interface()
	var running: bool = ei.is_playing_scene()
	return { &"ok": true, &"running": running }


# =============================================================================
# git_status - Show working tree status
# =============================================================================
func git_status(_args: Dictionary) -> Dictionary:
	var project_path := _project_path
	var output: Array = []
	var exit_code := OS.execute("git", ["-C", project_path, "status", "--porcelain"], output)
	if exit_code != 0:
		return { &"ok": false, &"error": "git status failed (exit %d). Is this a git repo?" % exit_code }

	var raw: String = output[0] if output.size() > 0 else ""
	var files: Array = []
	for line: String in raw.split("\n"):
		if line.strip_edges().is_empty():
			continue
		if line.length() < 4:
			continue
		var status := line.substr(0, 2).strip_edges()
		var file_path := line.substr(3).strip_edges()
		# Handle renames (old -> new)
		if " -> " in file_path:
			file_path = file_path.split(" -> ")[1]
		var label := "changed"
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
	var branch_output: Array = []
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
	var files: Array = args.get(&"files", [])
	var stage_all: bool = bool(args.get(&"all", false))

	if message.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'message'" }

	var project_path := _project_path

	# Stage files
	if stage_all:
		var output: Array = []
		var exit_code := OS.execute("git", ["-C", project_path, "add", "-A"], output)
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
		var exit_code := OS.execute("git", git_args, output)
		if exit_code != 0:
			return { &"ok": false, &"error": "git add failed (exit %d): %s" % [exit_code, output[0] if output.size() > 0 else ""] }
	else:
		return { &"ok": false, &"error": "No files specified. Provide 'files' array or set 'all' to true." }

	# Commit
	var commit_output: Array = []
	var commit_code := OS.execute("git", ["-C", project_path, "commit", "-m", message], commit_output)
	if commit_code != 0:
		var err_text: String = commit_output[0] if commit_output.size() > 0 else "unknown error"
		return { &"ok": false, &"error": "git commit failed (exit %d): %s" % [commit_code, err_text.strip_edges()] }

	# Parse commit hash from output
	var output_text: String = commit_output[0] if commit_output.size() > 0 else ""
	var commit_hash := ""
	# Output format: "[branch hash] message"
	var bracket_start := output_text.find("[")
	var bracket_end := output_text.find("]", bracket_start)
	if bracket_start != -1 and bracket_end > bracket_start:
		var inside := output_text.substr(bracket_start + 1, bracket_end - bracket_start - 1)
		var parts := inside.split(" ")
		if parts.size() >= 2:
			commit_hash = parts[1]

	return {
		&"ok": true,
		&"message": message,
		&"commit": commit_hash,
		&"output": output_text.strip_edges(),
	}

@tool
extends RefCounted

class_name InputTools
## InputMap management tools for MCP.
## Handles: input_edit (get_actions, set_action)
## Consolidates former get_input_map + configure_input_map.

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func input(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"list":
			return _get_actions(args)
		"set":
			return _set_action(args)
		_:
			return { &"err": "Unknown input_edit action: " + action }


func _get_actions(args: Dictionary) -> Dictionary:
	var include_deadzones: bool = args.get(&"include_deadzones", true)
	var actions: Array[StringName] = InputMap.get_actions()
	actions.sort()

	var result: Dictionary = {}
	for act: StringName in actions:
		var events: Array[Dictionary] = []
		for e: InputEvent in InputMap.action_get_events(act):
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
		result[act] = events

	return { &"actions": result }


func _set_action(args: Dictionary) -> Dictionary:
	var input_action: String = args[&"input_action"]
	var operation: String = args[&"operation"]

	if input_action.strip_edges().is_empty():
		return { &"err": "Missing 'input_action'" }
	if operation.strip_edges().is_empty():
		return { &"err": "Missing 'operation'. Use: add, remove, set" }

	match operation:
		"add":
			return _add(input_action, args)
		"remove":
			return _remove(input_action)
		"set":
			return _replace(input_action, args)
		_:
			return { &"err": "Unknown operation: %s. Use: add, remove, set" % operation }


func _add(input_action: String, args: Dictionary) -> Dictionary:
	if not InputMap.has_action(input_action):
		InputMap.add_action(input_action, args.get(&"deadzone", 0.5))

	var event_errors: Array[String] = []
	for event_desc: Variant in args.get(&"events", []):
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"err"):
			event_errors.append(result[&"err"])
			continue
		InputMap.action_add_event(input_action, result[&"event"])

	_persist_action(input_action)
	_save_and_refresh()

	return { &"event_errors": event_errors }


func _remove(input_action: String) -> Dictionary:
	if not InputMap.has_action(input_action):
		return { &"err": "Action not found: " + input_action, &"sug": "Use input_edit action:get_actions" }
	if input_action.begins_with("ui_"):
		return { &"err": "Refusing to remove built-in action: " + input_action }

	InputMap.erase_action(input_action)
	var input_key: String = "input/" + input_action
	if ProjectSettings.has_setting(input_key):
		ProjectSettings.clear(input_key)
	_save_and_refresh()

	return {}


func _replace(input_action: String, args: Dictionary) -> Dictionary:
	if InputMap.has_action(input_action):
		InputMap.erase_action(input_action)

	InputMap.add_action(input_action, args.get(&"deadzone", 0.5))

	var event_errors: Array[String] = []
	for event_desc: Variant in args.get(&"events", []):
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"err"):
			event_errors.append(result[&"err"])
			continue
		InputMap.action_add_event(input_action, result[&"event"])

	_persist_action(input_action)
	_save_and_refresh()

	return { &"event_errors": event_errors }


func _create_input_event(desc: Dictionary) -> Dictionary:
	var type: String = desc.get(&"type", "")
	match type:
		"key":
			var key_string: String = desc.get(&"key", "")
			if key_string.is_empty():
				return { &"err": "Missing 'key' for key event" }
			var event: InputEventKey = InputEventKey.new()
			var keycode: Key = OS.find_keycode_from_string(key_string)
			if keycode == 0:
				return { &"err": "Unknown key: " + key_string }
			event.physical_keycode = keycode
			return { &"event": event }
		"mouse_button":
			var button_index: int = desc.get(&"button_index", 0)
			if button_index <= 0:
				return { &"err": "Invalid 'button_index' for mouse_button (must be >= 1)" }
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_button":
			var button_index: int = desc.get(&"button_index", -1)
			if button_index < 0:
				return { &"err": "Missing or invalid 'button_index' for joypad_button" }
			var event: InputEventJoypadButton = InputEventJoypadButton.new()
			event.button_index = button_index
			return { &"event": event }
		"joypad_motion":
			var axis: int = desc.get(&"axis", -1)
			if axis < 0:
				return { &"err": "Missing or invalid 'axis' for joypad_motion" }
			var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			event.axis = axis
			event.axis_value = desc.get(&"axis_value", 0.0)
			return { &"event": event }
		_:
			return { &"err": "Unknown event type: '%s'. Use: key, mouse_button, joypad_button, joypad_motion" % type }


func _persist_action(input_action: String) -> void:
	if not InputMap.has_action(input_action):
		return
	ProjectSettings.set_setting(
		"input/" + input_action,
		{
			"deadzone": InputMap.action_get_deadzone(input_action),
			"events": InputMap.action_get_events(input_action),
		},
	)


func _save_and_refresh() -> void:
	ProjectSettings.save()
	ProjectSettings.notify_property_list_changed()

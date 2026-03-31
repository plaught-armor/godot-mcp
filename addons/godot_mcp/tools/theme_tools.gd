@tool
extends RefCounted

class_name ThemeTools
## UI Theme tools for MCP.
## Handles: theme_edit (create, set_color, set_constant, set_font_size, set_stylebox, info)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func theme(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"create":
			return _create(args)
		&"color":
			return _set_color(args)
		&"constant":
			return _set_constant(args)
		&"font_size":
			return _set_font_size(args)
		&"stylebox":
			return _set_stylebox(args)
		&"info":
			return _info(args)
		_:
			return { &"err": "Unknown theme_edit action: " + action }


func _create(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])

	var theme := Theme.new()
	if args.has(&"default_font_size"):
		theme.default_font_size = int(args[&"default_font_size"])

	var err := ResourceSaver.save(theme, path)
	if err != OK:
		return { &"err": "Failed to save theme: " + error_string(err) }

	_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	return {}


func _find_control(args: Dictionary) -> Control:
	var scene_path: String = _utils.validate_res_path(args.get(&"scene_path", ""))
	var node_path: String = args[&"node_path"]

	var root: Node = _editor_plugin.get_editor_interface().get_edited_scene_root()
	if not root:
		return null
	if not scene_path.is_empty() and root.scene_file_path != scene_path:
		return null

	var node: Node = root if (node_path == "." or node_path.is_empty()) else root.get_node_or_null(node_path)
	if node is Control:
		return node as Control
	return null


func _set_color(args: Dictionary) -> Dictionary:
	var control: Control = _find_control(args)
	if not control:
		return { &"err": "Control node not found at: " + args[&"node_path"] }

	var color_name: String = args[&"name"]
	var color_str: String = args[&"color"]

	control.add_theme_color_override(color_name, Color(color_str))
	return {}


func _set_constant(args: Dictionary) -> Dictionary:
	var control: Control = _find_control(args)
	if not control:
		return { &"err": "Control node not found at: " + args[&"node_path"] }

	var const_name: String = args[&"name"]

	var value: int = int(args[&"value"])
	control.add_theme_constant_override(const_name, value)
	return {}


func _set_font_size(args: Dictionary) -> Dictionary:
	var control: Control = _find_control(args)
	if not control:
		return { &"err": "Control node not found at: " + args[&"node_path"] }

	var font_name: String = args[&"name"]

	var size: int = int(args[&"size"])
	control.add_theme_font_size_override(font_name, size)
	return {}


func _set_stylebox(args: Dictionary) -> Dictionary:
	var control: Control = _find_control(args)
	if not control:
		return { &"err": "Control node not found at: " + args[&"node_path"] }

	var style_name: String = args[&"name"]

	var stylebox := StyleBoxFlat.new()

	if args.has(&"bg_color"):
		stylebox.bg_color = Color(args[&"bg_color"])
	if args.has(&"border_color"):
		stylebox.border_color = Color(args[&"border_color"])
	if args.has(&"border_width"):
		var bw: int = int(args[&"border_width"])
		stylebox.border_width_left = bw
		stylebox.border_width_top = bw
		stylebox.border_width_right = bw
		stylebox.border_width_bottom = bw
	if args.has(&"corner_radius"):
		var cr: int = int(args[&"corner_radius"])
		stylebox.corner_radius_top_left = cr
		stylebox.corner_radius_top_right = cr
		stylebox.corner_radius_bottom_left = cr
		stylebox.corner_radius_bottom_right = cr
	if args.has(&"padding"):
		var p: int = int(args[&"padding"])
		stylebox.content_margin_left = p
		stylebox.content_margin_top = p
		stylebox.content_margin_right = p
		stylebox.content_margin_bottom = p

	control.add_theme_stylebox_override(style_name, stylebox)
	return {}


func _info(args: Dictionary) -> Dictionary:
	var control: Control = _find_control(args)
	if not control:
		return { &"err": "Control node not found at: " + args[&"node_path"] }

	var info: Dictionary = {}

	var theme: Theme = control.theme
	if theme:
		info[&"theme_path"] = theme.resource_path

	var overrides: Dictionary = { &"colors": {}, &"constants": {}, &"font_sizes": {}, &"styleboxes": {} }
	for prop: Dictionary in control.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("theme_override_colors/"):
			overrides[&"colors"][pname.substr(22)] = "#" + (control.get(pname) as Color).to_html()
		elif pname.begins_with("theme_override_constants/"):
			overrides[&"constants"][pname.substr(25)] = control.get(pname)
		elif pname.begins_with("theme_override_font_sizes/"):
			overrides[&"font_sizes"][pname.substr(26)] = control.get(pname)
		elif pname.begins_with("theme_override_styles/"):
			var style: Variant = control.get(pname)
			overrides[&"styleboxes"][pname.substr(22)] = style.get_class() if style else null

	info[&"overrides"] = overrides
	return info

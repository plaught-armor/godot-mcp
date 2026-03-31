@tool
extends RefCounted

class_name ResourceTools
## Resource (.tres) management tools for MCP.
## Handles: resource_edit (read, edit, create, preview)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func tres(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"read":
			return _read(args)
		&"edit":
			return _edit(args)
		&"create":
			return _create(args)
		&"preview":
			return _preview(args)
		_:
			return { &"err": "Unknown resource_edit action: " + action }


func _read(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])
	if not FileAccess.file_exists(path):
		return { &"err": "Resource not found: " + path }

	var resource: Resource = ResourceLoader.load(path)
	if not resource:
		return { &"err": "Failed to load resource: " + path }

	var props: Dictionary = {}
	for prop_info: Dictionary in resource.get_property_list():
		var prop_name: String = prop_info[&"name"]
		var usage: int = prop_info[&"usage"]
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if prop_name.begins_with("_") or prop_name in [&"script", &"resource_local_to_scene", &"resource_name", &"resource_path"]:
			continue
		props[prop_name] = _serialize_value(resource.get(prop_name))

	return {
		&"path": path,
		&"type": resource.get_class(),
		&"name": resource.resource_name,
		&"properties": props,
	}


func _edit(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])
	if not FileAccess.file_exists(path):
		return { &"err": "Resource not found: " + path }

	var new_props: Dictionary = args[&"properties"]

	var resource: Resource = ResourceLoader.load(path)
	if not resource:
		return { &"err": "Failed to load resource: " + path }

	var changed: Dictionary = {}
	for prop_name: String in new_props:
		if not prop_name in resource:
			continue
		var old_value: Variant = resource.get(prop_name)
		resource.set(prop_name, _parse_value(new_props[prop_name], typeof(old_value)))
		changed[prop_name] = {
			&"old": _serialize_value(old_value),
			&"new": _serialize_value(resource.get(prop_name)),
		}

	if changed.is_empty():
		return {}

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return { &"err": "Failed to save resource: " + error_string(err) }

	return {}


func _create(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])

	var resource_type: String = args[&"type"]
	if not ClassDB.class_exists(resource_type):
		return { &"err": "Unknown resource type: " + resource_type }
	if not ClassDB.is_parent_class(resource_type, &"Resource"):
		return { &"err": "'%s' is not a Resource type" % resource_type }

	if FileAccess.file_exists(path) and not args.get(&"overwrite", false):
		return { &"err": "Resource already exists: " + path, &"sug": "Set overwrite=true to replace" }

	var resource: Resource = ClassDB.instantiate(resource_type)
	if not resource:
		return { &"err": "Failed to instantiate: " + resource_type }

	var properties: Dictionary = args.get(&"properties", {})
	for prop_name: String in properties:
		if prop_name in resource:
			var current: Variant = resource.get(prop_name)
			resource.set(prop_name, _parse_value(properties[prop_name], typeof(current)))

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return { &"err": "Failed to save resource: " + error_string(err) }

	_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	return {}


func _preview(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])
	if not FileAccess.file_exists(path):
		return { &"err": "Resource not found: " + path }

	var max_size: int = int(args.get(&"max_size", 256))
	var image: Image = null

	var ext: String = path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "bmp", "webp", "svg"]:
		image = Image.new()
		var err := image.load(path)
		if err != OK:
			return { &"err": "Failed to load image: " + error_string(err) }
	else:
		var resource: Resource = ResourceLoader.load(path)
		if not resource:
			return { &"err": "Failed to load resource: " + path }
		if resource is Texture2D:
			image = (resource as Texture2D).get_image()
		elif resource is Image:
			image = resource as Image
		else:
			return { &"err": "Resource type '%s' has no image preview" % resource.get_class() }

	if not image:
		return { &"err": "Could not extract image from resource" }

	if image.get_width() > max_size or image.get_height() > max_size:
		var s: float = minf(float(max_size) / float(image.get_width()), float(max_size) / float(image.get_height()))
		image.resize(int(image.get_width() * s), int(image.get_height() * s), Image.INTERPOLATE_LANCZOS)

	var png_buffer: PackedByteArray = image.save_png_to_buffer()
	var base64: String = Marshalls.raw_to_base64(png_buffer)

	return {
		&"img": base64,
		&"width": image.get_width(),
		&"height": image.get_height(),
		&"format": "png",
		&"path": path,
	}


func _serialize_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return { &"x": value.x, &"y": value.y }
		TYPE_VECTOR3:
			return { &"x": value.x, &"y": value.y, &"z": value.z }
		TYPE_COLOR:
			return "#" + (value as Color).to_html()
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return value.resource_path if not value.resource_path.is_empty() else value.get_class()
			return value.get_class()
		_:
			return value


func _parse_value(value: Variant, target_type: int) -> Variant:
	match target_type:
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_COLOR:
			if value is String:
				return Color(value)
		TYPE_VECTOR2:
			if value is Dictionary:
				return Vector2(value.get(&"x", 0), value.get(&"y", 0))
		TYPE_VECTOR3:
			if value is Dictionary:
				return Vector3(value.get(&"x", 0), value.get(&"y", 0), value.get(&"z", 0))
	return value

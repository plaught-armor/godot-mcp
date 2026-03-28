@tool
extends RefCounted

class_name ShaderTools
## Shader file and material tools for MCP.
## Handles: shader_edit (create, read, edit, assign, set_param, get_params)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func shader(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"create":
			return _create(args)
		"read":
			return _read(args)
		"edit":
			return _edit(args)
		"assign":
			return _assign(args)
		"param":
			return _set_param(args)
		"params":
			return _get_params(args)
		_:
			return { &"err": "Unknown shader_edit action: " + action }


func _get_edited_root() -> Node:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_editor_interface().get_edited_scene_root()


func _find_node(node_path: String) -> Node:
	var root: Node = _get_edited_root()
	if not root:
		return null
	if node_path == "." or node_path.is_empty():
		return root
	return root.get_node_or_null(node_path)


func _create(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])

	var content: String = args.get(&"content", "")
	var shader_type: String = args.get(&"shader_type", "spatial")

	if content.is_empty():
		match shader_type:
			"spatial":
				content = "shader_type spatial;\n\nvoid vertex() {\n}\n\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"
			"canvas_item":
				content = "shader_type canvas_item;\n\nvoid fragment() {\n\tCOLOR = vec4(1.0);\n}\n"
			"particles":
				content = "shader_type particles;\n\nvoid start() {\n}\n\nvoid process() {\n}\n"
			"sky":
				content = "shader_type sky;\n\nvoid sky() {\n\tCOLOR = vec3(0.3, 0.5, 0.8);\n}\n"

	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return { &"err": "Cannot create shader: " + error_string(FileAccess.get_open_error()) }
	file.store_string(content)
	file.close()

	_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	return {}


func _read(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])
	if not FileAccess.file_exists(path):
		return { &"err": "Shader not found: " + path }

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return { &"err": "Cannot read shader" }
	var content: String = file.get_as_text()
	file.close()
	return { &"content": content }


func _edit(args: Dictionary) -> Dictionary:
	var path: String = _utils.validate_res_path(args[&"path"])
	if not FileAccess.file_exists(path):
		return { &"err": "Shader not found: " + path }

	var changes_made: int = 0

	if args.has(&"content"):
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if not file:
			return { &"err": "Cannot write shader" }
		file.store_string(str(args[&"content"]))
		file.close()
		changes_made = 1
	elif args.has(&"replacements") and args[&"replacements"] is Array:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if not file:
			return { &"err": "Cannot read shader" }
		var content: String = file.get_as_text()
		file.close()

		for replacement: Variant in args[&"replacements"]:
			if replacement is Dictionary:
				var search: String = replacement.get(&"search", "")
				var replace: String = replacement.get(&"replace", "")
				if not search.is_empty() and content.contains(search):
					content = content.replace(search, replace)
					changes_made += 1

		file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(content)
			file.close()

	if changes_made > 0:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
		if ResourceLoader.exists(path):
			var shader: Variant = load(path)
			if shader is Shader:
				shader.reload_from_file()

	return { &"n": changes_made }


func _assign(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var shader_path: String = _utils.validate_res_path(args[&"shader_path"])
	if not ResourceLoader.exists(shader_path):
		return { &"err": "Shader not found: " + shader_path }

	var shader: Shader = load(shader_path)
	if not shader:
		return { &"err": "Failed to load shader" }

	var material := ShaderMaterial.new()
	material.shader = shader

	if node is CanvasItem:
		(node as CanvasItem).material = material
	elif node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	elif &"material" in node:
		node.set(&"material", material)
	else:
		return { &"err": "Node does not support materials: " + node.get_class() }

	return {}


func _set_param(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var material: ShaderMaterial = _get_shader_material(node)
	if not material:
		return { &"err": "Node has no ShaderMaterial" }

	var param_name: String = args[&"param"]

	var value: Variant = args[&"value"]
	if value is String:
		var expr := Expression.new()
		if expr.parse(value) == OK:
			var parsed: Variant = expr.execute()
			if parsed != null:
				value = parsed

	material.set_shader_parameter(param_name, value)
	return {}


func _get_params(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var material: ShaderMaterial = _get_shader_material(node)
	if not material:
		return { &"err": "Node has no ShaderMaterial" }

	var shader_params: Dictionary = {}
	for prop: Dictionary in material.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("shader_parameter/"):
			shader_params[pname.substr(17)] = str(material.get(pname))

	return { &"params": shader_params }


func _get_shader_material(node: Node) -> ShaderMaterial:
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		return (node as CanvasItem).material
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		return (node as MeshInstance3D).material_override
	return null

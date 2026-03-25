@tool
extends RefCounted

class_name SceneTools
## Scene operation tools for MCP.
## Handles: scene_edit (add/remove/rename/move/duplicate/reorder/set_property),
##          create_scene, read_scene, attach_script, detach_script,
##          set_collision_shape, set_sprite_texture

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# Consolidated scene edit dispatcher
# =============================================================================
func scene_edit(args: Dictionary) -> Dictionary:
	var action: String = args[&"action"]
	match action:
		"add_node":
			return add_node(args)
		"remove_node":
			return remove_node(args)
		"set_property":
			return modify_node_property(args)
		"rename":
			return rename_node(args)
		"move":
			return move_node(args)
		"duplicate":
			return duplicate_node(args)
		"reorder":
			return reorder_node(args)
	return {&"error": "Unknown scene_edit action: " + action}


# =============================================================================
# Shared helpers
# =============================================================================
func _refresh_and_reload(scene_path: String) -> void:
	_utils.refresh_filesystem()
	_reload_scene_in_editor(scene_path)


func _reload_scene_in_editor(scene_path: String) -> void:
	if not _editor_plugin:
		return
	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	var edited: Node = ei.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		ei.reload_scene_from_path(scene_path)


## Returns [code][scene_root, error_dict][/code]. If error_dict is not empty, scene_root is null.
func _load_scene(scene_path: String) -> Array:
	if not FileAccess.file_exists(scene_path):
		return [null, { &"error": "Scene does not exist: " + scene_path }]

	var packed: PackedScene = load(scene_path) as PackedScene
	if not packed:
		return [null, { &"error": "Failed to load scene: " + scene_path }]

	var root: Node = packed.instantiate()
	if not root:
		return [null, { &"error": "Failed to instantiate scene" }]

	return [root, { }]


## Pack and save a scene. Returns error dict or empty on success.
func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	var packed: PackedScene = PackedScene.new()
	var pack_result: Error = packed.pack(scene_root)
	if pack_result != OK:
		scene_root.queue_free()
		return { &"error": "Failed to pack scene: " + str(pack_result) }

	var save_result: Error = ResourceSaver.save(packed, scene_path)
	scene_root.queue_free()

	if save_result != OK:
		return { &"error": "Failed to save scene: " + str(save_result) }

	_refresh_and_reload(scene_path)
	return { }


func _find_node(scene_root: Node, node_path: String) -> Node:
	if node_path == "." or node_path.is_empty():
		return scene_root
	return scene_root.get_node_or_null(node_path)


## Convert dictionary-encoded types to Godot types.
func _parse_value(value: Variant) -> Variant:
	if value is Dictionary:
		var t: String = value.get(&"type", "")
		match t:
			"Vector2":
				return Vector2(value.get(&"x", 0), value.get(&"y", 0))
			"Vector3":
				return Vector3(value.get(&"x", 0), value.get(&"y", 0), value.get(&"z", 0))
			"Color":
				return Color(value.get(&"r", 1), value.get(&"g", 1), value.get(&"b", 1), value.get(&"a", 1))
			"Vector2i":
				return Vector2i(value.get(&"x", 0), value.get(&"y", 0))
			"Vector3i":
				return Vector3i(value.get(&"x", 0), value.get(&"y", 0), value.get(&"z", 0))
			"Rect2":
				return Rect2(value.get(&"x", 0), value.get(&"y", 0), value.get(&"width", 0), value.get(&"height", 0))
	return value


func _set_node_properties(node: Node, properties: Dictionary) -> void:
	for prop_name: String in properties:
		var prop_value: Variant = _parse_value(properties[prop_name])
		node.set(prop_name, prop_value)


# =============================================================================
# create_scene
# =============================================================================
func create_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var root_node_name: String = args.get(&"root_node_name", "Node")
	var root_node_type: String = args[&"root_node_type"]
	var nodes: Array[Dictionary]
	nodes.assign(args.get(&"nodes", []))
	var attach_script_path: String = args.get(&"attach_script", "")

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path' parameter" }
	if root_node_type.strip_edges().is_empty():
		return { &"error": "Missing 'root_node_type' parameter" }
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	if FileAccess.file_exists(scene_path):
		return { &"error": "Scene already exists: " + scene_path }
	if not ClassDB.class_exists(root_node_type):
		return { &"error": "Invalid root node type: " + root_node_type }

	# Ensure parent directory
	var dir_path: String = scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var root: Node = ClassDB.instantiate(root_node_type) as Node
	if not root:
		return { &"error": "Failed to create root node of type: " + root_node_type }
	root.name = root_node_name

	if not attach_script_path.is_empty():
		attach_script_path = _utils.validate_res_path(attach_script_path)
		if not attach_script_path.is_empty():
			var script_res: Resource = load(attach_script_path)
			if script_res:
				root.set_script(script_res)

	var node_count: int = 0
	for node_data: Variant in nodes:
		if typeof(node_data) == TYPE_DICTIONARY:
			node_count += _create_node_recursive(node_data, root, root)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"path": scene_path,
		&"root_type": root_node_type,
		&"child_count": node_count,
	}


## Create node tree recursively. Returns the number of nodes created.
func _create_node_recursive(data: Dictionary, parent: Node, owner: Node) -> int:
	var n_name: String = data.get(&"name", "Node")
	var n_type: String = data.get(&"type", "Node")
	var n_script: String = data.get(&"script", "")
	var props: Dictionary = data.get(&"properties", { })
	var children: Array[Dictionary]
	children.assign(data.get(&"children", []))

	if not ClassDB.class_exists(n_type):
		return 0
	var node: Node = ClassDB.instantiate(n_type) as Node
	if not node:
		return 0

	node.name = n_name
	_set_node_properties(node, props)

	if not n_script.is_empty():
		n_script = _utils.validate_res_path(n_script)
		if not n_script.is_empty():
			var s: Resource = load(n_script)
			if s:
				node.set_script(s)

	parent.add_child(node)
	node.owner = owner

	var count: int = 1
	for child_data: Variant in children:
		if typeof(child_data) == TYPE_DICTIONARY:
			count += _create_node_recursive(child_data, node, owner)
	return count


# =============================================================================
# read_scene
# =============================================================================
func read_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var include_properties: bool = args.get(&"include_properties", false)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path' parameter" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var structure: Dictionary = _build_node_structure(root, include_properties)
	root.queue_free()

	return { &"scene_path": scene_path, &"root": structure }


func _build_node_structure(node: Node, include_props: bool, path: String = ".") -> Dictionary:
	const PROPERTIES: PackedStringArray = [
		"position",
		"rotation",
		"scale",
		"size",
		"offset",
		"visible",
		"modulate",
		"z_index",
		"text",
		"collision_layer",
		"collision_mask",
		"mass",
	]

	var data: Dictionary = { &"name": str(node.name), &"type": node.get_class(), &"path": path, &"children": [] }
	var script: Variant = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	if include_props:
		var props: Dictionary = { }
		for prop_name: String in PROPERTIES:
			var val: Variant = node.get(prop_name)
			if val != null:
				props[prop_name] = _utils.serialize_value(val)
		if not props.is_empty():
			data[&"properties"] = props

	for child: Node in node.get_children():
		var child_path: String = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_node_structure(child, include_props, child_path))
	return data


# =============================================================================
# add_node
# =============================================================================
func add_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_name: String = args[&"node_name"]
	var node_type: String = args[&"node_type"]
	var parent_path: String = args.get(&"parent_path", ".")
	var properties: Dictionary = args.get(&"properties", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if node_name.strip_edges().is_empty():
		return { &"error": "Missing 'node_name'" }
	if not ClassDB.class_exists(node_type):
		return { &"error": "Invalid node type: " + node_type }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var parent: Node = _find_node(root, parent_path)
	if not parent:
		root.queue_free()
		return { &"error": "Parent node not found: " + parent_path }

	var new_node: Node = ClassDB.instantiate(node_type) as Node
	if not new_node:
		root.queue_free()
		return { &"error": "Failed to create node of type: " + node_type }

	new_node.name = node_name
	_set_node_properties(new_node, properties)
	parent.add_child(new_node)
	new_node.owner = root

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"scene_path": scene_path,
		&"node_name": node_name,
		&"node_type": node_type,
	}


# =============================================================================
# remove_node
# =============================================================================
func remove_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }

	# Support bulk removal via node_paths array, or single via node_path
	var raw_paths: Array = args.get(&"node_paths", [])
	var paths: Array[String] = []
	for p: String in raw_paths:
		paths.append(p)
	if paths.is_empty():
		var single: String = args[&"node_path"]
		if not single.strip_edges().is_empty():
			paths = [single]
	if paths.is_empty():
		return { &"error": "Missing 'node_path' or 'node_paths'" }

	for p: String in paths:
		if p.strip_edges().is_empty() or p == ".":
			return { &"error": "Cannot remove root node" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var removed: Array[Dictionary] = []
	var not_found: Array[String] = []

	for p: String in paths:
		var target: Node = root.get_node_or_null(p)
		if not target:
			not_found.append(p)
			continue
		var info: String = "%s (%s)" % [target.name, target.get_class()]
		target.get_parent().remove_child(target)
		target.queue_free()
		removed.append({ &"path": p, &"info": info })

	if removed.is_empty():
		root.queue_free()
		return { &"error": "No nodes found: " + ", ".join(not_found) }

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	var out: Dictionary = {
		&"scene_path": scene_path,
		&"removed": removed,
	}
	if not not_found.is_empty():
		out[&"not_found"] = not_found
	return out


# =============================================================================
# modify_node_property
# =============================================================================
func modify_node_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var property_name: String = args[&"property_name"]
	var value: Variant = args[&"value"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"error": "Missing 'property_name'" }
	if value == null:
		return { &"error": "Missing 'value'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	# Check property exists
	if not (property_name in target):
		var node_type: String = target.get_class()
		root.queue_free()
		return { &"error": "Property '%s' not found on %s (%s). Use get_node_properties to discover available properties." % [property_name, node_path, node_type] }

	var parsed: Variant = _parse_value(value)
	var old_value: Variant = target.get(property_name)

	# Validate resource type compatibility
	if old_value is Resource and not (parsed is Resource):
		root.queue_free()
		return { &"error": "Property '%s' expects a Resource. Use specialized tools (set_collision_shape, set_sprite_texture) instead." % property_name }

	target.set(property_name, parsed)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property_name": property_name,
		&"old_value": str(old_value),
		&"new_value": str(parsed),
	}


# =============================================================================
# rename_node
# =============================================================================
func rename_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_name: String = args[&"new_name"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty():
		return { &"error": "Missing 'node_path'" }
	if new_name.strip_edges().is_empty():
		return { &"error": "Missing 'new_name'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var old_name: StringName = target.name
	target.name = new_name

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"old_name": str(old_name),
		&"new_name": new_name,
	}


# =============================================================================
# move_node
# =============================================================================
func move_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_parent_path: String = args[&"new_parent_path"]
	var sibling_index: int = args.get(&"sibling_index", -1)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"error": "Cannot move root node" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var new_parent: Node = _find_node(root, new_parent_path)
	if not new_parent:
		root.queue_free()
		return { &"error": "New parent not found: " + new_parent_path }

	# Prevent circular reference: new parent must not be the target or a descendant of it
	if new_parent == target or target.is_ancestor_of(new_parent):
		root.queue_free()
		return { &"error": "Cannot move node to its own descendant" }

	target.get_parent().remove_child(target)
	new_parent.add_child(target)
	target.owner = root

	if sibling_index >= 0:
		new_parent.move_child(target, mini(sibling_index, new_parent.get_child_count() - 1))

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"node_path": node_path, &"new_parent": new_parent_path }


# =============================================================================
# duplicate_node
# =============================================================================
func duplicate_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_name: String = args[&"new_name"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"error": "Cannot duplicate root node" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var parent: Node = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"error": "Cannot duplicate - no parent" }

	# Duplicate the node
	var duplicate: Node = target.duplicate()

	# Generate unique name if not provided
	if new_name.is_empty():
		var base_name: StringName = target.name
		var sibling_names: Dictionary = { }
		for c: Node in parent.get_children():
			sibling_names[c.name] = true
		var counter: int = 2
		new_name = base_name + str(counter)
		while sibling_names.has(StringName(new_name)):
			counter += 1
			new_name = base_name + str(counter)

	duplicate.name = new_name
	parent.add_child(duplicate)

	# Set owner for all duplicated nodes
	_set_owner_recursive(duplicate, root)

	# Move duplicate right after original
	var original_index: int = target.get_index()
	parent.move_child(duplicate, original_index + 1)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"new_name": new_name }


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)


# =============================================================================
# reorder_node - simpler function just for changing sibling order
# =============================================================================
func reorder_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_index: int = args.get(&"new_index", -1)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"error": "Cannot reorder root node" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var parent: Node = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"error": "Cannot reorder - no parent" }

	var old_index: int = target.get_index()
	var max_index: int = parent.get_child_count() - 1
	new_index = clampi(new_index, 0, max_index)

	if old_index == new_index:
		root.queue_free()
		return { &"old_index": old_index, &"new_index": old_index }

	parent.move_child(target, new_index)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"old_index": old_index,
		&"new_index": new_index,
	}


# =============================================================================
# attach_script
# =============================================================================
func attach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var script_path: String = args[&"script_path"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if script_path.strip_edges().is_empty():
		return { &"error": "Missing 'script_path'" }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"error": "script_path escapes project root" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var script_res: Resource = load(script_path)
	if not script_res:
		root.queue_free()
		return { &"error": "Failed to load script: " + script_path }

	target.set_script(script_res)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"script_path": script_path, &"node_path": node_path }


# =============================================================================
# detach_script
# =============================================================================
func detach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	target.set_script(null)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"node_path": node_path }


# =============================================================================
# set_collision_shape
# =============================================================================
func set_collision_shape(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var shape_type: String = args[&"shape_type"]
	var shape_params: Dictionary = args.get(&"shape_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if shape_type.strip_edges().is_empty():
		return { &"error": "Missing 'shape_type'" }
	if not ClassDB.class_exists(shape_type):
		return { &"error": "Invalid shape type: " + shape_type }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	# Create shape resource
	var shape: Variant = ClassDB.instantiate(shape_type)
	if not shape:
		root.queue_free()
		return { &"error": "Failed to create shape: " + shape_type }

	# Apply shape parameters
	if shape_params.has(&"radius"):
		shape.set(&"radius", shape_params[&"radius"])
	if shape_params.has(&"height"):
		shape.set(&"height", shape_params[&"height"])
	if shape_params.has(&"size"):
		var size_data: Variant = shape_params[&"size"]
		if typeof(size_data) == TYPE_DICTIONARY:
			if size_data.has(&"z"):
				shape.set(&"size", Vector3(size_data.get(&"x", 1), size_data.get(&"y", 1), size_data.get(&"z", 1)))
			else:
				shape.set(&"size", Vector2(size_data.get(&"x", 1), size_data.get(&"y", 1)))

	target.set(&"shape", shape)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"shape_type": shape_type, &"node_path": node_path }


# =============================================================================
# set_sprite_texture
# =============================================================================
func set_sprite_texture(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var texture_type: String = args[&"texture_type"]
	var texture_params: Dictionary = args.get(&"texture_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if texture_type.strip_edges().is_empty():
		return { &"error": "Missing 'texture_type'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var texture: Texture2D = null

	match texture_type:
		"ImageTexture":
			var tex_path: String = _utils.validate_res_path(texture_params.get(&"path", ""))
			if tex_path.is_empty():
				root.queue_free()
				return { &"error": "Missing or invalid 'path' in texture_params for ImageTexture" }
			texture = load(tex_path) as Texture2D
			if not texture:
				root.queue_free()
				return { &"error": "Failed to load texture: " + tex_path }
		"PlaceholderTexture2D":
			texture = PlaceholderTexture2D.new()
			var size_data: Variant = texture_params.get(&"size", { &"x": 64, &"y": 64 })
			if typeof(size_data) == TYPE_DICTIONARY:
				texture.size = Vector2(size_data.get(&"x", 64), size_data.get(&"y", 64))
		"GradientTexture2D":
			texture = GradientTexture2D.new()
			texture.width = texture_params.get(&"width", 64)
			texture.height = texture_params.get(&"height", 64)
		"NoiseTexture2D":
			texture = NoiseTexture2D.new()
			texture.width = texture_params.get(&"width", 64)
			texture.height = texture_params.get(&"height", 64)
		_:
			root.queue_free()
			return { &"error": "Unknown texture type: " + texture_type }

	target.set(&"texture", texture)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"texture_type": texture_type, &"node_path": node_path }


# =============================================================================
# get_scene_hierarchy (for visualizer)
# =============================================================================
## Get the full scene hierarchy with node information for the visualizer.
func get_scene_hierarchy(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var hierarchy: Dictionary = _build_hierarchy_recursive(root, ".")
	root.queue_free()

	return { &"scene_path": scene_path, &"hierarchy": hierarchy }


## Build node hierarchy with all info needed for visualizer.
func _build_hierarchy_recursive(node: Node, path: String) -> Dictionary:
	var data: Dictionary = {
		&"name": str(node.name),
		&"type": node.get_class(),
		&"path": path,
		&"children": [],
	}

	# Check for attached script
	var script: Variant = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	# Get node index (sibling order)
	var parent: Node = node.get_parent()
	if parent:
		data[&"index"] = node.get_index()

	# Build children (preserving order for 2D draw order)
	for child: Node in node.get_children():
		var child_path: String = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_hierarchy_recursive(child, child_path))

	return data


# =============================================================================
# get_scene_node_properties (dynamic property fetching)
# =============================================================================
## Get all properties of a specific node in a scene with their current values.
func get_scene_node_properties(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	var node_type: String = target.get_class()
	var properties: Array[Dictionary] = []
	var categories: Dictionary = { } # category -> [properties]

	# Build property→class lookup once (avoids O(n²) per-property hierarchy walk)
	var prop_owner: Dictionary = { } # prop_name → defining class
	var cls: String = node_type
	while cls != "":
		for p: Dictionary in ClassDB.class_get_property_list(cls, true):
			var pn: String = p[&"name"]
			if not prop_owner.has(pn):
				prop_owner[pn] = cls
		cls = ClassDB.get_parent_class(cls)

	# Get property list with full metadata
	for prop: Dictionary in target.get_property_list():
		var prop_name: String = prop[&"name"]

		# Skip internal/private properties
		if prop_name.begins_with("_"):
			continue
		if _utils.SKIP_PROPS.has(prop_name):
			continue

		# Only include editor-visible properties
		if not (prop[&"usage"] & PROPERTY_USAGE_EDITOR):
			continue

		# Get current value
		var current_value: Variant = target.get(prop_name)

		var prop_info: Dictionary = {
			&"name": prop_name,
			&"type": prop[&"type"],
			&"type_name": _utils.type_id_to_name(prop[&"type"]),
			&"hint": prop[&"hint"],
			&"hint_string": prop[&"hint_string"],
			&"value": _utils.serialize_value(current_value),
			&"usage": prop[&"usage"],
		}

		# Look up category from pre-built map
		var category: String = prop_owner.get(prop_name, node_type)
		prop_info[&"category"] = category

		if not categories.has(category):
			categories[category] = []
		categories[category].append(prop_info)
		properties.append(prop_info)

	# Get inheritance chain
	var chain: Array[String] = []
	cls = node_type
	while cls != "":
		chain.append(cls)
		cls = ClassDB.get_parent_class(cls)

	root.queue_free()

	return {
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"node_type": node_type,
		&"node_name": target.name,
		&"inheritance_chain": chain,
		&"properties": properties,
		&"categories": categories,
	}


# =============================================================================
# set_scene_node_property (for visualizer inline editing)
# =============================================================================
## Set a property on a node in a scene (supports complex types).
func set_scene_node_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var property_name: String = args[&"property_name"]
	var value: Variant = args[&"value"]
	var value_type: int = args.get(&"value_type", -1)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"error": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"error": "Missing 'property_name'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"error": "Node not found: " + node_path }

	# Parse value based on type
	var parsed_value: Variant = _parse_typed_value(value, value_type)
	var old_value: Variant = target.get(property_name)

	# Set the property
	target.set(property_name, parsed_value)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property_name": property_name,
		&"old_value": _utils.serialize_value(old_value),
		&"new_value": _utils.serialize_value(parsed_value),
	}


## Parse a value based on its type hint.
func _parse_typed_value(value: Variant, type_hint: int) -> Variant:
	if type_hint == -1:
		return _parse_value(value)

	if value is Dictionary:
		# Has explicit "type" key — delegate to _parse_value
		if value.has(&"type"):
			return _parse_value(value)

		# Parse based on type_hint
		match type_hint:
			TYPE_VECTOR2:
				return Vector2(value.get(&"x", 0), value.get(&"y", 0))
			TYPE_VECTOR2I:
				return Vector2i(value.get(&"x", 0), value.get(&"y", 0))
			TYPE_VECTOR3:
				return Vector3(value.get(&"x", 0), value.get(&"y", 0), value.get(&"z", 0))
			TYPE_VECTOR3I:
				return Vector3i(value.get(&"x", 0), value.get(&"y", 0), value.get(&"z", 0))
			TYPE_COLOR:
				return Color(value.get(&"r", 1), value.get(&"g", 1), value.get(&"b", 1), value.get(&"a", 1))
			TYPE_RECT2:
				return Rect2(value.get(&"x", 0), value.get(&"y", 0), value.get(&"width", 0), value.get(&"height", 0))

	return value

@tool
extends RefCounted

class_name SceneTools
## Scene operation tools for MCP.
## Handles: create_scene, read_scene, add_node, remove_node, modify_node_property,
##          rename_node, move_node, attach_script, detach_script, set_collision_shape,
##          set_sprite_texture

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# Shared helpers
# =============================================================================
func _refresh_and_reload(scene_path: String) -> void:
	_utils.refresh_filesystem()
	_reload_scene_in_editor(scene_path)


func _reload_scene_in_editor(scene_path: String) -> void:
	if not _editor_plugin:
		return
	var ei = _editor_plugin.get_editor_interface()
	var edited = ei.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		ei.reload_scene_from_path(scene_path)


## Returns [code][scene_root, error_dict][/code]. If error_dict is not empty, scene_root is null.
func _load_scene(scene_path: String) -> Array:
	if not FileAccess.file_exists(scene_path):
		return [null, { &"ok": false, &"error": "Scene does not exist: " + scene_path }]

	var packed = load(scene_path) as PackedScene
	if not packed:
		return [null, { &"ok": false, &"error": "Failed to load scene: " + scene_path }]

	var root = packed.instantiate()
	if not root:
		return [null, { &"ok": false, &"error": "Failed to instantiate scene" }]

	return [root, { }]


## Pack and save a scene. Returns error dict or empty on success.
func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	var packed = PackedScene.new()
	var pack_result = packed.pack(scene_root)
	if pack_result != OK:
		scene_root.queue_free()
		return { &"ok": false, &"error": "Failed to pack scene: " + str(pack_result) }

	var save_result = ResourceSaver.save(packed, scene_path)
	scene_root.queue_free()

	if save_result != OK:
		return { &"ok": false, &"error": "Failed to save scene: " + str(save_result) }

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
		var prop_value = _parse_value(properties[prop_name])
		node.set(prop_name, prop_value)


# =============================================================================
# create_scene
# =============================================================================
func create_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var root_node_name: String = str(args.get(&"root_node_name", "Node"))
	var root_node_type: String = str(args.get(&"root_node_type", ""))
	var nodes: Array = args.get(&"nodes", [])
	var attach_script_path: String = str(args.get(&"attach_script", ""))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path' parameter" }
	if root_node_type.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'root_node_type' parameter" }
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	if FileAccess.file_exists(scene_path):
		return { &"ok": false, &"error": "Scene already exists: " + scene_path }
	if not ClassDB.class_exists(root_node_type):
		return { &"ok": false, &"error": "Invalid root node type: " + root_node_type }

	# Ensure parent directory
	var dir_path := scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var root: Node = ClassDB.instantiate(root_node_type) as Node
	if not root:
		return { &"ok": false, &"error": "Failed to create root node of type: " + root_node_type }
	root.name = root_node_name

	if not attach_script_path.is_empty():
		attach_script_path = _utils.validate_res_path(attach_script_path)
		if not attach_script_path.is_empty():
			var script_res = load(attach_script_path)
			if script_res:
				root.set_script(script_res)

	var node_count := 0
	for node_data: Variant in nodes:
		if typeof(node_data) == TYPE_DICTIONARY:
			var created = _create_node_recursive(node_data, root, root)
			if created:
				node_count += _count_nodes(created)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"path": scene_path,
		&"root_type": root_node_type,
		&"child_count": node_count,
		&"message": "Scene created at " + scene_path,
	}


func _create_node_recursive(data: Dictionary, parent: Node, owner: Node) -> Node:
	var n_name: String = str(data.get(&"name", "Node"))
	var n_type: String = str(data.get(&"type", "Node"))
	var n_script: String = str(data.get(&"script", ""))
	var props: Dictionary = data.get(&"properties", { })
	var children: Array = data.get(&"children", [])

	if not ClassDB.class_exists(n_type):
		return null
	var node: Node = ClassDB.instantiate(n_type) as Node
	if not node:
		return null

	node.name = n_name
	_set_node_properties(node, props)

	if not n_script.is_empty():
		n_script = _utils.validate_res_path(n_script)
		if not n_script.is_empty():
			var s = load(n_script)
			if s:
				node.set_script(s)

	parent.add_child(node)
	node.owner = owner

	for child_data: Variant in children:
		if typeof(child_data) == TYPE_DICTIONARY:
			_create_node_recursive(child_data, node, owner)
	return node


func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


# =============================================================================
# read_scene
# =============================================================================
func read_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var include_properties: bool = args.get(&"include_properties", false)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path' parameter" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var structure = _build_node_structure(root, include_properties)
	root.queue_free()

	return { &"ok": true, &"scene_path": scene_path, &"root": structure }


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

	var data := { &"name": str(node.name), &"type": node.get_class(), &"path": path, &"children": [] }
	var script = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	if include_props:
		var props := { }
		for prop_name: String in PROPERTIES:
			var val = node.get(prop_name)
			if val != null:
				props[prop_name] = _utils.serialize_value(val)
		if not props.is_empty():
			data[&"properties"] = props

	for child: Node in node.get_children():
		var child_path = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_node_structure(child, include_props, child_path))
	return data


# =============================================================================
# add_node
# =============================================================================
func add_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_name: String = str(args.get(&"node_name", ""))
	var node_type: String = str(args.get(&"node_type", "Node"))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var properties: Dictionary = args.get(&"properties", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if node_name.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'node_name'" }
	if not ClassDB.class_exists(node_type):
		return { &"ok": false, &"error": "Invalid node type: " + node_type }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var parent = _find_node(root, parent_path)
	if not parent:
		root.queue_free()
		return { &"ok": false, &"error": "Parent node not found: " + parent_path }

	var new_node: Node = ClassDB.instantiate(node_type) as Node
	if not new_node:
		root.queue_free()
		return { &"ok": false, &"error": "Failed to create node of type: " + node_type }

	new_node.name = node_name
	_set_node_properties(new_node, properties)
	parent.add_child(new_node)
	new_node.owner = root

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_name": node_name,
		&"node_type": node_type,
		&"message": "Added %s (%s) to scene" % [node_name, node_type],
	}


# =============================================================================
# remove_node
# =============================================================================
func remove_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }

	# Support bulk removal via node_paths array, or single via node_path
	var paths: Array = args.get(&"node_paths", [])
	var single: String = str(args.get(&"node_path", ""))
	if paths.is_empty() and not single.strip_edges().is_empty():
		paths = [single]
	if paths.is_empty():
		return { &"ok": false, &"error": "Missing 'node_path' or 'node_paths'" }

	for p: String in paths:
		if p.strip_edges().is_empty() or p == ".":
			return { &"ok": false, &"error": "Cannot remove root node" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var removed: Array = []
	var not_found: Array = []

	for p: String in paths:
		var target = root.get_node_or_null(p)
		if not target:
			not_found.append(p)
			continue
		var info := "%s (%s)" % [target.name, target.get_class()]
		target.get_parent().remove_child(target)
		target.queue_free()
		removed.append({ &"path": p, &"info": info })

	if removed.is_empty():
		root.queue_free()
		return { &"ok": false, &"error": "No nodes found: " + ", ".join(not_found) }

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	var out: Dictionary = {
		&"ok": true,
		&"scene_path": scene_path,
		&"removed_count": removed.size(),
		&"removed": removed,
		&"message": "Removed %d node(s)" % removed.size(),
	}
	# Backward compat: single removal keeps removed_node key
	if removed.size() == 1:
		out[&"removed_node"] = removed[0][&"path"]
	if not not_found.is_empty():
		out[&"not_found"] = not_found
	return out


# =============================================================================
# modify_node_property
# =============================================================================
func modify_node_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'property_name'" }
	if value == null:
		return { &"ok": false, &"error": "Missing 'value'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	# Check property exists
	if not (property_name in target):
		var node_type = target.get_class()
		root.queue_free()
		return { &"ok": false, &"error": "Property '%s' not found on %s (%s). Use get_node_properties to discover available properties." % [property_name, node_path, node_type] }

	var parsed = _parse_value(value)
	var old_value = target.get(property_name)

	# Validate resource type compatibility
	if old_value is Resource and not (parsed is Resource):
		root.queue_free()
		return { &"ok": false, &"error": "Property '%s' expects a Resource. Use specialized tools (set_collision_shape, set_sprite_texture) instead." % property_name }

	target.set(property_name, parsed)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property_name": property_name,
		&"old_value": str(old_value),
		&"new_value": str(parsed),
		&"message": "Set %s.%s = %s" % [node_path, property_name, str(parsed)],
	}


# =============================================================================
# rename_node
# =============================================================================
func rename_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_name: String = str(args.get(&"new_name", ""))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'node_path'" }
	if new_name.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'new_name'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var old_name = target.name
	target.name = new_name

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"old_name": str(old_name),
		&"new_name": new_name,
		&"message": "Renamed '%s' to '%s'" % [old_name, new_name],
	}


# =============================================================================
# move_node
# =============================================================================
func move_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_parent_path: String = str(args.get(&"new_parent_path", "."))
	var sibling_index: int = int(args.get(&"sibling_index", -1))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"ok": false, &"error": "Cannot move root node" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var new_parent = _find_node(root, new_parent_path)
	if not new_parent:
		root.queue_free()
		return { &"ok": false, &"error": "New parent not found: " + new_parent_path }

	# Prevent circular reference: new parent must not be the target or a descendant of it
	if new_parent == target or target.is_ancestor_of(new_parent):
		root.queue_free()
		return { &"ok": false, &"error": "Cannot move node to its own descendant" }

	target.get_parent().remove_child(target)
	new_parent.add_child(target)
	target.owner = root

	if sibling_index >= 0:
		new_parent.move_child(target, mini(sibling_index, new_parent.get_child_count() - 1))

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"ok": true, &"message": "Moved '%s' to '%s'" % [node_path, new_parent_path] }


# =============================================================================
# duplicate_node
# =============================================================================
func duplicate_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_name: String = str(args.get(&"new_name", ""))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"ok": false, &"error": "Cannot duplicate root node" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var parent = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"ok": false, &"error": "Cannot duplicate - no parent" }

	# Duplicate the node
	var duplicate = target.duplicate()

	# Generate unique name if not provided
	if new_name.is_empty():
		var base_name = target.name
		var counter = 2
		new_name = base_name + str(counter)
		while parent.has_node(NodePath(new_name)):
			counter += 1
			new_name = base_name + str(counter)

	duplicate.name = new_name
	parent.add_child(duplicate)

	# Set owner for all duplicated nodes
	_set_owner_recursive(duplicate, root)

	# Move duplicate right after original
	var original_index = target.get_index()
	parent.move_child(duplicate, original_index + 1)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"new_name": new_name,
		&"message": "Duplicated '%s' as '%s'" % [node_path, new_name],
	}


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)


# =============================================================================
# reorder_node - simpler function just for changing sibling order
# =============================================================================
func reorder_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_index: int = int(args.get(&"new_index", -1))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"ok": false, &"error": "Cannot reorder root node" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var parent = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"ok": false, &"error": "Cannot reorder - no parent" }

	var old_index = target.get_index()
	var max_index = parent.get_child_count() - 1
	new_index = clampi(new_index, 0, max_index)

	if old_index == new_index:
		root.queue_free()
		return { &"ok": true, &"message": "No change needed" }

	parent.move_child(target, new_index)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"old_index": old_index,
		&"new_index": new_index,
		&"message": "Moved '%s' from index %d to %d" % [node_path, old_index, new_index],
	}


# =============================================================================
# attach_script
# =============================================================================
func attach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var script_path: String = str(args.get(&"script_path", ""))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if script_path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'script_path'" }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"ok": false, &"error": "script_path escapes project root" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var script_res = load(script_path)
	if not script_res:
		root.queue_free()
		return { &"ok": false, &"error": "Failed to load script: " + script_path }

	target.set_script(script_res)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"ok": true, &"message": "Attached %s to node '%s'" % [script_path, node_path] }


# =============================================================================
# detach_script
# =============================================================================
func detach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	target.set_script(null)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"ok": true, &"message": "Detached script from node '%s'" % node_path }


# =============================================================================
# set_collision_shape
# =============================================================================
func set_collision_shape(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var shape_type: String = str(args.get(&"shape_type", ""))
	var shape_params: Dictionary = args.get(&"shape_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if shape_type.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'shape_type'" }
	if not ClassDB.class_exists(shape_type):
		return { &"ok": false, &"error": "Invalid shape type: " + shape_type }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	# Create shape resource
	var shape = ClassDB.instantiate(shape_type)
	if not shape:
		root.queue_free()
		return { &"ok": false, &"error": "Failed to create shape: " + shape_type }

	# Apply shape parameters
	if shape_params.has(&"radius"):
		shape.set(&"radius", float(shape_params[&"radius"]))
	if shape_params.has(&"height"):
		shape.set(&"height", float(shape_params[&"height"]))
	if shape_params.has(&"size"):
		var size_data = shape_params[&"size"]
		if typeof(size_data) == TYPE_DICTIONARY:
			if size_data.has(&"z"):
				shape.set(&"size", Vector3(size_data.get(&"x", 1), size_data.get(&"y", 1), size_data.get(&"z", 1)))
			else:
				shape.set(&"size", Vector2(size_data.get(&"x", 1), size_data.get(&"y", 1)))

	target.set(&"shape", shape)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"ok": true, &"message": "Set %s on node '%s'" % [shape_type, node_path] }


# =============================================================================
# set_sprite_texture
# =============================================================================
func set_sprite_texture(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var texture_type: String = str(args.get(&"texture_type", ""))
	var texture_params: Dictionary = args.get(&"texture_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if texture_type.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'texture_type'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var texture: Texture2D = null

	match texture_type:
		"ImageTexture":
			var tex_path: String = _utils.validate_res_path(str(texture_params.get(&"path", "")))
			if tex_path.is_empty():
				root.queue_free()
				return { &"ok": false, &"error": "Missing or invalid 'path' in texture_params for ImageTexture" }
			texture = load(tex_path)
			if not texture:
				root.queue_free()
				return { &"ok": false, &"error": "Failed to load texture: " + tex_path }
		"PlaceholderTexture2D":
			texture = PlaceholderTexture2D.new()
			var size_data = texture_params.get(&"size", { &"x": 64, &"y": 64 })
			if typeof(size_data) == TYPE_DICTIONARY:
				texture.size = Vector2(size_data.get(&"x", 64), size_data.get(&"y", 64))
		"GradientTexture2D":
			texture = GradientTexture2D.new()
			texture.width = int(texture_params.get(&"width", 64))
			texture.height = int(texture_params.get(&"height", 64))
		"NoiseTexture2D":
			texture = NoiseTexture2D.new()
			texture.width = int(texture_params.get(&"width", 64))
			texture.height = int(texture_params.get(&"height", 64))
		_:
			root.queue_free()
			return { &"ok": false, &"error": "Unknown texture type: " + texture_type }

	target.set(&"texture", texture)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"ok": true, &"message": "Set %s texture on node '%s'" % [texture_type, node_path] }


# =============================================================================
# get_scene_hierarchy (for visualizer)
# =============================================================================
## Get the full scene hierarchy with node information for the visualizer.
func get_scene_hierarchy(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var hierarchy = _build_hierarchy_recursive(root, ".")
	root.queue_free()

	return { &"ok": true, &"scene_path": scene_path, &"hierarchy": hierarchy }


## Build node hierarchy with all info needed for visualizer.
func _build_hierarchy_recursive(node: Node, path: String) -> Dictionary:
	var data := {
		&"name": str(node.name),
		&"type": node.get_class(),
		&"path": path,
		&"children": [],
		&"child_count": node.get_child_count(),
	}

	# Check for attached script
	var script = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	# Get node index (sibling order)
	var parent = node.get_parent()
	if parent:
		data[&"index"] = node.get_index()

	# Build children (preserving order for 2D draw order)
	for i: int in range(node.get_child_count()):
		var child = node.get_child(i)
		var child_path = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_hierarchy_recursive(child, child_path))

	return data


# =============================================================================
# get_scene_node_properties (dynamic property fetching)
# =============================================================================
## Get all properties of a specific node in a scene with their current values.
func get_scene_node_properties(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	var node_type = target.get_class()
	var properties: Array = []
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
		var current_value = target.get(prop_name)

		var prop_info := {
			&"name": prop_name,
			&"type": prop[&"type"],
			&"type_name": _utils.type_id_to_name(prop[&"type"]),
			&"hint": prop[&"hint"],
			&"hint_string": prop[&"hint_string"],
			&"value": _utils.serialize_value(current_value),
			&"usage": prop[&"usage"],
		}

		# Look up category from pre-built map
		var category = prop_owner.get(prop_name, node_type)
		prop_info[&"category"] = category

		if not categories.has(category):
			categories[category] = []
		categories[category].append(prop_info)
		properties.append(prop_info)

	# Get inheritance chain
	var chain: Array = []
	cls = node_type
	while cls != "":
		chain.append(cls)
		cls = ClassDB.get_parent_class(cls)

	root.queue_free()

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"node_type": node_type,
		&"node_name": target.name,
		&"inheritance_chain": chain,
		&"properties": properties,
		&"categories": categories,
		&"property_count": properties.size(),
	}


## Determine which class in the hierarchy defines this property.
func _get_property_category(node: Node, prop_name: String) -> String:
	var cls: String = node.get_class()
	while cls != "":
		# Check if this class defines the property (not inherited)
		var class_props = ClassDB.class_get_property_list(cls, true) # true = no inheritance
		for prop: Dictionary in class_props:
			if prop[&"name"] == prop_name:
				return cls
		cls = ClassDB.get_parent_class(cls)
	return node.get_class()


# =============================================================================
# set_scene_node_property (for visualizer inline editing)
# =============================================================================
## Set a property on a node in a scene (supports complex types).
func set_scene_node_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")
	var value_type: int = int(args.get(&"value_type", -1))

	if scene_path.is_empty() or scene_path == "res://":
		return { &"ok": false, &"error": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'property_name'" }

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"ok": false, &"error": "Node not found: " + node_path }

	# Parse value based on type
	var parsed_value = _parse_typed_value(value, value_type)
	var old_value = target.get(property_name)

	# Set the property
	target.set(property_name, parsed_value)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property_name": property_name,
		&"old_value": _utils.serialize_value(old_value),
		&"new_value": _utils.serialize_value(parsed_value),
		&"message": "Set %s.%s" % [node_path, property_name],
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

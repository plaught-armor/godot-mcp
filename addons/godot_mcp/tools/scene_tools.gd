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
# UndoRedo helpers
# =============================================================================

## Get the EditorUndoRedoManager, or null if unavailable.
func _get_undo_redo() -> EditorUndoRedoManager:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_undo_redo()


## Get the currently edited scene root, or null if none is open.
func _get_edited_root() -> Node:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_editor_interface().get_edited_scene_root()


## Check if the given scene_path is currently open in the editor.
## Returns the live scene root if so, otherwise null.
func _get_live_scene(scene_path: String) -> Node:
	var root: Node = _get_edited_root()
	if root and root.scene_file_path == scene_path:
		return root
	return null


## Find a node in the live scene tree.
func _find_live_node(root: Node, node_path: String) -> Node:
	if node_path == "." or node_path.is_empty():
		return root
	return root.get_node_or_null(node_path)


# =============================================================================
# Consolidated scene edit dispatcher
# =============================================================================
func scene_edit(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
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
		"batch":
			return _batch(args)
	return {&"err": "Unknown scene_edit action: " + action}


func _batch(args: Dictionary) -> Dictionary:
	var ops: Array = args[&"ops"]
	var errors: Array[Dictionary] = []
	var scene_path: String = args[&"scene_path"]

	for i: int in ops.size():
		var op: Dictionary = ops[i]
		op[&"scene_path"] = scene_path
		op.merge(op.get(&"properties", {}))
		var action: String = op[&"action"]
		var result: Dictionary
		match action:
			"add_node": result = add_node(op)
			"remove_node": result = remove_node(op)
			"set_property": result = modify_node_property(op)
			"rename": result = rename_node(op)
			"move": result = move_node(op)
			"duplicate": result = duplicate_node(op)
			"reorder": result = reorder_node(op)
			_: result = { &"err": "Unknown op action: " + action }
		if result.has(&"err"):
			errors.append({ &"i": i, &"err": result[&"err"] })

	return { &"errs": errors }


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
		return [null, { &"err": "Scene does not exist: " + scene_path, &"sug": "Use list_dir to find available .tscn files" }]

	var packed: PackedScene = load(scene_path) as PackedScene
	if not packed:
		return [null, { &"err": "Failed to load scene: " + scene_path }]

	var root: Node = packed.instantiate()
	if not root:
		return [null, { &"err": "Failed to instantiate scene" }]

	return [root, { }]


## Pack and save a scene. Returns error dict or empty on success.
func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	var packed: PackedScene = PackedScene.new()
	var pack_result: Error = packed.pack(scene_root)
	if pack_result != OK:
		scene_root.queue_free()
		return { &"err": "Failed to pack scene: " + str(pack_result) }

	var save_result: Error = ResourceSaver.save(packed, scene_path)
	scene_root.queue_free()

	if save_result != OK:
		return { &"err": "Failed to save scene: " + str(save_result) }

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
		return { &"err": "Missing 'scene_path' parameter" }
	if root_node_type.strip_edges().is_empty():
		return { &"err": "Missing 'root_node_type' parameter" }
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	if FileAccess.file_exists(scene_path):
		return { &"err": "Scene already exists: " + scene_path }
	if not ClassDB.class_exists(root_node_type):
		return { &"err": "Invalid root node type: " + root_node_type, &"sug": "Use query_classes to find valid node types" }

	# Ensure parent directory
	var dir_path: String = scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var root: Node = ClassDB.instantiate(root_node_type) as Node
	if not root:
		return { &"err": "Failed to create root node of type: " + root_node_type }
	root.name = root_node_name

	if not attach_script_path.is_empty():
		attach_script_path = _utils.validate_res_path(attach_script_path)
		if not attach_script_path.is_empty():
			var script_res: Resource = load(attach_script_path)
			if script_res:
				root.set_script(script_res)

	var node_count: int = 0
	for node_data: Variant in nodes:
		if node_data is Dictionary:
			node_count += _create_node_recursive(node_data, root, root)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


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
		if child_data is Dictionary:
			count += _create_node_recursive(child_data, node, owner)
	return count


# =============================================================================
# read_scene
# =============================================================================
func read_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var include_properties: bool = args.get(&"include_properties", false)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path' parameter" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var structure: Dictionary = _build_node_structure(root, include_properties)
	root.queue_free()

	return { &"root": structure }


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
		return { &"err": "Missing 'scene_path'" }
	if node_name.strip_edges().is_empty():
		return { &"err": "Missing 'node_name'" }
	if not ClassDB.class_exists(node_type):
		return { &"err": "Invalid node type: " + node_type, &"sug": "Use query_classes to find valid node types" }

	# Live scene path — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var ur: EditorUndoRedoManager = _get_undo_redo()
		var parent: Node = _find_live_node(live_root, parent_path)
		if not parent:
			return { &"err": "Parent node not found: " + parent_path }

		var new_node: Node = ClassDB.instantiate(node_type) as Node
		if not new_node:
			return { &"err": "Failed to create node of type: " + node_type }

		new_node.name = node_name
		_set_node_properties(new_node, properties)

		ur.create_action("MCP: Add node " + node_name)
		ur.add_do_method(parent, &"add_child", new_node)
		ur.add_do_method(new_node, &"set_owner", live_root)
		ur.add_do_reference(new_node)
		ur.add_undo_method(parent, &"remove_child", new_node)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var parent: Node = _find_node(root, parent_path)
	if not parent:
		root.queue_free()
		return { &"err": "Parent node not found: " + parent_path, &"sug": "Use read_scene to see node paths in this scene" }

	var new_node: Node = ClassDB.instantiate(node_type) as Node
	if not new_node:
		root.queue_free()
		return { &"err": "Failed to create node of type: " + node_type }

	new_node.name = node_name
	_set_node_properties(new_node, properties)
	parent.add_child(new_node)
	new_node.owner = root

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# remove_node
# =============================================================================
func remove_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }

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
		return { &"err": "Missing 'node_path' or 'node_paths'" }

	for p: String in paths:
		if p.strip_edges().is_empty() or p == ".":
			return { &"err": "Cannot remove root node" }

	# Live scene path — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var ur: EditorUndoRedoManager = _get_undo_redo()
		var removed: Array[Dictionary] = []
		var not_found: Array[String] = []

		# Collect targets first (removing while iterating is unsafe)
		var targets: Array[Array] = [] # [[node, parent, path], ...]
		for p: String in paths:
			var target: Node = live_root.get_node_or_null(p)
			if not target:
				not_found.append(p)
				continue
			targets.append([target, target.get_parent(), p])

		if targets.is_empty():
			return { &"err": "No nodes found: " + ", ".join(not_found), &"sug": "Use read_scene to see node paths in this scene" }

		ur.create_action("MCP: Remove %d node(s)" % targets.size())
		for entry: Array in targets:
			var target: Node = entry[0]
			var parent: Node = entry[1]
			var p: String = entry[2]
			var info: String = "%s (%s)" % [target.name, target.get_class()]
			var idx: int = target.get_index()
			ur.add_do_method(parent, &"remove_child", target)
			ur.add_undo_method(parent, &"add_child", target)
			ur.add_undo_method(parent, &"move_child", target, idx)
			ur.add_undo_method(target, &"set_owner", live_root)
			ur.add_undo_reference(target)
			removed.append({ &"path": p, &"info": info })
		ur.commit_action()

		var out: Dictionary = { &"removed": removed }
		if not not_found.is_empty():
			out[&"not_found"] = not_found
		return out

	# Fallback: disk-based
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
		return { &"err": "No nodes found: " + ", ".join(not_found), &"sug": "Use read_scene to see node paths in this scene" }

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	var out: Dictionary = { &"removed": removed }
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
		return { &"err": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"err": "Missing 'property_name'" }
	if value == null:
		return { &"err": "Missing 'value'" }

	var parsed: Variant = _parse_value(value)

	# Live scene path — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }
		if not (property_name in target):
			return { &"err": "Property '%s' not found on %s (%s). Use get_node_properties to discover available properties." % [property_name, node_path, target.get_class()] }

		var old_value: Variant = target.get(property_name)
		if old_value is Resource and not (parsed is Resource):
			return { &"err": "Property '%s' expects a Resource. Use specialized tools (set_collision_shape, set_sprite_texture) instead." % property_name }

		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Set %s.%s" % [node_path, property_name])
		ur.add_do_property(target, property_name, parsed)
		ur.add_undo_property(target, property_name, old_value)
		ur.commit_action()

		return { &"old": str(old_value) }

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	# Check property exists
	if not (property_name in target):
		var node_type: String = target.get_class()
		root.queue_free()
		return { &"err": "Property '%s' not found on %s (%s). Use get_node_properties to discover available properties." % [property_name, node_path, node_type] }

	var old_value: Variant = target.get(property_name)

	# Validate resource type compatibility
	if old_value is Resource and not (parsed is Resource):
		root.queue_free()
		return { &"err": "Property '%s' expects a Resource. Use specialized tools (set_collision_shape, set_sprite_texture) instead." % property_name }

	target.set(property_name, parsed)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"old": str(old_value) }


# =============================================================================
# rename_node
# =============================================================================
func rename_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_name: String = args[&"new_name"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty():
		return { &"err": "Missing 'node_path'" }
	if new_name.strip_edges().is_empty():
		return { &"err": "Missing 'new_name'" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

		var old_name: StringName = target.name
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Rename " + str(old_name) + " -> " + new_name)
		ur.add_do_property(target, &"name", new_name)
		ur.add_undo_property(target, &"name", old_name)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	var old_name: StringName = target.name
	target.name = new_name

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# move_node
# =============================================================================
func move_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_parent_path: String = args[&"new_parent_path"]
	var sibling_index: int = args.get(&"sibling_index", -1)

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"err": "Cannot move root node" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = live_root.get_node_or_null(node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }
		var new_parent: Node = _find_live_node(live_root, new_parent_path)
		if not new_parent:
			return { &"err": "New parent not found: " + new_parent_path, &"sug": "Use read_scene to see node paths in this scene" }
		if new_parent == target or target.is_ancestor_of(new_parent):
			return { &"err": "Cannot move node to its own descendant" }

		var old_parent: Node = target.get_parent()
		var old_index: int = target.get_index()
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Move " + str(target.name))
		ur.add_do_method(old_parent, &"remove_child", target)
		ur.add_do_method(new_parent, &"add_child", target)
		ur.add_do_method(target, &"set_owner", live_root)
		if sibling_index >= 0:
			ur.add_do_method(new_parent, &"move_child", target, sibling_index)
		ur.add_undo_method(new_parent, &"remove_child", target)
		ur.add_undo_method(old_parent, &"add_child", target)
		ur.add_undo_method(old_parent, &"move_child", target, old_index)
		ur.add_undo_method(target, &"set_owner", live_root)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	var new_parent: Node = _find_node(root, new_parent_path)
	if not new_parent:
		root.queue_free()
		return { &"err": "New parent not found: " + new_parent_path, &"sug": "Use read_scene to see node paths in this scene" }

	# Prevent circular reference: new parent must not be the target or a descendant of it
	if new_parent == target or target.is_ancestor_of(new_parent):
		root.queue_free()
		return { &"err": "Cannot move node to its own descendant" }

	target.get_parent().remove_child(target)
	new_parent.add_child(target)
	target.owner = root

	if sibling_index >= 0:
		new_parent.move_child(target, mini(sibling_index, new_parent.get_child_count() - 1))

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# duplicate_node
# =============================================================================
func duplicate_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var new_name: String = args[&"new_name"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"err": "Cannot duplicate root node" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = live_root.get_node_or_null(node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }
		var parent: Node = target.get_parent()
		if not parent:
			return { &"err": "Cannot duplicate - no parent" }

		var dup: Node = target.duplicate()
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
		dup.name = new_name

		var original_index: int = target.get_index()
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Duplicate " + str(target.name))
		ur.add_do_method(parent, &"add_child", dup)
		ur.add_do_method(parent, &"move_child", dup, original_index + 1)
		ur.add_do_method(dup, &"set_owner", live_root)
		ur.add_do_reference(dup)
		ur.add_undo_method(parent, &"remove_child", dup)
		ur.commit_action()

		# Set owner recursively for children after the action commits
		_set_owner_recursive(dup, live_root)

		return { &"new_name": new_name }

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	var parent: Node = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"err": "Cannot duplicate - no parent" }

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
		return { &"err": "Missing 'scene_path'" }
	if node_path.strip_edges().is_empty() or node_path == ".":
		return { &"err": "Cannot reorder root node" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = live_root.get_node_or_null(node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }
		var parent: Node = target.get_parent()
		if not parent:
			return { &"err": "Cannot reorder - no parent" }

		var old_index: int = target.get_index()
		var max_index: int = parent.get_child_count() - 1
		new_index = clampi(new_index, 0, max_index)
		if old_index == new_index:
			return {}

		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Reorder " + str(target.name))
		ur.add_do_method(parent, &"move_child", target, new_index)
		ur.add_undo_method(parent, &"move_child", target, old_index)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = root.get_node_or_null(node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	var parent: Node = target.get_parent()
	if not parent:
		root.queue_free()
		return { &"err": "Cannot reorder - no parent" }

	var old_index: int = target.get_index()
	var max_index: int = parent.get_child_count() - 1
	new_index = clampi(new_index, 0, max_index)

	if old_index == new_index:
		root.queue_free()
		return {}

	parent.move_child(target, new_index)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# attach_script
# =============================================================================
func attach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var script_path: String = args[&"script_path"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if script_path.strip_edges().is_empty():
		return { &"err": "Missing 'script_path'" }
	script_path = _utils.validate_res_path(script_path)
	if script_path.is_empty():
		return { &"err": "script_path escapes project root" }

	var script_res: Resource = load(script_path)
	if not script_res:
		return { &"err": "Failed to load script: " + script_path, &"sug": "Use list_scripts to find available scripts" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

		var old_script: Variant = target.get_script()
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Attach script " + script_path.get_file())
		ur.add_do_method(target, &"set_script", script_res)
		ur.add_undo_method(target, &"set_script", old_script)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	target.set_script(script_res)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# detach_script
# =============================================================================
func detach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

		var old_script: Variant = target.get_script()
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Detach script from " + str(target.name))
		ur.add_do_method(target, &"set_script", null)
		ur.add_undo_method(target, &"set_script", old_script)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	target.set_script(null)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# set_collision_shape
# =============================================================================
func set_collision_shape(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var shape_type: String = args[&"shape_type"]
	var shape_params: Dictionary = args.get(&"shape_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if shape_type.strip_edges().is_empty():
		return { &"err": "Missing 'shape_type'" }
	if not ClassDB.class_exists(shape_type):
		return { &"err": "Invalid shape type: " + shape_type, &"sug": "Use query_class_info with 'Shape2D' or 'Shape3D' to find valid shape types" }

	# Create shape resource (shared by both paths)
	var shape: Variant = ClassDB.instantiate(shape_type)
	if not shape:
		return { &"err": "Failed to create shape: " + shape_type }

	# Apply shape parameters
	if shape_params.has(&"radius"):
		shape.set(&"radius", shape_params[&"radius"])
	if shape_params.has(&"height"):
		shape.set(&"height", shape_params[&"height"])
	if shape_params.has(&"size"):
		var size_data: Variant = shape_params[&"size"]
		if size_data is Dictionary:
			if size_data.has(&"z"):
				shape.set(&"size", Vector3(size_data.get(&"x", 1), size_data.get(&"y", 1), size_data.get(&"z", 1)))
			else:
				shape.set(&"size", Vector2(size_data.get(&"x", 1), size_data.get(&"y", 1)))

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

		var old_shape: Variant = target.get(&"shape")
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Set collision shape " + shape_type)
		ur.add_do_property(target, &"shape", shape)
		ur.add_undo_property(target, &"shape", old_shape)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

	target.set(&"shape", shape)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# set_sprite_texture
# =============================================================================
func set_sprite_texture(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var texture_type: String = args[&"texture_type"]
	var texture_params: Dictionary = args.get(&"texture_params", { })

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }
	if texture_type.strip_edges().is_empty():
		return { &"err": "Missing 'texture_type'" }

	# Create texture resource (shared by both paths)
	var texture: Texture2D = null
	match texture_type:
		"ImageTexture":
			var tex_path: String = _utils.validate_res_path(texture_params.get(&"path", ""))
			if tex_path.is_empty():
				return { &"err": "Missing or invalid 'path' in texture_params for ImageTexture" }
			texture = load(tex_path) as Texture2D
			if not texture:
				return { &"err": "Failed to load texture: " + tex_path }
		"PlaceholderTexture2D":
			texture = PlaceholderTexture2D.new()
			var size_data: Variant = texture_params.get(&"size", { &"x": 64, &"y": 64 })
			if size_data is Dictionary:
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
			return { &"err": "Unknown texture type: " + texture_type }

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path }

		var old_texture: Variant = target.get(&"texture")
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Set texture " + texture_type)
		ur.add_do_property(target, &"texture", texture)
		ur.add_undo_property(target, &"texture", old_texture)
		ur.commit_action()

		return {}

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path }

	target.set(&"texture", texture)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {}


# =============================================================================
# get_scene_hierarchy (for visualizer)
# =============================================================================
## Get the full scene hierarchy with node information for the visualizer.
func get_scene_hierarchy(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])

	if scene_path.is_empty() or scene_path == "res://":
		return { &"err": "Missing 'scene_path'" }

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
		return { &"err": "Missing 'scene_path'" }

	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path, &"sug": "Use read_scene to see node paths in this scene" }

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
		return { &"err": "Missing 'scene_path'" }
	if property_name.strip_edges().is_empty():
		return { &"err": "Missing 'property_name'" }

	var parsed_value: Variant = _parse_typed_value(value, value_type)

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path }

		var old_value: Variant = target.get(property_name)
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Set %s.%s" % [node_path, property_name])
		ur.add_do_property(target, property_name, parsed_value)
		ur.add_undo_property(target, property_name, old_value)
		ur.commit_action()

		return { &"old": _utils.serialize_value(old_value) }

	# Fallback: disk-based
	var result: Array = _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target: Node = _find_node(root, node_path)
	if not target:
		root.queue_free()
		return { &"err": "Node not found: " + node_path }

	# Parse value based on type
	var old_value: Variant = target.get(property_name)

	# Set the property
	target.set(property_name, parsed_value)

	var err: Dictionary = _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return { &"old": _utils.serialize_value(old_value) }


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

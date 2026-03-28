@tool
extends RefCounted

class_name PhysicsTools
## Physics setup tools for MCP.
## Handles: physics_edit (setup_collision, set_layers, get_layers, add_raycast, setup_body, info)
## Consolidates former get_collision_layers + set_collision_shape.

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func phys(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"collision":
			return _setup_collision(args)
		"layers":
			return _set_layers(args)
		"get_layers":
			return _get_layers(args)
		"raycast":
			return _add_raycast(args)
		"body":
			return _setup_body(args)
		"info":
			return _info(args)
		_:
			return { &"err": "Unknown physics_edit action: " + action }


# =============================================================================
# Helpers
# =============================================================================

func _get_undo_redo() -> EditorUndoRedoManager:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_undo_redo()


func _get_edited_root() -> Node:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_editor_interface().get_edited_scene_root()


func _get_live_scene(scene_path: String) -> Node:
	var root: Node = _get_edited_root()
	if root and root.scene_file_path == scene_path:
		return root
	return null


func _find_live_node(root: Node, node_path: String) -> Node:
	if node_path == "." or node_path.is_empty():
		return root
	return root.get_node_or_null(node_path)


# =============================================================================
# setup_collision — create CollisionShape2D/3D with shape
# Absorbs former set_collision_shape
# =============================================================================
func _setup_collision(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var shape_type: String = args[&"shape_type"]
	var shape_params: Dictionary = args.get(&"shape_params", {})

	if not ClassDB.class_exists(shape_type):
		return { &"err": "Invalid shape type: " + shape_type, &"sug": "Use query_class_info with 'Shape2D' or 'Shape3D'" }

	var shape: Variant = ClassDB.instantiate(shape_type)
	if not shape:
		return { &"err": "Failed to create shape: " + shape_type }

	# Apply shape parameters
	if shape_params.has(&"radius"):
		shape.set(&"radius", shape_params[&"radius"])
	if shape_params.has(&"height"):
		shape.set(&"height", shape_params[&"height"])
	if shape_params.has(&"size"):
		var s: Dictionary = shape_params[&"size"]
		if s.has(&"z"):
			shape.set(&"size", Vector3(s[&"x"], s[&"y"], s[&"z"]))
		else:
			shape.set(&"size", Vector2(s[&"x"], s[&"y"]))

	# Live scene — use UndoRedo
	var live_root: Node = _get_live_scene(scene_path)
	if live_root:
		var target: Node = _find_live_node(live_root, node_path)
		if not target:
			return { &"err": "Node not found: " + node_path }

		var old_shape: Variant = target.get(&"shape")
		var ur: EditorUndoRedoManager = _get_undo_redo()
		ur.create_action("MCP: Set collision shape " + shape_type)
		ur.add_do_property(target, &"shape", shape)
		ur.add_undo_property(target, &"shape", old_shape)
		ur.commit_action()

		return {}

	# Fallback: disk-based via scene_tools pattern
	return { &"err": "Scene not open in editor: " + scene_path, &"sug": "Open the scene first with open_in_godot" }


# =============================================================================
# set_layers — configure collision_layer/collision_mask
# =============================================================================
func _set_layers(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]

	var live_root: Node = _get_live_scene(scene_path)
	if not live_root:
		return { &"err": "Scene not open: " + scene_path }

	var target: Node = _find_live_node(live_root, node_path)
	if not target:
		return { &"err": "Node not found: " + node_path }

	if args.has(&"collision_layer"):
		target.set(&"collision_layer", int(args[&"collision_layer"]))
	if args.has(&"collision_mask"):
		target.set(&"collision_mask", int(args[&"collision_mask"]))

	return {}


# =============================================================================
# get_layers — named physics layers from ProjectSettings
# Absorbs former get_collision_layers
# =============================================================================
func _get_layers(args: Dictionary) -> Dictionary:
	match args.get(&"dimension", ""):
		"2d":
			return { &"layers_2d": _collect_layers("layer_names/2d_physics") }
		"3d":
			return { &"layers_3d": _collect_layers("layer_names/3d_physics") }

	var layers_2d: Array[Dictionary] = _collect_layers("layer_names/2d_physics")
	var layers_3d: Array[Dictionary] = _collect_layers("layer_names/3d_physics")
	var keys: Array[StringName] = [&"index", &"value"]
	return { &"layers_2d": _utils.tabular(layers_2d, keys), &"layers_3d": _utils.tabular(layers_3d, keys) }


func _collect_layers(prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(1, 33):
		var key: String = "%s/layer_%d" % [prefix, i]
		if ProjectSettings.has_setting(key):
			out.append({ &"index": i, &"value": ProjectSettings.get_setting(key) })
	return out


# =============================================================================
# add_raycast — create RayCast2D/3D
# =============================================================================
func _add_raycast(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var target_pos: Dictionary = args[&"target_position"]

	var live_root: Node = _get_live_scene(scene_path)
	if not live_root:
		return { &"err": "Scene not open: " + scene_path }

	var parent: Node = _find_live_node(live_root, node_path)
	if not parent:
		return { &"err": "Node not found: " + node_path }

	var is_3d: bool = target_pos.has(&"z")
	var raycast: Node
	if is_3d:
		var rc := RayCast3D.new()
		rc.target_position = Vector3(target_pos[&"x"], target_pos[&"y"], target_pos[&"z"])
		raycast = rc
	else:
		var rc := RayCast2D.new()
		rc.target_position = Vector2(target_pos[&"x"], target_pos[&"y"])
		raycast = rc

	raycast.name = &"RayCast"
	var ur: EditorUndoRedoManager = _get_undo_redo()
	ur.create_action("MCP: Add RayCast")
	ur.add_do_method(parent, &"add_child", raycast)
	ur.add_do_method(raycast, &"set_owner", live_root)
	ur.add_undo_method(parent, &"remove_child", raycast)
	ur.commit_action()

	return { &"node_path": str(live_root.get_path_to(raycast)) }


# =============================================================================
# setup_body — configure physics body properties
# =============================================================================
func _setup_body(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var properties: Dictionary = args.get(&"properties", {})

	var live_root: Node = _get_live_scene(scene_path)
	if not live_root:
		return { &"err": "Scene not open: " + scene_path }

	var target: Node = _find_live_node(live_root, node_path)
	if not target:
		return { &"err": "Node not found: " + node_path }

	for prop_name: String in properties:
		if prop_name in target:
			target.set(prop_name, properties[prop_name])

	return {}


# =============================================================================
# info — enumerate collision shapes and raycasts in subtree
# =============================================================================
func _info(args: Dictionary) -> Dictionary:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]

	var live_root: Node = _get_live_scene(scene_path)
	if not live_root:
		return { &"err": "Scene not open: " + scene_path }

	var target: Node = _find_live_node(live_root, node_path)
	if not target:
		return { &"err": "Node not found: " + node_path }

	var shapes: Array[Dictionary] = []
	var raycasts: Array[Dictionary] = []
	_collect_physics_nodes(live_root, target, shapes, raycasts)

	return { &"shapes": shapes, &"rays": raycasts }


func _collect_physics_nodes(scene_root: Node, node: Node, shapes: Array[Dictionary], raycasts: Array[Dictionary]) -> void:
	if node is CollisionShape2D or node is CollisionShape3D:
		var shape: Variant = node.get(&"shape")
		shapes.append({
			&"path": str(scene_root.get_path_to(node)),
			&"type": node.get_class(),
			&"shape": shape.get_class() if shape else "none",
		})
	elif node is RayCast2D or node is RayCast3D:
		raycasts.append({
			&"path": str(scene_root.get_path_to(node)),
			&"type": node.get_class(),
		})

	for child: Node in node.get_children():
		_collect_physics_nodes(scene_root, child, shapes, raycasts)

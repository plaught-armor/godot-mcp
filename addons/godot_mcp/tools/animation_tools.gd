@tool
extends RefCounted

class_name AnimationTools
## Animation and AnimationTree tools for MCP.
## Handles: animation_edit (list, create, add_track, set_keyframe, info, remove,
##   create_tree, get_tree_structure, add_state, remove_state, add_transition,
##   remove_transition, set_blend_node, set_parameter)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func anim(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"list":
			return _list(args)
		"create":
			return _create(args)
		"track":
			return _add_track(args)
		"keyframe":
			return _set_keyframe(args)
		"info":
			return _info(args)
		"remove":
			return _remove(args)
		"new_tree":
			return _create_tree(args)
		"tree":
			return _get_tree_structure(args)
		"add_state":
			return _add_state(args)
		"rm_state":
			return _remove_state(args)
		"add_trans":
			return _add_transition(args)
		"rm_trans":
			return _remove_transition(args)
		"blend_node":
			return _set_blend_node(args)
		"set_param":
			return _set_parameter(args)
		_:
			return { &"err": "Unknown animation_edit action: " + action }


# =============================================================================
# Helpers
# =============================================================================

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


func _find_player(args: Dictionary) -> AnimationPlayer:
	var node: Node = _find_node(args[&"node_path"])
	if node is AnimationPlayer:
		return node as AnimationPlayer
	return null


func _find_tree(args: Dictionary) -> AnimationTree:
	var node: Node = _find_node(args[&"node_path"])
	if node is AnimationTree:
		return node as AnimationTree
	return null


func _resolve_state_machine(tree: AnimationTree, sm_path: String) -> Array:
	var root_node: AnimationNode = tree.tree_root
	if not root_node is AnimationNodeStateMachine:
		return [null, { &"err": "Tree root is not AnimationNodeStateMachine" }]
	if sm_path.is_empty() or sm_path == ".":
		return [root_node as AnimationNodeStateMachine, null]

	var current: AnimationNodeStateMachine = root_node as AnimationNodeStateMachine
	for part: String in sm_path.split("/"):
		if not current.has_node(StringName(part)):
			return [null, { &"err": "State machine node '%s' not found" % part }]
		var child: AnimationNode = current.get_node(StringName(part))
		if not child is AnimationNodeStateMachine:
			return [null, { &"err": "Node '%s' is not a StateMachine" % part }]
		current = child as AnimationNodeStateMachine
	return [current, null]


# =============================================================================
# AnimationPlayer actions
# =============================================================================

func _list(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var animations: Array[Dictionary] = []
	for anim_name: StringName in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		animations.append({ &"name": anim_name, &"length": anim.length, &"loop_mode": anim.loop_mode, &"track_count": anim.get_track_count() })
	return { &"anims": animations }


func _create(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var anim_name: String = args[&"name"]

	var anim := Animation.new()
	anim.length = args.get(&"length", 1.0)
	anim.loop_mode = int(args.get(&"loop_mode", 0))

	var lib: AnimationLibrary = player.get_animation_library(&"")
	if not lib:
		lib = AnimationLibrary.new()
		player.add_animation_library(&"", lib)
	lib.add_animation(anim_name, anim)
	return {}


func _add_track(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var anim: Animation = player.get_animation(args[&"animation"])
	if not anim:
		return { &"err": "Animation not found: " + args[&"animation"] }

	var track_path: String = args[&"track_path"]

	var track_type_str: String = args.get(&"track_type", "value")
	var track_type: int = Animation.TYPE_VALUE
	match track_type_str:
		"value": track_type = Animation.TYPE_VALUE
		"position_2d": track_type = Animation.TYPE_POSITION_3D
		"rotation_2d": track_type = Animation.TYPE_ROTATION_3D
		"scale_2d": track_type = Animation.TYPE_SCALE_3D
		"method": track_type = Animation.TYPE_METHOD
		"bezier": track_type = Animation.TYPE_BEZIER
		"blend_shape": track_type = Animation.TYPE_BLEND_SHAPE

	var track_idx: int = anim.add_track(track_type)
	anim.track_set_path(track_idx, NodePath(track_path))

	if args.has(&"update_mode") and track_type == Animation.TYPE_VALUE:
		match args[&"update_mode"]:
			"continuous": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_CONTINUOUS)
			"discrete": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_DISCRETE)
			"capture": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_CAPTURE)

	return { &"ti": track_idx }


func _set_keyframe(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var anim: Animation = player.get_animation(args[&"animation"])
	if not anim:
		return { &"err": "Animation not found" }

	var track_index: int = int(args[&"track_index"])
	if track_index < 0 or track_index >= anim.get_track_count():
		return { &"err": "Invalid track_index: %d" % track_index }

	var time: float = float(args[&"time"])
	var value: Variant = args[&"value"]

	# Parse string values
	if value is String:
		var expr := Expression.new()
		if expr.parse(value) == OK:
			var parsed: Variant = expr.execute()
			if parsed != null:
				value = parsed

	var key_idx: int = anim.track_insert_key(track_index, time, value)

	if args.has(&"easing"):
		anim.track_set_key_transition(track_index, key_idx, float(args[&"easing"]))

	return { &"ki": key_idx }


func _info(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var anim_name: String = args[&"animation"]
	var anim: Animation = player.get_animation(anim_name)
	if not anim:
		return { &"err": "Animation not found: " + anim_name }

	var tracks: Array[Dictionary] = []
	for i: int in anim.get_track_count():
		var keys: Array[Dictionary] = []
		for k: int in anim.track_get_key_count(i):
			keys.append({ &"time": anim.track_get_key_time(i, k), &"value": str(anim.track_get_key_value(i, k)), &"easing": anim.track_get_key_transition(i, k) })
		tracks.append({ &"index": i, &"path": str(anim.track_get_path(i)), &"type": anim.track_get_type(i), &"keys": keys })

	return { &"name": anim_name, &"length": anim.length, &"loop_mode": anim.loop_mode, &"step": anim.step, &"tracks": tracks }


func _remove(args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _find_player(args)
	if not player:
		return { &"err": "AnimationPlayer not found" }

	var anim_name: String = args[&"name"]
	var lib: AnimationLibrary = player.get_animation_library(&"")
	if not lib or not lib.has_animation(anim_name):
		return { &"err": "Animation not found: " + anim_name }

	lib.remove_animation(anim_name)
	return {}


# =============================================================================
# AnimationTree actions
# =============================================================================

func _create_tree(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"node_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var tree := AnimationTree.new()
	tree.name = args.get(&"name", "AnimationTree")
	tree.tree_root = AnimationNodeStateMachine.new()

	if args.has(&"anim_player"):
		tree.anim_player = NodePath(args[&"anim_player"])

	parent.add_child(tree, true)
	tree.owner = root
	return { &"node_path": str(root.get_path_to(tree)) }


func _get_tree_structure(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }
	if not tree.tree_root:
		return { &"root": null }

	var structure: Dictionary = _read_node_structure(tree.tree_root)
	structure[&"active"] = tree.active
	return structure


func _read_node_structure(node: AnimationNode) -> Dictionary:
	if node is AnimationNodeStateMachine:
		return _read_sm(node as AnimationNodeStateMachine)
	elif node is AnimationNodeBlendTree:
		return _read_bt(node as AnimationNodeBlendTree)
	elif node is AnimationNodeAnimation:
		return { &"type": "AnimationNodeAnimation", &"animation": str((node as AnimationNodeAnimation).animation) }
	return { &"type": node.get_class() }


func _read_sm(sm: AnimationNodeStateMachine) -> Dictionary:
	var states: Array[Dictionary] = []
	for prop: Dictionary in sm.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("states/") and pname.ends_with("/node"):
			var state_name: String = pname.get_slice("/", 1)
			if state_name != "Start" and state_name != "End":
				var child: AnimationNode = sm.get_node(StringName(state_name))
				var info: Dictionary = { &"name": state_name }
				info.merge(_read_node_structure(child))
				states.append(info)

	var transitions: Array[Dictionary] = []
	for i: int in sm.get_transition_count():
		transitions.append({ &"from": str(sm.get_transition_from(i)), &"to": str(sm.get_transition_to(i)), &"switch_mode": sm.get_transition(i).switch_mode, &"advance_mode": sm.get_transition(i).advance_mode })

	return { &"type": "AnimationNodeStateMachine", &"states": states, &"transitions": transitions }


func _read_bt(bt: AnimationNodeBlendTree) -> Dictionary:
	var nodes: Array[Dictionary] = []
	for prop: Dictionary in bt.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("nodes/") and pname.ends_with("/node"):
			var n_name: String = pname.get_slice("/", 1)
			if n_name != "output":
				var child: AnimationNode = bt.get_node(StringName(n_name))
				var info: Dictionary = { &"name": n_name, &"type": child.get_class() }
				if child is AnimationNodeAnimation:
					info[&"animation"] = str((child as AnimationNodeAnimation).animation)
				nodes.append(info)
	return { &"type": "AnimationNodeBlendTree", &"nodes": nodes }


func _add_state(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var sm_result: Array = _resolve_state_machine(tree, args.get(&"state_machine_path", ""))
	if sm_result[1] != null:
		return sm_result[1]
	var sm: AnimationNodeStateMachine = sm_result[0]

	var state_name: String = args[&"state_name"]
	if sm.has_node(StringName(state_name)):
		return { &"err": "State already exists: " + state_name }

	var state_type: String = args.get(&"state_type", "animation")
	var node: AnimationNode
	match state_type:
		"animation":
			var anim_node := AnimationNodeAnimation.new()
			if args.has(&"animation"):
				anim_node.animation = StringName(args[&"animation"])
			node = anim_node
		"blend_tree":
			node = AnimationNodeBlendTree.new()
		"state_machine":
			node = AnimationNodeStateMachine.new()
		_:
			return { &"err": "Unknown state_type: " + state_type }

	sm.add_node(StringName(state_name), node, Vector2(args.get(&"position_x", 0.0), args.get(&"position_y", 0.0)))
	return {}


func _remove_state(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var sm_result: Array = _resolve_state_machine(tree, args.get(&"state_machine_path", ""))
	if sm_result[1] != null:
		return sm_result[1]
	var sm: AnimationNodeStateMachine = sm_result[0]

	var state_name: String = args[&"state_name"]
	if not sm.has_node(StringName(state_name)):
		return { &"err": "State not found: " + state_name }

	sm.remove_node(StringName(state_name))
	return {}


func _add_transition(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var sm_result: Array = _resolve_state_machine(tree, args.get(&"state_machine_path", ""))
	if sm_result[1] != null:
		return sm_result[1]
	var sm: AnimationNodeStateMachine = sm_result[0]

	var from_state: String = args[&"from_state"]
	var to_state: String = args[&"to_state"]

	var transition := AnimationNodeStateMachineTransition.new()

	match args.get(&"switch_mode", "immediate"):
		"at_end": transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		"immediate": transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE

	match args.get(&"advance_mode", "enabled"):
		"disabled": transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		"enabled": transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		"auto": transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO

	if args.has(&"advance_expression"):
		transition.advance_expression = args[&"advance_expression"]

	if args.has(&"xfade_time"):
		transition.xfade_time = float(args[&"xfade_time"])

	sm.add_transition(StringName(from_state), StringName(to_state), transition)
	return {}


func _remove_transition(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var sm_result: Array = _resolve_state_machine(tree, args.get(&"state_machine_path", ""))
	if sm_result[1] != null:
		return sm_result[1]
	var sm: AnimationNodeStateMachine = sm_result[0]

	var from_state: String = args[&"from_state"]
	var to_state: String = args[&"to_state"]
	sm.remove_transition(StringName(from_state), StringName(to_state))
	return {}


func _set_blend_node(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var sm_result: Array = _resolve_state_machine(tree, args.get(&"state_machine_path", ""))
	if sm_result[1] != null:
		return sm_result[1]
	var sm: AnimationNodeStateMachine = sm_result[0]

	var bt_state: String = args[&"blend_tree_state"]
	if not sm.has_node(StringName(bt_state)):
		return { &"err": "BlendTree state not found: " + bt_state }
	var bt_node: AnimationNode = sm.get_node(StringName(bt_state))
	if not bt_node is AnimationNodeBlendTree:
		return { &"err": "State is not a BlendTree" }
	var bt: AnimationNodeBlendTree = bt_node as AnimationNodeBlendTree

	var bt_node_name: String = args[&"bt_node_name"]
	var bt_node_type: String = args[&"bt_node_type"]

	if bt.has_node(StringName(bt_node_name)):
		bt.remove_node(StringName(bt_node_name))

	var node: AnimationNode
	match bt_node_type:
		"Animation":
			var anim_node := AnimationNodeAnimation.new()
			if args.has(&"animation"):
				anim_node.animation = StringName(args[&"animation"])
			node = anim_node
		"Add2": node = AnimationNodeAdd2.new()
		"Blend2": node = AnimationNodeBlend2.new()
		"Add3": node = AnimationNodeAdd3.new()
		"Blend3": node = AnimationNodeBlend3.new()
		"TimeScale": node = AnimationNodeTimeScale.new()
		"TimeSeek": node = AnimationNodeTimeSeek.new()
		"Transition": node = AnimationNodeTransition.new()
		"OneShot": node = AnimationNodeOneShot.new()
		"Sub2": node = AnimationNodeSub2.new()
		_:
			return { &"err": "Unknown bt_node_type: " + bt_node_type }

	bt.add_node(StringName(bt_node_name), node, Vector2(args.get(&"position_x", 0.0), args.get(&"position_y", 0.0)))

	if args.has(&"connect_to"):
		bt.connect_node(StringName(args[&"connect_to"]), int(args.get(&"connect_port", 0)), StringName(bt_node_name))

	return {}


func _set_parameter(args: Dictionary) -> Dictionary:
	var tree: AnimationTree = _find_tree(args)
	if not tree:
		return { &"err": "AnimationTree not found" }

	var parameter: String = args[&"parameter"]
	if not parameter.begins_with("parameters/"):
		parameter = "parameters/" + parameter

	var value: Variant = args.get(&"value")
	if value is String:
		var expr := Expression.new()
		if expr.parse(value) == OK:
			var parsed: Variant = expr.execute()
			if parsed != null:
				value = parsed

	tree.set(parameter, value)
	return {}

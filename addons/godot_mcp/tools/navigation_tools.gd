@tool
extends RefCounted

class_name NavigationTools
## Navigation region, agent, and mesh tools for MCP.
## Handles: navigation_edit (setup_region, bake, setup_agent, set_layers, info)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func nav(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"region":
			return _setup_region(args)
		&"bake":
			return _bake(args)
		&"agent":
			return _setup_agent(args)
		&"layers":
			return _set_layers(args)
		&"info":
			return _info(args)
		_:
			return { &"err": "Unknown navigation_edit action: " + action }


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


func _is_3d_context(node: Node) -> bool:
	var current: Node = node
	while current:
		if current is Node3D: return true
		if current is Node2D: return false
		current = current.get_parent()
	return false


func _detect_mode(args: Dictionary, node: Node) -> bool:
	match args.get(&"mode", "auto"):
		"2d": return false
		"3d": return true
	return _is_3d_context(node)


# =============================================================================
# setup_region
# =============================================================================
func _setup_region(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args[&"node_path"])
	if not parent:
		return { &"err": "Node not found" }

	var is_3d: bool = _detect_mode(args, parent)

	if is_3d:
		var region := NavigationRegion3D.new()
		region.name = args.get(&"name", "NavigationRegion3D")

		var nav_mesh := NavigationMesh.new()
		nav_mesh.agent_radius = float(args.get(&"agent_radius", 0.5))
		nav_mesh.agent_height = float(args.get(&"agent_height", 1.5))
		nav_mesh.cell_size = float(args.get(&"cell_size", 0.25))
		region.navigation_mesh = nav_mesh

		if args.has(&"navigation_layers"):
			region.navigation_layers = int(args[&"navigation_layers"])

		parent.add_child(region, true)
		region.owner = root
		return { &"node_path": str(root.get_path_to(region)) }
	else:
		var region := NavigationRegion2D.new()
		region.name = args.get(&"name", "NavigationRegion2D")

		var nav_poly := NavigationPolygon.new()
		if args.has(&"cell_size"):
			nav_poly.cell_size = float(args[&"cell_size"])
		if args.has(&"agent_radius"):
			nav_poly.agent_radius = float(args[&"agent_radius"])
		region.navigation_polygon = nav_poly

		if args.has(&"navigation_layers"):
			region.navigation_layers = int(args[&"navigation_layers"])

		parent.add_child(region, true)
		region.owner = root
		return { &"node_path": str(root.get_path_to(region)) }


# =============================================================================
# bake
# =============================================================================
func _bake(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	if node is NavigationRegion3D:
		var region: NavigationRegion3D = node as NavigationRegion3D
		if not region.navigation_mesh:
			return { &"err": "No NavigationMesh resource" }
		region.bake_navigation_mesh()
		return {}

	elif node is NavigationRegion2D:
		var region: NavigationRegion2D = node as NavigationRegion2D
		if not region.navigation_polygon:
			region.navigation_polygon = NavigationPolygon.new()

		if args.has(&"outline"):
			var outline_data: Array = args[&"outline"]
			var outline := PackedVector2Array()
			for point: Variant in outline_data:
				if point is Array and point.size() >= 2:
					outline.append(Vector2(float(point[0]), float(point[1])))
				elif point is Dictionary:
					outline.append(Vector2(float(point[&"x"]), float(point[&"y"])))
			if outline.size() < 3:
				return { &"err": "Outline needs at least 3 vertices" }
			while region.navigation_polygon.get_outline_count() > 0:
				region.navigation_polygon.remove_outline(0)
			region.navigation_polygon.add_outline(outline)
			region.navigation_polygon.make_polygons_from_outlines()
			return {}
		else:
			region.bake_navigation_polygon()
			return {}

	return { &"err": "Node is not a NavigationRegion2D/3D" }


# =============================================================================
# setup_agent
# =============================================================================
func _setup_agent(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args[&"node_path"])
	if not parent:
		return { &"err": "Node not found" }

	var is_3d: bool = _detect_mode(args, parent)

	if is_3d:
		var agent := NavigationAgent3D.new()
		agent.name = args.get(&"name", "NavigationAgent3D")
		if args.has(&"radius"): agent.radius = float(args[&"radius"])
		if args.has(&"max_speed"): agent.max_speed = float(args[&"max_speed"])
		if args.has(&"avoidance_enabled"): agent.avoidance_enabled = bool(args[&"avoidance_enabled"])
		if args.has(&"navigation_layers"): agent.navigation_layers = int(args[&"navigation_layers"])
		parent.add_child(agent, true)
		agent.owner = root
		return { &"node_path": str(root.get_path_to(agent)) }
	else:
		var agent := NavigationAgent2D.new()
		agent.name = args.get(&"name", "NavigationAgent2D")
		if args.has(&"radius"): agent.radius = float(args[&"radius"])
		if args.has(&"max_speed"): agent.max_speed = float(args[&"max_speed"])
		if args.has(&"avoidance_enabled"): agent.avoidance_enabled = bool(args[&"avoidance_enabled"])
		if args.has(&"navigation_layers"): agent.navigation_layers = int(args[&"navigation_layers"])
		parent.add_child(agent, true)
		agent.owner = root
		return { &"node_path": str(root.get_path_to(agent)) }


# =============================================================================
# set_layers
# =============================================================================
func _set_layers(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var layers_val: int = 0

	if args.has(&"layers"):
		layers_val = int(args[&"layers"])
	elif args.has(&"layer_bits"):
		var bits: Array = args[&"layer_bits"]
		for bit: Variant in bits:
			var num: int = int(bit)
			if num >= 1 and num <= 32:
				layers_val |= (1 << (num - 1))
	elif args.has(&"layer_names"):
		var names: Array = args[&"layer_names"]
		var is_2d: bool = node is NavigationRegion2D or node is NavigationAgent2D
		var prefix: String = "layer_names/2d_navigation/layer_" if is_2d else "layer_names/3d_navigation/layer_"
		for i: int in range(1, 33):
			var key: String = prefix + str(i)
			if ProjectSettings.has_setting(key):
				if str(ProjectSettings.get_setting(key)) in names:
					layers_val |= (1 << (i - 1))
	else:
		return { &"err": "Need 'layers', 'layer_bits', or 'layer_names'" }

	if &"navigation_layers" in node:
		node.set(&"navigation_layers", layers_val)
		return {}
	return { &"err": "Node does not support navigation_layers" }


# =============================================================================
# info
# =============================================================================
func _info(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var regions: Array[Dictionary] = []
	var agents: Array[Dictionary] = []
	_collect(node, regions, agents)

	return { &"regions": regions, &"agents": agents }


func _collect(node: Node, regions: Array[Dictionary], agents: Array[Dictionary]) -> void:
	if node is NavigationRegion2D:
		var r: NavigationRegion2D = node as NavigationRegion2D
		regions.append({ &"path": str(node.get_path()), &"type": "NavigationRegion2D", &"enabled": r.enabled, &"navigation_layers": r.navigation_layers })
	elif node is NavigationRegion3D:
		var r: NavigationRegion3D = node as NavigationRegion3D
		regions.append({ &"path": str(node.get_path()), &"type": "NavigationRegion3D", &"enabled": r.enabled, &"navigation_layers": r.navigation_layers })

	if node is NavigationAgent2D:
		var a: NavigationAgent2D = node as NavigationAgent2D
		agents.append({ &"path": str(node.get_path()), &"type": "NavigationAgent2D", &"radius": a.radius, &"max_speed": a.max_speed })
	elif node is NavigationAgent3D:
		var a: NavigationAgent3D = node as NavigationAgent3D
		agents.append({ &"path": str(node.get_path()), &"type": "NavigationAgent3D", &"radius": a.radius, &"max_speed": a.max_speed })

	for child: Node in node.get_children():
		_collect(child, regions, agents)

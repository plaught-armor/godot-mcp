@tool
extends RefCounted

class_name ParticleTools
## GPU particle tools for MCP.
## Handles: particle_edit (create, set_material, set_color_gradient, apply_preset, info)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func ptcl(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"create":
			return _create(args)
		"material":
			return _set_material(args)
		"gradient":
			return _set_color_gradient(args)
		"preset":
			return _apply_preset(args)
		"info":
			return _info(args)
		_:
			return { &"err": "Unknown particle_edit action: " + action }


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


func _find_particles(node_path: String) -> Node:
	var node: Node = _find_node(node_path)
	if node is GPUParticles2D or node is GPUParticles3D:
		return node
	return null


func _create(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var particles_node: Node = GPUParticles3D.new() if args.get(&"is_3d", false) else GPUParticles2D.new()
	particles_node.amount = int(args.get(&"amount", 16))
	particles_node.lifetime = float(args.get(&"lifetime", 1.0))
	particles_node.one_shot = args.get(&"one_shot", false)
	particles_node.explosiveness = float(args.get(&"explosiveness", 0.0))
	particles_node.emitting = args.get(&"emitting", true)
	particles_node.process_material = ParticleProcessMaterial.new()

	particles_node.name = args.get(&"name", "Particles")
	parent.add_child(particles_node, true)
	particles_node.owner = root
	return { &"node_path": str(root.get_path_to(particles_node)) }


func _set_material(args: Dictionary) -> Dictionary:
	var node: Node = _find_particles(args[&"node_path"])
	if not node:
		return { &"err": "GPUParticles not found" }

	var mat: ParticleProcessMaterial = node.process_material as ParticleProcessMaterial
	if not mat:
		mat = ParticleProcessMaterial.new()
		node.process_material = mat

	if args.has(&"direction"):
		var d: Dictionary = args[&"direction"]
		mat.direction = Vector3(d[&"x"], d[&"y"], d[&"z"])
	if args.has(&"spread"):
		mat.spread = float(args[&"spread"])
	if args.has(&"gravity"):
		var g: Dictionary = args[&"gravity"]
		mat.gravity = Vector3(g[&"x"], g[&"y"], g[&"z"])
	if args.has(&"initial_velocity_min"):
		mat.initial_velocity_min = float(args[&"initial_velocity_min"])
	if args.has(&"initial_velocity_max"):
		mat.initial_velocity_max = float(args[&"initial_velocity_max"])
	if args.has(&"scale_min"):
		mat.scale_min = float(args[&"scale_min"])
	if args.has(&"scale_max"):
		mat.scale_max = float(args[&"scale_max"])
	if args.has(&"emission_shape"):
		var shape_str: String = args[&"emission_shape"]
		match shape_str:
			"point": mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			"sphere": mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			"sphere_surface": mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			"box": mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			"ring": mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING

	return {}


func _set_color_gradient(args: Dictionary) -> Dictionary:
	var node: Node = _find_particles(args[&"node_path"])
	if not node:
		return { &"err": "GPUParticles not found" }

	var mat: ParticleProcessMaterial = node.process_material as ParticleProcessMaterial
	if not mat:
		return { &"err": "No ParticleProcessMaterial" }

	var colors: Array = args[&"colors"]
	var gradient := Gradient.new()
	gradient.remove_point(0)
	if gradient.get_point_count() > 0:
		gradient.remove_point(0)

	for entry: Variant in colors:
		if entry is Dictionary:
			gradient.add_point(float(entry[&"offset"]), Color(entry[&"color"]))

	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	mat.color_ramp = tex

	return {}


func _apply_preset(args: Dictionary) -> Dictionary:
	var node: Node = _find_particles(args[&"node_path"])
	if not node:
		return { &"err": "GPUParticles not found" }

	var mat: ParticleProcessMaterial = node.process_material as ParticleProcessMaterial
	if not mat:
		mat = ParticleProcessMaterial.new()
		node.process_material = mat

	var preset: String = args[&"preset"]
	match preset:
		"explosion":
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 10.0
			mat.gravity = Vector3(0, -9.8, 0)
			node.one_shot = true
			node.explosiveness = 1.0
		"fire":
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 15.0
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 5.0
			mat.gravity = Vector3(0, 0, 0)
			mat.scale_min = 0.5
			mat.scale_max = 1.5
		"smoke":
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 20.0
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 2.0
			mat.gravity = Vector3(0, 0, 0)
			mat.scale_min = 1.0
			mat.scale_max = 3.0
		"sparks":
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 60.0
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 8.0
			mat.gravity = Vector3(0, 9.8, 0)
			mat.scale_min = 0.1
			mat.scale_max = 0.3
		"rain":
			mat.direction = Vector3(0, 1, 0)
			mat.spread = 5.0
			mat.initial_velocity_min = 10.0
			mat.initial_velocity_max = 15.0
			mat.gravity = Vector3(0, 9.8, 0)
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		"snow":
			mat.direction = Vector3(0, 1, 0)
			mat.spread = 30.0
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 2.0
			mat.gravity = Vector3(0, 1.0, 0)
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_:
			return { &"err": "Unknown preset: " + preset }

	return {}


func _info(args: Dictionary) -> Dictionary:
	var node: Node = _find_particles(args[&"node_path"])
	if not node:
		return { &"err": "GPUParticles not found" }

	var info: Dictionary = {
		&"type": node.get_class(),
		&"amount": node.amount,
		&"lifetime": node.lifetime,
		&"one_shot": node.one_shot,
		&"emitting": node.emitting,
		&"explosiveness": node.explosiveness,
	}

	var mat: ParticleProcessMaterial = node.process_material as ParticleProcessMaterial
	if mat:
		info[&"material"] = {
			&"direction": { &"x": mat.direction.x, &"y": mat.direction.y, &"z": mat.direction.z },
			&"spread": mat.spread,
			&"gravity": { &"x": mat.gravity.x, &"y": mat.gravity.y, &"z": mat.gravity.z },
			&"initial_velocity_min": mat.initial_velocity_min,
			&"initial_velocity_max": mat.initial_velocity_max,
			&"scale_min": mat.scale_min,
			&"scale_max": mat.scale_max,
		}

	return info

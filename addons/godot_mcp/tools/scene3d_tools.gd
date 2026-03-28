@tool
extends RefCounted

class_name Scene3DTools
## 3D scene setup tools for MCP.
## Handles: scene_3d_edit (add_mesh, setup_lighting, set_material, setup_environment, setup_camera, add_gridmap)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func s3d(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		"mesh":
			return _add_mesh(args)
		"lighting":
			return _setup_lighting(args)
		"material":
			return _set_material(args)
		"environment":
			return _setup_environment(args)
		"camera":
			return _setup_camera(args)
		"gridmap":
			return _add_gridmap(args)
		_:
			return { &"err": "Unknown scene_3d_edit action: " + action }


# =============================================================================
# Helpers
# =============================================================================

func _get_undo_redo() -> EditorUndoRedoManager:
	return _editor_plugin.get_undo_redo()


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


func _parse_vec3(args: Dictionary, key: String, default: Vector3) -> Vector3:
	if not args.has(key):
		return default
	var val: Variant = args[key]
	if val is Dictionary:
		return Vector3(float(val.get(&"x", default.x)), float(val.get(&"y", default.y)), float(val.get(&"z", default.z)))
	return default


func _parse_color(args: Dictionary, key: String, default: Color) -> Color:
	if not args.has(key):
		return default
	var val: Variant = args[key]
	if val is String:
		return Color(val)
	if val is Dictionary:
		return Color(float(val.get(&"r", default.r)), float(val.get(&"g", default.g)), float(val.get(&"b", default.b)), float(val.get(&"a", default.a)))
	return default


func _add_child_undo(node: Node, parent: Node, root: Node, action_name: String) -> void:
	var ur: EditorUndoRedoManager = _get_undo_redo()
	ur.create_action(action_name)
	ur.add_do_method(parent, &"add_child", node)
	ur.add_do_method(node, &"set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, &"remove_child", node)
	ur.commit_action()


# =============================================================================
# add_mesh
# =============================================================================
func _add_mesh(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var mesh_type: String = args.get(&"mesh_type", "")
	var mesh_file: String = args.get(&"mesh_file", "")
	if mesh_type.is_empty() and mesh_file.is_empty():
		return { &"err": "Need 'mesh_type' or 'mesh_file'" }

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = args.get(&"name", "MeshInstance3D")

	if not mesh_file.is_empty():
		if not ResourceLoader.exists(mesh_file):
			mesh_inst.queue_free()
			return { &"err": "Mesh file not found: " + mesh_file }
		var loaded: Resource = load(mesh_file)
		if loaded is Mesh:
			mesh_inst.mesh = loaded as Mesh
		elif loaded is PackedScene:
			var inst: Node = (loaded as PackedScene).instantiate()
			var found_mesh: Mesh = null
			var queue: Array[Node] = [inst]
			while not queue.is_empty():
				var n: Node = queue.pop_front()
				if n is MeshInstance3D and (n as MeshInstance3D).mesh:
					found_mesh = (n as MeshInstance3D).mesh
					break
				for child: Node in n.get_children():
					queue.append(child)
			inst.queue_free()
			if not found_mesh:
				mesh_inst.queue_free()
				return { &"err": "No mesh found in: " + mesh_file }
			mesh_inst.mesh = found_mesh
		else:
			mesh_inst.queue_free()
			return { &"err": "Not a Mesh or PackedScene: " + mesh_file }
	else:
		var mesh_classes: Dictionary = {
			"BoxMesh": BoxMesh, "SphereMesh": SphereMesh, "CylinderMesh": CylinderMesh,
			"CapsuleMesh": CapsuleMesh, "PlaneMesh": PlaneMesh, "PrismMesh": PrismMesh,
			"TorusMesh": TorusMesh, "QuadMesh": QuadMesh,
		}
		if not mesh_classes.has(mesh_type):
			mesh_inst.queue_free()
			return { &"err": "Unknown mesh_type: " + mesh_type }
		var mesh_res: Mesh = mesh_classes[mesh_type].new()
		var mesh_props: Dictionary = args.get(&"mesh_properties", {})
		for prop_name: String in mesh_props:
			if prop_name in mesh_res:
				mesh_res.set(prop_name, mesh_props[prop_name])
		mesh_inst.mesh = mesh_res

	mesh_inst.position = _parse_vec3(args, &"position", Vector3.ZERO)
	if args.has(&"rotation"):
		mesh_inst.rotation_degrees = _parse_vec3(args, &"rotation", Vector3.ZERO)

	_add_child_undo(mesh_inst, parent, root, "MCP: Add MeshInstance3D")
	return { &"node_path": str(root.get_path_to(mesh_inst)) }


# =============================================================================
# setup_lighting
# =============================================================================
func _setup_lighting(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var light_type: String = args.get(&"light_type", "")
	var preset: String = args.get(&"preset", "")

	if not preset.is_empty():
		match preset:
			"sun": light_type = "DirectionalLight3D"
			"indoor": light_type = "OmniLight3D"
			"dramatic": light_type = "SpotLight3D"
			_:
				return { &"err": "Unknown preset: " + preset }

	if light_type.is_empty():
		return { &"err": "Need 'light_type' or 'preset'" }

	var light: Light3D
	match light_type:
		"DirectionalLight3D": light = DirectionalLight3D.new()
		"OmniLight3D": light = OmniLight3D.new()
		"SpotLight3D": light = SpotLight3D.new()
		_:
			return { &"err": "Unknown light_type: " + light_type }

	light.name = args.get(&"name", light_type)
	light.light_color = _parse_color(args, &"color", Color.WHITE)
	light.light_energy = float(args.get(&"energy", 1.0))
	light.shadow_enabled = args.get(&"shadows", false)

	if light is OmniLight3D:
		(light as OmniLight3D).omni_range = float(args.get(&"range", 5.0))
	elif light is SpotLight3D:
		(light as SpotLight3D).spot_range = float(args.get(&"range", 5.0))
		(light as SpotLight3D).spot_angle = float(args.get(&"spot_angle", 45.0))

	# Preset defaults
	if preset == "sun":
		light.shadow_enabled = args.get(&"shadows", true)
		light.rotation_degrees = _parse_vec3(args, &"rotation", Vector3(-45, -30, 0))
	elif preset == "indoor":
		light.light_energy = float(args.get(&"energy", 0.8))
		light.light_color = _parse_color(args, &"color", Color(1.0, 0.95, 0.85))
		if light is OmniLight3D:
			(light as OmniLight3D).omni_range = float(args.get(&"range", 8.0))
	elif preset == "dramatic":
		light.light_energy = float(args.get(&"energy", 2.0))
		light.shadow_enabled = args.get(&"shadows", true)

	light.position = _parse_vec3(args, &"position", Vector3.ZERO)
	if args.has(&"rotation") and preset != "sun":
		light.rotation_degrees = _parse_vec3(args, &"rotation", Vector3.ZERO)

	_add_child_undo(light, parent, root, "MCP: Add " + light_type)
	return { &"node_path": str(root.get_path_to(light)) }


# =============================================================================
# set_material
# =============================================================================
func _set_material(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args.get(&"node_path", ""))
	if not node or not node is MeshInstance3D:
		return { &"err": "MeshInstance3D not found" }

	var mesh_inst: MeshInstance3D = node as MeshInstance3D
	var surface_index: int = int(args.get(&"surface_index", 0))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _parse_color(args, &"albedo_color", Color.WHITE)
	mat.metallic = float(args.get(&"metallic", 0.0))
	mat.roughness = float(args.get(&"roughness", 1.0))

	if args.has(&"albedo_texture"):
		if ResourceLoader.exists(args[&"albedo_texture"]):
			mat.albedo_texture = load(args[&"albedo_texture"]) as Texture2D

	if args.has(&"normal_texture"):
		mat.normal_enabled = true
		if ResourceLoader.exists(args[&"normal_texture"]):
			mat.normal_texture = load(args[&"normal_texture"]) as Texture2D

	if args.has(&"emission") or args.has(&"emission_color"):
		mat.emission_enabled = true
		mat.emission = _parse_color(args, &"emission", _parse_color(args, &"emission_color", Color.BLACK))

	var old_mat: Material = mesh_inst.get_surface_override_material(surface_index)
	var ur: EditorUndoRedoManager = _get_undo_redo()
	ur.create_action("MCP: Set material")
	ur.add_do_method(mesh_inst, &"set_surface_override_material", surface_index, mat)
	ur.add_undo_method(mesh_inst, &"set_surface_override_material", surface_index, old_mat)
	ur.commit_action()

	return {}


# =============================================================================
# setup_environment
# =============================================================================
func _setup_environment(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", args.get(&"node_path", ".")))
	if not parent:
		return { &"err": "Parent not found" }

	var world_env: WorldEnvironment = null
	var is_existing: bool = false

	# Check for existing
	if args.has(&"node_path"):
		var existing: Node = _find_node(args[&"node_path"])
		if existing is WorldEnvironment:
			world_env = existing as WorldEnvironment
			is_existing = true

	if not world_env:
		world_env = WorldEnvironment.new()
		world_env.name = args.get(&"name", "WorldEnvironment")

	var env: Environment = world_env.environment if world_env.environment else Environment.new()

	# Background
	var bg_mode: String = args.get(&"background_mode", "sky")
	match bg_mode:
		"sky": env.background_mode = Environment.BG_SKY
		"color":
			env.background_mode = Environment.BG_COLOR
			env.background_color = _parse_color(args, &"background_color", Color(0.3, 0.3, 0.3))
		"canvas": env.background_mode = Environment.BG_CANVAS
		"clear_color": env.background_mode = Environment.BG_CLEAR_COLOR

	# Procedural sky
	if args.has(&"sky") and args[&"sky"] is Dictionary:
		var sky_params: Dictionary = args[&"sky"]
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = _parse_color(sky_params, &"sky_top_color", Color(0.385, 0.454, 0.55))
		sky_mat.sky_horizon_color = _parse_color(sky_params, &"sky_horizon_color", Color(0.646, 0.654, 0.67))
		sky_mat.ground_bottom_color = _parse_color(sky_params, &"ground_bottom_color", Color(0.2, 0.169, 0.133))
		sky_mat.ground_horizon_color = _parse_color(sky_params, &"ground_horizon_color", Color(0.646, 0.654, 0.67))
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY

	# Effects
	if args.has(&"fog_enabled"):
		env.fog_enabled = bool(args[&"fog_enabled"])
	if args.has(&"glow_enabled"):
		env.glow_enabled = bool(args[&"glow_enabled"])
	if args.has(&"ssao_enabled"):
		env.ssao_enabled = bool(args[&"ssao_enabled"])

	world_env.environment = env

	if not is_existing:
		_add_child_undo(world_env, parent, root, "MCP: Add WorldEnvironment")

	return { &"node_path": str(root.get_path_to(world_env)) }


# =============================================================================
# setup_camera
# =============================================================================
func _setup_camera(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var camera: Camera3D = null
	var is_existing: bool = false

	if args.has(&"node_path"):
		var existing: Node = _find_node(args[&"node_path"])
		if existing is Camera3D:
			camera = existing as Camera3D
			is_existing = true

	if not camera:
		camera = Camera3D.new()
		camera.name = args.get(&"name", "Camera3D")

	var projection: String = args.get(&"projection", "")
	if not projection.is_empty():
		match projection:
			"perspective": camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			"orthogonal", "orthographic": camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			"frustum": camera.projection = Camera3D.PROJECTION_FRUSTUM

	if args.has(&"fov"): camera.fov = float(args[&"fov"])
	if args.has(&"near"): camera.near = float(args[&"near"])
	if args.has(&"far"): camera.far = float(args[&"far"])

	camera.position = _parse_vec3(args, &"position", camera.position if is_existing else Vector3(0, 1, 3))
	if args.has(&"rotation"):
		camera.rotation_degrees = _parse_vec3(args, &"rotation", camera.rotation_degrees)
	if args.has(&"look_at"):
		camera.look_at(_parse_vec3(args, &"look_at", Vector3.ZERO))

	if not is_existing:
		_add_child_undo(camera, parent, root, "MCP: Add Camera3D")

	return { &"node_path": str(root.get_path_to(camera)) }


# =============================================================================
# add_gridmap
# =============================================================================
func _add_gridmap(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args.get(&"parent_path", "."))
	if not parent:
		return { &"err": "Parent not found" }

	var gridmap := GridMap.new()
	gridmap.name = args.get(&"name", "GridMap")

	if args.has(&"mesh_library_path"):
		var lib_path: String = args[&"mesh_library_path"]
		if not ResourceLoader.exists(lib_path):
			gridmap.queue_free()
			return { &"err": "MeshLibrary not found: " + lib_path }
		var lib: Resource = load(lib_path)
		if lib is MeshLibrary:
			gridmap.mesh_library = lib as MeshLibrary
		else:
			gridmap.queue_free()
			return { &"err": "Not a MeshLibrary: " + lib_path }

	if args.has(&"cell_size"):
		gridmap.cell_size = _parse_vec3(args, &"cell_size", Vector3(2, 2, 2))

	gridmap.position = _parse_vec3(args, &"position", Vector3.ZERO)

	_add_child_undo(gridmap, parent, root, "MCP: Add GridMap")

	for cell: Variant in args.get(&"cells", []):
		if cell is Dictionary:
			gridmap.set_cell_item(Vector3i(int(cell[&"x"]), int(cell[&"y"]), int(cell[&"z"])), int(cell[&"item"]), int(cell.get(&"orientation", 0)))

	return { &"node_path": str(root.get_path_to(gridmap)) }

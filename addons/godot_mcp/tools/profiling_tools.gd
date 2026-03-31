@tool
extends RefCounted

class_name ProfilingTools
## Performance monitoring tools for MCP.
## Handles: profiling (monitors, summary)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func perf(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"monitors":
			return _monitors(args)
		&"summary":
			return _summary()
		_:
			return { &"err": "Unknown profiling action: " + action }


func _monitors(args: Dictionary) -> Dictionary:
	var monitors: Dictionary = {
		&"fps": Performance.get_monitor(Performance.TIME_FPS),
		&"frame_time_msec": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		&"physics_frame_time_msec": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		&"navigation_process_msec": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		&"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		&"memory_static_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		&"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		&"object_resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		&"object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		&"object_orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		&"render_total_objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		&"render_total_primitives_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		&"render_total_draw_calls_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		&"render_video_mem_used": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		&"physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		&"physics_2d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		&"physics_2d_island_count": Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
		&"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		&"physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		&"physics_3d_island_count": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		&"navigation_active_maps": Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS),
		&"navigation_region_count": Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT),
		&"navigation_agent_count": Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT),
	}

	if args.has(&"category"):
		var filtered: Dictionary = {}
		for key: String in monitors:
			if key.begins_with(args[&"category"]):
				filtered[key] = monitors[key]
		return { &"mon": filtered }

	return { &"mon": monitors }


func _summary() -> Dictionary:
	return {
		&"fps": Performance.get_monitor(Performance.TIME_FPS),
		&"frame_time_msec": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		&"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		&"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		&"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		&"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		&"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		&"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0),
	}

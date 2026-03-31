@tool
extends RefCounted

class_name AnalysisTools
## Project analysis tools for MCP.
## Handles: analyze_project (unused_resources, signal_flow, scene_complexity,
##   script_references, circular_deps, statistics)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func analyze(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"unused":
			return _unused_resources(args)
		&"signals":
			return _signal_flow()
		&"complexity":
			return _scene_complexity(args)
		&"references":
			return _script_references(args)
		&"circular":
			return _circular_deps(args)
		&"stats":
			return _statistics(args)
		&"live_signals":
			return _live_signal_connections(args)
		_:
			return {&"err": "Unknown analyze_project action: " + action}


func _get_edited_root() -> Node:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_editor_interface().get_edited_scene_root()


# =============================================================================
# unused_resources
# =============================================================================
func _unused_resources(args: Dictionary) -> Dictionary:
	var path: String = args.get(&"path", "res://")
	var include_addons: bool = args.get(&"include_addons", false)

	var resource_exts: Array = ["tres", "png", "jpg", "svg", "wav", "ogg", "mp3", "ttf", "gdshader", "theme"]
	var all_resources: Array = []
	_collect_files_by_ext(path, resource_exts, all_resources, include_addons)

	var ref_exts: Array = ["tscn", "gd", "tres", "cfg", "godot"]
	var ref_files: Array = []
	_collect_files_by_ext(path, ref_exts, ref_files, include_addons)

	var referenced: Dictionary = {}
	for ref_file: Variant in ref_files:
		var content: String = _read_file_text(ref_file)
		var idx: int = 0
		while idx < content.length():
			var found: int = content.find("res://", idx)
			if found == -1:
				break
			var end: int = found + 6
			while end < content.length():
				var c: String = content[end]
				if c in ['"', "'", ' ', '\n', '\r', ')', ']', '}']:
					break
				end += 1
			referenced[content.substr(found, end - found)] = true
			idx = end

	var unused: Array = []
	for res_path: Variant in all_resources:
		if not referenced.has(res_path):
			unused.append(res_path)

	return { &"unused": unused }


# =============================================================================
# signal_flow
# =============================================================================
func _signal_flow() -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }

	var nodes_data: Array[Dictionary] = []
	_collect_signals(root, root, nodes_data)
	return { &"nodes": nodes_data }


func _collect_signals(node: Node, root: Node, out: Array[Dictionary]) -> void:
	var node_path: String = str(root.get_path_to(node))
	var emitted: Array[Dictionary] = []

	for sig: Dictionary in node.get_signal_list():
		var sig_name: String = sig[&"name"]
		var connections: Array = node.get_signal_connection_list(sig_name)
		if connections.size() > 0:
			var targets: Array[Dictionary] = []
			for conn: Dictionary in connections:
				var callable: Callable = conn[&"callable"]
				var target: Node = callable.get_object() as Node
				targets.append({
					&"target": str(root.get_path_to(target)) if target else "",
					&"method": callable.get_method(),
				})
			emitted.append({ &"signal": sig_name, &"targets": targets })

	if emitted.size() > 0:
		out.append({ &"path": node_path, &"type": node.get_class(), &"signals": emitted })

	for child: Node in node.get_children():
		_collect_signals(child, root, out)


# =============================================================================
# scene_complexity
# =============================================================================
func _scene_complexity(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }

	var total: int = _count_nodes(root)
	var max_depth: int = _get_depth(root, 0)
	var types: Dictionary = {}
	var scripts: Array[Dictionary] = []
	_walk_complexity(root, root, types, scripts)

	var issues: Array[String] = []
	if total > 1000:
		issues.append("Over 1000 nodes — consider splitting into sub-scenes")
	if max_depth > 15:
		issues.append("Nesting depth > 15 — deep hierarchies are hard to maintain")

	return {
		&"total_nodes": total, &"max_depth": max_depth,
		&"nodes_by_type": types, &"scripts": scripts, &"issues": issues,
	}


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


func _get_depth(node: Node, depth: int) -> int:
	var max_d: int = depth
	for child: Node in node.get_children():
		var d: int = _get_depth(child, depth + 1)
		if d > max_d:
			max_d = d
	return max_d


func _walk_complexity(node: Node, root: Node, types: Dictionary, scripts: Array[Dictionary]) -> void:
	var type_name: String = node.get_class()
	types[type_name] = types.get(type_name, 0) + 1
	if node.get_script():
		var script: Script = node.get_script()
		if not script.resource_path.is_empty():
			scripts.append({ &"node": str(root.get_path_to(node)), &"script": script.resource_path })
	for child: Node in node.get_children():
		_walk_complexity(child, root, types, scripts)


# =============================================================================
# script_references
# =============================================================================
func _script_references(args: Dictionary) -> Dictionary:
	var query: String = args[&"query"]
	var path: String = args.get(&"path", "res://")
	var include_addons: bool = args.get(&"include_addons", false)

	var search_files: Array = []
	_collect_files_by_ext(path, ["tscn", "gd", "tres", "cfg"], search_files, include_addons)

	var references: Array[Dictionary] = []
	for file_path: Variant in search_files:
		var content: String = _read_file_text(file_path)
		if content.is_empty():
			continue
		var lines: PackedStringArray = content.split("\n")
		for i: int in lines.size():
			if lines[i].contains(query):
				references.append({ &"file": file_path, &"line": i + 1, &"content": lines[i].strip_edges() })

	return { &"refs": references }


# =============================================================================
# circular_deps
# =============================================================================
func _circular_deps(args: Dictionary) -> Dictionary:
	var path: String = args.get(&"path", "res://")
	var include_addons: bool = args.get(&"include_addons", false)

	var tscn_files: Array = []
	_collect_files_by_ext(path, ["tscn"], tscn_files, include_addons)

	var dep_graph: Dictionary = {}
	for tscn_path: Variant in tscn_files:
		var content: String = _read_file_text(tscn_path)
		var deps: Array = []
		for line: String in content.split("\n"):
			if line.begins_with("[ext_resource") and ".tscn" in line:
				var ps: int = line.find('path="')
				if ps == -1:
					continue
				ps += 6
				var pe: int = line.find('"', ps)
				if pe == -1:
					continue
				var ref: String = line.substr(ps, pe - ps)
				if ref.ends_with(".tscn"):
					deps.append(ref)
		dep_graph[tscn_path] = deps

	var cycles: Array = []
	var visited: Dictionary = {}
	for scene: String in dep_graph:
		visited[scene] = "unvisited"
	for scene: String in dep_graph:
		if visited[scene] == "unvisited":
			_dfs(scene, dep_graph, visited, [], cycles)

	return { &"cycles": cycles }


func _dfs(node: String, graph: Dictionary, visited: Dictionary, stack: Array, cycles: Array) -> void:
	visited[node] = "visiting"
	stack.append(node)
	if graph.has(node):
		for dep: Variant in graph[node]:
			if not visited.has(dep):
				continue
			if visited[dep] == "visiting":
				cycles.append(stack.slice(stack.find(dep)) + [dep])
			elif visited[dep] == "unvisited":
				_dfs(dep, graph, visited, stack, cycles)
	stack.pop_back()
	visited[node] = "visited"


# =============================================================================
# statistics
# =============================================================================
func _statistics(args: Dictionary) -> Dictionary:
	var path: String = args.get(&"path", "res://")
	var include_addons: bool = args.get(&"include_addons", false)

	var counts: Dictionary = {}
	_walk_stats(path, include_addons, counts)

	# Extract internal counters
	var sl: int = int(counts.get(&"_sl", 0)); counts.erase(&"_sl")
	var sc: int = int(counts.get(&"_sc", 0)); counts.erase(&"_sc")
	var rc: int = int(counts.get(&"_rc", 0)); counts.erase(&"_rc")
	counts.erase(&"_tf")

	var autoloads: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("autoload/"):
			autoloads[pname.substr(9)] = str(ProjectSettings.get_setting(pname))

	return {
		&"file_counts": counts,
		&"script_lines": sl, &"scene_count": sc,
		&"resource_count": rc, &"autoloads": autoloads,
	}


func _walk_stats(path: String, include_addons: bool, counts: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full: String = path.path_join(fname)
			if dir.current_is_dir():
				if fname != "addons" or include_addons:
					_walk_stats(full, include_addons, counts)
			else:
				var ext: String = fname.get_extension().to_lower()
				counts[ext] = counts.get(ext, 0) + 1
				counts[&"_tf"] = counts.get(&"_tf", 0) + 1
				if ext == "gd":
					var content: String = _read_file_text(full)
					counts[&"_sl"] = counts.get(&"_sl", 0) + (content.count("\n") + 1 if not content.is_empty() else 0)
				if ext == "tscn":
					counts[&"_sc"] = counts.get(&"_sc", 0) + 1
				if ext in ["tres", "material", "theme"]:
					counts[&"_rc"] = counts.get(&"_rc", 0) + 1
		fname = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# Shared helpers
# =============================================================================
func _collect_files_by_ext(path: String, extensions: Array, out: Array, include_addons: bool) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full: String = path.path_join(fname)
			if dir.current_is_dir():
				if fname != "addons" or include_addons:
					_collect_files_by_ext(full, extensions, out, include_addons)
			else:
				if fname.get_extension().to_lower() in extensions:
					out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()


func _read_file_text(file_path: Variant) -> String:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# =============================================================================
# live_signals — signal connections in the live edited scene tree
# =============================================================================
func _live_signal_connections(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if root == null:
		return {&"err": "No scene open"}
	var signal_filter: String = ""
	if args.has(&"signal_name"):
		signal_filter = args[&"signal_name"]
	var connections: Array[Dictionary] = []
	_collect_live_signals(root, signal_filter, connections)
	return {&"connections": connections}


func _collect_live_signals(node: Node, signal_filter: String, connections: Array[Dictionary]) -> void:
	for sig_info: Dictionary in node.get_signal_list():
		var sig_name: String = sig_info[&"name"]
		if not signal_filter.is_empty() and not sig_name.contains(signal_filter):
			continue
		for conn: Dictionary in node.get_signal_connection_list(sig_name):
			var target_obj: Object = conn[&"callable"].get_object()
			var target_path: String = str(target_obj.get_path()) if target_obj is Node else target_obj.get_class()
			connections.append({
				&"source": str(node.get_path()),
				&"signal": sig_name,
				&"target": target_path,
				&"method": conn[&"callable"].get_method(),
			})
	for child: Node in node.get_children():
		_collect_live_signals(child, signal_filter, connections)

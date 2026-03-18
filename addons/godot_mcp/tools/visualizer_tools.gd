@tool
extends RefCounted

class_name VisualizerTools
## Crawls a Godot project and parses all GDScript files to build a project map.

const _EDGE_EXTENDS := "extends"
const _EDGE_PRELOAD := "preload"
const _EDGE_SIGNAL := "signal"

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils

# Cached RegEx patterns for _parse_script (compiled once, reused per file)
var _re_desc: RegEx
var _re_extends: RegEx
var _re_class_name: RegEx
var _re_var: RegEx
var _re_func: RegEx
var _re_signal: RegEx
var _re_preload: RegEx
var _re_connect_obj: RegEx
var _re_connect_direct: RegEx

# Cached RegEx patterns for _parse_scene
var _re_ext_resource: RegEx

var _re_node: RegEx
var _re_node_instance: RegEx


func _init() -> void:
	_re_desc = RegEx.create_from_string("^##\\s*@desc:\\s*(.+)")
	_re_extends = RegEx.create_from_string("^extends\\s+(\\w+)")
	_re_class_name = RegEx.create_from_string("^class_name\\s+(\\w+)")
	_re_var = RegEx.create_from_string("^(@export(?:\\([^)]*\\))?\\s+)?(@onready\\s+)?var\\s+(\\w+)\\s*(?::\\s*(\\w+))?(?:\\s*=\\s*(.+))?")
	_re_func = RegEx.create_from_string("^func\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*(?:->\\s*(\\w+))?")
	_re_signal = RegEx.create_from_string("^signal\\s+(\\w+)(?:\\(([^)]*)\\))?")
	_re_preload = RegEx.create_from_string("(?:preload|load)\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
	_re_connect_obj = RegEx.create_from_string("(\\w+)\\.(\\w+)\\.connect\\s*\\(")
	_re_connect_direct = RegEx.create_from_string("^\\s*(\\w+)\\.connect\\s*\\(")

	_re_ext_resource = RegEx.create_from_string('\\[ext_resource.*path="([^"]+)".*type="([^"]+)"')

	_re_node = RegEx.create_from_string('\\[node name="([^"]+)".*type="([^"]+)"')
	_re_node_instance = RegEx.create_from_string('\\[node name="([^"]+)".*instance=ExtResource\\("([^"]+)"\\)')



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


## Crawl the entire project and build a structural map of all scripts.
func map_project(args: Dictionary) -> Dictionary:
	var root_path: String = _utils.validate_res_path(str(args.get(&"root", "res://")))
	var include_addons: bool = bool(args.get(&"include_addons", false))

	if root_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	# Collect all .gd files
	var script_paths: PackedStringArray = []
	_collect_scripts(root_path, script_paths, include_addons)

	if script_paths.is_empty():
		return { &"ok": false, &"error": "No GDScript files found in " + root_path }

	# Parse each script
	var nodes: Array[Dictionary] = []
	var class_map: Dictionary = { } # class_name -> path

	for path: String in script_paths:
		var info: Dictionary = _parse_script(path)
		nodes.append(info)
		if info[&"class_name"] != "":
			class_map[info[&"class_name"]] = path

	# Build edges
	var edges: Array[Dictionary] = []
	for node: Dictionary in nodes:
		var from_path: String = node[&"path"]

		# extends relationship (resolve class_name to path)
		var extends_class: String = node[&"extends"]
		if extends_class in class_map:
			edges.append({ &"from": from_path, &"to": class_map[extends_class], &"type": _EDGE_EXTENDS })

		# preload/load references
		for ref: String in node[&"preloads"]:
			if ref.ends_with(".gd"):
				edges.append({ &"from": from_path, &"to": ref, &"type": _EDGE_PRELOAD })

		# signal connections
		for conn: Dictionary in node[&"connections"]:
			var target: String = conn[&"target"]
			if target in class_map:
				edges.append({ &"from": from_path, &"to": class_map[target], &"type": _EDGE_SIGNAL, &"signal_name": conn[&"signal"] })

	return {
		&"ok": true,
		&"project_map": {
			&"nodes": nodes,
			&"edges": edges,
			&"total_scripts": nodes.size(),
			&"total_connections": edges.size(),
		},
	}


const MAX_TRAVERSAL_DEPTH := 20


## Recursively collect all [code].gd[/code] files.
func _collect_scripts(path: String, results: PackedStringArray, include_addons: bool, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var full_path: String = path.path_join(name)

		if dir.current_is_dir():
			if name == "addons" and not include_addons:
				name = dir.get_next()
				continue
			_collect_scripts(full_path, results, include_addons, depth + 1)
		elif name.ends_with(".gd"):
			results.append(full_path)

		name = dir.get_next()
	dir.list_dir_end()


## Parse a GDScript file and extract its structure.
func _parse_script(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			&"path": path,
			&"error": "Cannot open file",
			&"class_name": "",
			&"extends": "",
			&"preloads": [],
			&"connections": [],
		}

	var content: String = file.get_as_text()
	file.close()

	var lines: PackedStringArray = content.split("\n")
	var line_count: int = lines.size()

	var description: String = ""
	var extends_class: String = ""
	var class_name_str: String = ""
	var variables: Array[Dictionary] = []
	var functions: Array[Dictionary] = []
	var signals_list: Array[Dictionary] = []
	var preloads: Array[String] = []
	var connections: Array[Dictionary] = []

	# Map of variable names to their types (for resolving signal connections)
	var var_type_map: Dictionary = { }

	# First pass: extract metadata and find function boundaries
	var func_starts: Array[Dictionary] = [] # [{line_idx, name}]

	for i: int in range(line_count):
		var line: String = lines[i]
		if line.is_empty():
			continue
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		var is_indented: bool = line.unicode_at(0) == 9 or line.unicode_at(0) == 32

		# Top-level declarations only apply to non-indented lines
		if not is_indented:
			# Description tag (check first 15 lines)
			if i < 15 and description.is_empty():
				var m: RegExMatch = _re_desc.search(stripped)
				if m:
					description = m.get_string(1)
					continue

			# extends
			if extends_class.is_empty():
				var m: RegExMatch = _re_extends.search(stripped)
				if m:
					extends_class = m.get_string(1)
					continue

			# class_name
			if class_name_str.is_empty():
				var m: RegExMatch = _re_class_name.search(stripped)
				if m:
					class_name_str = m.get_string(1)
					continue

			# Variables
			var m_var: RegExMatch = _re_var.search(stripped)
			if m_var:
				var exported: bool = m_var.get_string(1) != ""
				var onready: bool = m_var.get_string(2) != ""
				var var_name: String = m_var.get_string(3)
				var var_type: String = m_var.get_string(4)
				var default_val: String = m_var.get_string(5).strip_edges()

				if var_type.is_empty() and not default_val.is_empty():
					var_type = _infer_type(default_val)

				if not var_type.is_empty():
					var_type_map[var_name] = var_type

				variables.append(
					{
						&"name": var_name,
						&"type": var_type,
						&"exported": exported,
						&"onready": onready,
						&"default": default_val,
					},
				)

			# Functions
			var m_func: RegExMatch = _re_func.search(stripped)
			if m_func:
				var func_name: String = m_func.get_string(1)
				var return_type: String = m_func.get_string(3)
				func_starts.append({ &"line_idx": i, &"name": func_name })
				functions.append(
					{
						&"name": func_name,
						&"params": m_func.get_string(2).strip_edges(),
						&"return_type": return_type,
						&"line": i + 1,
						&"body": "", # filled in second pass
					},
				)

			# Signals
			var m_sig: RegExMatch = _re_signal.search(stripped)
			if m_sig:
				signals_list.append(
					{
						&"name": m_sig.get_string(1),
						&"params": m_sig.get_string(2).strip_edges() if m_sig.get_string(2) else "",
					},
				)

		# Preload/load and connections can appear anywhere (including inside functions)
		if stripped.contains("load"):
			var m_preload: RegExMatch = _re_preload.search(stripped)
			if m_preload:
				preloads.append(m_preload.get_string(1))

		# Signal connections (Godot 4 style)
		if stripped.find(".connect") != -1:
			# Pattern: obj.signal.connect(...) - e.g. wave_manager.wave_started.connect(...)
			var m_conn_obj: RegExMatch = _re_connect_obj.search(stripped)
			if m_conn_obj:
				var obj_name: String = m_conn_obj.get_string(1)
				var signal_name: String = m_conn_obj.get_string(2)
				var target_type: String = var_type_map.get(obj_name, "")
				connections.append(
					{
						&"object": obj_name,
						&"signal": signal_name,
						&"target": target_type,
						&"line": i + 1,
					},
				)
			else:
				# Pattern: signal.connect(...) - e.g. body_entered.connect(...)
				var m_conn_direct: RegExMatch = _re_connect_direct.search(stripped)
				if m_conn_direct:
					connections.append(
						{
							&"signal": m_conn_direct.get_string(1),
							&"target": extends_class,
							&"line": i + 1,
						},
					)

	# Second pass: extract function bodies
	for fi: int in range(func_starts.size()):
		var start_idx: int = func_starts[fi][&"line_idx"]
		var end_idx: int
		if fi + 1 < func_starts.size():
			end_idx = func_starts[fi + 1][&"line_idx"]
		else:
			end_idx = line_count

		# Find actual end: look backwards from next func to skip blank lines
		while end_idx > start_idx + 1 and lines[end_idx - 1].strip_edges().is_empty():
			end_idx -= 1

		# Also check for top-level declarations (var, signal, @export, class_name, etc.)
		# that would end the function body
		for check_idx: int in range(start_idx + 1, end_idx):
			var check_line: String = lines[check_idx]
			# If line is not indented and not empty and not a comment, it's not part of the function
			if not check_line.is_empty() and not check_line.begins_with("\t") and not check_line.begins_with(" ") and not check_line.begins_with("#"):
				end_idx = check_idx
				break

		var body: String = "\n".join(lines.slice(start_idx, end_idx))
		# Cap body size to avoid huge payloads
		if body.length() > 3000:
			body = body.substr(0, 3000) + "\n# ... (truncated)"

		functions[fi][&"body"] = body
		functions[fi][&"body_lines"] = end_idx - start_idx

	# Determine folder
	var folder: String = path.get_base_dir()
	var filename: String = path.get_file()

	return {
		&"path": path,
		&"filename": filename,
		&"folder": folder,
		&"class_name": class_name_str,
		&"extends": extends_class,
		&"description": description,
		&"line_count": line_count,
		&"variables": variables,
		&"functions": functions,
		&"signals": signals_list,
		&"preloads": preloads,
		&"connections": connections,
	}


## Try to infer GDScript type from a default value.
func _infer_type(default_val: String) -> String:
	if default_val == "true" or default_val == "false":
		return "bool"
	if default_val.is_valid_int():
		return "int"
	if default_val.is_valid_float():
		return "float"
	if default_val.begins_with("\"") or default_val.begins_with("'"):
		return "String"
	if default_val.begins_with("Vector2"):
		return "Vector2"
	if default_val.begins_with("Vector3"):
		return "Vector3"
	if default_val.begins_with("Color"):
		return "Color"
	if default_val.begins_with("["):
		return "Array"
	if default_val.begins_with("{"):
		return "Dictionary"
	if default_val == "null":
		return "Variant"
	if default_val.ends_with(".new()"):
		return default_val.replace(".new()", "")
	return ""


## Crawl the project and build a map of all scenes.
func map_scenes(args: Dictionary) -> Dictionary:
	var root_path: String = _utils.validate_res_path(str(args.get(&"root", "res://")))
	var include_addons: bool = bool(args.get(&"include_addons", false))

	if root_path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	# Collect all .tscn files
	var scene_paths: PackedStringArray = []
	_collect_scenes(root_path, scene_paths, include_addons)

	if scene_paths.is_empty():
		return { &"ok": true, &"scene_map": { &"scenes": [], &"total_scenes": 0 } }

	# Parse each scene
	var scenes: Array[Dictionary] = []
	for path: String in scene_paths:
		var info: Dictionary = _parse_scene(path)
		scenes.append(info)

	# Build edges between scenes (instantiation, preloads)
	var edges: Array[Dictionary] = []
	for scene: Dictionary in scenes:
		var from_path: String = scene[&"path"]
		for instance: String in scene[&"instances"]:
			edges.append({ &"from": from_path, &"to": instance, &"type": "instance" })

	return {
		&"ok": true,
		&"scene_map": {
			&"scenes": scenes,
			&"edges": edges,
			&"total_scenes": scenes.size(),
		},
	}


## Recursively collect all [code].tscn[/code] files.
func _collect_scenes(path: String, results: PackedStringArray, include_addons: bool, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var d_name: String = dir.get_next()
	while d_name != "":
		if d_name.begins_with("."):
			d_name = dir.get_next()
			continue

		var full_path: String = path.path_join(d_name)

		if dir.current_is_dir():
			if d_name == "addons" and not include_addons:
				d_name = dir.get_next()
				continue
			_collect_scenes(full_path, results, include_addons, depth + 1)
		elif d_name.ends_with(".tscn"):
			results.append(full_path)

		d_name = dir.get_next()
	dir.list_dir_end()


## Parse a scene file and extract its structure.
func _parse_scene(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { &"path": path, &"error": "Cannot open file", &"instances": [] }

	var content: String = file.get_as_text()
	file.close()

	var scene_name: String = path.get_file().replace(".tscn", "")
	var root_type: String = ""
	var nodes: Array[Dictionary] = []
	var instances: Array[String] = []
	var scripts: Array[String] = []

	# Parse .tscn format
	var lines: PackedStringArray = content.split("\n")
	for line: String in lines:
		# External resources
		var m_ext: RegExMatch = _re_ext_resource.search(line)
		if m_ext:
			var res_path: String = m_ext.get_string(1)
			var res_type: String = m_ext.get_string(2)
			if res_type == "PackedScene":
				instances.append(res_path)
			elif res_type == "Script":
				scripts.append(res_path)
			continue

		# Regular nodes
		var m_node: RegExMatch = _re_node.search(line)
		if m_node:
			var node_name: String = m_node.get_string(1)
			var node_type: String = m_node.get_string(2)
			if root_type.is_empty():
				root_type = node_type
			nodes.append({ &"name": node_name, &"type": node_type })
			continue

		# Instance nodes
		var m_inst: RegExMatch = _re_node_instance.search(line)
		if m_inst:
			var node_name: String = m_inst.get_string(1)
			nodes.append({ &"name": node_name, &"type": "Instance" })

	return {
		&"path": path,
		&"name": scene_name,
		&"root_type": root_type,
		&"nodes": nodes,
		&"instances": instances,
		&"scripts": scripts,
		&"node_count": nodes.size(),
	}

@tool
extends RefCounted

class_name FileTools
## File operation tools for MCP.
## Handles: list_dir, read_file, read_files, create_file, search_project,
##          create_folder, delete_file, delete_folder, rename_file,
##          replace_in_files, bulk_edit, find_references, list_resources

const DEFAULT_MAX_BYTES: int = 200_000
const DEFAULT_MAX_RESULTS: int = 200
const MAX_TRAVERSAL_DEPTH: int = 20
const MAX_BULK_FILES: int = 20
const _REGEX_META_CHARS: PackedStringArray = ["\\", ".", "+", "*", "?", "^", "$", "{", "}", "(", ")", "[", "]", "|"]

var _editor_plugin: EditorPlugin = null
var _exclude_dirs: PackedStringArray = []
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# list_dir - List files and folders in a directory
# =============================================================================
func list_dir(args: Dictionary) -> Dictionary:
	var root: String = _utils.validate_res_path(args[&"root"])
	if root.is_empty():
		return { &"err": "Path escapes project root" }
	var include_hidden: bool = args.get(&"include_hidden", false)
	var recursive: bool = args.get(&"recursive", false)
	var glob_filter: String = args.get(&"glob", "")

	if recursive:
		var all_files: PackedStringArray = _collect_files(root, glob_filter)
		return { &"files": all_files }

	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return { &"err": "Cannot open directory: " + root, &"sug": "Use list_dir to verify the directory exists" }

	var files: PackedStringArray = []
	var folders: PackedStringArray = []

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		# Skip hidden files unless requested
		if not include_hidden and name.begins_with("."):
			name = dir.get_next()
			continue

		# Skip .uid files
		if name.ends_with(".uid"):
			name = dir.get_next()
			continue

		if dir.current_is_dir():
			folders.append(name)
		else:
			if glob_filter.is_empty() or _matches_glob(root.path_join(name), glob_filter):
				files.append(name)

		name = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically
	files.sort()
	folders.sort()

	return { &"files": files, &"folders": folders }


# =============================================================================
# read_file - Read contents of a file
# =============================================================================
func read_file(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	var start_line: int = args.get(&"start_line", 1)
	var end_line: int = args.get(&"end_line", 0)
	var max_bytes: int = args.get(&"max_bytes", DEFAULT_MAX_BYTES)

	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path' parameter" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"err": "File not found: " + path, &"sug": "Use list_dir or search_project to find the correct path" }

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { &"err": "Cannot open file: " + path }

	var content: String

	# Read as text — get_as_text() handles UTF-8 correctly without splitting
	# multi-byte characters (unlike get_buffer().get_string_from_utf8())
	var raw_content: String = file.get_as_text()
	file.close()
	if raw_content.length() > max_bytes:
		raw_content = raw_content.left(max_bytes)

	if end_line <= 0 and start_line <= 1:
		content = raw_content
	else:
		# Slice the requested line range from the bulk-read content
		var all_lines: PackedStringArray = raw_content.split("\n")
		var from: int = maxi(start_line - 1, 0)
		var to: int = all_lines.size() if end_line <= 0 else mini(end_line, all_lines.size())
		var sliced: PackedStringArray = all_lines.slice(from, to)
		content = "\n".join(sliced)

	var result: Dictionary = { &"content": content }
	if end_line > 0:
		result[&"range"] = [start_line, end_line]
	return result


# =============================================================================
# read_files - Read multiple files in one call
# =============================================================================
## Read multiple files in a single call. More efficient than calling
## [method read_file] repeatedly. Maximum [const MAX_BULK_FILES] files per call.
func read_files(args: Dictionary) -> Dictionary:
	var paths: Array[String]
	paths.assign(args[&"paths"])
	var max_bytes: int = args.get(&"max_bytes", DEFAULT_MAX_BYTES)

	if paths.is_empty():
		return { &"err": "Missing 'paths' array" }
	if paths.size() > MAX_BULK_FILES:
		return { &"err": "Too many files (%d). Maximum is %d" % [paths.size(), MAX_BULK_FILES] }

	var files: Array[Dictionary] = []
	for p: String in paths:
		var result: Dictionary = read_file({ &"path": p, &"max_bytes": max_bytes })
		if result.has(&"err"):
			files.append({ &"path": p, &"err": result[&"err"] })
		else:
			files.append({ &"path": p, &"content": result[&"content"] })

	return { &"files": files }


# =============================================================================
# bulk_edit - Multiple text replacements across files
# =============================================================================
## Apply multiple text replacements across files in a single call.
## Each edit specifies a file, old text to find, and new text to replace it with.
func bulk_edit(args: Dictionary) -> Dictionary:
	var edits: Array
	edits.assign(args[&"edits"])
	if edits.is_empty():
		return { &"err": "Missing 'edits' array" }

	var results: Array[Dictionary] = []
	var success_count: int = 0

	for edit: Variant in edits:
		if edit is not Dictionary:
			results.append({ &"err": "Invalid edit entry (not a dictionary)" })
			continue

		var file_path: String = edit[&"file"]
		if file_path.is_empty():
			results.append({ &"err": "Missing 'file' in edit entry" })
			continue

		file_path = _utils.validate_res_path(file_path)
		if file_path.is_empty():
			results.append({ &"file": edit[&"file"], &"replaced": false, &"err": "Path escapes project root" })
			continue

		if not FileAccess.file_exists(file_path):
			results.append({ &"file": file_path, &"replaced": false, &"err": "File not found" })
			continue

		var old_text: String = edit[&"old"]
		var new_text: String = edit[&"new"]
		if old_text.is_empty():
			results.append({ &"file": file_path, &"replaced": false, &"err": "Missing 'old' text" })
			continue

		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			results.append({ &"file": file_path, &"replaced": false, &"err": "Cannot open file" })
			continue
		var content: String = file.get_as_text()
		file.close()

		if content.find(old_text) == -1:
			results.append({ &"file": file_path, &"replaced": false, &"err": "old text not found in file" })
			continue

		var new_content: String = content.replace(old_text, new_text)
		file = FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			results.append({ &"file": file_path, &"replaced": false, &"err": "Cannot write file" })
			continue
		file.store_string(new_content)
		file.close()

		results.append({ &"file": file_path, &"replaced": true })
		success_count += 1

	if success_count > 0:
		_utils.refresh_filesystem()

	return { &"results": results }


# =============================================================================
# create_file - Create or overwrite a text file
# =============================================================================
func create_file(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	var content: String = args[&"content"]
	var overwrite: bool = args.get(&"overwrite", false)

	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if FileAccess.file_exists(path) and not overwrite:
		return { &"err": "File already exists: " + path + ". Set overwrite=true to replace." }

	# Ensure parent directory exists
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { &"err": "Cannot create file: " + path }
	file.store_string(content)
	file.close()

	_utils.refresh_filesystem()

	return {}


# =============================================================================
# search_project - Search for text in project files
# =============================================================================
func search_project(args: Dictionary) -> Dictionary:
	var query: String = args[&"query"]
	var glob_filter: String = args.get(&"glob", "")
	var max_results: int = args.get(&"max_results", DEFAULT_MAX_RESULTS)
	var case_sensitive: bool = args.get(&"case_sensitive", false)
	var use_regex: bool = args.get(&"regex", false)
	var exclude_dirs: PackedStringArray = _parse_exclude_dirs(args)

	if query.strip_edges().is_empty():
		return { &"err": "Missing 'query' parameter" }

	# Compile regex if requested
	var compiled_regex: RegEx = null
	if use_regex:
		compiled_regex = RegEx.new()
		var err: Error = compiled_regex.compile(query)
		if err != OK:
			return { &"err": "Invalid regex pattern: " + query }

	var search_query: String = query if case_sensitive else query.to_lower()
	var files: PackedStringArray = _collect_files("res://", glob_filter, exclude_dirs)
	var matches: Array[Dictionary] = []

	for file_path: String in files:
		if matches.size() >= max_results:
			break

		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue

		# Sniff first 512 bytes for null bytes — skip binary files
		var head: PackedByteArray = file.get_buffer(mini(512, file.get_length()))
		if head.has(0):
			file.close()
			continue
		file.seek(0)

		var content: String = file.get_as_text()
		file.close()

		# Quick whole-file check to skip non-matching files entirely
		if use_regex:
			if compiled_regex.search(content) == null:
				continue
		else:
			var search_content: String = content if case_sensitive else content.to_lower()
			if search_content.find(search_query) == -1:
				continue

		var lines: PackedStringArray = content.split("\n")
		var lower_lines: PackedStringArray
		if not case_sensitive and not use_regex:
			var search_content: String = content.to_lower()
			lower_lines = search_content.split("\n")
		for i: int in range(lines.size()):
			var matched: bool = false
			if use_regex:
				matched = compiled_regex.search(lines[i]) != null
			else:
				var check_line: String = lines[i] if case_sensitive else lower_lines[i]
				matched = check_line.find(search_query) != -1
			if matched:
				matches.append(
					{
						&"file": file_path,
						&"line": i + 1,
						&"content": lines[i].strip_edges(),
					},
				)
				if matches.size() >= max_results:
					break

	return {
		&"m": _utils.tabular(matches, [&"file", &"line", &"content"]),
		&"trunc": matches.size() >= max_results,
	}


## Parse [code]exclude_dirs[/code] array from tool args.
func _parse_exclude_dirs(args: Dictionary) -> PackedStringArray:
	var raw: Array[String]
	raw.assign(args.get(&"exclude_dirs", []))
	var out: PackedStringArray = []
	for d: String in raw:
		out.append(d)
	return out


## Recursively collect all searchable files.
func _collect_files(path: String, glob_filter: String, exclude_dirs: PackedStringArray = []) -> PackedStringArray:
	var result: PackedStringArray = []
	_exclude_dirs = exclude_dirs
	_collect_files_recursive(path, glob_filter, result, 0)
	_exclude_dirs = []
	return result


func _collect_files_recursive(path: String, glob_filter: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Skip hidden
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path: String = path.path_join(file_name)

		if dir.current_is_dir():
			# Skip excluded directories by name
			if not _exclude_dirs.is_empty() and file_name in _exclude_dirs:
				file_name = dir.get_next()
				continue
			_collect_files_recursive(full_path, glob_filter, out, depth + 1)
		else:
			if not _is_binary_ext(file_name.get_extension()):
				if glob_filter.is_empty() or _matches_glob(full_path, glob_filter):
					out.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


## Simple glob matching: [code]*.gd[/code], [code]**/*.tscn[/code], [code]**/dirname/**[/code], etc.
func _matches_glob(path: String, pattern: String) -> bool:
	if pattern.begins_with("**/"):
		var rest: String = pattern.substr(3) # Remove **/
		# Handle **/dirname/** — directory exclusion
		if rest.ends_with("/**"):
			var dir_name: String = rest.substr(0, rest.length() - 3)
			return ("/" + dir_name + "/") in path
		# Handle **/*.ext — extension match anywhere
		return path.ends_with(rest.replace("*", ""))

	# Handle *.ext pattern
	if pattern.begins_with("*."):
		return path.ends_with(pattern.substr(1))

	# Simple contains check
	return path.find(pattern) != -1


# =============================================================================
# replace_in_files - Bulk find-and-replace across project files
# =============================================================================
func replace_in_files(args: Dictionary) -> Dictionary:
	var search: String = args[&"search"]
	var replace: String = args[&"replace"]
	var glob_filter: String = args.get(&"glob", "")
	var exclude_patterns: Array[String]
	exclude_patterns.assign(args.get(&"exclude", []))
	var exclude_dirs: PackedStringArray = _parse_exclude_dirs(args)
	var case_sensitive: bool = args.get(&"case_sensitive", true)
	var preview: bool = args.get(&"preview", false)

	if search.is_empty():
		return { &"err": "Missing 'search' parameter" }
	if search == replace:
		return { &"err": "'search' and 'replace' are identical" }

	var files: PackedStringArray = _collect_files("res://", glob_filter, exclude_dirs)
	var search_term: String = search if case_sensitive else search.to_lower()
	var modified_files: PackedStringArray = []
	var total_replacements: int = 0

	for file_path: String in files:
		# Check exclude patterns
		var excluded: bool = false
		for pattern: String in exclude_patterns:
			if _matches_glob(file_path, pattern):
				excluded = true
				break
		if excluded:
			continue

		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		var head: PackedByteArray = file.get_buffer(mini(512, file.get_length()))
		if head.has(0):
			file.close()
			continue
		file.seek(0)
		var content: String = file.get_as_text()
		file.close()

		# Quick whole-file check
		var check_content: String = content if case_sensitive else content.to_lower()
		if check_content.find(search_term) == -1:
			continue

		if not preview:
			var new_content: String
			var count: int
			if case_sensitive:
				count = content.count(search)
				if count == 0:
					continue
				new_content = content.replace(search, replace)
			else:
				# Case-insensitive replace: collect segments, count during replacement
				var parts: PackedStringArray = []
				var src: String = content
				var src_lower: String = check_content
				count = 0
				var idx: int = src_lower.find(search_term)
				while idx != -1:
					parts.append(src.substr(0, idx))
					parts.append(replace)
					src = src.substr(idx + search_term.length())
					src_lower = src_lower.substr(idx + search_term.length())
					count += 1
					idx = src_lower.find(search_term)
				parts.append(src)
				if count == 0:
					continue
				new_content = "".join(parts)

			total_replacements += count
			modified_files.append(file_path)
			file = FileAccess.open(file_path, FileAccess.WRITE)
			if file == null:
				continue
			file.store_string(new_content)
			file.close()
		else:
			# Preview: count only
			var count: int = 0
			var pos: int = check_content.find(search_term)
			while pos != -1:
				count += 1
				pos = check_content.find(search_term, pos + search_term.length())
			if count == 0:
				continue
			total_replacements += count
			modified_files.append(file_path)

	if not preview and modified_files.size() > 0:
		_utils.refresh_filesystem()

	return {
		&"files": modified_files,
		&"replacements": total_replacements,
	}


static func _is_binary_ext(ext: String) -> bool:
	match ext:
		"import", "png", "jpg", "jpeg", "webp", "svg", "exr", "ico", "bmp", "tga", "hdr", "ogg", "wav", "mp3", "oggstr", "sample", "mp4", "ogv", "avi", "escn", "glb", "gltf", "obj", "fbx", "dae", "ttf", "otf", "woff", "woff2", "res", "scn", "ctex", "stex", "uid", "translation", "mesh", "material", "so", "dll", "dylib", "exe", "bin", "o", "a", "lib", "zip", "gz", "tar", "pck", "7z", "rar":
			return true
	return false


# =============================================================================
# create_folder - Create a directory
# =============================================================================
func create_folder(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if DirAccess.dir_exists_absolute(path):
		return {}

	var err: Error = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return { &"err": "Failed to create directory: " + str(err) }

	_utils.refresh_filesystem()

	return {}


# =============================================================================
# delete_file - Delete a file with optional backup
# =============================================================================
func delete_file(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	var confirm: bool = args[&"confirm"]
	var create_backup: bool = args.get(&"create_backup", true)

	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }
	if not confirm:
		return { &"err": "Must set confirm=true to delete" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"err": "File not found: " + path, &"sug": "Use list_dir or search_project to find the correct path" }

	# Create backup
	if create_backup:
		var backup_path: String = path + ".bak"
		DirAccess.copy_absolute(path, backup_path)

	var err: Error = DirAccess.remove_absolute(path)
	if err != OK:
		return { &"err": "Failed to delete file: " + str(err) }

	_utils.refresh_filesystem()

	return {}


# =============================================================================
# delete_folder - Delete an empty directory
# =============================================================================
func delete_folder(args: Dictionary) -> Dictionary:
	var path: String = args[&"path"]
	var confirm: bool = args[&"confirm"]
	var recursive: bool = args.get(&"recursive", false)

	if path.strip_edges().is_empty():
		return { &"err": "Missing 'path'" }
	if not confirm:
		return { &"err": "Must set confirm=true to delete" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"err": "Path escapes project root" }
	if path == "res://" or path == "res://addons" or path == "res://addons/godot_mcp":
		return { &"err": "Refusing to delete protected directory: " + path }

	if not DirAccess.dir_exists_absolute(path):
		return { &"err": "Directory not found: " + path, &"sug": "Use list_dir to see available directories" }

	if recursive:
		var removed: bool = _remove_dir_recursive(path)
		if not removed:
			return { &"err": "Failed to remove directory recursively: " + path }
	else:
		# Only delete if empty
		var dir: DirAccess = DirAccess.open(path)
		if dir == null:
			return { &"err": "Cannot open directory: " + path }
		dir.list_dir_begin()
		var has_contents: bool = false
		var name: String = dir.get_next()
		while name != "":
			if not name.begins_with("."):
				has_contents = true
				break
			name = dir.get_next()
		dir.list_dir_end()
		if has_contents:
			return { &"err": "Directory is not empty. Use recursive=true to delete contents." }
		var err: Error = DirAccess.remove_absolute(path)
		if err != OK:
			return { &"err": "Failed to delete directory: " + str(err) }

	_utils.refresh_filesystem()
	return {}


func _remove_dir_recursive(path: String) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path: String = path.path_join(name)
		if dir.current_is_dir():
			if not _remove_dir_recursive(full_path):
				return false
		else:
			var err: Error = DirAccess.remove_absolute(full_path)
			if err != OK:
				return false
		name = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


# =============================================================================
# rename_file - Rename or move a file
# =============================================================================
func rename_file(args: Dictionary) -> Dictionary:
	var old_path: String = args[&"old_path"]
	var new_path: String = args[&"new_path"]

	if old_path.strip_edges().is_empty():
		return { &"err": "Missing 'old_path'" }
	if new_path.strip_edges().is_empty():
		return { &"err": "Missing 'new_path'" }

	old_path = _utils.validate_res_path(old_path)
	if old_path.is_empty():
		return { &"err": "old_path escapes project root" }
	new_path = _utils.validate_res_path(new_path)
	if new_path.is_empty():
		return { &"err": "new_path escapes project root" }

	if not FileAccess.file_exists(old_path):
		return { &"err": "File not found: " + old_path, &"sug": "Use list_dir or search_project to find the correct path" }
	if FileAccess.file_exists(new_path):
		return { &"err": "Target already exists: " + new_path }

	# Ensure target directory exists
	var dir_path: String = new_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err: Error = DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		return { &"err": "Failed to rename: " + str(err) }

	_utils.refresh_filesystem()

	return {}


# =============================================================================
# find_references - Find all references to a symbol with word boundaries
# =============================================================================
## Find all references to a symbol using word-boundary regex matching.
func find_references(args: Dictionary) -> Dictionary:
	var symbol: String = args[&"symbol"]
	var glob_filter: String = args.get(&"glob", "")
	var max_results: int = args.get(&"max_results", DEFAULT_MAX_RESULTS)
	var exclude_dirs: PackedStringArray = _parse_exclude_dirs(args)

	if symbol.strip_edges().is_empty():
		return { &"err": "Missing 'symbol' parameter" }

	# Escape regex metacharacters in the symbol name, then wrap with word boundaries
	var escaped: String = symbol
	for ch: String in _REGEX_META_CHARS:
		escaped = escaped.replace(ch, "\\" + ch)
	var regex: RegEx = RegEx.new()
	var err: Error = regex.compile("\\b" + escaped + "\\b")
	if err != OK:
		return { &"err": "Cannot compile regex for symbol: " + symbol }

	var files: PackedStringArray = _collect_files("res://", glob_filter, exclude_dirs)
	var matches: Array[Dictionary] = []

	for file_path: String in files:
		if matches.size() >= max_results:
			break

		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		var content: String = file.get_as_text()
		file.close()

		if regex.search(content) == null:
			continue

		var lines: PackedStringArray = content.split("\n")
		for i: int in range(lines.size()):
			if regex.search(lines[i]) != null:
				matches.append(
					{
						&"file": file_path,
						&"line": i + 1,
						&"content": lines[i].strip_edges(),
					},
				)
				if matches.size() >= max_results:
					break

	return {
		&"m": _utils.tabular(matches, [&"file", &"line", &"content"]),
		&"trunc": matches.size() >= max_results,
	}


# =============================================================================
# list_resources - Find .tres files, optionally filtered by type
# =============================================================================
## Find all [code].tres[/code] resource files, optionally filtered by resource class.
func list_resources(args: Dictionary) -> Dictionary:
	var type_filter: String = args.get(&"type", "")
	var glob_filter: String = args.get(&"glob", "")
	var exclude_dirs: PackedStringArray = _parse_exclude_dirs(args)

	# Collect .tres files
	var effective_glob: String = "**/*.tres" if glob_filter.is_empty() else glob_filter
	var files: PackedStringArray = _collect_files("res://", effective_glob, exclude_dirs)
	var resources: Array[Dictionary] = []

	for file_path: String in files:
		if not file_path.ends_with(".tres"):
			continue
		if type_filter.is_empty():
			resources.append({ &"path": file_path })
		else:
			# Load and check type
			var res: Resource = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if res != null:
				var cls: String = res.get_class()
				if cls == type_filter or res.is_class(type_filter):
					resources.append({ &"path": file_path, &"type": cls })

	return { &"resources": resources }

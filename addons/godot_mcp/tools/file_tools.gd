@tool
extends RefCounted

class_name FileTools
## File operation tools for MCP.
## Handles: list_dir, read_file, read_files, create_file, search_project,
##          create_folder, delete_file, delete_folder, rename_file,
##          replace_in_files, bulk_edit, find_references, list_resources

const DEFAULT_MAX_BYTES := 200_000
const DEFAULT_MAX_RESULTS := 200
const MAX_TRAVERSAL_DEPTH := 20
const MAX_BULK_FILES := 20

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# list_dir - List files and folders in a directory
# =============================================================================
func list_dir(args: Dictionary) -> Dictionary:
	var root: String = _utils.validate_res_path(str(args.get(&"root", "res://")))
	if root.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }
	var include_hidden: bool = bool(args.get(&"include_hidden", false))
	var recursive: bool = bool(args.get(&"recursive", false))
	var glob_filter: String = str(args.get(&"glob", ""))

	if recursive:
		var all_files := _collect_files(root, glob_filter)
		return {
			&"ok": true,
			&"path": root,
			&"files": all_files,
			&"total": all_files.size(),
			&"recursive": true,
		}

	var dir := DirAccess.open(root)
	if dir == null:
		return { &"ok": false, &"error": "Cannot open directory: " + root }

	var files: PackedStringArray = []
	var folders: PackedStringArray = []

	dir.list_dir_begin()
	var name := dir.get_next()
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

	return {
		&"ok": true,
		&"path": root,
		&"files": files,
		&"folders": folders,
		&"total": files.size() + folders.size(),
	}


# =============================================================================
# read_file - Read contents of a file
# =============================================================================
func read_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var start_line: int = int(args.get(&"start_line", 1))
	var end_line: int = int(args.get(&"end_line", 0))
	var max_bytes: int = int(args.get(&"max_bytes", DEFAULT_MAX_BYTES))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path' parameter" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { &"ok": false, &"error": "Cannot open file: " + path }

	var content: String
	var line_count: int = 0

	# Read as text — get_as_text() handles UTF-8 correctly without splitting
	# multi-byte characters (unlike get_buffer().get_string_from_utf8())
	var raw_content := file.get_as_text()
	file.close()
	if raw_content.length() > max_bytes:
		raw_content = raw_content.left(max_bytes)

	if end_line <= 0 and start_line <= 1:
		content = raw_content
		line_count = content.count("\n") + 1
	else:
		# Slice the requested line range from the bulk-read content
		var all_lines := raw_content.split("\n")
		var from := maxi(start_line - 1, 0)
		var to := all_lines.size() if end_line <= 0 else mini(end_line, all_lines.size())
		var sliced := all_lines.slice(from, to)
		content = "\n".join(sliced)
		line_count = sliced.size()

	return {
		&"ok": true,
		&"path": path,
		&"content": content,
		&"line_count": line_count,
		&"range": [start_line, end_line] if end_line > 0 else null,
	}


# =============================================================================
# read_files - Read multiple files in one call
# =============================================================================
## Read multiple files in a single call. More efficient than calling
## [method read_file] repeatedly. Maximum [const MAX_BULK_FILES] files per call.
func read_files(args: Dictionary) -> Dictionary:
	var paths: Array = args.get(&"paths", [])
	var max_bytes: int = int(args.get(&"max_bytes", DEFAULT_MAX_BYTES))

	if paths.is_empty():
		return { &"ok": false, &"error": "Missing 'paths' array" }
	if paths.size() > MAX_BULK_FILES:
		return { &"ok": false, &"error": "Too many files (%d). Maximum is %d" % [paths.size(), MAX_BULK_FILES] }

	var files: Array = []
	for p: Variant in paths:
		var result := read_file({ &"path": str(p), &"max_bytes": max_bytes })
		if result[&"ok"]:
			files.append({ &"path": result[&"path"], &"content": result[&"content"], &"line_count": result[&"line_count"] })
		else:
			files.append({ &"path": str(p), &"error": result[&"error"] })

	return {
		&"ok": true,
		&"files": files,
		&"count": files.size(),
	}


# =============================================================================
# bulk_edit - Multiple text replacements across files
# =============================================================================
## Apply multiple text replacements across files in a single call.
## Each edit specifies a file, old text to find, and new text to replace it with.
func bulk_edit(args: Dictionary) -> Dictionary:
	var edits: Array = args.get(&"edits", [])
	if edits.is_empty():
		return { &"ok": false, &"error": "Missing 'edits' array" }

	var results: Array = []
	var success_count := 0
	var error_count := 0

	for edit: Variant in edits:
		if edit is not Dictionary:
			results.append({ &"error": "Invalid edit entry (not a dictionary)" })
			error_count += 1
			continue

		var file_path: String = str(edit.get(&"file", ""))
		if file_path.is_empty():
			results.append({ &"error": "Missing 'file' in edit entry" })
			error_count += 1
			continue

		file_path = _utils.validate_res_path(file_path)
		if file_path.is_empty():
			results.append({ &"file": str(edit.get(&"file", "")), &"replaced": false, &"error": "Path escapes project root" })
			error_count += 1
			continue

		if not FileAccess.file_exists(file_path):
			results.append({ &"file": file_path, &"replaced": false, &"error": "File not found" })
			error_count += 1
			continue

		var old_text: String = str(edit.get(&"old", ""))
		var new_text: String = str(edit.get(&"new", ""))
		if old_text.is_empty():
			results.append({ &"file": file_path, &"replaced": false, &"error": "Missing 'old' text" })
			error_count += 1
			continue

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			results.append({ &"file": file_path, &"replaced": false, &"error": "Cannot open file" })
			error_count += 1
			continue
		var content := file.get_as_text()
		file.close()

		if content.find(old_text) == -1:
			results.append({ &"file": file_path, &"replaced": false, &"error": "old text not found in file" })
			error_count += 1
			continue

		var new_content := content.replace(old_text, new_text)
		file = FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			results.append({ &"file": file_path, &"replaced": false, &"error": "Cannot write file" })
			error_count += 1
			continue
		file.store_string(new_content)
		file.close()

		results.append({ &"file": file_path, &"replaced": true })
		success_count += 1

	if success_count > 0:
		_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"results": results,
		&"success_count": success_count,
		&"error_count": error_count,
	}


# =============================================================================
# create_file - Create or overwrite a text file
# =============================================================================
func create_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var content: String = str(args.get(&"content", ""))
	var overwrite: bool = bool(args.get(&"overwrite", false))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if FileAccess.file_exists(path) and not overwrite:
		return { &"ok": false, &"error": "File already exists: " + path + ". Set overwrite=true to replace." }

	# Ensure parent directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { &"ok": false, &"error": "Cannot create file: " + path }
	file.store_string(content)
	file.close()

	_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"line_count": content.count("\n") + 1,
		&"message": "File created: " + path,
	}


# =============================================================================
# search_project - Search for text in project files
# =============================================================================
func search_project(args: Dictionary) -> Dictionary:
	var query: String = str(args.get(&"query", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var max_results: int = int(args.get(&"max_results", DEFAULT_MAX_RESULTS))
	var case_sensitive: bool = bool(args.get(&"case_sensitive", false))
	var use_regex: bool = bool(args.get(&"regex", false))
	var exclude_dirs := _parse_exclude_dirs(args)

	if query.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'query' parameter" }

	# Compile regex if requested
	var compiled_regex: RegEx = null
	if use_regex:
		compiled_regex = RegEx.new()
		var err := compiled_regex.compile(query)
		if err != OK:
			return { &"ok": false, &"error": "Invalid regex pattern: " + query }

	var search_query := query if case_sensitive else query.to_lower()
	var files := _collect_files("res://", glob_filter, exclude_dirs)
	var matches: Array = []

	for file_path: String in files:
		if matches.size() >= max_results:
			break

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue

		# Sniff first 512 bytes for null bytes — skip binary files
		var head := file.get_buffer(mini(512, file.get_length()))
		if head.has(0):
			file.close()
			continue
		file.seek(0)

		var content := file.get_as_text()
		file.close()

		# Quick whole-file check to skip non-matching files entirely
		if use_regex:
			if compiled_regex.search(content) == null:
				continue
		else:
			var search_content := content if case_sensitive else content.to_lower()
			if search_content.find(search_query) == -1:
				continue

		var lines := content.split("\n")
		for i: int in range(lines.size()):
			var matched := false
			if use_regex:
				matched = compiled_regex.search(lines[i]) != null
			else:
				var check_line := lines[i] if case_sensitive else lines[i].to_lower()
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
		&"ok": true,
		&"query": query,
		&"matches": matches,
		&"total_matches": matches.size(),
		&"truncated": matches.size() >= max_results,
	}


## Parse [code]exclude_dirs[/code] array from tool args.
func _parse_exclude_dirs(args: Dictionary) -> PackedStringArray:
	var raw: Array = args.get(&"exclude_dirs", [])
	var out: PackedStringArray = []
	for d: Variant in raw:
		out.append(str(d))
	return out


## Recursively collect all searchable files.
func _collect_files(path: String, glob_filter: String, exclude_dirs: PackedStringArray = []) -> PackedStringArray:
	var result: PackedStringArray = []
	_collect_files_recursive(path, glob_filter, result, 0, exclude_dirs)
	return result


func _collect_files_recursive(path: String, glob_filter: String, out: PackedStringArray, depth: int = 0, exclude_dirs: PackedStringArray = []) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Skip hidden
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			# Skip excluded directories by name
			if not exclude_dirs.is_empty() and file_name in exclude_dirs:
				file_name = dir.get_next()
				continue
			_collect_files_recursive(full_path, glob_filter, out, depth + 1, exclude_dirs)
		else:
			if not _is_binary_ext(file_name.get_extension()):
				if glob_filter.is_empty() or _matches_glob(full_path, glob_filter):
					out.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


## Simple glob matching: [code]*.gd[/code], [code]**/*.tscn[/code], [code]**/dirname/**[/code], etc.
func _matches_glob(path: String, pattern: String) -> bool:
	if pattern.begins_with("**/"):
		var rest := pattern.substr(3) # Remove **/
		# Handle **/dirname/** — directory exclusion
		if rest.ends_with("/**"):
			var dir_name := rest.substr(0, rest.length() - 3)
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
	var search: String = str(args.get(&"search", ""))
	var replace: String = str(args.get(&"replace", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var exclude_patterns: Array = args.get(&"exclude", [])
	var exclude_dirs := _parse_exclude_dirs(args)
	var case_sensitive: bool = bool(args.get(&"case_sensitive", true))
	var preview: bool = bool(args.get(&"preview", false))

	if search.is_empty():
		return { &"ok": false, &"error": "Missing 'search' parameter" }
	if search == replace:
		return { &"ok": false, &"error": "'search' and 'replace' are identical" }

	var files := _collect_files("res://", glob_filter, exclude_dirs)
	var search_term := search if case_sensitive else search.to_lower()
	var modified_files: PackedStringArray = []
	var total_replacements := 0

	for file_path: String in files:
		# Check exclude patterns
		var excluded := false
		for pattern: String in exclude_patterns:
			if _matches_glob(file_path, pattern):
				excluded = true
				break
		if excluded:
			continue

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		var head := file.get_buffer(mini(512, file.get_length()))
		if head.has(0):
			file.close()
			continue
		file.seek(0)
		var content := file.get_as_text()
		file.close()

		# Quick whole-file check
		var check_content := content if case_sensitive else content.to_lower()
		if check_content.find(search_term) == -1:
			continue

		# Count occurrences
		var count := 0
		var pos := check_content.find(search_term)
		while pos != -1:
			count += 1
			pos = check_content.find(search_term, pos + search_term.length())

		if count == 0:
			continue

		total_replacements += count
		modified_files.append(file_path)

		if not preview:
			var new_content: String
			if case_sensitive:
				new_content = content.replace(search, replace)
			else:
				# Case-insensitive replace: collect segments, join once
				var parts: PackedStringArray = []
				var src := content
				var src_lower := check_content
				var idx := src_lower.find(search_term)
				while idx != -1:
					parts.append(src.substr(0, idx))
					parts.append(replace)
					src = src.substr(idx + search_term.length())
					src_lower = src_lower.substr(idx + search_term.length())
					idx = src_lower.find(search_term)
				parts.append(src)
				new_content = "".join(parts)

			file = FileAccess.open(file_path, FileAccess.WRITE)
			if file == null:
				continue
			file.store_string(new_content)
			file.close()

	if not preview and modified_files.size() > 0:
		_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"search": search,
		&"replace": replace,
		&"files_modified": modified_files.size(),
		&"total_replacements": total_replacements,
		&"files": modified_files,
		&"preview": preview,
		&"message": "%s %d occurrence(s) across %d file(s)" % [
			"Would replace" if preview else "Replaced",
			total_replacements,
			modified_files.size(),
		],
	}


static func _is_binary_ext(ext: String) -> bool:
	match ext:
		"import", "png", "jpg", "jpeg", "webp", "svg", "exr", "ico", "bmp", "tga", "hdr", \
		"ogg", "wav", "mp3", "oggstr", "sample", "mp4", "ogv", "avi", \
		"escn", "glb", "gltf", "obj", "fbx", "dae", \
		"ttf", "otf", "woff", "woff2", \
		"res", "scn", "ctex", "stex", "uid", "translation", "mesh", "material", \
		"so", "dll", "dylib", "exe", "bin", "o", "a", "lib", \
		"zip", "gz", "tar", "pck", "7z", "rar":
			return true
	return false


# =============================================================================
# create_folder - Create a directory
# =============================================================================
func create_folder(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if DirAccess.dir_exists_absolute(path):
		return { &"ok": true, &"path": path, &"message": "Directory already exists" }

	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to create directory: " + str(err) }

	_utils.refresh_filesystem()

	return { &"ok": true, &"path": path, &"message": "Directory created" }


# =============================================================================
# delete_file - Delete a file with optional backup
# =============================================================================
func delete_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var confirm: bool = bool(args.get(&"confirm", false))
	var create_backup: bool = bool(args.get(&"create_backup", true))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }
	if not confirm:
		return { &"ok": false, &"error": "Must set confirm=true to delete" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }

	if not FileAccess.file_exists(path):
		return { &"ok": false, &"error": "File not found: " + path }

	# Create backup
	if create_backup:
		var backup_path := path + ".bak"
		DirAccess.copy_absolute(path, backup_path)

	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to delete file: " + str(err) }

	_utils.refresh_filesystem()

	return { &"ok": true, &"path": path, &"message": "File deleted" + (" (backup created)" if create_backup else "") }


# =============================================================================
# delete_folder - Delete an empty directory
# =============================================================================
func delete_folder(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var confirm: bool = bool(args.get(&"confirm", false))
	var recursive: bool = bool(args.get(&"recursive", false))

	if path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'path'" }
	if not confirm:
		return { &"ok": false, &"error": "Must set confirm=true to delete" }

	path = _utils.validate_res_path(path)
	if path.is_empty():
		return { &"ok": false, &"error": "Path escapes project root" }
	if path == "res://" or path == "res://addons" or path == "res://addons/godot_mcp":
		return { &"ok": false, &"error": "Refusing to delete protected directory: " + path }

	if not DirAccess.dir_exists_absolute(path):
		return { &"ok": false, &"error": "Directory not found: " + path }

	if recursive:
		var removed := _remove_dir_recursive(path)
		if not removed:
			return { &"ok": false, &"error": "Failed to remove directory recursively: " + path }
	else:
		# Only delete if empty
		var dir := DirAccess.open(path)
		if dir == null:
			return { &"ok": false, &"error": "Cannot open directory: " + path }
		dir.list_dir_begin()
		var has_contents := false
		var name := dir.get_next()
		while name != "":
			if not name.begins_with("."):
				has_contents = true
				break
			name = dir.get_next()
		dir.list_dir_end()
		if has_contents:
			return { &"ok": false, &"error": "Directory is not empty. Use recursive=true to delete contents." }
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return { &"ok": false, &"error": "Failed to delete directory: " + str(err) }

	_utils.refresh_filesystem()
	return {
		&"ok": true,
		&"path": path,
		&"message": "Directory deleted" + (" (recursive)" if recursive else ""),
	}


func _remove_dir_recursive(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := path.path_join(name)
		if dir.current_is_dir():
			if not _remove_dir_recursive(full_path):
				return false
		else:
			var err := DirAccess.remove_absolute(full_path)
			if err != OK:
				return false
		name = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


# =============================================================================
# rename_file - Rename or move a file
# =============================================================================
func rename_file(args: Dictionary) -> Dictionary:
	var old_path: String = str(args.get(&"old_path", ""))
	var new_path: String = str(args.get(&"new_path", ""))

	if old_path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'old_path'" }
	if new_path.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'new_path'" }

	old_path = _utils.validate_res_path(old_path)
	if old_path.is_empty():
		return { &"ok": false, &"error": "old_path escapes project root" }
	new_path = _utils.validate_res_path(new_path)
	if new_path.is_empty():
		return { &"ok": false, &"error": "new_path escapes project root" }

	if not FileAccess.file_exists(old_path):
		return { &"ok": false, &"error": "File not found: " + old_path }
	if FileAccess.file_exists(new_path):
		return { &"ok": false, &"error": "Target already exists: " + new_path }

	# Ensure target directory exists
	var dir_path := new_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to rename: " + str(err) }

	_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"old_path": old_path,
		&"new_path": new_path,
		&"message": "Renamed %s to %s" % [old_path, new_path],
	}


# =============================================================================
# find_references - Find all references to a symbol with word boundaries
# =============================================================================
## Find all references to a symbol using word-boundary regex matching.
func find_references(args: Dictionary) -> Dictionary:
	var symbol: String = str(args.get(&"symbol", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var max_results: int = int(args.get(&"max_results", DEFAULT_MAX_RESULTS))
	var exclude_dirs := _parse_exclude_dirs(args)

	if symbol.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'symbol' parameter" }

	# Escape regex metacharacters in the symbol name, then wrap with word boundaries
	var escaped := symbol
	for ch: String in ["\\", ".", "+", "*", "?", "^", "$", "{", "}", "(", ")", "[", "]", "|"]:
		escaped = escaped.replace(ch, "\\" + ch)
	var regex := RegEx.new()
	var err := regex.compile("\\b" + escaped + "\\b")
	if err != OK:
		return { &"ok": false, &"error": "Cannot compile regex for symbol: " + symbol }

	var files := _collect_files("res://", glob_filter, exclude_dirs)
	var matches: Array = []

	for file_path: String in files:
		if matches.size() >= max_results:
			break

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		var content := file.get_as_text()
		file.close()

		if regex.search(content) == null:
			continue

		var lines := content.split("\n")
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
		&"ok": true,
		&"symbol": symbol,
		&"matches": matches,
		&"total_matches": matches.size(),
		&"truncated": matches.size() >= max_results,
	}


# =============================================================================
# list_resources - Find .tres files, optionally filtered by type
# =============================================================================
## Find all [code].tres[/code] resource files, optionally filtered by resource class.
func list_resources(args: Dictionary) -> Dictionary:
	var type_filter: String = str(args.get(&"type", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var exclude_dirs := _parse_exclude_dirs(args)

	# Collect .tres files
	var effective_glob := "**/*.tres" if glob_filter.is_empty() else glob_filter
	var files := _collect_files("res://", effective_glob, exclude_dirs)
	var resources: Array = []

	for file_path: String in files:
		if not file_path.ends_with(".tres"):
			continue
		if type_filter.is_empty():
			resources.append({ &"path": file_path })
		else:
			# Load and check type
			var res := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if res != null:
				var cls := res.get_class()
				if cls == type_filter or res.is_class(type_filter):
					resources.append({ &"path": file_path, &"type": cls })

	return {
		&"ok": true,
		&"resources": resources,
		&"count": resources.size(),
		&"type_filter": type_filter if not type_filter.is_empty() else "all",
	}

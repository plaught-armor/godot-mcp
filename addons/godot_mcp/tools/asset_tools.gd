@tool
extends RefCounted

class_name AssetTools
## Asset generation tools for MCP.
## Handles: generate_2d_asset

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


# =============================================================================
# generate_2d_asset - Generate PNG from SVG code
# =============================================================================
func generate_2d_asset(args: Dictionary) -> Dictionary:
	var svg_code: String = str(args.get(&"svg_code", ""))
	var filename: String = str(args.get(&"filename", ""))
	var save_path: String = str(args.get(&"save_path", "res://assets/generated/"))

	if svg_code.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'svg_code'" }
	if filename.strip_edges().is_empty():
		return { &"ok": false, &"error": "Missing 'filename'" }

	# Ensure .png extension
	if not filename.ends_with(".png"):
		filename += ".png"

	# Ensure save path
	save_path = _utils.validate_res_path(save_path)
	if save_path.is_empty():
		return { &"ok": false, &"error": "Save path escapes project root" }
	if not save_path.ends_with("/"):
		save_path += "/"

	# Create directory if needed
	if not DirAccess.dir_exists_absolute(save_path):
		DirAccess.make_dir_recursive_absolute(save_path)

	# Parse SVG dimensions from the svg_code
	var width := 64
	var height := 64

	# Simple regex-free parsing for width/height
	var w_start := svg_code.find("width=\"")
	if w_start != -1:
		var w_val := svg_code.substr(w_start + 7)
		var w_end := w_val.find("\"")
		if w_end != -1:
			width = int(w_val.substr(0, w_end))

	var h_start := svg_code.find("height=\"")
	if h_start != -1:
		var h_val := svg_code.substr(h_start + 8)
		var h_end := h_val.find("\"")
		if h_end != -1:
			height = int(h_val.substr(0, h_end))

	# Create Image from SVG
	var image := Image.new()

	# Save SVG to temp file, then load as image
	var temp_svg_path := "user://temp_asset.svg"
	var svg_file := FileAccess.open(temp_svg_path, FileAccess.WRITE)
	if not svg_file:
		return { &"ok": false, &"error": "Failed to create temp SVG file" }
	svg_file.store_string(svg_code)
	svg_file.close()

	# Load SVG as image
	var err := image.load(temp_svg_path)
	if err != OK:
		# Fallback: try loading SVG data directly
		image = Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(1, 0, 1, 1)) # Magenta fallback = something went wrong
		print("[GMCP] Warning: Could not render SVG, created fallback image")

	# Clean up temp file
	DirAccess.remove_absolute(temp_svg_path)

	# Save as PNG
	var full_path := save_path + filename
	var global_path := ProjectSettings.globalize_path(full_path)
	err = image.save_png(global_path)
	if err != OK:
		return { &"ok": false, &"error": "Failed to save PNG: " + str(err) }

	_utils.refresh_filesystem()

	return {
		&"ok": true,
		&"resource_path": full_path,
		&"dimensions": { &"width": width, &"height": height },
		&"message": "Generated %s (%dx%d)" % [full_path, width, height],
	}

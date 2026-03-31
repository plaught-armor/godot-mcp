@tool
extends RefCounted

class_name TilemapTools
## TileMapLayer editing tools for MCP.
## Handles: tilemap_edit (set_cell, fill_rect, get_cell, clear, info, get_used_cells)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func tmap(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"set_cell":
			return _set_cell(args)
		&"fill_rect":
			return _fill_rect(args)
		&"get_cell":
			return _get_cell(args)
		&"clear":
			return _clear(args)
		&"info":
			return _info(args)
		&"used_cells":
			return _get_used_cells(args)
		_:
			return { &"err": "Unknown tilemap_edit action: " + action }


func _find_tilemap(args: Dictionary) -> TileMapLayer:
	var scene_path: String = _utils.validate_res_path(args[&"scene_path"])
	var node_path: String = args[&"node_path"]
	var root: Node = _editor_plugin.get_editor_interface().get_edited_scene_root()
	if not root:
		return null
	if not scene_path.is_empty() and root.scene_file_path != scene_path:
		return null
	var node: Node = root if (node_path == "." or node_path.is_empty()) else root.get_node_or_null(node_path)
	if node is TileMapLayer:
		return node as TileMapLayer
	return null


func _set_cell(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	var coords := Vector2i(int(args[&"x"]), int(args[&"y"]))
	var source_id: int = int(args.get(&"source_id", 0))
	var atlas := Vector2i(int(args.get(&"atlas_x", 0)), int(args.get(&"atlas_y", 0)))
	tilemap.set_cell(coords, source_id, atlas, int(args.get(&"alternative", 0)))
	return {}


func _fill_rect(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	var x1: int = int(args[&"x1"])
	var y1: int = int(args[&"y1"])
	var x2: int = int(args[&"x2"])
	var y2: int = int(args[&"y2"])
	var source_id: int = int(args.get(&"source_id", 0))
	var atlas := Vector2i(int(args.get(&"atlas_x", 0)), int(args.get(&"atlas_y", 0)))
	var alternative: int = int(args.get(&"alternative", 0))

	var count: int = 0
	for cx: int in range(mini(x1, x2), maxi(x1, x2) + 1):
		for cy: int in range(mini(y1, y2), maxi(y1, y2) + 1):
			tilemap.set_cell(Vector2i(cx, cy), source_id, atlas, alternative)
			count += 1

	return { &"filled": count }


func _get_cell(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	var coords := Vector2i(int(args[&"x"]), int(args[&"y"]))
	var source_id: int = tilemap.get_cell_source_id(coords)
	var atlas_coords: Vector2i = tilemap.get_cell_atlas_coords(coords)
	var alternative: int = tilemap.get_cell_alternative_tile(coords)

	return { &"source_id": source_id, &"atlas_coords": [atlas_coords.x, atlas_coords.y], &"alternative": alternative, &"empty": source_id == -1 }


func _clear(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	tilemap.clear()
	return {}


func _info(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	var tile_set: TileSet = tilemap.tile_set
	var sources: Array[Dictionary] = []
	if tile_set:
		for i: int in tile_set.get_source_count():
			var source_id: int = tile_set.get_source_id(i)
			var source: TileSetSource = tile_set.get_source(source_id)
			var info: Dictionary = { &"id": source_id, &"type": source.get_class() }
			if source is TileSetAtlasSource:
				var atlas: TileSetAtlasSource = source
				info[&"texture"] = atlas.texture.resource_path if atlas.texture else ""
				info[&"tile_count"] = atlas.get_tiles_count()
			sources.append(info)

	return { &"used_cells": tilemap.get_used_cells().size(), &"tile_set_sources": sources, &"tile_size": [tile_set.tile_size.x, tile_set.tile_size.y] if tile_set else [0, 0] }


func _get_used_cells(args: Dictionary) -> Dictionary:
	var tilemap: TileMapLayer = _find_tilemap(args)
	if not tilemap:
		return { &"err": "TileMapLayer not found at: " + args[&"node_path"] }

	var max_count: int = int(args.get(&"max_count", 500))
	var cells: Array[Dictionary] = []
	var used: Array[Vector2i] = tilemap.get_used_cells()

	for i: int in mini(used.size(), max_count):
		var pos: Vector2i = used[i]
		cells.append({ &"x": pos.x, &"y": pos.y, &"source_id": tilemap.get_cell_source_id(pos) })

	return { &"cells": cells, &"total": used.size() }

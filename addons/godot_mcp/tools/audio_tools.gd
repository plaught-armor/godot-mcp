@tool
extends RefCounted

class_name AudioTools
## Audio bus and player tools for MCP.
## Handles: audio_edit (get_buses, add_bus, set_bus, add_effect, add_player, info)

var _editor_plugin: EditorPlugin = null
var _utils: ToolUtils


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_utils(utils: ToolUtils) -> void:
	_utils = utils


func audio(args: Dictionary) -> Dictionary:
	args.merge(args.get(&"properties", {}))
	var action: String = args[&"action"]
	match action:
		&"list":
			return _get_buses()
		&"add":
			return _add_bus(args)
		&"set":
			return _set_bus(args)
		&"effect":
			return _add_effect(args)
		&"player":
			return _add_player(args)
		&"info":
			return _info(args)
		_:
			return { &"err": "Unknown audio_edit action: " + action }


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


func _get_buses() -> Dictionary:
	var buses: Array[Dictionary] = []
	for i: int in range(AudioServer.bus_count):
		var effects: Array[Dictionary] = []
		for j: int in range(AudioServer.get_bus_effect_count(i)):
			var effect: AudioEffect = AudioServer.get_bus_effect(i, j)
			effects.append({ &"index": j, &"type": effect.get_class(), &"enabled": AudioServer.is_bus_effect_enabled(i, j) })
		buses.append({
			&"index": i, &"name": AudioServer.get_bus_name(i),
			&"volume_db": AudioServer.get_bus_volume_db(i),
			&"solo": AudioServer.is_bus_solo(i), &"mute": AudioServer.is_bus_mute(i),
			&"send": AudioServer.get_bus_send(i), &"effects": effects,
		})
	return { &"buses": buses }


func _add_bus(args: Dictionary) -> Dictionary:
	var bus_name: String = args[&"name"]
	for i: int in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == bus_name:
			return { &"err": "Bus already exists: " + bus_name }

	var at_position: int = int(args.get(&"at_position", -1))
	AudioServer.add_bus(at_position)
	var idx: int = AudioServer.bus_count - 1 if at_position < 0 else at_position
	AudioServer.set_bus_name(idx, bus_name)

	if args.has(&"volume_db"):
		AudioServer.set_bus_volume_db(idx, float(args[&"volume_db"]))
	if args.has(&"send"):
		AudioServer.set_bus_send(idx, args[&"send"])
	if args.has(&"solo"):
		AudioServer.set_bus_solo(idx, bool(args[&"solo"]))
	if args.has(&"mute"):
		AudioServer.set_bus_mute(idx, bool(args[&"mute"]))

	return { &"index": idx }


func _set_bus(args: Dictionary) -> Dictionary:
	var bus_name: String = args[&"name"]
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return { &"err": "Bus not found: " + bus_name }

	if args.has(&"volume_db"):
		AudioServer.set_bus_volume_db(idx, float(args[&"volume_db"]))
	if args.has(&"solo"):
		AudioServer.set_bus_solo(idx, bool(args[&"solo"]))
	if args.has(&"mute"):
		AudioServer.set_bus_mute(idx, bool(args[&"mute"]))
	if args.has(&"send"):
		AudioServer.set_bus_send(idx, args[&"send"])
	if args.has(&"rename"):
		AudioServer.set_bus_name(idx, args[&"rename"])

	return {}


func _add_effect(args: Dictionary) -> Dictionary:
	var bus_name: String = args[&"bus"]
	var effect_type: String = args[&"effect_type"]
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return { &"err": "Bus not found: " + bus_name }

	var effect_params: Dictionary = args.get(&"params", {})
	var effect: AudioEffect

	match effect_type.to_lower():
		&"reverb":
			var e := AudioEffectReverb.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"chorus":
			var e := AudioEffectChorus.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"delay":
			var e := AudioEffectDelay.new()
			for k: String in effect_params:
				if k in e: e.set(k, effect_params[k])
			effect = e
		&"compressor":
			var e := AudioEffectCompressor.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"limiter":
			var e := AudioEffectLimiter.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"phaser":
			var e := AudioEffectPhaser.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"distortion":
			var e := AudioEffectDistortion.new()
			for k: String in effect_params:
				if k in e: e.set(k, effect_params[k])
			effect = e
		&"lowpass":
			var e := AudioEffectLowPassFilter.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"highpass":
			var e := AudioEffectHighPassFilter.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"bandpass":
			var e := AudioEffectBandPassFilter.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		&"amplify":
			var e := AudioEffectAmplify.new()
			for k: String in effect_params:
				if k in e: e.set(k, float(effect_params[k]))
			effect = e
		_:
			return { &"err": "Unknown effect_type: " + effect_type }

	AudioServer.add_bus_effect(bus_idx, effect, int(args.get(&"at_position", -1)))
	return {}


func _add_player(args: Dictionary) -> Dictionary:
	var root: Node = _get_edited_root()
	if not root:
		return { &"err": "No scene open" }
	var parent: Node = _find_node(args[&"node_path"])
	if not parent:
		return { &"err": "Node not found" }

	var player_type: String = args.get(&"type", "AudioStreamPlayer")
	var player: Node
	match player_type:
		"AudioStreamPlayer": player = AudioStreamPlayer.new()
		"AudioStreamPlayer2D": player = AudioStreamPlayer2D.new()
		"AudioStreamPlayer3D": player = AudioStreamPlayer3D.new()
		_:
			return { &"err": "Invalid type: " + player_type }

	player.name = args[&"name"]

	if args.has(&"stream"):
		var stream_path: String = args[&"stream"]
		if ResourceLoader.exists(stream_path):
			var stream: Variant = ResourceLoader.load(stream_path)
			if stream is AudioStream:
				player.set(&"stream", stream)
	if args.has(&"volume_db"):
		player.set(&"volume_db", float(args[&"volume_db"]))
	if args.has(&"bus"):
		player.set(&"bus", args[&"bus"])
	if args.has(&"autoplay"):
		player.set(&"autoplay", bool(args[&"autoplay"]))

	parent.add_child(player)
	player.owner = root
	return { &"node_path": str(root.get_path_to(player)) }


func _info(args: Dictionary) -> Dictionary:
	var node: Node = _find_node(args[&"node_path"])
	if not node:
		return { &"err": "Node not found" }

	var players: Array[Dictionary] = []
	_collect_players(node, players)
	return { &"players": players }


func _collect_players(node: Node, result: Array[Dictionary]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		var root: Node = _get_edited_root()
		var stream: Variant = node.get(&"stream")
		result.append({
			&"path": str(root.get_path_to(node)) if root else str(node.name),
			&"type": node.get_class(),
			&"volume_db": node.get(&"volume_db"),
			&"bus": node.get(&"bus"),
			&"stream": stream.resource_path if stream is AudioStream else "",
		})
	for child: Node in node.get_children():
		_collect_players(child, result)

@tool
extends RefCounted

class_name ToolUtils
## Shared utility functions used across all MCP tool handlers.

const SKIP_PROPS: Dictionary = {
	&"script": true,
	&"owner": true,
	&"scene_file_path": true,
	&"unique_name_in_owner": true,
	&"editor_description": true,
}

var _editor_plugin: EditorPlugin = null


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

# =============================================================================
# Filesystem helpers
# =============================================================================


## Tell Godot to rescan the filesystem.
func refresh_filesystem() -> void:
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	elif Engine.is_editor_hint():
		var editor_interface: Object = Engine.get_singleton("EditorInterface")
		if editor_interface:
			editor_interface.get_resource_filesystem().scan()


func ensure_res_path(path: String) -> String:
	if path.begins_with(&"uid://"):
		var uid: int = ResourceUID.text_to_id(path)
		if uid != -1 and ResourceUID.has_id(uid):
			return ResourceUID.get_id_path(uid)
		return path
	if path.is_valid_int():
		var uid: int = int(path)
		if ResourceUID.has_id(uid):
			return ResourceUID.get_id_path(uid)
		return path
	if not path.begins_with("res://"):
		path = "res://" + path
	return path


## Return a safe [code]res://[/code] path, or empty string if it escapes the project root.
func validate_res_path(path: String) -> String:
	path = ensure_res_path(path)
	var abs: String = ProjectSettings.globalize_path(path)
	var root: String = ProjectSettings.globalize_path("res://")
	if not abs.begins_with(root):
		return ""
	return path

# =============================================================================
# Serialization
# =============================================================================


## Serialize Godot types to compact string format.
func serialize_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return "V2(%s,%s)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "V3(%s,%s,%s)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return "C(%s,%s,%s,%s)" % [value.r, value.g, value.b, value.a]
		TYPE_VECTOR2I:
			return "V2i(%s,%s)" % [value.x, value.y]
		TYPE_VECTOR3I:
			return "V3i(%s,%s,%s)" % [value.x, value.y, value.z]
		TYPE_RECT2:
			return "R2(%s,%s,%s,%s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_OBJECT:
			if value is Resource and value.resource_path:
				return value.resource_path
			return null
		_:
			return value


## Convert an array of uniform dicts to header + rows format for token savings.
func tabular(items: Array, keys: Array[StringName]) -> Dictionary:
	var rows: Array[Array] = []
	for item: Dictionary in items:
		var row: Array = []
		for k: StringName in keys:
			row.append(item.get(k))
		rows.append(row)
	return { &"_h": keys, &"rows": rows }

# =============================================================================
# Type conversion
# =============================================================================


## Convert Godot type ID to human-readable name.
func type_id_to_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "String"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR2I:
			return "Vector2i"
		TYPE_RECT2:
			return "Rect2"
		TYPE_RECT2I:
			return "Rect2i"
		TYPE_VECTOR3:
			return "Vector3"
		TYPE_VECTOR3I:
			return "Vector3i"
		TYPE_TRANSFORM2D:
			return "Transform2D"
		TYPE_VECTOR4:
			return "Vector4"
		TYPE_VECTOR4I:
			return "Vector4i"
		TYPE_PLANE:
			return "Plane"
		TYPE_QUATERNION:
			return "Quaternion"
		TYPE_AABB:
			return "AABB"
		TYPE_BASIS:
			return "Basis"
		TYPE_TRANSFORM3D:
			return "Transform3D"
		TYPE_PROJECTION:
			return "Projection"
		TYPE_COLOR:
			return "Color"
		TYPE_STRING_NAME:
			return "StringName"
		TYPE_NODE_PATH:
			return "NodePath"
		TYPE_RID:
			return "RID"
		TYPE_OBJECT:
			return "Object"
		TYPE_CALLABLE:
			return "Callable"
		TYPE_SIGNAL:
			return "Signal"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_ARRAY:
			return "Array"
		TYPE_PACKED_BYTE_ARRAY:
			return "PackedByteArray"
		TYPE_PACKED_INT32_ARRAY:
			return "PackedInt32Array"
		TYPE_PACKED_INT64_ARRAY:
			return "PackedInt64Array"
		TYPE_PACKED_FLOAT32_ARRAY:
			return "PackedFloat32Array"
		TYPE_PACKED_FLOAT64_ARRAY:
			return "PackedFloat64Array"
		TYPE_PACKED_STRING_ARRAY:
			return "PackedStringArray"
		TYPE_PACKED_VECTOR2_ARRAY:
			return "PackedVector2Array"
		TYPE_PACKED_VECTOR3_ARRAY:
			return "PackedVector3Array"
		TYPE_PACKED_COLOR_ARRAY:
			return "PackedColorArray"
		_:
			return "Variant"

# =============================================================================
# Editor node traversal
# =============================================================================


## Recursively find first child node matching the given class name.
func find_node_by_class(root: Node, cls_name: StringName) -> Node:
	if root.get_class() == cls_name:
		return root
	for child: Node in root.get_children():
		var found: Node = find_node_by_class(child, cls_name)
		if found:
			return found
	return null


## Recursively find first [RichTextLabel] descendant.
func find_child_rtl(node: Node) -> RichTextLabel:
	for child: Node in node.get_children():
		if child is RichTextLabel:
			return child
		var found: RichTextLabel = find_child_rtl(child)
		if found:
			return found
	return null

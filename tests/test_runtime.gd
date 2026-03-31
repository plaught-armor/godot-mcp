extends RefCounted
## Tests for mcp_runtime.gd value serialization/deserialization.
## These test the pure functions without needing a running game.

var _runtime # mcp_runtime.gd instance (untyped — methods not on Node base)


func _init() -> void:
	_runtime = load("res://addons/godot_mcp/mcp_runtime.gd").new()


func test_serialize_primitives() -> String:
	if _runtime._serialize_value(null) != null:
		return "null should serialize to null"
	if _runtime._serialize_value(42) != 42:
		return "int should pass through"
	if _runtime._serialize_value(3.14) != 3.14:
		return "float should pass through"
	if _runtime._serialize_value("hello") != "hello":
		return "string should pass through"
	if _runtime._serialize_value(true) != true:
		return "bool should pass through"
	return ""


func test_serialize_vector2() -> String:
	var result: Variant = _runtime._serialize_value(Vector2(1.0, 2.0))
	if not str(result).begins_with("V2("):
		return "Vector2 should start with V2(, got: " + str(result)
	return ""


func test_serialize_vector3() -> String:
	var result: Variant = _runtime._serialize_value(Vector3(1.0, 2.0, 3.0))
	if not str(result).begins_with("V3("):
		return "Vector3 should start with V3(, got: " + str(result)
	return ""


func test_serialize_color() -> String:
	var result: Variant = _runtime._serialize_value(Color(1.0, 0.0, 0.0, 1.0))
	if not str(result).begins_with("C("):
		return "Color should start with C(, got: " + str(result)
	return ""


func test_serialize_array() -> String:
	var result: Variant = _runtime._serialize_value([1, "two", Vector2.ZERO])
	if result is not Array:
		return "Array should serialize to Array"
	if result[0] != 1 or result[1] != "two":
		return "Array first elements wrong: " + str(result)
	if not str(result[2]).begins_with("V2("):
		return "Array V2 element wrong: " + str(result[2])
	return ""


func test_serialize_dictionary() -> String:
	var result: Variant = _runtime._serialize_value({"key": Vector2(1, 2)})
	if result is not Dictionary:
		return "Dict should serialize to Dict"
	if not str(result["key"]).begins_with("V2("):
		return "Dict value wrong: " + str(result)
	return ""


func test_serialize_node_path() -> String:
	var result: Variant = _runtime._serialize_value(NodePath("/root/Main"))
	if result != "NP(/root/Main)":
		return "NodePath expected NP(/root/Main), got: " + str(result)
	return ""


func test_deserialize_vector2() -> String:
	var result: Variant = _runtime._deserialize_value("V2(3.5,7.2)")
	if result is not Vector2:
		return "Expected Vector2, got: " + str(typeof(result))
	if not is_equal_approx(result.x, 3.5) or not is_equal_approx(result.y, 7.2):
		return "V2 values wrong: " + str(result)
	return ""


func test_deserialize_vector3() -> String:
	var result: Variant = _runtime._deserialize_value("V3(1,2,3)")
	if result is not Vector3:
		return "Expected Vector3, got: " + str(typeof(result))
	return ""


func test_deserialize_color() -> String:
	var result: Variant = _runtime._deserialize_value("C(1,0,0,1)")
	if result is not Color:
		return "Expected Color, got: " + str(typeof(result))
	return ""


func test_deserialize_node_path() -> String:
	var result: Variant = _runtime._deserialize_value("NP(/root/Main)")
	if result is not NodePath:
		return "Expected NodePath, got: " + str(typeof(result))
	if str(result) != "/root/Main":
		return "NodePath value wrong: " + str(result)
	return ""


func test_deserialize_plain_string() -> String:
	var result: Variant = _runtime._deserialize_value("hello world")
	if result != "hello world":
		return "Plain string should pass through: " + str(result)
	return ""


func test_deserialize_legacy_dict() -> String:
	var result: Variant = _runtime._deserialize_value({&"_type": &"Vector2", &"x": 5.0, &"y": 10.0})
	if result is not Vector2:
		return "Expected Vector2 from legacy dict, got: " + str(typeof(result))
	if not is_equal_approx(result.x, 5.0) or not is_equal_approx(result.y, 10.0):
		return "Legacy dict values wrong: " + str(result)
	return ""


func test_roundtrip_vector2() -> String:
	var original: Vector2 = Vector2(42.5, -13.7)
	var serialized: Variant = _runtime._serialize_value(original)
	var deserialized: Variant = _runtime._deserialize_value(serialized)
	if deserialized is not Vector2:
		return "Roundtrip should produce Vector2"
	if not original.is_equal_approx(deserialized):
		return "Roundtrip mismatch: %s -> %s -> %s" % [original, serialized, deserialized]
	return ""


func test_roundtrip_vector3() -> String:
	var original: Vector3 = Vector3(1, 2, 3)
	var serialized: Variant = _runtime._serialize_value(original)
	var deserialized: Variant = _runtime._deserialize_value(serialized)
	if deserialized is not Vector3:
		return "Roundtrip should produce Vector3"
	return ""


func test_roundtrip_color() -> String:
	var original: Color = Color(0.5, 0.25, 0.75, 1.0)
	var serialized: Variant = _runtime._serialize_value(original)
	var deserialized: Variant = _runtime._deserialize_value(serialized)
	if deserialized is not Color:
		return "Roundtrip should produce Color"
	return ""


func test_tabular_empty() -> String:
	var result: Dictionary = _runtime._tabular([], [&"a", &"b"])
	if result[&"_h"] != [&"a", &"b"]:
		return "Headers wrong"
	if result[&"rows"].size() != 0:
		return "Should have 0 rows"
	return ""


func test_tabular_data() -> String:
	var items: Array = [{&"x": 1, &"y": 2}, {&"x": 3, &"y": 4}]
	var result: Dictionary = _runtime._tabular(items, [&"x", &"y"])
	if result[&"rows"].size() != 2:
		return "Should have 2 rows"
	if result[&"rows"][0][0] != 1 or result[&"rows"][0][1] != 2:
		return "Row 0 wrong: " + str(result[&"rows"][0])
	return ""

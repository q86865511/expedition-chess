extends RefCounted

const POLICY_PATH := "res://presentation/viewport/world_viewport_policy.gd"
const MAPPER_PATH := "res://presentation/viewport/window_coordinate_mapper.gd"


static func load_script(test: GutTest, path: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "T10 production contract missing: %s" % path)
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "T10 script must load: %s" % path)
	return resource as Script


static func require_methods(
	test: GutTest,
	target: Variant,
	method_names: Array[StringName]
) -> bool:
	for method_name: StringName in method_names:
		var present: bool = target != null and target.has_method(method_name)
		test.assert_true(present, "T10 contract requires method %s" % String(method_name))
		if not present:
			return false
	return true


static func assert_vector2_near(
	test: GutTest,
	actual: Vector2,
	expected: Vector2,
	message: String
) -> void:
	test.assert_almost_eq(actual.x, expected.x, 0.001, "%s (x)" % message)
	test.assert_almost_eq(actual.y, expected.y, 0.001, "%s (y)" % message)

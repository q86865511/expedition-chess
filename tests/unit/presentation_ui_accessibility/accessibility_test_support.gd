extends RefCounted

const SEMANTIC_TOKENS_PATH := \
	"res://presentation/accessibility/accessibility_semantic_tokens.gd"
const FOCUS_GRAPH_PATH := \
	"res://presentation/accessibility/keyboard_focus_graph.gd"
const TYPOGRAPHY_PATH := \
	"res://presentation/accessibility/localized_typography_policy.gd"
const ERROR_MAPPER_PATH := \
	"res://presentation/common/presentation_error_mapper.gd"


static func load_script(test: GutTest, path: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "T12 production contract missing: %s" % path)
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "T12 script must load: %s" % path)
	return resource as Script


static func require_methods(
	test: GutTest,
	target: Variant,
	method_names: Array[StringName],
	owner: String
) -> bool:
	for method_name: StringName in method_names:
		var present: bool = target != null and target.has_method(method_name)
		test.assert_true(
			present,
			"%s must implement %s" % [owner, String(method_name)]
		)
		if not present:
			return false
	return true


static func names(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not values is Array:
		return result
	for value: Variant in values:
		result.append(StringName(value))
	return result

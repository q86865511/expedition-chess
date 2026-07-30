extends RefCounted

const VALIDATOR_PATH := "res://tools/presentation_ui_static_gate.gd"
const EXPECTED_METHOD_SIGNATURE := \
	"func validate_candidate(candidate: Dictionary) -> Dictionary"
const EXPECTED_PROJECT_METHOD_PREFIX := "func validate_project(root_path: String"


static func load_validator(test: GutTest) -> Object:
	var exists := FileAccess.file_exists(VALIDATOR_PATH)
	test.assert_true(
		exists,
		"T14 production static validator missing: %s" % VALIDATOR_PATH
	)
	if not exists:
		return null
	var source := FileAccess.get_file_as_string(VALIDATOR_PATH)
	test.assert_true(
		source.contains(EXPECTED_METHOD_SIGNATURE),
		"T14 validator must expose typed candidate API: %s" % EXPECTED_METHOD_SIGNATURE
	)
	test.assert_true(
		source.contains(EXPECTED_PROJECT_METHOD_PREFIX),
		"T14 validator must expose a filesystem project entry point"
	)
	var resource := load(VALIDATOR_PATH)
	test.assert_not_null(resource, "T14 validator script must load")
	if resource == null:
		return null
	var validator: Object = (resource as Script).new()
	test.assert_not_null(validator, "T14 validator must instantiate")
	if validator == null:
		return null
	test.assert_true(
		validator.has_method(&"validate_candidate"),
		"T14 validator must implement validate_candidate"
	)
	test.assert_true(
		validator.has_method(&"validate_project"),
		"T14 validator must implement validate_project"
	)
	return validator


static func validate(test: GutTest, candidate: Dictionary) -> Dictionary:
	var validator := load_validator(test)
	if validator == null or not validator.has_method(&"validate_candidate"):
		return {}
	var report: Variant = validator.call(&"validate_candidate", candidate)
	test.assert_true(report is Dictionary, "T14 report must be a Dictionary")
	if not report is Dictionary:
		return {}
	var typed_report: Dictionary = report
	test.assert_true(typed_report.has("ok"), "T14 report requires ok")
	test.assert_true(typed_report.has("exit_code"), "T14 report requires exit_code")
	test.assert_true(typed_report.has("issues"), "T14 report requires issues")
	return typed_report


static func assert_clean(test: GutTest, report: Dictionary) -> void:
	if report.is_empty():
		return
	test.assert_true(report.get("ok", false), "clean production candidate must pass")
	test.assert_eq(report.get("exit_code", -1), 0, "clean candidate exit code must be zero")
	var issues: Variant = report.get("issues", [])
	test.assert_true(issues is Array, "issues must be an Array")
	if issues is Array:
		test.assert_eq((issues as Array).size(), 0, "clean candidate must have zero issues")


static func assert_rejected_with(
	test: GutTest,
	report: Dictionary,
	expected_code: StringName
) -> void:
	if report.is_empty():
		return
	test.assert_false(report.get("ok", true), "%s must reject candidate" % expected_code)
	test.assert_ne(
		report.get("exit_code", 0),
		0,
		"%s must produce a non-zero gate status" % expected_code
	)
	var issues: Variant = report.get("issues", [])
	test.assert_true(issues is Array, "issues must be an Array")
	if not issues is Array:
		return
	var found := false
	for issue: Variant in issues:
		if issue is Dictionary and StringName(issue.get("code", "")) == expected_code:
			found = true
			test.assert_ne(
				String(issue.get("path", "")),
				"",
				"%s issue must name its source path" % expected_code
			)
	test.assert_true(found, "expected named issue %s, got %s" % [expected_code, issues])


static func append_source(candidate: Dictionary, path: String, suffix: String) -> void:
	var sources: Dictionary = candidate["sources"]
	sources[path] = String(sources.get(path, "")) + suffix

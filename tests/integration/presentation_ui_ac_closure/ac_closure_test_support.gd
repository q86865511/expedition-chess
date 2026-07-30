extends RefCounted

const BOOTSTRAP_RESULT_PATH := \
	"res://app/content/project_content_bootstrap_result.gd"
const TUNE_VIEW_MODEL_PATH := \
	"res://presentation/viewmodels/run_tune_view_model.gd"
const WORLD_HOST_PATH := \
	"res://presentation/viewport/world_viewport_host.gd"
const UI_SCALE_ROOT_PATH := \
	"res://presentation/viewport/ui_scale_root.gd"
const ACCESSIBILITY_RENDERER_PATH := \
	"res://presentation/accessibility/accessibility_runtime_renderer.gd"
const RUNTIME_FIXTURE_PATH := \
	"res://tests/fixtures/presentation_runtime/runtime_probe.tscn"
const RUNTIME_RUNNER_PATH := \
	"res://tests/runners/presentation_runtime_screenshot_runner.gd"


static func load_script(test: GutTest, path: String, contract: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "%s missing: %s" % [contract, path])
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "%s must load: %s" % [contract, path])
	return resource as Script


static func require_methods(
	test: GutTest,
	target: Variant,
	method_names: Array[StringName],
	contract: String
) -> bool:
	for method_name: StringName in method_names:
		var present: bool = target != null and target.has_method(method_name)
		test.assert_true(
			present,
			"%s must implement %s" % [contract, String(method_name)]
		)
		if not present:
			return false
	return true


static func report_ok(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get("ok", false))

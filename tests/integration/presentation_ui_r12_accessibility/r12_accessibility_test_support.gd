extends RefCounted

const RENDERER_PATH := (
	"res://presentation/accessibility/accessibility_runtime_renderer.gd"
)
const TYPOGRAPHY_PATH := (
	"res://presentation/accessibility/localized_typography_policy.gd"
)
const FIXTURE_PATH := (
	"res://tests/fixtures/presentation_r12_accessibility/"
	+ "accessibility_runtime_probe.tscn"
)
const RUNNER_PATH := (
	"res://tests/runners/presentation_r12_accessibility_runner.gd"
)


static func load_script(
	test: GutTest,
	path: String,
	contract: String
) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "%s missing: %s" % [contract, path])
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "%s must load: %s" % [contract, path])
	return resource as Script


static func instantiate_fixture(test: GutTest) -> Control:
	var exists := ResourceLoader.exists(FIXTURE_PATH, "PackedScene")
	test.assert_true(exists, "R12-B02 runtime fixture must be importable")
	if not exists:
		return null
	var packed := load(FIXTURE_PATH) as PackedScene
	test.assert_not_null(packed)
	if packed == null:
		return null
	return test.autofree(packed.instantiate()) as Control


static func require_methods(
	test: GutTest,
	target: Variant,
	methods: Array[StringName],
	contract: String
) -> bool:
	for method_name: StringName in methods:
		var present: bool = target != null and target.has_method(method_name)
		test.assert_true(
			present,
			"%s must implement %s" % [contract, String(method_name)]
		)
		if not present:
			return false
	return true


static func ok(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get("ok", false))

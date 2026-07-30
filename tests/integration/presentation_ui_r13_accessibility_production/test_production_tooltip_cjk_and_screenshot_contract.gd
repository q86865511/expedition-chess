extends GutTest

const Support := preload(
	"res://tests/integration/"
	+ "presentation_ui_r13_accessibility_production/"
	+ "r13_accessibility_production_test_support.gd"
)


func test_run_combat_tooltip_guard_and_cjk_font_use_production_hosts() -> void:
	var root := Support.instantiate_run_combat(self)
	if root == null:
		return
	var nodes_complete := Support.require_runtime_nodes(self, root)
	var consumer := Support.load_consumer(self, root)
	if consumer == null:
		return
	for method_name: StringName in [
		&"open_accessibility_tooltip",
		&"runtime_accessibility_report",
	]:
		assert_true(
			consumer.has_method(method_name),
			"production consumer missing %s" % method_name
		)
	if not nodes_complete \
		or not consumer.has_method(&"open_accessibility_tooltip") \
		or not consumer.has_method(&"runtime_accessibility_report"):
		return

	var baseline: Variant = consumer.call(
		&"activate",
		&"theme",
		SettingsSnapshot.new()
	)
	assert_eq(StringName(baseline), &"")
	for depth: int in [0, 1, 2]:
		var accepted := consumer.call(
			&"open_accessibility_tooltip",
			depth
		) as AccessibilityTooltipResult
		assert_not_null(accepted)
		if accepted == null:
			continue
		assert_true(accepted.ok, "depth %d must be accepted" % depth)
		assert_true(accepted.accepted)
		assert_eq(accepted.opened_depth, depth)
	var before := consumer.call(
		&"runtime_accessibility_report"
	) as AccessibilityRuntimeReport
	var rejected := consumer.call(
		&"open_accessibility_tooltip",
		3
	) as AccessibilityTooltipResult
	assert_not_null(rejected)
	assert_false(rejected.ok)
	assert_false(rejected.accepted)
	assert_eq(rejected.error, &"ACCESSIBILITY_TOOLTIP_DEPTH_INVALID")
	var after := consumer.call(
		&"runtime_accessibility_report"
	) as AccessibilityRuntimeReport
	assert_not_null(before)
	assert_not_null(after)
	if before == null or after == null:
		return
	assert_true(after.ok, after.error)
	assert_eq(
		after.tooltip_opened_depth,
		before.tooltip_opened_depth,
		"invalid nesting must not partially mutate the production tooltip"
	)
	assert_lte(after.tooltip_visible_layers, 2)

	var cjk_label := root.get_node(Support.NODE_PATHS[&"cjk"]) as Label
	assert_eq(cjk_label.text, Support.REQUIRED_ZH_TW_TEXT)
	assert_true(cjk_label.has_theme_font_override(&"font"))
	assert_true(after.cjk_ok)
	assert_true(after.cjk_readable)
	assert_eq(after.cjk_missing_glyphs, [])
	assert_eq(
		after.cjk_font_source,
		LocalizedTypographyPolicy.FONT_SOURCE_SYSTEM
	)


func test_production_screenshot_runner_uses_no_accessibility_fixture() -> void:
	assert_true(FileAccess.file_exists(Support.RUNNER_PATH))
	if not FileAccess.file_exists(Support.RUNNER_PATH):
		return
	var source := FileAccess.get_file_as_string(Support.RUNNER_PATH)
	assert_true(source.contains(Support.RUN_COMBAT_SCENE_PATH))
	assert_true(source.contains(Support.CONSUMER_PATH))
	assert_false(
		source.contains("tests/fixtures/"),
		"R13 production screenshot evidence must not inject a test fixture"
	)
	for case_name: String in [
		"baseline-full",
		"motion-reduced",
		"flash-reduced",
		"particles-reduced",
		"density-off",
		"density-reduced",
		"density-full",
	]:
		assert_true(
			source.contains(case_name),
			"runner must capture independently identifiable %s" % case_name
		)

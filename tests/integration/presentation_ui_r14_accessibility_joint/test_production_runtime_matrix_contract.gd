extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

const CASES: Array[Dictionary] = [
	{"name": "baseline-720", "size": Vector2i(1280, 720), "ui": 100, "color": &"default"},
	{"name": "resolution-1080", "size": Vector2i(1920, 1080), "ui": 100, "color": &"default"},
	{"name": "resolution-1440", "size": Vector2i(2560, 1440), "ui": 100, "color": &"default"},
	{"name": "aspect-4x3", "size": Vector2i(1024, 768), "ui": 100, "color": &"default"},
	{"name": "aspect-16x10", "size": Vector2i(1280, 800), "ui": 100, "color": &"default"},
	{"name": "ui-125", "size": Vector2i(1280, 720), "ui": 125, "color": &"default"},
	{"name": "ui-150", "size": Vector2i(1280, 720), "ui": 150, "color": &"default"},
	{"name": "color-protanopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"protanopia"},
	{"name": "color-deuteranopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"deuteranopia"},
	{"name": "color-tritanopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"tritanopia"},
]


func test_layered_matrix_declares_every_required_dimension_without_fixture_scenes() -> void:
	assert_eq(CASES.size(), 10)
	var sizes: Array[Vector2i] = []
	var ui_scales: Array[int] = []
	var color_modes: Array[StringName] = []
	var has_four_by_three := false
	var has_sixteen_by_ten := false
	for case: Dictionary in CASES:
		var size: Vector2i = case["size"]
		var ui_scale: int = case["ui"]
		var color_mode: StringName = case["color"]
		var ratio := float(size.x) / float(size.y)
		has_four_by_three = (
			has_four_by_three
			or is_equal_approx(ratio, 4.0 / 3.0)
		)
		has_sixteen_by_ten = (
			has_sixteen_by_ten
			or is_equal_approx(ratio, 16.0 / 10.0)
		)
		if not sizes.has(size):
			sizes.append(size)
		if not ui_scales.has(ui_scale):
			ui_scales.append(ui_scale)
		if not color_modes.has(color_mode):
			color_modes.append(color_mode)
	assert_has(sizes, Vector2i(1280, 720))
	assert_has(sizes, Vector2i(1920, 1080))
	assert_has(sizes, Vector2i(2560, 1440))
	assert_true(has_four_by_three)
	assert_true(has_sixteen_by_ten)
	assert_eq(ui_scales, [100, 125, 150])
	assert_eq(
		color_modes,
		[&"default", &"protanopia", &"deuteranopia", &"tritanopia"]
	)
	var runner_source := FileAccess.get_file_as_string(
		"res://tests/runners/presentation_r14_production_runtime_runner.gd"
	)
	assert_false(runner_source.contains("tests/fixtures/"))
	assert_false(runner_source.contains("PresentationSettingsRuntimeConsumer.new"))
	assert_false(runner_source.contains("consumer.activate"))
	assert_true(runner_source.contains("ApplicationRoot"))
	assert_true(runner_source.contains("settings_application_port"))
	assert_true(runner_source.contains("RUN_COMBAT"))


func test_machine_checks_cover_focus_cues_clipping_and_all_pointer_spaces() -> void:
	for case: Dictionary in CASES:
		var mapping := Support.mapping_report(
			case["size"] as Vector2i,
			int(case["ui"])
		)
		assert_true(
			bool(mapping.get("ok", false)),
			"%s must preserve world/Camp/UI pointer round trips"
			% String(case["name"])
		)
		assert_true(bool((mapping["world"] as Dictionary)["same_tile"]))
		assert_true(bool((mapping["camp"] as Dictionary)["same_hotspot"]))
		assert_true(bool((mapping["ui"] as Dictionary)["same_control"]))
	var source := FileAccess.get_file_as_string(
		"res://tests/integration/presentation_ui_r14_accessibility_joint/"
		+ "r14_accessibility_joint_test_support.gd"
	)
	for token: String in [
		"focus_not_visible",
		"non_color_action_cues_missing",
		"required_controls_clipped",
		"pointer_mapping_failed",
		"color_mode_runtime_mismatch",
		"ui_scale_runtime_mismatch",
	]:
		assert_true(
			source.contains(token),
			"machine report must name `%s`" % token
		)

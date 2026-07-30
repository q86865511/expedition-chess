extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_r12_accessibility/"
	+ "r12_accessibility_test_support.gd"
)


func test_tooltip_depth_above_two_is_named_rejection_without_partial_apply() -> void:
	var script := Support.load_script(
		self,
		Support.RENDERER_PATH,
		"R12-B02 tooltip runtime guard"
	)
	var fixture := Support.instantiate_fixture(self)
	if script == null or fixture == null:
		return
	var renderer: Variant = script.new()
	if not Support.require_methods(
		self,
		renderer,
		[&"open_tooltip", &"tooltip_report", &"tooltip_max_depth"],
		"R12-B02 tooltip runtime guard"
	):
		return
	assert_eq(renderer.call(&"tooltip_max_depth"), 2)

	for depth: int in [0, 1, 2]:
		var accepted: Variant = renderer.call(&"open_tooltip", fixture, depth)
		assert_true(Support.ok(accepted), "depth %d" % depth)
		assert_eq(accepted.get("opened_depth"), depth)
		var report: Variant = renderer.call(&"tooltip_report", fixture)
		assert_true(Support.ok(report))
		assert_eq(report.get("opened_depth"), depth)
		assert_lte(int(report.get("visible_layers", -1)), 2)

	var before: Variant = renderer.call(&"tooltip_report", fixture)
	for invalid_depth: int in [-1, 3, 99]:
		var rejected: Variant = renderer.call(
			&"open_tooltip",
			fixture,
			invalid_depth
		)
		assert_false(Support.ok(rejected))
		assert_eq(
			rejected.get("error"),
			&"ACCESSIBILITY_TOOLTIP_DEPTH_INVALID"
		)
		assert_eq(rejected.get("accepted"), false)
		assert_eq(
			renderer.call(&"tooltip_report", fixture),
			before,
			"invalid tooltip depth must not partially mutate runtime state"
		)

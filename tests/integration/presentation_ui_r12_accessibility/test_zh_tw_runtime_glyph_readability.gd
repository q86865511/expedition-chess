extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_r12_accessibility/"
	+ "r12_accessibility_test_support.gd"
)
const REQUIRED_ZH_TW_PROBE := "遠征棋設定羈絆稀有度傷害提示"


func test_zh_tw_probe_has_engine_font_fallback_and_all_required_glyphs() -> void:
	var script := Support.load_script(
		self,
		Support.TYPOGRAPHY_PATH,
		"R12-B02 zh_TW runtime typography"
	)
	var fixture := Support.instantiate_fixture(self)
	if script == null or fixture == null:
		return
	var typography: Variant = script.new()
	if not Support.require_methods(
		self,
		typography,
		[&"readability_report", &"apply_to"],
		"R12-B02 zh_TW runtime typography"
	):
		return

	var report: Variant = typography.call(
		&"readability_report",
		&"zh_TW",
		REQUIRED_ZH_TW_PROBE
	)
	assert_true(Support.ok(report))
	if not Support.ok(report):
		return
	assert_eq(report.get("locale"), &"zh_TW")
	assert_eq(report.get("primary_font_token"), &"font.cjk")
	assert_false(String(report.get("font_source", "")).is_empty())
	assert_true(bool(report.get("font_available", false)))
	assert_true(bool(report.get("readable", false)))
	assert_gt(int(report.get("required_glyph_count", 0)), 0)
	assert_eq(report.get("missing_glyphs", []), [])
	var measured: Variant = report.get("measured_size")
	assert_true(
		measured is Vector2
		and (measured as Vector2).x > 0.0
		and (measured as Vector2).y > 0.0
	)

	var label := fixture.get_node(^"CjkProbe") as Label
	var applied: Variant = typography.call(
		&"apply_to",
		label,
		&"zh_TW",
		REQUIRED_ZH_TW_PROBE
	)
	assert_true(Support.ok(applied))
	assert_eq(label.text, REQUIRED_ZH_TW_PROBE)
	assert_true(label.has_theme_font_override(&"font"))
	assert_not_null(label.get_theme_font(&"font"))

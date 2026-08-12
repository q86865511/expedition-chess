extends GutTest

const RUNNER_PATH := (
	"res://tests/runners/presentation_phase_b1_evidence_runner.gd"
)
const SCRIPT_PATH := "res://tools/run-isolated-ui-evidence.ps1"


func test_evidence_runner_declares_the_nine_case_matrix() -> void:
	var source := FileAccess.get_file_as_string(RUNNER_PATH)
	var matcher := RegEx.new()
	assert_eq(
		matcher.compile(
			"\\{\\\"name\\\": \\\"(720p|1080p|1440p)-ui(100|125|150)\\\""
		),
		OK
	)
	assert_eq(matcher.search_all(source).size(), 9)
	assert_true(source.contains("content_scale_size = UI_REFERENCE_SIZE"))
	assert_true(source.contains("const UI_REFERENCE_SIZE := Vector2i(1920, 1080)"))
	assert_true(source.contains("res://specs/in-run-hud/evidence"))
	assert_true(source.contains("const BASELINE_REPORT_CASE_COUNT := 128"))
	assert_true(source.contains("const SHOP_TIER_EVIDENCE_CASE_COUNT := 9"))
	assert_true(source.contains("prepare-shop-tiers-%s.png"))
	assert_true(source.contains("ProjectContentBootstrap.new().run"))
	assert_true(source.contains("ShopOfferPreviewViewModel.new"))
	assert_true(source.contains("prepare_shop_tier_styles_not_distinct"))
	assert_true(source.contains("prepare_shop_tier_non_color_cue"))
	assert_true(source.contains("prepare_shop_tier_cue_contract"))
	assert_true(source.contains("prepare_shop_tier_shape_count"))
	assert_true(source.contains("prepare_shop_tier_shape_geometry"))
	assert_true(source.contains("_shop_tier_cue_has_visible_geometry"))
	assert_true(source.contains("tier_cues.get_child_count() != tier"))
	assert_true(source.contains("shape.custom_minimum_size.x <= 0.0"))
	assert_true(source.contains("shape.custom_minimum_size.y <= 0.0"))
	assert_true(source.contains("not shape.get_global_rect().has_area()"))
	assert_true(source.contains("variations.size() != 5"))
	assert_true(source.contains("style_signatures.size() != 5"))
	assert_true(source.contains("prepare_shop_tier_accessibility_copy"))
	assert_true(source.contains("prepare_shop_tier_raw_unit_identity"))
	assert_true(source.contains("prepare_shop_tier_raw_trait_identity"))
	assert_true(source.contains("_scroll_ancestor_chain"))
	assert_true(source.contains("prepare_action_does_not_fit_viewport"))
	assert_true(source.contains("prepare_action_focus_clipped_in_viewport"))
	assert_false(source.contains("_install_evidence_world"))
	assert_false(source.contains("EvidenceViewportRoot"))
	assert_false(source.contains("ProductionWorldSurface.new()"))
	assert_false(source.contains("ProductionViewportCoordinator.new()"))
	assert_true(source.contains("surfaces.size() == 1"))
	assert_false(source.contains("specs/ui-art-refresh/evidence"))


func test_isolated_script_restricts_output_to_in_run_hud_evidence() -> void:
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_true(source.contains("'1280x720', '1920x1080', '2560x1440'"))
	assert_true(source.contains("specs\\in-run-hud\\evidence"))
	assert_true(source.contains("Evidence output must remain below"))
	assert_true(source.contains("--output-dir=$evidenceResPath"))
	assert_false(source.contains("specs\\ui-art-refresh\\evidence"))

extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_responsive_color/"
	+ "r14_responsive_color_test_support.gd"
)


func test_four_color_modes_change_real_visible_semantic_styling() -> void:
	var signatures: Dictionary[StringName, String] = {}
	for mode: StringName in [
		&"default",
		&"protanopia",
		&"deuteranopia",
		&"tritanopia",
	]:
		var screen := Support.instantiate_combat(self, Vector2(1280, 720))
		if screen == null:
			return
		var snapshot := SettingsSnapshot.new()
		snapshot.color_vision_mode = mode
		Support.activate(self, Support.consumer(screen), snapshot)
		signatures[mode] = Support.visual_signature(screen)
		var runtime := Support.accessibility_runtime(screen)
		assert_eq(
			StringName(runtime.get_meta(&"effective_color_vision_mode", &"")),
			mode,
			"runtime must report the mode actually rendered by visible nodes"
		)
	var unique: Dictionary[String, bool] = {}
	for signature: String in signatures.values():
		unique[signature] = true
	assert_eq(
		unique.size(),
		4,
		"mode evidence must differ through meaningful visible styling"
	)


func test_color_mode_keeps_text_and_pattern_cues_visible() -> void:
	for mode: StringName in [
		&"default",
		&"protanopia",
		&"deuteranopia",
		&"tritanopia",
	]:
		var screen := Support.instantiate_combat(self, Vector2(1280, 720))
		if screen == null:
			return
		var snapshot := SettingsSnapshot.new()
		snapshot.color_vision_mode = mode
		Support.activate(self, Support.consumer(screen), snapshot)
		var runtime := Support.accessibility_runtime(screen)
		var rule := runtime.get_node_or_null("RuleInformation") as Label
		var summary := runtime.get_node_or_null("StateSummary") as Label
		assert_not_null(rule)
		assert_not_null(summary)
		if rule != null:
			assert_false(rule.text.strip_edges().is_empty())
		if summary != null:
			assert_false(summary.text.strip_edges().is_empty())
		assert_false(
			String(runtime.get_meta(&"semantic_pattern_token", "")).is_empty(),
			"color changes must retain a visible non-color pattern cue"
		)

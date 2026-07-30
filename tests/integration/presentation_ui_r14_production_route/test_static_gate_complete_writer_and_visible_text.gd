extends GutTest

const Candidate = preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/"
	+ "minimal_static_gate_candidate.gd"
)
const StaticSupport = preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_complete_raw_writer_and_facade_type_set_is_rejected() -> void:
	for writer_type: String in [
		"RunPresentationSession",
		"RunCommandFactory",
		"ApplicationRoot",
		"CampController",
		"RunController",
		"SaveRepository",
		"SettingsRepository",
	]:
		var candidate := Candidate.build()
		StaticSupport.append_source(
			candidate,
			"res://presentation/screens/forbidden_%s.gd"
			% writer_type.to_snake_case(),
			"extends Control\nvar forbidden: %s\n" % writer_type
		)
		var report := StaticSupport.validate(self, candidate)
		StaticSupport.assert_rejected_with(
			self,
			report,
			&"PUI_SCREEN_WRITER_DEPENDENCY"
		)


func test_english_and_mixed_visible_scene_text_is_rejected() -> void:
	for visible_text: String in [
		"Start Expedition",
		"開始 Expedition",
	]:
		var candidate := Candidate.build()
		StaticSupport.append_source(
			candidate,
			"res://scenes/production/visible_hardcode.tscn",
			"[gd_scene format=3]\n"
			+ "[node name=\"Visible\" type=\"Label\"]\n"
			+ "text = \"%s\"\n" % visible_text
		)
		var report := StaticSupport.validate(self, candidate)
		StaticSupport.assert_rejected_with(
			self,
			report,
			&"PUI_HARDCODED_PLAYER_TEXT"
		)

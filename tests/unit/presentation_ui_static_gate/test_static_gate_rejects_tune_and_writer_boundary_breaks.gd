extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/minimal_static_gate_candidate.gd"
)
const Support := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_ui_tune_literal_duplicate_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	Support.append_source(
		candidate,
		"res://presentation/screens/menu_main.gd",
		"const MAX_PARTY_SIZE := 12\n"
	)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_UI_TUNE_DUPLICATE")


func test_production_screen_direct_writer_dependency_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	Support.append_source(
		candidate,
		"res://presentation/screens/menu_main.gd",
		"var forbidden_repository: SettingsRepository\n"
		+ "func bypass_writer() -> void:\n"
		+ "\tget_node(\"/root/SettingsService\").save(null)\n"
	)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_SCREEN_WRITER_DEPENDENCY")

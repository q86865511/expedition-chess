extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/minimal_static_gate_candidate.gd"
)
const Support := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_clean_candidate_passes_and_non_production_artifacts_are_ignored() -> void:
	var report := Support.validate(self, Candidate.build())

	Support.assert_clean(self, report)

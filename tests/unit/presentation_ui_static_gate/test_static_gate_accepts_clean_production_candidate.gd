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


func test_checked_out_production_localization_passes_reference_gate() -> void:
	var validator := Support.load_validator(self)
	if validator == null:
		return
	assert_true(validator.has_method(&"validate_localization_project"))
	var report: Variant = validator.call(&"validate_localization_project", "res://")
	assert_true(report is Dictionary)
	if not report is Dictionary:
		return
	Support.assert_clean(self, report as Dictionary)
	assert_gt(
		int((report as Dictionary).get("localization_reference_count", 0)),
		0,
		"checked-out production source must expose localization references"
	)

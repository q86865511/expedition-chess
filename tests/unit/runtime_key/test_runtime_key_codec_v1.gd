extends GutTest

const VerificationSuite = preload("res://tests/fixtures/canonical/canonical_verification_suite.gd")

func test_six_typed_schemas_goldens_negatives_and_ledger() -> void:
	var report: Dictionary = VerificationSuite.new().run("RuntimeKey")
	assert_eq(int(report["case_count"]), 1)
	assert_true(int(report["assertion_count"]) >= 20)
	assert_eq((report["failures"] as Array).size(), 0, JSON.stringify(report["failures"]))

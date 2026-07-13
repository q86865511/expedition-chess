extends GutTest

const VerificationSuite = preload("res://tests/fixtures/canonical/canonical_verification_suite.gd")

func test_u64_boundaries_arithmetic_shifts_and_stable_id_contract() -> void:
	var report: Dictionary = VerificationSuite.new().run("U64")
	assert_eq(int(report["case_count"]), 1)
	assert_true(int(report["assertion_count"]) >= 20)
	assert_eq((report["failures"] as Array).size(), 0, JSON.stringify(report["failures"]))

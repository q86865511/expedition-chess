extends GutTest

const VerificationSuite = preload("res://tests/fixtures/canonical/canonical_verification_suite.gd")

func test_1559_byte_golden_round_trip_and_hash_builder() -> void:
	var report: Dictionary = VerificationSuite.new().run("BattleSetupV1")
	assert_eq(int(report["case_count"]), 1)
	assert_true(int(report["assertion_count"]) >= 10)
	assert_eq((report["failures"] as Array).size(), 0, JSON.stringify(report["failures"]))

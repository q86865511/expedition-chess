extends GutTest

const VerificationSuite = preload("res://tests/fixtures/canonical/canonical_verification_suite.gd")

func test_pcg_reference_bounded_derive_and_stream_isolation() -> void:
	var report: Dictionary = VerificationSuite.new().run("RngV1")
	assert_eq(int(report["case_count"]), 1)
	assert_true(int(report["assertion_count"]) >= 20)
	assert_eq((report["failures"] as Array).size(), 0, JSON.stringify(report["failures"]))

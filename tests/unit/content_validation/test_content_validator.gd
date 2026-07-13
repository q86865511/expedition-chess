extends GutTest

func test_valid_vertical_slice_and_population_reports() -> void:
	var baseline: Dictionary = ContentVerificationSuite.new().run("valid_slice")
	assert_true(bool(baseline["ok"]), JSON.stringify(baseline["failures"]))
	var expanded: Dictionary = ContentVerificationSuite.new().run("population_recompute")
	assert_true(bool(expanded["ok"]), JSON.stringify(expanded["failures"]))

func test_every_locked_invariant_has_a_failing_mutation() -> void:
	for mutation_name in ContentVerificationSuite.MUTATION_NAMES:
		var result: Dictionary = ContentVerificationSuite.new().run(String(mutation_name))
		assert_eq(int(result["case_count"]), 1, String(mutation_name))
		assert_true(bool(result["ok"]), "%s: %s" % [String(mutation_name), JSON.stringify(result["failures"])])

func test_validation_issue_order_is_deterministic() -> void:
	var input := SyntheticContentFixture.mutate(&"reference")
	input.definitions[0].id = &"Invalid"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	for index in range(1, report.issues.size()):
		var previous := report.issues[index - 1]
		var current := report.issues[index]
		var ordered := String(previous.code) < String(current.code)
		if previous.code == current.code:
			ordered = String(previous.source_id) < String(current.source_id)
			if previous.source_id == current.source_id:
				ordered = String(previous.field_path) <= String(current.field_path)
		assert_true(ordered, "%s/%s/%s then %s/%s/%s" % [previous.code, previous.source_id, previous.field_path, current.code, current.source_id, current.field_path])

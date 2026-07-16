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

func test_reactive_damage_cycle_requires_finite_max_uses_guard() -> void:
	var input := SyntheticContentFixture.build_valid()
	var effect: EffectDef = null
	for definition: ContentDefinition in input.definitions:
		if definition.id == &"effect.operation_matrix":
			effect = definition as EffectDef
			break
	assert_not_null(effect)
	effect.trigger = &"damaged"
	var rejected := ContentValidator.new().validate(input)
	assert_false(rejected.valid)
	assert_true(_has_issue(rejected, &"CONTENT_EFFECT_TRIGGER_CYCLE"))
	var guard := ConditionDef.new()
	guard.kind = &"max_uses_per_battle"
	guard.subject = &"effect"
	guard.comparator = &"lt"
	guard.has_max_uses_per_battle = true
	guard.max_uses_per_battle = 3
	effect.conditions.append(guard)
	var accepted := ContentValidator.new().validate(input)
	assert_true(accepted.valid, _issue_text(accepted))

func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)

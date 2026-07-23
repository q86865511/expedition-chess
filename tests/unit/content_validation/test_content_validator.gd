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

func test_expedition_generators_and_reward_stages_are_content_gated() -> void:
	var bad_generator := SyntheticContentFixture.build_valid()
	for definition: ContentDefinition in bad_generator.definitions:
		if definition.id == &"map_node.normal":
			(definition as MapNodeDef).generator_ref = &"effect.general"
			break
	var generator_report := ContentValidator.new().validate(bad_generator)
	assert_false(generator_report.valid)
	assert_true(_has_issue(generator_report, &"CONTENT_NODE_GENERATOR"))

	var missing_relic := SyntheticContentFixture.build_valid()
	for index: int in range(missing_relic.definitions.size() - 1, -1, -1):
		if missing_relic.definitions[index].id == &"reward_table.relic":
			missing_relic.definitions.remove_at(index)
			break
	var coverage_report := ContentValidator.new().validate(missing_relic)
	assert_false(coverage_report.valid)
	assert_true(_has_issue(coverage_report, &"CONTENT_REWARD_STAGE_COVERAGE"))

	var mixed := SyntheticContentFixture.build_valid()
	var mixed_table: RewardTableDef = null
	for definition: ContentDefinition in mixed.definitions:
		if definition.id == &"reward_table.default":
			mixed_table = definition as RewardTableDef
			break
	assert_not_null(mixed_table)
	var relic_candidate := RewardCandidateDef.new()
	relic_candidate.kind = &"relic"
	relic_candidate.has_content_ref = true
	relic_candidate.content_ref = &"relic.r0"
	relic_candidate.weight_i32 = 1
	mixed_table.reward_candidates.append(relic_candidate)
	var mixed_report := ContentValidator.new().validate(mixed)
	assert_false(mixed_report.valid)
	assert_true(_has_issue(mixed_report, &"CONTENT_REWARD_STAGE"))

	var conditioned := SyntheticContentFixture.build_valid()
	for definition: ContentDefinition in conditioned.definitions:
		if definition.id == &"reward_table.default":
			var condition := ConditionDef.new()
			condition.kind = &"max_uses_per_battle"
			(definition as RewardTableDef).reward_candidates[0].conditions = [condition]
			break
	var condition_report := ContentValidator.new().validate(conditioned)
	assert_false(condition_report.valid)
	assert_true(_has_issue(
		condition_report, &"CONTENT_REWARD_CONDITION"
	))

	var no_fallback := SyntheticContentFixture.build_valid()
	for definition: ContentDefinition in no_fallback.definitions:
		if definition.id == &"reward_table.default":
			var table := definition as RewardTableDef
			table.reward_candidates = [table.reward_candidates[0]]
			break
	var fallback_report := ContentValidator.new().validate(no_fallback)
	assert_false(fallback_report.valid)
	assert_true(_has_issue(fallback_report, &"CONTENT_REWARD_FALLBACK"))

# T11 wave4(specs/build-systems 內容缺口修復):EconomyConfigDef 必填欄位完整性
# 須與 EconomyExpeditionCatalogBuilder._valid_config() 一致——驗證器放行但 builder
# 拒絕即為分歧缺陷(實測見 content/packs/vertical_slice/economy_configs/
# slice_default.tres 曾缺 layer_income/xp_thresholds)。逐一清空必填欄位,驗證器皆須
# 攔下。
func test_economy_config_missing_required_fields_are_rejected() -> void:
	var missing_layer_income := SyntheticContentFixture.build_valid()
	(_find(missing_layer_income, &"economy.default") as EconomyConfigDef).layer_income = []
	var layer_income_report := ContentValidator.new().validate(missing_layer_income)
	assert_false(layer_income_report.valid)
	assert_true(_has_issue(layer_income_report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

	var missing_xp_thresholds := SyntheticContentFixture.build_valid()
	(_find(missing_xp_thresholds, &"economy.default") as EconomyConfigDef).xp_thresholds = []
	var xp_thresholds_report := ContentValidator.new().validate(missing_xp_thresholds)
	assert_false(xp_thresholds_report.valid)
	assert_true(_has_issue(xp_thresholds_report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

	var missing_unit_costs := SyntheticContentFixture.build_valid()
	(_find(missing_unit_costs, &"economy.default") as EconomyConfigDef).unit_costs_by_tier = []
	var unit_costs_report := ContentValidator.new().validate(missing_unit_costs)
	assert_false(unit_costs_report.valid)
	assert_true(_has_issue(unit_costs_report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

	var missing_odds_level := SyntheticContentFixture.build_valid()
	var config := _find(missing_odds_level, &"economy.default") as EconomyConfigDef
	config.shop_odds_by_level.remove_at(config.shop_odds_by_level.size() - 1)
	var odds_report := ContentValidator.new().validate(missing_odds_level)
	assert_false(odds_report.valid)
	assert_true(_has_issue(odds_report, &"CONTENT_SHOP_PROBABILITY"))

# W4-F5(specs/build-systems 收尾):上一個測試只覆蓋 layer_income/xp_thresholds/
# unit_costs_by_tier 三個陣列欄位,content_validator.gd 同一條 CONTENT_ECONOMY_CONFIG_INCOMPLETE
# 判斷式(content_validator.gd:299-301)還鏡射了 EconomyExpeditionCatalogBuilder._valid_config()
# 的 5 個純量欄位下限——逐一補獨立紅燈測試,每個測試只違反自己的欄位,其餘欄位維持
# SyntheticContentFixture 的合法預設值(interest_step_gold=10/gold_cap=99/reroll_cost=2/
# xp_buy_cost=4/xp_buy_amount=4,見 EconomyConfigDef 的 @export 預設)。
func test_economy_config_missing_interest_step_gold_is_rejected() -> void:
	var input := SyntheticContentFixture.build_valid()
	(_find(input, &"economy.default") as EconomyConfigDef).interest_step_gold = 0
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

func test_economy_config_missing_gold_cap_is_rejected() -> void:
	var input := SyntheticContentFixture.build_valid()
	(_find(input, &"economy.default") as EconomyConfigDef).gold_cap = 0
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

func test_economy_config_negative_reroll_cost_is_rejected() -> void:
	var input := SyntheticContentFixture.build_valid()
	(_find(input, &"economy.default") as EconomyConfigDef).reroll_cost = -1
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

func test_economy_config_missing_xp_buy_cost_is_rejected() -> void:
	var input := SyntheticContentFixture.build_valid()
	(_find(input, &"economy.default") as EconomyConfigDef).xp_buy_cost = 0
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

func test_economy_config_missing_xp_buy_amount_is_rejected() -> void:
	var input := SyntheticContentFixture.build_valid()
	(_find(input, &"economy.default") as EconomyConfigDef).xp_buy_amount = 0
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"))

# T11 wave4:此前完全沒有任何驗證器規則要求 meta_reward_table 分類存在——雙 pack
# 曾經完全沒有這個分類的內容,ContentRegistryReceiptAdapter 的 save/load 因此在
# receipt 重建階段必定失敗,卻沒有任何驗證器訊號提前攔下。
func test_missing_meta_reward_table_is_rejected() -> void:
	var fixture := SyntheticContentFixture.build_valid()
	_remove(fixture, &"meta_reward.default")
	var report := ContentValidator.new().validate(fixture)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_META_REWARD_TABLE_MISSING"))

func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in input.definitions:
		if definition.id == content_id: return definition
	return null

func _remove(input: ContentValidationInput, content_id: StringName) -> void:
	for index: int in range(input.definitions.size() - 1, -1, -1):
		if input.definitions[index].id == content_id:
			input.definitions.remove_at(index)
			return

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

extends GutTest

## S5 wave5 雙審 B5／Sonnet#3 修正（.pipeline/reviews/2026-07-25-reviewer-w5.md、
## .pipeline/reviews/2026-07-25-sonnet-w5.md）：runtime 需要 xp_thresholds 覆蓋
## economy level 1..8（新遠征從 RunBootstrapService.STARTING_ECONOMY_LEVEL==1 起步，
## 見 tests/integration/meta_progression/test_vertical_slice_xp_threshold_gap.gd），但
## content_validator.gd 與 economy_expedition_catalog_builder.gd 曾各自只驗 3..8——兩邊
## 改為驗 1..8 後，本檔鎖定「只覆蓋 3..8 的 config」必須被兩邊都具名拒絕，證明兩邊判準已
## 同步、分歧已閉合（不再重演 HANDOFF.md 記錄過的「驗證器放行、builder 拒絕」缺陷型態）。
##
## 兩個測試分別直接打各自的判準入口，不透過 ContentRegistryService.install_validated()
## 串接——該入口內部固定先跑 ContentValidator，本次同步後驗證器必定先攔下這個案例，
## 兩者在該路徑上已結構性耦合而無法個別觀察 builder 那一半，因此 builder 半改為直接呼叫
## EconomyExpeditionCatalogBuilder._valid_config()（GDScript 底線前綴僅為慣例、非語言級
## private，可直接呼叫），比照 tests/fixtures/economy/economy_test_fixture.gd 手刻
## EconomyConfigRule 的既有寫法。

func test_xp_thresholds_covering_only_levels_3_to_8_is_rejected_by_validator() -> void:
	var fixture := SyntheticContentFixture.build_valid()
	var economy := _find_economy(fixture)
	assert_not_null(economy)
	if economy == null:
		return
	economy.xp_thresholds = _def_thresholds_for_levels_3_to_8()

	var report := ContentValidator.new().validate(fixture)

	assert_false(report.valid)
	assert_true(
		_has_issue(report, &"CONTENT_ECONOMY_CONFIG_INCOMPLETE"),
		"xp_thresholds 只覆蓋 3..8（缺 1、2）時 ContentValidator 必須拒絕: %s" % _issue_text(report)
	)


func test_xp_thresholds_covering_only_levels_3_to_8_is_rejected_by_builder() -> void:
	var config := _valid_rule_config()
	config.xp_thresholds = _rule_thresholds_for_levels_3_to_8()

	var accepted := EconomyExpeditionCatalogBuilder.new()._valid_config(config)

	assert_false(
		accepted,
		"xp_thresholds 只覆蓋 3..8（缺 1、2）時 EconomyExpeditionCatalogBuilder._valid_config() 必須回 false"
	)


## 與 EconomyTestFixture.catalog() 同形狀的最小合法 EconomyConfigRule，供本檔只替換
## xp_thresholds 一個欄位做對照組（其餘欄位維持合法值，確保紅燈只反映 xp_thresholds 這個
## 判準，不被其他必填欄位污染）。
func _valid_rule_config() -> EconomyConfigRule:
	var config := EconomyConfigRule.new()
	config.config_id = &"economy.gate_parity"
	config.layer_income = [EconomyValueRule.new(0, 5)]
	config.interest_step_gold = 10
	config.interest_per_step = 1
	config.max_interest = 5
	config.gold_cap = 99
	config.reroll_cost = 2
	config.xp_buy_cost = 4
	config.xp_buy_amount = 4
	for level: int in range(3, 10):
		config.shop_odds_by_level.append(ShopOddsRule.new(level, [10000, 0, 0, 0, 0]))
	var copies := [18, 15, 12, 10, 9]
	for tier: int in range(1, 6):
		config.pool_copies_by_tier.append(EconomyValueRule.new(tier, copies[tier - 1]))
		config.unit_costs_by_tier.append(EconomyValueRule.new(tier, tier))
	config.xp_thresholds = _rule_thresholds_for_levels_1_to_8()
	return config


func _rule_thresholds_for_levels_1_to_8() -> Array[EconomyValueRule]:
	var thresholds := [2, 3, 4, 8, 16, 28, 44, 64]
	var result: Array[EconomyValueRule] = []
	for level in range(1, 9):
		result.append(EconomyValueRule.new(level, thresholds[level - 1]))
	return result


func _rule_thresholds_for_levels_3_to_8() -> Array[EconomyValueRule]:
	var thresholds := [4, 8, 16, 28, 44, 64]
	var result: Array[EconomyValueRule] = []
	for level in range(3, 9):
		result.append(EconomyValueRule.new(level, thresholds[level - 3]))
	return result


func _def_thresholds_for_levels_3_to_8() -> Array[U32PairDef]:
	var thresholds := [4, 8, 16, 28, 44, 64]
	var result: Array[U32PairDef] = []
	for level in range(3, 9):
		var pair := U32PairDef.new()
		pair.key_u32 = level
		pair.value_u32 = thresholds[level - 3]
		result.append(pair)
	return result


func _find_economy(input: ContentValidationInput) -> EconomyConfigDef:
	for definition: ContentDefinition in input.definitions:
		if definition is EconomyConfigDef:
			return definition as EconomyConfigDef
	return null


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

extends GutTest

## T06 (specs/build-systems) — 經濟型遺物在 IncomeService 決策點生效。
## Covers：REQ-RELIC-001、S4-AC-011（經濟型於 income 計算生效、決定性、依 slot_index 升序）。
## 依據 design.md §6：「經濟 -> IncomeService/ShopService 決策點 -> RunRelicTable 於
## income 計算（基礎/利息/連勝）...依槽序套用 intent；只讀 pinned rule、決定性」。
##
## 假設聲明（見 test_run_relic_table_operations.gd 的總說明）：economy 類 RunRelicRule 的
## kind == &"add_gold" 之 run_operations.amount 加總，做為「income 計算完成後、gold_cap
## 夾限前」的一次性 flat 加值；base_income/interest_income/streak_income 三個既有追蹤欄位
## 維持只反映 config 本身的計算結果（不含遺物加值），加值只反映在最終 economy_state.gold。
## IncomeQuoteRequest 新增兩個尾端可選建構參數 relic_table/active_relic_ids（預設
## null/[]），對既有呼叫端（test_map_and_income.gd 等）加值等於 0、完全不改變既有行為。

func test_baseline_without_relic_params_matches_existing_income_result() -> void:
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog()
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.base_income, 5)
	assert_eq(result.transaction.interest_income, 4)
	assert_eq(result.transaction.streak_income, 2)
	assert_eq(result.transaction.economy_state.gold, 58)

func test_single_active_economy_relic_adds_flat_gold_bonus() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 10)])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a"]
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.base_income, 5, "config-derived components stay unchanged by relic bonus")
	assert_eq(result.transaction.interest_income, 4)
	assert_eq(result.transaction.streak_income, 2)
	assert_eq(result.transaction.economy_state.gold, 68, "58 baseline + 10 relic bonus")

func test_multiple_active_economy_relics_sum_deterministically() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_economy_rule(&"relic.eco_a", 3),
		_economy_rule(&"relic.eco_b", 4),
	])
	var request := IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a", &"relic.eco_b"]
	)
	var first := IncomeService.new().quote(request)
	var second := IncomeService.new().quote(request)
	assert_true(first.ok)
	assert_true(second.ok)
	if not first.ok or not second.ok:
		return
	assert_eq(first.transaction.economy_state.gold, 65, "58 baseline + (3+4) relic bonus")
	assert_eq(second.transaction.economy_state.gold, first.transaction.economy_state.gold)
	assert_eq(
		String(second.transaction.receipt.payload_digest),
		String(first.transaction.receipt.payload_digest),
		"identical request must yield identical transaction digest (determinism)"
	)

func test_relic_bonus_is_still_clamped_by_gold_cap() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 10)])
	# base 5 + interest(80/10=8 steps -> capped at max_interest 5) + streak 2 = 92 pre-relic (< 99 cap).
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(80, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a"]
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 99, "92 + 10 relic bonus exceeds gold_cap 99 and must clamp")

func test_empty_active_relic_ids_with_non_null_table_has_no_effect() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 10)])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 58, "no active relic ids must reproduce the no-relic baseline")

func test_non_economy_category_relic_does_not_contribute_to_income() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_economy_rule(&"relic.eco_a", 6),
		_rule_category_heal_rule(&"relic.rule_a", 99),
	])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a", &"relic.rule_a"]
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 64, "only the economy-category relic's add_gold amount (6) applies; the rule-category relic must be ignored here")

func _economy_rule(relic_id: StringName, add_gold_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = add_gold_amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _rule_category_heal_rule(relic_id: StringName, heal_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"heal_expedition_hp"
	operation.amount = heal_amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"rule"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

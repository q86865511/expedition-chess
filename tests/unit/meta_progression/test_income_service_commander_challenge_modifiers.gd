extends GutTest

## T06(specs/meta-progression) — IncomeService 在既有 slot-gated 遺物加總後,再加
## 指揮官/挑戰 always-active 貢獻。
## Covers：S5-AC-003；tasks.md T06 驗收：「四個 run 層作用點消費端在 slot-gated 後加
## always-active 貢獻」(income 為其一)。
## 依據 design.md §6.1:117「各 run 層消費端(income/shop/map/settlement 作用點)在既有
## slot-gated 加總後再加 always-active 貢獻」。
##
## 基準情境沿用 tests/unit/economy_expediton/test_income_service_relics.gd 的既有 fixture
## 數值(gold=47,level=3,win_streak=5 → base=5,interest=4,streak=2,pre-relic gold=58),
## 以便讀者對照既有 S4 slot-gated 行為與本檔新增的 always-active 疊加行為。
##
## 範圍聲明：本檔只鎖 IncomeService.quote() 這一個消費端;RunRelicTable 直接以
## RunRelicRule.new()+.source 手動建構(不經 RunModifierTableBuilder/內容註冊)——
## 內容解析正確性見 test_run_modifier_table_builder.gd。

func test_commander_always_active_add_gold_applies_with_no_relic_slots_active() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"add_gold", 7),
	])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(
		result.transaction.economy_state.gold, 65,
		"58 baseline + 7 commander always-active,即使 active_relic_ids 為空陣列"
	)

func test_challenge_always_active_add_gold_applies_with_no_relic_slots_active() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"challenge.fixture", &"challenge", &"add_gold", 3),
	])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 61, "58 baseline + 3 challenge always-active")

func test_always_active_contribution_stacks_on_top_of_slot_gated_relic() -> void:
	var slot_rule := _slot_gated_rule(&"relic.eco_a", 10)
	var commander_rule := _always_active_rule(&"commander.fixture", &"commander", &"add_gold", 7)
	var challenge_rule := _always_active_rule(&"challenge.fixture", &"challenge", &"add_gold", 2)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [slot_rule, commander_rule, challenge_rule])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a"]
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(
		result.transaction.economy_state.gold, 77,
		"58 baseline + 10 slot-gated relic + 7 commander + 2 challenge (皆疊加)"
	)

func test_always_active_contribution_is_unaffected_by_which_relic_slots_are_active() -> void:
	# 同一張表:relic.eco_a 存在但這次不在 active_relic_ids 內 -> 其貢獻不計;
	# commander/challenge 不看 active_relic_ids,貢獻不變。
	var slot_rule := _slot_gated_rule(&"relic.eco_a", 10)
	var commander_rule := _always_active_rule(&"commander.fixture", &"commander", &"add_gold", 7)
	var challenge_rule := _always_active_rule(&"challenge.fixture", &"challenge", &"add_gold", 2)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [slot_rule, commander_rule, challenge_rule])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(
		result.transaction.economy_state.gold, 67,
		"58 baseline + 0(relic.eco_a 未在 active_relic_ids) + 7 commander + 2 challenge"
	)

func test_always_active_contribution_is_still_clamped_by_gold_cap() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"add_gold", 50),
	])
	# base 5 + interest(80/10=8 steps -> capped at max_interest 5) + streak 2 = 92 pre-bonus.
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(80, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 99, "92 + 50 commander bonus exceeds gold_cap 99 and must clamp")

func test_non_economy_category_always_active_rule_does_not_contribute_to_income() -> void:
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule_with_category(&"commander.fixture", &"commander", &"rule", &"heal_expedition_hp", 99),
	])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, []
	))
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.transaction.economy_state.gold, 58, "rule 類 always-active 規則不應影響 income")

func _slot_gated_rule(relic_id: StringName, amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _always_active_rule(source_id: StringName, source: StringName, kind: StringName, amount: int) -> RunRelicRule:
	return _always_active_rule_with_category(source_id, source, &"economy", kind, amount)

func _always_active_rule_with_category(
	source_id: StringName, source: StringName, category: StringName, kind: StringName, amount: int
) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

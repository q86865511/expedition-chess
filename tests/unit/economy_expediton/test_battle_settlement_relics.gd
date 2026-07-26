extends GutTest

## T06 (specs/build-systems) — 規則型遺物在 BattleSettlementService 的 settlement 決策點生效。
## Covers：REQ-RELIC-001、S4-AC-011（規則型進 rules snapshot / settlement，如遠征 HP／
## 獎勵修正，依 slot_index 升序、不經 EffectResolver）。
## 依據 design.md §6：「規則 -> 戰鬥規則 / settlement -> 進 BattleRulesSnapshotBuilder
## 輸入或 BattleSettlementService（如遠征 HP/獎勵修正），依槽序」。
##
## 假設聲明（見 test_run_relic_table_operations.gd 的總說明）：本檔只鎖定 BattleSettlementService
## 這一個作用點（不含 BattleRulesSnapshotBuilder 輸入，design.md 原文以「或」並列兩個可能落點，
## 本片選擇實作/測試較單純的 settlement 落點）。rule 類 RunRelicRule 的
## kind == &"heal_expedition_hp" 之 run_operations.amount 加總，語意為「遠征 HP 修正」：
## 勝利結算時，在既有 _apply_proposals 之後、產生獎勵階段之前，把加總值加到
## expedition_hp（仍受 EXPEDITION_HP_CAP=100 夾限）；落敗結算時，把加總值視為「傷害減免」，
## 從 result.expedition_damage 扣除（下限 0，不得產生負傷害）。BattleSettlementService.settle()
## 新增兩個尾端可選參數 relic_table/active_relic_ids（預設 null/[]），對既有呼叫端
## （test_battle_settlement_and_rewards.gd 等）完全不改變既有行為。

func test_existing_two_arg_settle_call_still_compiles_and_behaves_unchanged() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80)

func test_win_settlement_adds_rule_relic_heal_bonus_after_existing_proposals() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [_rule_heal_rule(&"relic.rule_a", 5)])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 85, "80 pre-settlement hp + 5 rule relic bonus")

func test_win_settlement_heal_bonus_is_capped_at_expedition_hp_cap() -> void:
	var root := _win_root(98, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [_rule_heal_rule(&"relic.rule_a", 5)])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 100, "98 + 5 exceeds the 100 cap and must clamp")

func test_multiple_rule_relics_sum_the_settlement_heal_bonus() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_rule_heal_rule(&"relic.rule_a", 3),
		_rule_heal_rule(&"relic.rule_b", 4),
	])
	var settled := BattleSettlementService.new().settle(
		root.run, catalog, table, [&"relic.rule_a", &"relic.rule_b"]
	)
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 87, "80 + (3+4) summed rule relic bonus")

func test_economy_category_relic_does_not_affect_settlement_hp() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var economy_operation := RunRelicOperationRule.new()
	economy_operation.operation_index = 0
	economy_operation.kind = &"add_gold"
	economy_operation.amount = 20
	economy_operation.claim_scope = &"once_per_node"
	var economy_rule := RunRelicRule.new()
	economy_rule.relic_id = &"relic.eco_a"
	economy_rule.category = &"economy"
	economy_rule.effect_ids = [&"effect.fixture"]
	economy_rule.run_operations = [economy_operation]
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [economy_rule])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.eco_a"])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80, "an economy-category relic must not change expedition_hp at settlement")

func test_loss_settlement_reduces_expedition_damage_by_rule_relic_bonus() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [_rule_heal_rule(&"relic.rule_a", 10)])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80, "100 - max(0, 30 - 10) = 80")

func test_loss_damage_reduction_floors_at_zero_and_never_heals() -> void:
	var root := _loss_root(100, 5)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [_rule_heal_rule(&"relic.rule_a", 10)])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 100, "damage 5 fully absorbed, must not heal past pre-battle hp")

func _rule_heal_rule(relic_id: StringName, heal_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"heal_expedition_hp"
	operation.amount = heal_amount
	# w3 仲裁（2026-07-25）：本 fixture 只驗戰敗減免算術，scope 語意屬 test_claim_scope_semantics；
	# once_per_node 舊預留值在勝利才消耗的新語意下不再於戰敗生效，改 always 保留測試原意。
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"rule"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _win_root(expedition_hp: int, damage: int, proposals: Array[RunMutationProposal]) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	_set_result(root.run, &"player_win", damage, proposals)
	return root

func _loss_root(expedition_hp: int, damage: int) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	var empty_proposals: Array[RunMutationProposal] = []
	_set_result(root.run, &"player_loss", damage, empty_proposals)
	return root

func _set_result(
	run: RunState, outcome: StringName, damage: int, proposals: Array[RunMutationProposal]
) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = outcome
	result.final_tick = 20
	result.survivor_instance_ids = [
		&"e_0000000000000001" if outcome == &"player_loss" else &"u_0000000000000001"
	]
	result.expedition_damage = damage
	for proposal: RunMutationProposal in proposals:
		result.run_mutation_proposals.append(proposal.deep_clone())
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)

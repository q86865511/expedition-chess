extends GutTest

## T06(specs/meta-progression) — BattleSettlementService 在既有 slot-gated 規則型遺物
## 加總後,再加指揮官/挑戰 always-active 遠征 HP 修正貢獻。
## Covers：S5-AC-003；tasks.md T06 驗收：「四個 run 層作用點消費端在 slot-gated 後加
## always-active 貢獻」(settlement 為其一)。
## 依據 design.md §6.1:117 與既有 tests/unit/economy_expediton/test_battle_settlement_relics.gd
## 的 rule×heal_expedition_hp 慣例(勝利：加總值加到 expedition_hp,受 EXPEDITION_HP_CAP=100
## 夾限；落敗：加總值視為傷害減免,從 expedition_damage 扣除,下限 0)。
##
## 範圍聲明：本檔只鎖 BattleSettlementService.settle() 的遠征 HP 修正子點;RunRelicTable
## 手動建構,不經 RunModifierTableBuilder(見 test_run_modifier_table_builder.gd)。

func test_commander_always_active_heal_bonus_applies_on_win_with_no_relic_slots_active() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 5),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 85, "80 pre-settlement hp + 5 commander always-active bonus")

func test_always_active_heal_bonus_stacks_with_slot_gated_rule_relic_on_win() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_slot_gated_rule(&"relic.rule_a", 3),
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 4),
		_always_active_rule(&"challenge.fixture", &"challenge", &"heal_expedition_hp", 2),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(
		settled.run_state.expedition_hp, 89,
		"80 + 3 slot-gated + 4 commander + 2 challenge (皆疊加)"
	)

func test_always_active_heal_bonus_is_still_capped_at_expedition_hp_cap() -> void:
	var root := _win_root(98, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 5),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 100, "98 + 5 exceeds the 100 cap and must clamp")

func test_always_active_bonus_reduces_expedition_damage_on_loss() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_slot_gated_rule(&"relic.rule_a", 5),
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 5),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80, "100 - max(0, 30 - 5 slot-gated - 5 commander) = 80")

func test_always_active_damage_reduction_floors_at_zero_and_never_heals() -> void:
	var root := _loss_root(100, 5)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 10),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 100, "damage 5 fully absorbed, must not heal past pre-battle hp")

func test_economy_category_always_active_rule_does_not_affect_settlement_hp() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule_with_category(&"commander.fixture", &"commander", &"economy", &"add_gold", 20),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80, "economy 類 always-active 規則不得影響 settlement 遠征 HP")

func _slot_gated_rule(relic_id: StringName, heal_amount: int) -> RunRelicRule:
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

func _always_active_rule(source_id: StringName, source: StringName, kind: StringName, amount: int) -> RunRelicRule:
	return _always_active_rule_with_category(source_id, source, &"rule", kind, amount)

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

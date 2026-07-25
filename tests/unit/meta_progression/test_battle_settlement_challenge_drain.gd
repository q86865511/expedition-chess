extends GutTest

## T07 (specs/meta-progression) — BattleSettlementService 在既有 rule×heal_expedition_hp
## 加總處，額外加總 DrainExpeditionHp 的 always-active 貢獻，於戰敗路徑加深遠征 HP 損失
## （design §6.3 軌 B：「既有 heal 加總處於戰敗路徑加算額外損失，與 heal 同一決定性加總慣例、
## 受 HP 下限 clamp」）。
## Covers：S5-AC-010（軌 B：DrainExpeditionHp 實際加深戰敗損失）；tasks.md T07 驗收
## 「shop/settlement 作用點消費端實際生效（...drain 加深戰敗損失、clamp 沿用）」。
## 依據 design.md §6.3:131-134 與既有 tests/unit/meta_progression/
## test_battle_settlement_commander_challenge_modifiers.gd 的 rule×heal_expedition_hp
## always-active 慣例。
##
## 假設聲明（design.md 未釘死處，本檔測試作者決定，逐條列出；實作代理請照此實作）：
## 1. RunRelicOperationRule.kind 的執行期字串為 &"drain_expedition_hp"（category=&"rule"，
##    與 &"heal_expedition_hp" 同一 category，消費端同一 BattleSettlementService 結算路徑）。
##    本檔只用既有 RunRelicTable／RunRelicRule／RunRelicOperationRule 型別以純字串 kind
##    建構，不參照任何尚不存在的 class_name（DrainExpeditionHpOperationDef 屬內容編譯層，見
##    tests/unit/content_validation/test_challenge_affix_operation_validation.gd）。
## 2. 公式（settle() 內既有 heal 加總處擴充，見 battle_settlement_service.gd:48-51）：
##      relic_heal_bonus  = 既有 slot-gated always heal 加總 + commander/challenge
##                           always-active heal 加總（不變，既有行為）
##      relic_drain_bonus = commander/challenge always-active drain 加總（本任務新增，
##                           relic_table.sum_always_active(&"rule", &"drain_expedition_hp")）
##    戰敗路徑（_settle_loss）：
##      reduced_damage = max(0, expedition_damage − relic_heal_bonus)   （既有行為不變）
##      total_damage   = reduced_damage + relic_drain_bonus              （新增：drain 為獨立
##                                                                          加項，不與 heal
##                                                                          的下限 clamp 互相
##                                                                          抵銷／吸收——heal
##                                                                          先把傷害砍到不低於
##                                                                          0，drain 再對這個
##                                                                          已砍過的值疊加,
##                                                                          兩者不合併成單一
##                                                                          淨值再取一次 max(0,·)）
##      expedition_hp  = max(0, expedition_hp − total_damage)            （既有下限 clamp 不變）
##    勝利路徑：drain 完全不生效（design 原文僅描述「戰敗時額外遠征 HP 損失」），heal 仍照既有
##    行為生效——見 test_drain_bonus_does_not_affect_win_settlement_hp。
## 3. 消費點只讀 category=&"rule" 的 drain 貢獻（比照 heal 現行只讀 rule 類），economy／route
##    類即使 kind=drain_expedition_hp 也不得影響結算 HP——見
##    test_economy_category_drain_rule_does_not_affect_settlement_hp。
## 4. 本檔只驗 always-active（commander/challenge 來源）路徑；slot-gated drain（一般遺物 authored
##    的 drain_expedition_hp）不在本任務內容著作範圍（design §6.3 僅描述 challenge 來源），未列
##    入本檔斷言。
##    W4-F3 修正（2026-07-25）：上述「未列入」的缺口即為雙審發現的實際缺陷——settlement 修正前
##    只讀 always-active 貢獻，slot-gated (rule, drain_expedition_hp) 遺物建表成功卻結算靜默
##    零效果。見 test_slot_gated_drain_relic_increases_loss_damage_on_loss，比照既有
##    _sum_always_rule_heal_bonus 的 slot-gated 讀取慣例修正。

func test_challenge_drain_increases_loss_damage_with_no_heal_bonus() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"challenge.fixture", &"challenge", &"drain_expedition_hp", 10),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 60, "100 - (30 damage + 10 challenge drain)")

func test_drain_stacks_additively_with_existing_heal_reduction_on_loss() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"commander.fixture", &"commander", &"heal_expedition_hp", 5),
		_always_active_rule(&"challenge.fixture", &"challenge", &"drain_expedition_hp", 8),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(
		settled.run_state.expedition_hp, 67,
		"100 - (max(0, 30 - 5 heal) + 8 drain) = 100 - (25 + 8) = 67"
	)

func test_drain_floors_at_zero_expedition_hp() -> void:
	var root := _loss_root(10, 5)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"challenge.fixture", &"challenge", &"drain_expedition_hp", 20),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 0, "10 - (5 + 20) would be negative, must clamp at 0")

func test_drain_bonus_does_not_affect_win_settlement_hp() -> void:
	var root := _win_root(80, 0, [])
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule(&"challenge.fixture", &"challenge", &"drain_expedition_hp", 15),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 80, "drain 只在戰敗路徑生效，勝利結算不受影響")

func test_economy_category_drain_rule_does_not_affect_settlement_hp() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_always_active_rule_with_category(&"challenge.fixture", &"challenge", &"economy", &"drain_expedition_hp", 25),
	])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [])
	assert_true(settled.ok)
	if not settled.ok:
		return
	assert_eq(settled.run_state.expedition_hp, 70, "economy 類 drain 規則不得影響結算 HP，僅原始 30 傷害生效")

## W4-F3 修正（2026-07-25）：slot-gated (rule, drain_expedition_hp) 遺物必須與 slot-gated
## heal 對稱地被結算讀取——修正前 settle() 只加總 always-active drain 貢獻，這件一般遺物
## （source=relic 預設值，經 active_relic_ids 啟用）會建表成功但結算完全不讀，靜默零效果。
func test_slot_gated_drain_relic_increases_loss_damage_on_loss() -> void:
	var root := _loss_root(100, 30)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(root.run.content_snapshot.manifest_digest_value(), [
		_slot_gated_rule(&"relic.drain_fixture", &"drain_expedition_hp", 12),
	])
	var settled := BattleSettlementService.new().settle(
		root.run, catalog, table, [&"relic.drain_fixture"]
	)
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok:
		return
	assert_eq(
		settled.run_state.expedition_hp, 58,
		"100 - (30 damage + 12 slot-gated drain)：slot-gated rule×drain 必須與 heal 對稱地被讀取"
	)

func _slot_gated_rule(relic_id: StringName, kind: StringName, amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
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

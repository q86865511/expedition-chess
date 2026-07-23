extends GutTest

## T12（specs/build-systems）— W3-F7 補充規則：IncomeService/ShopService/
## BattleSettlementService 收到 relic_table 時，須比對其 manifest digest 與呼叫端 catalog／
## run content_snapshot 的 manifest digest；不符須具名拒絕，比照 forge/equip 慣例
## （forge_equipment_command.gd:44-48 的 `_forge_table.manifest_digest_value() !=
## draft.content_snapshot.manifest_digest_value()` 模式）。
## MapService 的對應案例獨立拆到
## test_map_service_relic_table_generation_guard.gd——該案例引用的
## MapGenerationError.GENERATION_MISMATCH 常數今日不存在，會讓整個腳本在載入階段就
## Parse Error（GDScript 對「腳本內任何一個測試 function 引用未知常數」的失敗粒度是整檔，
## 不是單一 test case），若留在同一檔會連帶蓋掉本檔其餘三個 service 的斷言層級紅證據。
## Covers：REQ-RELIC-001（W3-F7，tasks.md T12 補充：wave2 雙審延後項，使用者裁決 2026-07-23）。
##
## 假設聲明（三個 service 現有簽名各自決定的斷言形狀——本檔新增，非既有慣例）：
## 1. IncomeService.quote() / ShopService.generate_offers() 不直接持有 RunState.content_snapshot，
##    只收 catalog（EconomyExpeditionCatalog，已有 manifest_digest_value()）與 relic_table
##    （RunRelicTable，已有 manifest_digest_value()）——比對基準取 relic_table 對 catalog，
##    而非 content_snapshot（catalog 本身與 content_snapshot 的一致性已由呼叫端 RunCommand
##    在更早一步驗證，如 generate_expedition_map_command.gd:21-23，故 catalog 可視為
##    content_snapshot 的可信代理）。兩者錯誤型別沿用既有 ShopError（IncomeService 現有失敗
##    路徑已重用 ShopError，見 income_service.gd:8 的 ShopError.INPUT_INVALID），沿用既有
##    ShopError.GENERATION_MISMATCH（今日已用於 catalog vs content_snapshot 不符，語意相通）。
## 2. BattleSettlementService.settle() 直接持有完整 RunState（source.content_snapshot），
##    比對基準採 relic_table 對 source.content_snapshot（與其既有 catalog vs content_snapshot
##    檢查同一份 digest，見 battle_settlement_service.gd:272-276）。錯誤型別沿用既有
##    ExpeditionActionError.GENERATION_MISMATCH（今日已用於 catalog 不符，語意相通，且
##    settle() 已回傳 ExpeditionActionResult/ExpeditionActionError）。
## 3. 本檔只鎖定各 service 自身的 digest 比對邏輯，不涉及 RunController composition-root
##    是否已把 relic_table 接進對應 command（例如 generate_expedition_map_command.gd 當初
##    呼叫 MapGenerationRequest.new() 完全未傳 relic_table/active_relic_ids——該缺口已於
##    同批（T12 生產接線）修復，不在此處新增或修改任何 command 測試）。

const _OTHER_DIGEST: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

func test_income_service_rejects_a_relic_table_whose_manifest_digest_does_not_match_the_catalog() -> void:
	var table := RunRelicTable.new(_OTHER_DIGEST, [_economy_rule(&"relic.eco_a", 10)])
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog(), table, [&"relic.eco_a"]
	))
	assert_false(result.ok, "a relic_table pinned to a stale manifest digest must never be allowed to author an income quote")
	if result.ok:
		return
	assert_eq(result.error.code, ShopError.GENERATION_MISMATCH)

func test_shop_service_rejects_a_relic_table_whose_manifest_digest_does_not_match_the_catalog() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(_OTHER_DIGEST, [_economy_shop_discount_rule(&"relic.eco_a", 2)])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.eco_a"]
	))
	assert_false(generated.ok, "a relic_table pinned to a stale manifest digest must never be allowed to author shop offers")
	if generated.ok:
		return
	assert_eq(generated.error.code, ShopError.GENERATION_MISMATCH)

func test_battle_settlement_service_rejects_a_relic_table_whose_manifest_digest_does_not_match_the_content_snapshot() -> void:
	var root := _win_root(80, 0)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var table := RunRelicTable.new(_OTHER_DIGEST, [_rule_heal_rule(&"relic.rule_a", 5)])
	var settled := BattleSettlementService.new().settle(root.run, catalog, table, [&"relic.rule_a"])
	assert_false(settled.ok, "a relic_table pinned to a stale manifest digest must never be allowed to author a settlement")
	if settled.ok:
		return
	assert_eq(settled.error.code, ExpeditionActionError.GENERATION_MISMATCH)

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

func _economy_shop_discount_rule(relic_id: StringName, discount_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"shop_discount"
	operation.amount = discount_amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _rule_heal_rule(relic_id: StringName, heal_amount: int) -> RunRelicRule:
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

func _win_root(expedition_hp: int, damage: int) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	var empty_proposals: Array[RunMutationProposal] = []
	_set_result(root.run, &"player_win", damage, empty_proposals)
	return root

func _set_result(
	run: RunState, outcome: StringName, damage: int, proposals: Array[RunMutationProposal]
) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = outcome
	result.final_tick = 20
	result.survivor_instance_ids = [&"u_0000000000000001"]
	result.expedition_damage = damage
	for proposal: RunMutationProposal in proposals:
		result.run_mutation_proposals.append(proposal.deep_clone())
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)

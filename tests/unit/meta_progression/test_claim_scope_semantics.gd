extends GutTest

## T08(specs/meta-progression) — claim_scope 真語意（once_per_node/on_first_clear 防重放）。
## Covers：S5-AC-013（design.md §6.4；design.md §12 測試案例 013
## test_claim_scope_semantics_once_per_node_and_first_clear）。
##
## 兩層放寬（依 design §6.4 逐字）：
## - validator：content_validator.gd:264-274 `_validate_relic_effect_scope` 對非 battle 遺物
##   run intent 目前僅接受 &"always"，須同步放寬為 {always, once_per_node, on_first_clear}
##   （content_validator.gd:688 的通用 scalar 路徑已允許三者，本檔只鎖 relic-scope 這層額外收斂）。
## - builder：run_relic_table_builder.gd:83-84 目前對非 always run intent 一律 UNSUPPORTED_INTENT，
##   須同步放寬。
## 消費端真語意（design §6.4）：帶 claim_scope 的 relic run intent 於結算作用點消費時走
## RuntimeKeySchemaRegistry.build_effect_claim + claim_receipts 去重（battle_settlement_service.gd:
## 169-200 既有樣式）。once_per_node 的 node_id 用當前節點（同節點恰一次、跨節點重觸發）；
## on_first_clear 的 node_id 用 run 級 sentinel（全 run 同一 key，首次通過後恰一次，不因換節點
## 重觸發）。本檔以 BattleSettlementService.settle() 的 rule×heal_expedition_hp 消費點驗證此語意
## （沿用 tests/unit/meta_progression/test_battle_settlement_commander_challenge_modifiers.gd 的
## RunRelicTable 手動建構慣例，不經 builder/RunModifierTableBuilder——那條路徑由 Group A 覆蓋）。
##
## 範圍聲明：本檔不驗證 IncomeService／ShopService 的 economy 類 claim_scope 消費（design 未明確
## 指出這兩個消費端在本任務同步改動；task 簡報明確只點名 battle_settlement_service.gd:169-200
## 的既有樣式）。若實作段也同步改了 income/shop 消費端，屬額外正確性，不在本檔鎖定範圍內。
##
## W3 雙審追加（2026-07-25 裁決「全修」，見 .pipeline/reviews/2026-07-25-reviewer-w3-r2.md F4/F5、
## 2026-07-25-sonnet-w3.md #2）：claim key 曾以 relic_id 頂替 effect_id，同遺物跨 effect_refs
## 但 operation_index 相同時會撞 key、吞掉加成；且既有 claim 命中時未比對 payload_digest，與
## _apply_proposals 的竄改偵測不同調。Group D 覆蓋這兩項修正。

# ---------- Group A：validator × builder 同步放寬三種 claim_scope（非 battle 遺物 run intent）----------

func test_validator_and_builder_accept_once_per_node_run_intent_for_non_battle_relic() -> void:
	_assert_scope_accepted_end_to_end(&"once_per_node", "t08_once_per_node")

func test_validator_and_builder_accept_on_first_clear_run_intent_for_non_battle_relic() -> void:
	_assert_scope_accepted_end_to_end(&"on_first_clear", "t08_on_first_clear")

func _assert_scope_accepted_end_to_end(scope: StringName, tag: String) -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var operation := HealExpeditionHpOperationDef.new()
	operation.operation_index = 0
	operation.amount = 5
	operation.claim_scope = scope
	var effect := EffectDef.new()
	effect.id = StringName("effect.%s" % tag)
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % tag)
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = [operation]
	fixture.definitions.append(effect)
	# relic.r11 屬 SyntheticContentFixture 的 rule 類遺物（index 11..14），非 battle。
	var relic := _find(fixture, &"relic.r11") as RelicDef
	assert_not_null(relic, "fixture must contain relic.r11")
	if relic == null:
		return
	relic.effect_refs = [StringName("effect.%s" % tag)]
	var installed := registry.install_validated(
		fixture, "fixture.t08.%s" % tag, [&"pack.core"]
	)
	assert_true(
		installed.ok,
		"content_validator must accept claim_scope=%s for non-battle relic run intent (S5-AC-013): %s" % [
			String(scope),
			String(installed.error.code) if not installed.ok and installed.error != null else "n/a",
		]
	)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r11"]
	)
	assert_true(
		built.ok,
		"RunRelicTableBuilder must accept claim_scope=%s for non-battle relic run intent (S5-AC-013): %s" % [
			String(scope),
			String(built.error.code) if not built.ok and built.error != null else "n/a",
		]
	)

func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null

# ---------- Group B：消費端真語意（BattleSettlementService 的 rule×heal_expedition_hp 消費點）----------

## 2026-07-25 裁決：once_per_node/on_first_clear 的 claim 只在勝利結算提交與消耗；戰敗不建
## claim、不套 bonus（design §6.4 補註）。以下以「節點 A 落敗 → 節點 A 重戰勝利 → 同節點重放
## → 跨節點」序列驗證：落敗不消耗 claim、首次勝利恰一次套用、Boss 重戰同節點恰一次、
## 重載重放不重複、跨節點依 scope 決定是否重觸發。
func test_once_per_node_relic_bonus_ignores_loss_then_claims_once_on_win_and_retriggers_on_a_different_node() -> void:
	var root := _boss_root(50)
	var setup_hash := String((root.run.resolution_state as BattleResultPendingResolutionState).battle_setup_hash)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var relic_table := _rule_relic_table(
		root.run.content_snapshot.manifest_digest_value(), &"relic.t08_once", &"effect.t08_once",
		&"once_per_node", 20
	)
	var active_ids: Array[StringName] = [&"relic.t08_once"]

	# 1) 節點 A 落敗：戰敗結算不得建立/消耗 once_per_node claim，20 點加成完全不生效。
	_set_loss(root.run, 30, setup_hash)
	var lost := BattleSettlementService.new().settle(root.run, catalog, relic_table, active_ids)
	assert_true(lost.ok, _settle_err(lost))
	if not lost.ok:
		return
	assert_eq(
		lost.run_state.expedition_hp, 20,
		"loss must NOT consume/apply the once_per_node bonus: 50 - 30 damage, no reduction"
	)
	assert_eq(
		lost.run_state.claim_receipts.size(), root.run.claim_receipts.size(),
		"loss must not create a claim_receipts entry for once_per_node"
	)
	assert_eq(
		lost.run_state.run_phase, RunState.RunPhase.PREPARE,
		"boss loss with hp remaining must retry the same node"
	)

	# 2) 同節點 A 重戰勝利（Boss 重戰情境）：once_per_node 首次消費恰一次，20 點加成套用。
	_set_win(lost.run_state, setup_hash)
	var first_win := BattleSettlementService.new().settle(lost.run_state, catalog, relic_table, active_ids)
	assert_true(first_win.ok, _settle_err(first_win))
	if not first_win.ok:
		return
	assert_eq(
		first_win.run_state.expedition_hp, 40,
		"first win at this node must consume the once_per_node claim and heal 20: 20 + 20"
	)
	var claimed_count := first_win.run_state.claim_receipts.size()
	assert_eq(
		claimed_count, root.run.claim_receipts.size() + 1,
		"first win must append exactly one claim receipt"
	)

	# 3) 重載重放：同節點再次提交同一筆勝利結算（模擬重載後重放同一戰果），claim 已存在，
	#    不得重複套用、不得重複記入。
	_set_win(first_win.run_state, setup_hash)
	var replay := BattleSettlementService.new().settle(first_win.run_state, catalog, relic_table, active_ids)
	assert_true(replay.ok, _settle_err(replay))
	if not replay.ok:
		return
	assert_eq(
		replay.run_state.expedition_hp, 40,
		"replaying the same node's win must NOT re-apply the already-claimed once_per_node bonus"
	)
	assert_eq(
		replay.run_state.claim_receipts.size(), claimed_count,
		"replay must not append a duplicate claim receipt"
	)

	# 4) 跨節點（節點 B）勝利：once_per_node 針對新節點必須可重觸發。
	_set_node(replay.run_state, MapNodeState.NodeKind.BOSS, 0, 1, 0)
	_set_win(replay.run_state, setup_hash)
	var other_node_win := BattleSettlementService.new().settle(replay.run_state, catalog, relic_table, active_ids)
	assert_true(other_node_win.ok, _settle_err(other_node_win))
	if not other_node_win.ok:
		return
	assert_eq(
		other_node_win.run_state.expedition_hp, 60,
		"once_per_node must retrigger at a different node_id: 40 + 20"
	)

func test_on_first_clear_relic_bonus_ignores_loss_then_claims_once_for_the_whole_run_and_never_retriggers() -> void:
	var root := _boss_root(50)
	var setup_hash := String((root.run.resolution_state as BattleResultPendingResolutionState).battle_setup_hash)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var relic_table := _rule_relic_table(
		root.run.content_snapshot.manifest_digest_value(), &"relic.t08_first_clear", &"effect.t08_first_clear",
		&"on_first_clear", 15
	)
	var active_ids: Array[StringName] = [&"relic.t08_first_clear"]

	# 1) 節點 A 落敗：on_first_clear 同樣不得於戰敗建立/消耗 claim。
	_set_loss(root.run, 30, setup_hash)
	var lost := BattleSettlementService.new().settle(root.run, catalog, relic_table, active_ids)
	assert_true(lost.ok, _settle_err(lost))
	if not lost.ok:
		return
	assert_eq(
		lost.run_state.expedition_hp, 20,
		"loss must NOT consume/apply the on_first_clear bonus: 50 - 30 damage, no reduction"
	)
	assert_eq(
		lost.run_state.claim_receipts.size(), root.run.claim_receipts.size(),
		"loss must not create a claim_receipts entry for on_first_clear"
	)

	# 2) 同節點 A 重戰勝利：on_first_clear 全 run 首次消費恰一次，15 點加成套用。
	_set_win(lost.run_state, setup_hash)
	var first_win := BattleSettlementService.new().settle(lost.run_state, catalog, relic_table, active_ids)
	assert_true(first_win.ok, _settle_err(first_win))
	if not first_win.ok:
		return
	assert_eq(
		first_win.run_state.expedition_hp, 35,
		"first win in the run must consume on_first_clear once: 20 + 15"
	)
	var claimed_count := first_win.run_state.claim_receipts.size()
	assert_eq(
		claimed_count, root.run.claim_receipts.size() + 1,
		"first win must append exactly one claim receipt"
	)

	# 3) 重載重放：同節點再次提交同一筆勝利結算，claim 已存在，不得重複套用/記入。
	_set_win(first_win.run_state, setup_hash)
	var replay := BattleSettlementService.new().settle(first_win.run_state, catalog, relic_table, active_ids)
	assert_true(replay.ok, _settle_err(replay))
	if not replay.ok:
		return
	assert_eq(
		replay.run_state.expedition_hp, 35,
		"replaying the same win must NOT re-apply the already-claimed on_first_clear bonus"
	)
	assert_eq(
		replay.run_state.claim_receipts.size(), claimed_count,
		"replay must not append a duplicate claim receipt"
	)

	# 4) 跨節點（節點 B）勝利：on_first_clear 的 sentinel 是 run 級，已消費過就不應在新節點重觸發
	#    ——這是與 once_per_node 語意的關鍵分野（後者換節點會重觸發，見上一個測試）。
	_set_node(replay.run_state, MapNodeState.NodeKind.BOSS, 0, 1, 0)
	_set_win(replay.run_state, setup_hash)
	var other_node_win := BattleSettlementService.new().settle(replay.run_state, catalog, relic_table, active_ids)
	assert_true(other_node_win.ok, _settle_err(other_node_win))
	if not other_node_win.ok:
		return
	assert_eq(
		other_node_win.run_state.expedition_hp, 35,
		"on_first_clear must NOT retrigger at a different node once consumed in this run: 35 + 0"
	)
	assert_eq(
		other_node_win.run_state.claim_receipts.size(), claimed_count,
		"on_first_clear must not append a second claim receipt anywhere else in the run"
	)

func test_always_relic_bonus_still_applies_unconditionally_every_settlement_regression() -> void:
	# 迴歸保護：既有 always 語意（S4 行為，逐節點無條件加總）不得被本任務的 claim 去重機制波及。
	var root := _boss_root(100)
	var setup_hash := String((root.run.resolution_state as BattleResultPendingResolutionState).battle_setup_hash)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var relic_table := _rule_relic_table(
		root.run.content_snapshot.manifest_digest_value(), &"relic.t08_always", &"effect.t08_always",
		&"always", 10
	)
	var active_ids: Array[StringName] = [&"relic.t08_always"]

	_set_loss(root.run, 30, setup_hash)
	var first := BattleSettlementService.new().settle(root.run, catalog, relic_table, active_ids)
	assert_true(first.ok, _settle_err(first))
	if not first.ok:
		return
	assert_eq(first.run_state.expedition_hp, 80, "always bonus applies on first settlement: 100 - (30 - 10)")

	_set_loss(first.run_state, 30, setup_hash)
	var second := BattleSettlementService.new().settle(first.run_state, catalog, relic_table, active_ids)
	assert_true(second.ok, _settle_err(second))
	if not second.ok:
		return
	assert_eq(
		second.run_state.expedition_hp, 60,
		"always bonus must keep applying unconditionally on the very same node retry too: 80 - (30 - 10)"
	)

# ---------- Group C：claim keys 全 run 唯一、重複 tuple 拒載（既有通用機制，兩種新 scope 亦適用）----------

func test_run_state_validator_rejects_duplicate_claim_receipt_tuple_for_once_per_node_and_on_first_clear() -> void:
	for scope: StringName in [&"once_per_node", &"on_first_clear"]:
		var root := SaveRootFixture.create_valid_root()
		var key_result := RuntimeKeySchemaRegistry.new().build_effect_claim(
			StringName(root.run.run_id), &"node_a", scope, &"relic.t08_dup", &"effect.t08_dup", 0
		)
		assert_true(key_result.ok, "fixture claim key must encode for scope=%s" % String(scope))
		if not key_result.ok:
			continue
		var claim := ClaimReceiptState.new(
			key_result.key_state as EffectClaimKeyState,
			"7777777777777777777777777777777777777777777777777777777777777777"
		)
		root.run.claim_receipts = [claim.deep_clone(), claim.deep_clone()]
		var result := RunStateValidator.new().validate_run(root.run)
		assert_false(
			result.ok,
			"duplicate claim_receipts tuple (scope=%s) must be rejected, not silently accepted" % String(scope)
		)

# ---------- Group D：W3-F4／F5 修正迴歸（claim key 的 effect_id 消歧、既有 claim 命中比對 payload_digest）----------

## F4 迴歸：同一遺物兩個 effect_refs，其 run_operations 各自的 operation_index 都是 0
## （合法——operation_index 只在單一 effect 內唯一，見 content_validator.gd:691-693）。修正前
## claim key 的 effect_id 欄用 relic_id 頂替，兩筆操作會撞成同一把 key，第二筆遭 _find_claim
## 誤判已存在而靜默丟棄；修正後 key 改用 operation.effect_id 消歧，兩筆都必須各自 claim 一次。
func test_two_effect_refs_on_the_same_relic_sharing_operation_index_claim_independently_without_colliding() -> void:
	var root := _boss_root(50)
	var setup_hash := String((root.run.resolution_state as BattleResultPendingResolutionState).battle_setup_hash)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var relic_table := _rule_relic_table_two_effects(
		root.run.content_snapshot.manifest_digest_value(), &"relic.t08_multi",
		&"effect.t08_multi_a", 5, &"effect.t08_multi_b", 7, &"once_per_node"
	)
	var active_ids: Array[StringName] = [&"relic.t08_multi"]

	_set_win(root.run, setup_hash)
	var result := BattleSettlementService.new().settle(root.run, catalog, relic_table, active_ids)
	assert_true(result.ok, _settle_err(result))
	if not result.ok:
		return
	assert_eq(
		result.run_state.expedition_hp, 62,
		"both effect_refs sharing operation_index=0 must apply independently, not collide: 50 + 5 + 7"
	)
	assert_eq(
		result.run_state.claim_receipts.size(), root.run.claim_receipts.size() + 2,
		"two distinct effect_refs must append two distinct claim receipts, not one shared key"
	)

## F5 迴歸：draft.claim_receipts 已存在一筆與本次計算 key 相同、但 payload_digest 不同的 claim
## （模擬竄改或未來 amount 調整）。修正前 _find_claim 命中即直接 continue、靜默放行；修正後必須
## 比對 payload_digest 並回具名錯誤，與同檔 _apply_proposals 的竄改偵測同調。
func test_existing_claim_hit_with_mismatched_payload_digest_is_rejected_not_silently_skipped() -> void:
	var root := _boss_root(50)
	var setup_hash := String((root.run.resolution_state as BattleResultPendingResolutionState).battle_setup_hash)
	var catalog := EconomyTestFixture.settlement_catalog(root.run.content_snapshot.manifest_digest_value())
	var relic_id := &"relic.t08_digest_mismatch"
	var effect_id := &"effect.t08_digest_mismatch"
	var relic_table := _rule_relic_table(
		root.run.content_snapshot.manifest_digest_value(), relic_id, effect_id, &"once_per_node", 20
	)
	var active_ids: Array[StringName] = [relic_id]
	var node_token := EconomyCommandSupport.current_node_id(root.run)
	var key_result := RuntimeKeySchemaRegistry.new().build_effect_claim(
		StringName(root.run.run_id), node_token, &"once_per_node", relic_id, effect_id, 0
	)
	assert_true(key_result.ok, "test setup: claim key must encode")
	if not key_result.ok:
		return
	root.run.claim_receipts = [ClaimReceiptState.new(
		key_result.key_state as EffectClaimKeyState,
		"7777777777777777777777777777777777777777777777777777777777777777"
	)]

	_set_win(root.run, setup_hash)
	var result := BattleSettlementService.new().settle(root.run, catalog, relic_table, active_ids)
	assert_false(
		result.ok,
		"a claim key hit with a mismatched payload_digest must be rejected, not silently continue (F5)"
	)
	if result.ok:
		return
	assert_eq(
		result.error.code, ExpeditionActionError.RESULT_INVALID,
		"digest mismatch must surface the same named error code _apply_proposals uses"
	)
	assert_eq(
		result.error.field_path, &"claim_receipts.payload_digest",
		"digest mismatch error must point at claim_receipts.payload_digest"
	)

# ---------- 共用建構 ----------

func _rule_relic_table(
	manifest_digest: String, relic_id: StringName, effect_id: StringName,
	claim_scope: StringName, amount: int
) -> RunRelicTable:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"heal_expedition_hp"
	operation.amount = amount
	operation.claim_scope = claim_scope
	operation.effect_id = effect_id
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"rule"
	rule.effect_ids = [effect_id]
	rule.run_operations = [operation]
	return RunRelicTable.new(manifest_digest, [rule])

## F4 迴歸專用：單一遺物含兩個 effect_refs，各自 run_operations 的 operation_index 皆為 0。
func _rule_relic_table_two_effects(
	manifest_digest: String, relic_id: StringName,
	effect_a: StringName, amount_a: int, effect_b: StringName, amount_b: int,
	claim_scope: StringName
) -> RunRelicTable:
	var operation_a := RunRelicOperationRule.new()
	operation_a.operation_index = 0
	operation_a.kind = &"heal_expedition_hp"
	operation_a.amount = amount_a
	operation_a.claim_scope = claim_scope
	operation_a.effect_id = effect_a
	var operation_b := RunRelicOperationRule.new()
	operation_b.operation_index = 0
	operation_b.kind = &"heal_expedition_hp"
	operation_b.amount = amount_b
	operation_b.claim_scope = claim_scope
	operation_b.effect_id = effect_b
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"rule"
	rule.effect_ids = [effect_a, effect_b]
	rule.run_operations = [operation_a, operation_b]
	return RunRelicTable.new(manifest_digest, [rule])

func _boss_root(expedition_hp: int) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	_set_node(root.run, MapNodeState.NodeKind.BOSS, 0, 0, 0)
	root.run.income_claimed_node_ids = [root.run.map_state.nodes[0].node_id]
	return root

## 把 run 的唯一節點（索引 0）替換為指定 kind/act/layer/slot 的新節點，藉此模擬「跨節點」
## （不同 node_key digest）而不必跑完整地圖生成管線——比照
## tests/unit/economy_expediton/test_battle_settlement_and_rewards.gd 的 _replace_node_kind 慣例。
func _set_node(
	run: RunState, kind: MapNodeState.NodeKind, act_index: int, layer_index: int, slot_index: int
) -> void:
	var old := run.map_state.nodes[0]
	var key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), act_index, MapNodeState.node_kind_to_token(kind), layer_index, slot_index
	)
	var key := key_result.key_state as NodeKeyState
	run.map_state.nodes[0] = MapNodeState.new(
		String(key.digest), key, old.def_id, act_index, layer_index,
		slot_index, kind, old.generated_payload_digest, old.encounter_preview, false
	)
	run.current_node_id = OptionalStringValue.new(String(key.digest))
	run.map_state.current_node_id = OptionalStringValue.new(String(key.digest))
	run.act_index = act_index

## 以固定 setup_hash 建構一次落敗結果並寫回 resolution_state（供下一次 settle() 消費）。
## 不從目前 resolution_state 讀 setup_hash——settle() 落敗且非 boss-hp-exhausted 分支後
## resolution_state 會變成 IdleResolutionState，無法再從中取值，故由呼叫端於根建立時
## 擷取一次、之後每次重用同一個值（settle() 本身不驗證 battle_setup_hash 對應真實 BattleSetup）。
func _set_loss(run: RunState, damage: int, setup_hash: String) -> void:
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(setup_hash)
	result.outcome = &"player_loss"
	result.final_tick = 20
	result.survivor_instance_ids = [&"e_0000000000000001"]
	result.expedition_damage = damage
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok, "battle result seal should succeed")
	if not sealed.ok:
		return
	run.resolution_state = BattleResultPendingResolutionState.new(
		setup_hash, BattleResult.from_record(sealed.record)
	)
	run.run_phase = RunState.RunPhase.COMBAT

## 以固定 setup_hash 建構一次勝利結果並寫回 resolution_state（供下一次 settle() 消費）。
## 沿用 _set_loss 同一慣例：不從目前 resolution_state 讀 setup_hash，由呼叫端於根建立時
## 擷取一次、之後每次重用；不帶 run_mutation_proposals，只驗證規則遺物 heal_expedition_hp
## 的 claim 消費時機（本檔不覆蓋 proposals 類 claim）。
func _set_win(run: RunState, setup_hash: String) -> void:
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(setup_hash)
	result.outcome = &"player_win"
	result.final_tick = 20
	result.survivor_instance_ids = [&"u_0000000000000001"]
	result.expedition_damage = 0
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok, "battle result seal should succeed")
	if not sealed.ok:
		return
	run.resolution_state = BattleResultPendingResolutionState.new(
		setup_hash, BattleResult.from_record(sealed.record)
	)
	run.run_phase = RunState.RunPhase.COMBAT

func _settle_err(result: ExpeditionActionResult) -> String:
	if result.ok:
		return "ok"
	return "%s:%s" % [
		String(result.error.code) if result.error != null else "none",
		String(result.error.field_path) if result.error != null else "none",
	]

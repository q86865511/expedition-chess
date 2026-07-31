extends GutTest

## T25 review 第二輪 L2／N4 回歸：
## - design.md §5:200「ledger 依 transaction_serial 升冪…生命期到 run terminal 清除」。
##   三條把 run_phase 切成 RESULTS 的路徑（lethal settle／abandon_boss_retry／
##   act3 boss reward advance）都必須清掉 node_choice_receipts，非 terminal 的同名
##   路徑（→MAP／→PREPARE）則必須原樣保留，否則 reload 不再重播未 ack 的結果。
## - review N4：`NodeChoicePendingState.is_valid()` 失敗不得一律回報成
##   `lifecycle_nonce`——世代欄位不符要指向世代欄位，否則排查者往 RNG 方向找。


func test_lethal_battle_settlement_clears_the_ledger() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.expedition_hp = 20
	root.run.node_choice_receipts.append(_ledger_entry(root.run))
	_set_result(root.run, &"player_loss", 20)
	var settled := BattleSettlementService.new().settle(
		root.run, _catalog(root.run)
	)
	assert_true(settled.ok, _error(settled))
	if not settled.ok:
		return
	assert_eq(settled.run_state.run_phase, RunState.RunPhase.RESULTS)
	assert_eq(
		settled.run_state.node_choice_receipts.size(),
		0,
		"terminal settlement must clear the node choice ledger"
	)


func test_non_lethal_battle_settlement_keeps_the_ledger() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.expedition_hp = 100
	root.run.node_choice_receipts.append(_ledger_entry(root.run))
	_set_result(root.run, &"player_loss", 20)
	var settled := BattleSettlementService.new().settle(
		root.run, _catalog(root.run)
	)
	assert_true(settled.ok, _error(settled))
	if not settled.ok:
		return
	assert_eq(settled.run_state.run_phase, RunState.RunPhase.MAP)
	assert_eq(
		settled.run_state.node_choice_receipts.size(),
		1,
		"a run that continues must keep replaying its unacknowledged results"
	)


func test_abandon_boss_retry_clears_the_ledger() -> void:
	var root := _battle_root(MapNodeState.NodeKind.BOSS)
	root.run.run_phase = RunState.RunPhase.PREPARE
	root.run.resolution_state = IdleResolutionState.new()
	root.run.node_choice_receipts.append(_ledger_entry(root.run))
	var abandoned := BattleSettlementService.new().abandon_boss_retry(
		root.run, _catalog(root.run)
	)
	assert_true(abandoned.ok, _error(abandoned))
	if not abandoned.ok:
		return
	assert_eq(abandoned.run_state.run_phase, RunState.RunPhase.RESULTS)
	assert_eq(abandoned.run_state.node_choice_receipts.size(), 0)


func test_act_three_boss_reward_advance_clears_the_ledger() -> void:
	var root := _battle_root(MapNodeState.NodeKind.BOSS)
	_replace_node_kind(root.run, MapNodeState.NodeKind.BOSS, 3)
	root.run.node_choice_receipts.append(_ledger_entry(root.run))
	var catalog := _catalog(root.run)
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok, _error(settled))
	if not settled.ok:
		return
	assert_eq(
		settled.run_state.node_choice_receipts.size(),
		1,
		"a boss win that opens a reward stage is not yet terminal"
	)
	var pending := (
		settled.run_state.resolution_state as RewardPendingResolutionState
	).pending_reward
	var chosen := RewardService.new().choose(
		settled.run_state, pending.offers[0].choice_id, catalog
	)
	assert_true(chosen.ok, _error(chosen))
	if not chosen.ok:
		return
	var advanced := RewardService.new().advance(chosen.run_state, catalog)
	assert_true(advanced.ok, _error(advanced))
	if not advanced.ok:
		return
	assert_eq(advanced.run_state.run_phase, RunState.RunPhase.RESULTS)
	assert_eq(advanced.run_state.node_choice_receipts.size(), 0)


## review N4：釘在 catalog schema 1／codec 2 世代的 run 進入 event/rest/treasure 時，
## begin() 必須指出是世代欄位不合，而不是把診斷指向 lifecycle_nonce。
func test_begin_reports_the_generation_field_instead_of_the_nonce() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var source := SaveRootFixture.create_receipt()
	var legacy := ContentSnapshotState.from_pinned_receipt(
		PinnedCatalogBuildReceipt.new(
			1,
			2,
			source.content_version,
			source.selection_digest,
			source.active_entry_ids,
			source.economy_config_id,
			source.combat_config_id,
			source.reward_table_ids,
			source.map_node_def_ids,
			source.challenge_unlock_def_ids,
			source.meta_reward_table_id,
			source.manifest_digest
		)
	)
	assert_true(legacy.ok, "legacy (schema 1, codec 2) snapshot must build")
	if not legacy.ok:
		return
	run.content_snapshot = legacy.snapshot
	var result := CommitNodeChoiceService.new().begin(
		run,
		NodeChoiceServiceFixture.current_node_id(run),
		NodeChoiceServiceFixture.choice_set(),
		NodeChoiceServiceFixture.catalog_for(run)
	)
	assert_false(result.ok, "a legacy generation run must not open a node choice")
	if result.ok:
		return
	assert_eq(
		String(result.error.code), String(ExpeditionActionError.INPUT_INVALID)
	)
	assert_eq(
		String(result.error.field_path),
		"catalog_schema_version",
		"generation mismatch must not be reported as a nonce failure"
	)


func _ledger_entry(run: RunState) -> NodeChoiceReceiptLedgerEntry:
	var receipt := NodeChoiceCommitReceiptState.new()
	receipt.run_id = StringName(run.run_id)
	receipt.node_id = StringName(run.current_node_id.value)
	receipt.choice_set_id = &"choice_set.ledger.fixture"
	receipt.choice_id = &"choice.ledger.fixture"
	receipt.pending_digest = "a".repeat(64)
	receipt.lifecycle_nonce = "0123456789abcdef"
	receipt.transaction_serial = "0000000000000001"
	receipt.transaction_digest = "transaction_%s" % "b".repeat(64)
	receipt.result_key = &"loc.choice_result_fixture"
	receipt.outcome_kind = 1
	receipt.refresh_digest()
	return NodeChoiceReceiptLedgerEntry.new(receipt, false)


func _catalog(run: RunState) -> EconomyExpeditionCatalog:
	return EconomyTestFixture.settlement_catalog(
		run.content_snapshot.manifest_digest_value()
	)


func _error(result: ExpeditionActionResult) -> String:
	return String(result.error.code) if result.error != null else ""


func _battle_root(kind: MapNodeState.NodeKind) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(
		ResolutionState.Kind.BATTLE_RESULT_PENDING
	)
	root.run.run_phase = RunState.RunPhase.COMBAT
	_replace_node_kind(root.run, kind)
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	root.run.expedition_hp = 100
	return root


func _replace_node_kind(
	run: RunState,
	kind: MapNodeState.NodeKind,
	requested_act_index: int = -1
) -> void:
	var old := run.map_state.nodes[0]
	var act_index := (
		old.act_index if requested_act_index < 0 else requested_act_index
	)
	var key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id),
		act_index,
		MapNodeState.node_kind_to_token(kind),
		old.layer_index,
		old.slot_index
	)
	var key := key_result.key_state as NodeKeyState
	run.map_state.nodes[0] = MapNodeState.new(
		String(key.digest), key, old.def_id, act_index, old.layer_index,
		old.slot_index, kind, old.generated_payload_digest,
		old.encounter_preview, old.completed
	)
	if run.current_node_id != null and run.current_node_id.value == old.node_id:
		run.current_node_id = OptionalStringValue.new(String(key.digest))
	if run.map_state.current_node_id != null \
		and run.map_state.current_node_id.value == old.node_id:
		run.map_state.current_node_id = OptionalStringValue.new(
			String(key.digest)
		)
	for owner: ReservationOwnerState in run.reservation_owners:
		owner.key.node_id = key.digest
	for offer: ShopOffer in run.economy_state.shop_offers:
		offer.reservation_owner_key.node_id = key.digest
		offer.offer_id = String(offer.reservation_owner_key.digest)
	run.act_index = act_index


func _set_result(run: RunState, outcome: StringName, damage: int) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = outcome
	result.final_tick = 20
	var survivors: Array[StringName] = []
	survivors.append(
		&"e_0000000000000001"
		if outcome == &"player_loss"
		else &"u_0000000000000001"
	)
	result.survivor_instance_ids = survivors
	result.expedition_damage = damage
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)

extends GutTest

func test_node_entry_and_buy_commit_once_through_run_controller() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var generated := controller.dispatch(GenerateExpeditionMapCommand.new(catalog))
	assert_true(generated.ok)
	if not generated.ok: return
	var generated_root := repository.load()
	assert_true(generated_root.ok)
	if not generated_root.ok: return
	var target := generated_root.run.map_state.nodes[0]
	var battle_catalog := EconomyTestFixture.expedition_battle_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var entered := controller.transition(EnterNodeEvent.new(
		target.node_id, catalog, battle_catalog
	))
	assert_true(entered.ok, "%s:%s" % [
		String(entered.error.code) if entered.error != null else "none",
		String(entered.error.field_path) if entered.error != null else "none",
	])
	if not entered.ok: return
	assert_eq(entered.view_state.run_phase, RunState.RunPhase.PREPARE)
	assert_eq(entered.view_state.current_node_id.value, target.node_id)
	assert_eq(entered.view_state.economy.gold, 58)
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	assert_eq(after_enter.run.income_claimed_node_ids, [target.node_id])
	assert_eq(after_enter.run.economy_state.shop_offers.size(), 5)
	assert_eq(after_enter.run.transaction_receipts.size(), 2)
	assert_not_null(after_enter.run.map_state.nodes[0].encounter_preview)
	assert_eq(after_enter.run.map_state.nodes[0].encounter_preview.encounter_id, &"encounter.normal")
	_assert_pool_conserved(after_enter.run.unit_pool_state)

	var offer_id := after_enter.run.economy_state.shop_offers[0].offer_id
	var bought := controller.dispatch(BuyOfferCommand.new(
		offer_id, catalog,
		EconomyTestFixture.battle_catalog(root.run.content_snapshot.manifest_digest_value())
	))
	assert_true(bought.ok)
	if not bought.ok: return
	assert_eq(bought.view_state.economy.gold, 57)
	assert_eq(bought.view_state.roster.unit_instances.size(), 2)
	var after_buy := repository.load()
	assert_true(after_buy.ok)
	assert_eq(after_buy.run.economy_state.shop_offers.size(), 4)
	assert_eq(after_buy.run.transaction_receipts.size(), 3)
	_assert_pool_conserved(after_buy.run.unit_pool_state)
	var stale := controller.dispatch(BuyOfferCommand.new(
		offer_id, catalog,
		EconomyTestFixture.battle_catalog(root.run.content_snapshot.manifest_digest_value())
	))
	assert_false(stale.ok)
	assert_eq(controller.view_state().economy.gold, 57)

func test_node_entry_save_failure_preserves_income_shop_rng_and_phase() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var map_result := MapService.new().generate_map(MapGenerationRequest.new(
		StringName(root.run.run_id), root.run.run_seed, catalog
	))
	assert_true(map_result.ok)
	if not map_result.ok: return
	root.run.map_state = map_result.map_state
	var target := root.run.map_state.nodes[0]
	var storage := FakeSaveStorage.new()
	storage.inject_fault(StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0))
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var before := controller.view_state()
	var result := controller.transition(EnterNodeEvent.new(
		target.node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(
			root.run.content_snapshot.manifest_digest_value()
		)
	))
	assert_false(result.ok)
	assert_eq(controller.view_state().run_phase, before.run_phase)
	assert_eq(controller.view_state().economy.gold, before.economy.gold)
	assert_null(controller.view_state().current_node_id)
	assert_eq(controller.view_state().publication_serial.to_hex(), before.publication_serial.to_hex())

func test_refresh_save_failure_preserves_gold_offers_rng_and_ledger() -> void:
	var root := _prepared_root()
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.save_fixture_catalog(manifest)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(manifest)
	)).ok)
	var before := repository.load()
	assert_true(before.ok)
	if not before.ok: return
	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0
	))
	var refreshed := controller.dispatch(RefreshShopCommand.new(catalog))
	assert_false(refreshed.ok)
	storage.clear_faults()
	var after := repository.load()
	assert_true(after.ok)
	if not after.ok: return
	assert_eq(after.run.economy_state.gold, before.run.economy_state.gold)
	assert_eq(
		after.run.economy_state.shop_refresh_index,
		before.run.economy_state.shop_refresh_index
	)
	assert_eq(
		after.run.rng_stream_states[NamedRngState.StreamName.SHOP].snapshot.counter.to_hex(),
		before.run.rng_stream_states[NamedRngState.StreamName.SHOP].snapshot.counter.to_hex()
	)
	assert_eq(
		after.run.economy_state.shop_offers.size(),
		before.run.economy_state.shop_offers.size()
	)
	assert_eq(after.run.reservation_owners.size(), before.run.reservation_owners.size())
	assert_eq(after.run.transaction_receipts.size(), before.run.transaction_receipts.size())

func test_generated_map_entry_persists_preview_and_can_start_combat() -> void:
	var root := _prepared_root()
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.save_fixture_catalog(manifest)
	var battle_catalog := EconomyTestFixture.expedition_battle_catalog(manifest)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var generated := controller.dispatch(GenerateExpeditionMapCommand.new(catalog))
	assert_true(generated.ok)
	if not generated.ok: return
	var after_map := repository.load()
	assert_true(after_map.ok)
	if not after_map.ok: return
	var target := after_map.run.map_state.nodes[0]
	var entered := controller.transition(EnterNodeEvent.new(
		target.node_id, catalog, battle_catalog
	))
	assert_true(entered.ok)
	if not entered.ok: return
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	assert_not_null(after_enter.run.map_state.nodes[0].encounter_preview)
	var start_event := StartCombatEvent.new(
		battle_catalog, _battle_sources(manifest)
	)
	var direct_start := start_event.apply_to(after_enter.run.deep_clone())
	assert_true(direct_start.ok, "%s:%s" % [
		String(direct_start.error.field_path) if direct_start.error != null else "none",
		str(direct_start.error.diagnostic_values) if direct_start.error != null else "none",
	])
	if not direct_start.ok: return
	var started := controller.transition(start_event)
	assert_true(started.ok, String(started.error.code) if started.error != null else "")
	if not started.ok: return
	assert_eq(started.view_state.run_phase, RunState.RunPhase.COMBAT)
	var after_start := repository.load()
	assert_true(after_start.ok)
	if not after_start.ok: return
	assert_true(after_start.run.resolution_state is CombatPendingResolutionState)

func test_generated_non_combat_and_rest_nodes_have_committed_exits() -> void:
	for target_group: Array in [
		[
			MapNodeState.NodeKind.MERCHANT,
			MapNodeState.NodeKind.EVENT,
			MapNodeState.NodeKind.TREASURE,
		],
		[MapNodeState.NodeKind.REST],
	]:
		var root := _prepared_root()
		_install_node_choice_snapshot(root.run)
		var manifest := root.run.content_snapshot.manifest_digest_value()
		var catalog := EconomyTestFixture.settlement_catalog(manifest)
		var generated := MapService.new().generate_map(MapGenerationRequest.new(
			StringName(root.run.run_id), root.run.run_seed, catalog
		))
		assert_true(generated.ok)
		if not generated.ok: continue
		root.run.map_state = generated.map_state
		var target: MapNodeState = null
		for node: MapNodeState in root.run.map_state.nodes:
			if node.node_kind in target_group:
				target = node
				break
		assert_not_null(target)
		if target == null: continue
		_make_target_reachable(root.run, target)
		var storage := FakeSaveStorage.new()
		var repository := _node_choice_repository(storage)
		add_child_autofree(repository)
		var controller := _controller_for(root, repository)
		var entered := controller.transition(EnterNodeEvent.new(
			target.node_id, catalog,
			EconomyTestFixture.expedition_battle_catalog(manifest)
		))
		assert_true(entered.ok)
		if not entered.ok: continue
		var choice_set := catalog.try_node_choice_set_for_map_node(target.def_id)
		if choice_set == null:
			# merchant 沒有 node choice set，出口仍是既有的 non-combat resolve。
			assert_eq(target.node_kind, MapNodeState.NodeKind.MERCHANT)
			var resolved := controller.dispatch(ResolveNonCombatNodeCommand.new(catalog))
			assert_true(resolved.ok)
			if not resolved.ok: continue
			assert_eq(resolved.view_state.run_phase, RunState.RunPhase.MAP)
		else:
			# event／rest／treasure 進入即產生 pending choice，出口改由 commit 承載。
			assert_not_null(controller.node_choice_pending_snapshot())
			var opens_reward := target.node_kind in [
				MapNodeState.NodeKind.EVENT, MapNodeState.NodeKind.TREASURE,
			]
			var wanted_outcome := NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE
			if opens_reward:
				wanted_outcome = NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
			var choice_id := _choice_id_with_outcome(choice_set, wanted_outcome)
			assert_false(choice_id.is_empty())
			var committed := controller.dispatch(CommitNodeChoiceCommand.new(
				choice_set, choice_id, catalog
			))
			assert_true(committed.ok)
			if not committed.ok: continue
			if opens_reward:
				assert_eq(committed.view_state.run_phase, RunState.RunPhase.REWARD)
				var reward_root := repository.load()
				assert_true(reward_root.ok)
				if not reward_root.ok: continue
				var pending := (reward_root.run.resolution_state as RewardPendingResolutionState).pending_reward
				assert_true(controller.dispatch(ChooseRewardCommand.new(
					pending.offers[0].choice_id, catalog
				)).ok)
				assert_true(controller.dispatch(AdvanceRewardCommand.new(catalog)).ok)
			else:
				assert_eq(committed.view_state.run_phase, RunState.RunPhase.MAP)
		var completed := repository.load()
		assert_true(completed.ok)
		if completed.ok:
			assert_true(_node_by_id(completed.run, target.node_id).completed)

## G2 content-production：unit grant 現在掛在 event choice 的 OPEN_REWARD_STAGE
## 出口（commit_node_choice_service.gd:141-157），因此原本對
## ResolveNonCombatNodeCommand 的原子性驗證改成對 CommitNodeChoiceCommand——
## 存檔失敗那一次不得留下保留副本、choice receipt 或相位變化。
func test_event_unit_grant_reservation_is_atomic_on_save_failure() -> void:
	var root := _prepared_root()
	_install_node_choice_snapshot(root.run)
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.event_unit_reward_catalog(manifest)
	var event_target: MapNodeState = null
	for seed_index: int in range(100):
		var seed := U64Bits.from_u32(0, seed_index).value
		var generated := MapService.new().generate_map(MapGenerationRequest.new(
			StringName(root.run.run_id), seed, catalog
		))
		if not generated.ok: continue
		for node: MapNodeState in generated.map_state.nodes:
			if node.node_kind == MapNodeState.NodeKind.EVENT:
				root.run.run_seed = seed
				root.run.map_state = generated.map_state
				event_target = node
				break
		if event_target != null: break
	assert_not_null(event_target)
	if event_target == null: return
	_make_target_reachable(root.run, event_target)
	var storage := FakeSaveStorage.new()
	var repository := _node_choice_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.transition(EnterNodeEvent.new(
		event_target.node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(manifest)
	)).ok)
	var choice_set := catalog.try_node_choice_set_for_map_node(event_target.def_id)
	assert_not_null(choice_set)
	if choice_set == null: return
	var grant_choice_id := _choice_id_with_outcome(
		choice_set, NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
	)
	assert_false(grant_choice_id.is_empty())
	var before := controller.view_state()
	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0
	))
	assert_false(controller.dispatch(CommitNodeChoiceCommand.new(
		choice_set, grant_choice_id, catalog
	)).ok)
	assert_eq(controller.view_state().run_phase, before.run_phase)
	storage.clear_faults()
	var after_failure := repository.load()
	assert_true(after_failure.ok)
	if not after_failure.ok: return
	assert_true(after_failure.run.resolution_state is NodeChoicePendingState)
	assert_true(after_failure.run.node_choice_receipts.is_empty())
	_assert_pool_conserved(after_failure.run.unit_pool_state)
	var resolved := controller.dispatch(CommitNodeChoiceCommand.new(
		choice_set, grant_choice_id, catalog
	))
	assert_true(resolved.ok)
	if not resolved.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	var pending := (loaded.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.stage_id, PendingRewardState.StageId.EVENT_GRANT)
	assert_eq(pending.offers.size(), 1)
	assert_eq(pending.offers[0].reward_kind, RewardOfferState.RewardKind.UNIT)
	assert_eq(pending.reserved_copies.size(), 1)
	assert_eq(loaded.run.node_choice_receipts.size(), 1)
	_assert_pool_conserved(loaded.run.unit_pool_state)

func test_unit_only_event_with_exhausted_pool_commits_noop_fallback_and_exits() -> void:
	var root := _prepared_root()
	_install_node_choice_snapshot(root.run)
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.event_unit_reward_catalog(manifest)
	var event_target: MapNodeState = null
	for seed_index: int in range(100):
		var seed := U64Bits.from_u32(0, seed_index).value
		var generated := MapService.new().generate_map(MapGenerationRequest.new(
			StringName(root.run.run_id), seed, catalog
		))
		if not generated.ok: continue
		for node: MapNodeState in generated.map_state.nodes:
			if node.node_kind == MapNodeState.NodeKind.EVENT:
				root.run.run_seed = seed
				root.run.map_state = generated.map_state
				event_target = node
				break
		if event_target != null: break
	assert_not_null(event_target)
	if event_target == null: return
	root.run.unit_pool_state.entries[0].total_copies = 1
	root.run.unit_pool_state.entries[0].remaining_copies = 0
	root.run.unit_pool_state.entries[0].held_copies = 1
	_make_target_reachable(root.run, event_target)
	var storage := FakeSaveStorage.new()
	var repository := _node_choice_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.transition(EnterNodeEvent.new(
		event_target.node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(manifest)
	)).ok)
	var choice_set := catalog.try_node_choice_set_for_map_node(event_target.def_id)
	assert_not_null(choice_set)
	if choice_set == null: return
	var grant_choice_id := _choice_id_with_outcome(
		choice_set, NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
	)
	assert_false(grant_choice_id.is_empty())
	var resolved := controller.dispatch(CommitNodeChoiceCommand.new(
		choice_set, grant_choice_id, catalog
	))
	assert_true(resolved.ok)
	if not resolved.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	var pending := (loaded.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.offers.size(), 1)
	assert_eq(pending.offers[0].reward_kind, RewardOfferState.RewardKind.EVENT)
	assert_eq(pending.offers[0].amount, 0)
	assert_true(pending.reserved_copies.is_empty())
	assert_true(controller.dispatch(ChooseRewardCommand.new(
		pending.offers[0].choice_id, catalog
	)).ok)
	assert_true(controller.dispatch(AdvanceRewardCommand.new(catalog)).ok)
	assert_eq(controller.view_state().run_phase, RunState.RunPhase.MAP)

func _prepared_root() -> SaveRoot:
	var root := SaveRootFixture.create_valid_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	root.run.run_phase = RunState.RunPhase.MAP
	root.run.current_node_id = null
	root.run.map_state.current_node_id = null
	root.run.map_state.completed_node_ids.clear()
	root.run.resolution_state = IdleResolutionState.new()
	root.run.economy_state = EconomyState.new(47, 3, 0, 5, 0, 0, [])
	root.run.unit_pool_state = catalog.create_initial_pool()
	root.run.unit_pool_state.entries[0].remaining_copies -= 1
	root.run.unit_pool_state.entries[0].held_copies = 1
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1,
		no_equipment, U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(3, 3, unit.instance_id)
	]
	var bench: Array[String] = []
	var units: Array[UnitInstance] = [unit]
	var items: Array[ItemInstanceState] = []
	var item_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	root.run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, items,
		item_ids, item_ids, relics
	)
	root.run.reservation_owners.clear()
	root.run.transaction_receipts.clear()
	root.run.income_claimed_node_ids.clear()
	root.run.next_transaction_serial = U64Bits.zero()
	root.run.next_unit_serial = U64Bits.from_u32(0, 2).value
	return root

## NodeChoicePendingState 只在 catalog schema 2／content codec 3 下合法
## （node_choice_pending_state.gd:45），而 SaveRootFixture 的基準 receipt 仍是 (1,2)。
## 需要 node choice 的案例改釘同內容的 codec3 receipt：manifest digest 不變，
## EconomyTestFixture 的 catalog 與既有斷言因此完全相容。
func _node_choice_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	return PinnedCatalogBuildReceipt.new(
		2, 3, base.content_version, base.selection_digest, base.active_entry_ids,
		base.economy_config_id, base.combat_config_id, base.reward_table_ids,
		base.map_node_def_ids, base.challenge_unlock_def_ids,
		base.meta_reward_table_id, base.manifest_digest
	)

func _install_node_choice_snapshot(run: RunState) -> void:
	var built := ContentSnapshotState.from_pinned_receipt(_node_choice_receipt())
	assert_true(built.ok)
	if built.ok:
		run.content_snapshot = built.snapshot

func _node_choice_repository(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(_node_choice_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

func _choice_id_with_outcome(
	choice_set: NodeChoiceSetRule, outcome_kind: int
) -> StringName:
	for choice: NodeChoiceRule in choice_set.choices:
		if choice.outcome_kind == outcome_kind:
			return choice.choice_id
	return &""

func _battle_sources(manifest: String) -> BattleSetupSourceBundle:
	var player := UnitBattleSnapshot.new()
	player.instance_id = &"u_0000000000000001"
	player.unit_id = &"unit.fixture"
	player.side = &"player"
	player.logical_y = 3
	player.logical_x = 3
	player.health = 100
	player.attack = 10
	player.armor = 5
	player.magic_resist = 5
	player.attack_speed_milli = 1000
	player.attack_range_cells = 1
	player.max_mana = 100
	player.move_speed_milli = 1000
	var players: Array[UnitBattleSnapshot] = [player]
	var traits: Array[TraitBattleSnapshot] = []
	var effects: Array[BattleEffectSnapshot] = []
	return BattleSetupSourceBundle.new(
		manifest, players, traits, effects, effects, effects, effects,
		true, true, true, true, true, true
	)

func _make_target_reachable(run: RunState, target: MapNodeState) -> void:
	for edge: MapEdgeState in run.map_state.edges:
		if edge.to_node_id == target.node_id:
			var predecessor := _node_by_id(run, edge.from_node_id)
			predecessor.completed = true
			run.map_state.completed_node_ids = [predecessor.node_id]
			run.current_node_id = OptionalStringValue.new(predecessor.node_id)
			run.map_state.current_node_id = OptionalStringValue.new(predecessor.node_id)
			return

func _node_by_id(run: RunState, node_id: String) -> MapNodeState:
	for node: MapNodeState in run.map_state.nodes:
		if node.node_id == node_id:
			return node
	return null

func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	var session := RunSession.new(
		root.profile, root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	)
	return RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	)

func _assert_pool_conserved(pool: UnitPoolState) -> void:
	for entry: UnitPoolEntryState in pool.entries:
		assert_eq(entry.remaining_copies + entry.reserved_copies + entry.held_copies, entry.total_copies)

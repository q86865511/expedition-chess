extends GutTest

func test_win_settlement_choice_and_advance_commit_each_subphase() -> void:
	var root := _battle_root()
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var settled := controller.dispatch(SettleBattleResultCommand.new(catalog))
	assert_true(settled.ok, _command_error(settled))
	if not settled.ok: return
	assert_eq(settled.view_state.run_phase, RunState.RunPhase.REWARD)
	var after_settle := repository.load()
	assert_true(after_settle.ok)
	if not after_settle.ok: return
	assert_true(after_settle.run.resolution_state is RewardPendingResolutionState)
	var pending := (after_settle.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.phase, PendingRewardState.Phase.CHOOSING)
	assert_eq(pending.offers.size(), 3)
	var choice_id := pending.offers[0].choice_id
	var chosen := controller.dispatch(ChooseRewardCommand.new(choice_id, catalog))
	assert_true(chosen.ok, _command_error(chosen))
	if not chosen.ok: return
	var after_choose := repository.load()
	assert_true(after_choose.ok)
	if not after_choose.ok: return
	assert_eq((after_choose.run.resolution_state as RewardPendingResolutionState).pending_reward.phase, PendingRewardState.Phase.READY_TO_ADVANCE)
	var advanced := controller.dispatch(AdvanceRewardCommand.new(catalog))
	assert_true(advanced.ok, _command_error(advanced))
	if not advanced.ok: return
	assert_eq(advanced.view_state.run_phase, RunState.RunPhase.MAP)
	var after_advance := repository.load()
	assert_true(after_advance.ok)
	if not after_advance.ok: return
	assert_true(after_advance.run.resolution_state is IdleResolutionState)
	assert_true(after_advance.run.map_state.nodes[0].completed)
	assert_eq(after_advance.run.economy_state.shop_offers.size(), 0)
	_assert_pool_conserved(after_advance.run.unit_pool_state)

func test_settlement_save_failure_preserves_result_hp_claims_rng_and_serial() -> void:
	var root := _battle_root()
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var storage := FakeSaveStorage.new()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0
	))
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var before := controller.view_state()
	var before_snapshot := controller.committed_combat_snapshot()
	var result := controller.dispatch(SettleBattleResultCommand.new(catalog))
	assert_false(result.ok)
	assert_eq(controller.view_state().run_phase, before.run_phase)
	assert_eq(controller.view_state().expedition_hp, before.expedition_hp)
	assert_eq(controller.view_state().publication_serial.to_hex(), before.publication_serial.to_hex())
	var after_snapshot := controller.committed_combat_snapshot()
	assert_eq(after_snapshot.resolution_state.kind, before_snapshot.resolution_state.kind)
	var before_result := (before_snapshot.resolution_state as BattleResultPendingResolutionState).battle_result
	var after_result := (after_snapshot.resolution_state as BattleResultPendingResolutionState).battle_result
	assert_eq(after_result.result_hash, before_result.result_hash)

func test_elite_two_stage_reward_reloads_each_stage_and_rolls_back_failed_transition() -> void:
	var root := _battle_root()
	_replace_node_kind(root.run, MapNodeState.NodeKind.ELITE)
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.settlement_catalog(manifest)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(SettleBattleResultCommand.new(catalog)).ok)
	var standard_root := repository.load()
	assert_true(standard_root.ok)
	if not standard_root.ok: return
	var standard := (standard_root.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(standard.stage_id, PendingRewardState.StageId.STANDARD)
	assert_true(controller.dispatch(ChooseRewardCommand.new(
		standard.offers[0].choice_id, catalog
	)).ok)
	var ready_standard := repository.load()
	assert_true(ready_standard.ok)
	if not ready_standard.ok: return
	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0
	))
	var failed := controller.dispatch(AdvanceRewardCommand.new(catalog))
	assert_false(failed.ok)
	storage.clear_faults()
	var after_failure := repository.load()
	assert_true(after_failure.ok)
	if not after_failure.ok: return
	var unchanged := (after_failure.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(unchanged.stage_id, PendingRewardState.StageId.STANDARD)
	assert_eq(unchanged.phase, PendingRewardState.Phase.READY_TO_ADVANCE)
	assert_eq(
		after_failure.run.rng_stream_states[NamedRngState.StreamName.REWARD].snapshot.counter.to_hex(),
		ready_standard.run.rng_stream_states[NamedRngState.StreamName.REWARD].snapshot.counter.to_hex()
	)
	var quoted_retry := RewardService.new().advance(after_failure.run, catalog)
	assert_true(quoted_retry.ok)
	if not quoted_retry.ok: return
	var retry_validation := RunStateValidator.new().validate_run(quoted_retry.run_state)
	assert_true(
		retry_validation.ok,
		String(retry_validation.error.field_path) if retry_validation.error != null else "none"
	)
	if not retry_validation.ok: return
	var retried := controller.dispatch(AdvanceRewardCommand.new(catalog))
	assert_true(retried.ok, _command_error(retried))
	if not retried.ok: return
	var relic_root := repository.load()
	assert_true(relic_root.ok)
	if not relic_root.ok: return
	var relic := (relic_root.run.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(relic.stage_id, PendingRewardState.StageId.RELIC)
	assert_eq(relic.phase, PendingRewardState.Phase.CHOOSING)
	assert_true(controller.dispatch(ChooseRewardCommand.new(
		relic.offers[0].choice_id, catalog
	)).ok)
	var chosen_relic := repository.load()
	assert_true(chosen_relic.ok)
	if not chosen_relic.ok: return
	assert_eq(
		(chosen_relic.run.resolution_state as RewardPendingResolutionState).pending_reward.phase,
		PendingRewardState.Phase.READY_TO_ADVANCE
	)
	assert_true(controller.dispatch(AdvanceRewardCommand.new(catalog)).ok)
	var completed := repository.load()
	assert_true(completed.ok)
	if not completed.ok: return
	assert_eq(completed.run.run_phase, RunState.RunPhase.MAP)
	assert_true(completed.run.map_state.nodes[0].completed)

func _replace_node_kind(run: RunState, kind: MapNodeState.NodeKind) -> void:
	var old := run.map_state.nodes[0]
	var built := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), old.act_index,
		MapNodeState.node_kind_to_token(kind), old.layer_index, old.slot_index
	)
	assert_true(built.ok)
	if not built.ok: return
	var key := built.key_state as NodeKeyState
	run.map_state.nodes[0] = MapNodeState.new(
		String(key.digest), key, old.def_id, old.act_index, old.layer_index,
		old.slot_index, kind, old.generated_payload_digest,
		old.encounter_preview, old.completed
	)
	run.current_node_id = OptionalStringValue.new(String(key.digest))
	run.map_state.current_node_id = OptionalStringValue.new(String(key.digest))
	run.income_claimed_node_ids = [String(key.digest)]
	var owner_keys: Dictionary = {}
	for owner: ReservationOwnerState in run.reservation_owners:
		var old_digest := owner.key.digest
		var owner_built := RuntimeKeySchemaRegistry.new().build_reservation_owner(
			StringName(run.run_id), key.digest, owner.key.source_kind,
			owner.key.stage_or_refresh_id, owner.key.slot_index
		)
		assert_true(owner_built.ok)
		if not owner_built.ok: return
		owner.key = owner_built.key_state as ReservationOwnerKeyState
		owner_keys[old_digest] = owner.key
	for offer: ShopOffer in run.economy_state.shop_offers:
		offer.reservation_owner_key = (
			owner_keys[offer.reservation_owner_key.digest] as ReservationOwnerKeyState
		).deep_clone() as ReservationOwnerKeyState
		offer.offer_id = String(offer.reservation_owner_key.digest)
	run.reservation_owners.sort_custom(func(left: ReservationOwnerState, right: ReservationOwnerState) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)

func _battle_root() -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(
		ResolutionState.Kind.BATTLE_RESULT_PENDING
	)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = 90
	root.run.economy_state.level = 3
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	return root

func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	var session := RunSession.new(
		root.profile, root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	)
	return RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	)

func _command_error(result: CommandResult) -> String:
	if result.error == null:
		return "none"
	var source := ""
	for diagnostic: DiagnosticValue in result.error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			source = diagnostic.string_value.value
	return "%s:%s:%s" % [
		String(result.error.code), String(result.error.field_path), source
	]

func _assert_pool_conserved(pool: UnitPoolState) -> void:
	for entry: UnitPoolEntryState in pool.entries:
		assert_eq(
			entry.remaining_copies + entry.reserved_copies + entry.held_copies,
			entry.total_copies
		)

extends GutTest

func test_valid_fixture_and_deep_clone_isolation() -> void:
	var root := SaveRootFixture.create_valid_root()
	var validation := RunStateValidator.new().validate_root(root)
	assert_true(validation.ok)
	var cloned := root.deep_clone()
	cloned.run.economy_state.gold = 77
	cloned.run.roster_state.active_relic_slots[0].relic_id = OptionalStringNameValue.new(&"relic.test")
	assert_eq(root.run.economy_state.gold, 0)
	assert_null(root.run.roster_state.active_relic_slots[0].relic_id)

func test_view_projection_does_not_share_nested_state() -> void:
	var root := SaveRootFixture.create_valid_root()
	var view := RunViewState.from_run(root.run, U64Bits.zero())
	view.economy.gold = 90
	view.roster.active_relic_slots[0].relic_id = OptionalStringNameValue.new(&"relic.test")
	assert_eq(root.run.economy_state.gold, 0)
	assert_null(root.run.roster_state.active_relic_slots[0].relic_id)

func test_content_snapshot_factories_normalize_order_and_reject_invalid_inputs() -> void:
	var receipt := SaveRootFixture.create_receipt()
	var reversed_ids: Array[StringName] = receipt.active_entry_ids.duplicate()
	reversed_ids.reverse()
	var normalized := ContentSnapshotState.from_persisted(
		receipt.content_version,
		reversed_ids,
		receipt.economy_config_id,
		receipt.combat_config_id,
		receipt.reward_table_ids,
		receipt.map_node_def_ids,
		receipt.challenge_unlock_def_ids,
		receipt.meta_reward_table_id,
		receipt.manifest_digest,
		receipt
	)
	assert_true(normalized.ok)
	assert_eq(normalized.snapshot.enabled_content_ids_copy(), receipt.active_entry_ids)
	var duplicate_ids: Array[StringName] = receipt.active_entry_ids.duplicate()
	duplicate_ids.append(duplicate_ids[0])
	var duplicate := ContentSnapshotState.from_persisted(
		receipt.content_version,
		duplicate_ids,
		receipt.economy_config_id,
		receipt.combat_config_id,
		receipt.reward_table_ids,
		receipt.map_node_def_ids,
		receipt.challenge_unlock_def_ids,
		receipt.meta_reward_table_id,
		receipt.manifest_digest,
		receipt
	)
	assert_false(duplicate.ok)
	assert_eq(duplicate.error.code, ContentSnapshotBuildError.INPUT_INVALID)
	assert_eq(duplicate.error.field_path, &"content_snapshot.enabled_content_ids")
	var invalid_digest := ContentSnapshotState.from_persisted(
		receipt.content_version,
		receipt.active_entry_ids,
		receipt.economy_config_id,
		receipt.combat_config_id,
		receipt.reward_table_ids,
		receipt.map_node_def_ids,
		receipt.challenge_unlock_def_ids,
		receipt.meta_reward_table_id,
		"invalid",
		receipt
	)
	assert_false(invalid_digest.ok)
	assert_eq(invalid_digest.error.code, ContentSnapshotBuildError.INPUT_INVALID)
	assert_eq(invalid_digest.error.field_path, &"content_snapshot.manifest_digest")
	var mismatch := ContentSnapshotState.from_persisted(
		"fixture.changed",
		receipt.active_entry_ids,
		receipt.economy_config_id,
		receipt.combat_config_id,
		receipt.reward_table_ids,
		receipt.map_node_def_ids,
		receipt.challenge_unlock_def_ids,
		receipt.meta_reward_table_id,
		receipt.manifest_digest,
		receipt
	)
	assert_false(mismatch.ok)
	assert_eq(mismatch.error.code, ContentSnapshotBuildError.RECEIPT_MISMATCH)

func test_runtime_key_digest_tamper_is_rejected() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.run_key.digest = &"run_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	root.run.run_id = String(root.run.run_key.digest)
	var validation := RunStateValidator.new().validate_root(root)
	assert_false(validation.ok)
	assert_eq(validation.error.field_path, &"run.run_key.digest")

func test_map_cycle_is_rejected_after_fixed_order_edge_validation() -> void:
	var root := SaveRootFixture.create_valid_root()
	var registry := RuntimeKeySchemaRegistry.new()
	var first_result := registry.build_node(
		StringName(root.run.run_id), 0, &"normal", 0, 0
	)
	var second_result := registry.build_node(
		StringName(root.run.run_id), 0, &"normal", 0, 1
	)
	var first_key := first_result.key_state as NodeKeyState
	var second_key := second_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [
		_map_node(first_key, 0),
		_map_node(second_key, 1),
	]
	var first_edge := MapEdgeState.new(String(first_key.digest), String(second_key.digest))
	var second_edge := MapEdgeState.new(String(second_key.digest), String(first_key.digest))
	var edges: Array[MapEdgeState] = []
	if first_edge.from_node_id < second_edge.from_node_id:
		edges.append(first_edge)
		edges.append(second_edge)
	else:
		edges.append(second_edge)
		edges.append(first_edge)
	var completed: Array[String] = []
	root.run.map_state = MapState.new(nodes, edges, null, completed)
	var validation := RunStateValidator.new().validate_root(root)
	assert_false(validation.ok)
	assert_eq(validation.error.field_path, &"run.map_state.edges.cycle")

func test_rng_snapshot_zero_increment_is_rejected() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.rng_stream_states[0].snapshot.inc = U64Bits.zero()
	var validation := RunStateValidator.new().validate_root(root)
	assert_false(validation.ok)
	assert_eq(validation.error.field_path, &"run.rng_stream_states.0.snapshot")

func test_rng_snapshot_even_increment_is_rejected() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.rng_stream_states[1].snapshot.inc = U64Bits.from_hex(
		"0000000000000002"
	).value
	var validation := RunStateValidator.new().validate_root(root)
	assert_false(validation.ok)
	assert_eq(validation.error.field_path, &"run.rng_stream_states.1.snapshot")

func test_rng_snapshot_missing_state_and_counter_are_rejected() -> void:
	var missing_state := SaveRootFixture.create_valid_root()
	missing_state.run.rng_stream_states[2].snapshot.state = null
	assert_false(RunStateValidator.new().validate_root(missing_state).ok)
	var missing_counter := SaveRootFixture.create_valid_root()
	missing_counter.run.rng_stream_states[3].snapshot.counter = null
	assert_false(RunStateValidator.new().validate_root(missing_counter).ok)

func test_combat_rng_snapshot_uses_the_same_pcg_invariant() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.resolution_state = CombatPendingResolutionState.new(_battle_setup())
	var combat := root.run.resolution_state as CombatPendingResolutionState
	combat.battle_setup.combat_rng_snapshot.inc = U64Bits.zero()
	var validation := RunStateValidator.new().validate_root(root)
	assert_false(validation.ok)
	assert_eq(
		validation.error.field_path,
		&"run.resolution_state.battle_setup.combat_rng_snapshot"
	)

func test_four_resolution_subclasses_have_one_payload_path() -> void:
	var idle: ResolutionState = IdleResolutionState.new()
	assert_true(idle.deep_clone() is IdleResolutionState)
	var setup := _battle_setup()
	var combat: ResolutionState = CombatPendingResolutionState.new(setup)
	assert_true(combat.deep_clone() is CombatPendingResolutionState)
	var battle_result := BattleResult.new()
	battle_result.battle_setup_hash = setup.battle_setup_hash
	battle_result.outcome = &"player_win"
	battle_result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(battle_result.to_record())
	assert_true(sealed.ok)
	battle_result = BattleResult.from_record(sealed.record)
	var result_pending: ResolutionState = BattleResultPendingResolutionState.new(
		String(setup.battle_setup_hash), battle_result
	)
	assert_true(result_pending.deep_clone() is BattleResultPendingResolutionState)
	var transaction_result := RuntimeKeySchemaRegistry.new().build_transaction(
		&"run_test", &"camp", &"reward", U64Bits.zero()
	)
	var empty_offers: Array[RewardOfferState] = []
	var empty_reserved: Array[ReservedCopyState] = []
	var pending := PendingRewardState.new(
		"node_test", PendingRewardState.StageId.STANDARD, PendingRewardState.Phase.CHOOSING,
		empty_offers, empty_reserved, null, null,
		transaction_result.key_state as TransactionKeyState
	)
	var reward: ResolutionState = RewardPendingResolutionState.new(pending)
	assert_true(reward.deep_clone() is RewardPendingResolutionState)

func _battle_setup() -> BattleSetup:
	var fixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")
	var inputs: BattleSetupInputs = fixture.create_inputs()
	var encoded := CanonicalBattleCodecV1.new().encode(inputs)
	var setup := BattleSetup.new()
	setup.inputs = inputs
	setup.hash_version = 1
	setup.battle_setup_hash = StringName(BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes))
	setup.rng_version = 1
	setup.combat_rng_snapshot = RngSnapshot.create(1, U64Bits.zero(), U64Bits.one(), U64Bits.zero()).snapshot
	return setup

func _map_node(key: NodeKeyState, slot_index: int) -> MapNodeState:
	return MapNodeState.new(
		String(key.digest), key, &"mapnode.fixture", 0, 0, slot_index,
		MapNodeState.NodeKind.NORMAL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		null, false
	)

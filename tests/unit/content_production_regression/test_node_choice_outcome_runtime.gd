extends GutTest


func test_treasure_choice_opens_exact_pinned_reward_table() -> void:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.IDLE)
	var run := root.run
	_install_codec3_content_snapshot(run)
	run.run_phase = RunState.RunPhase.PREPARE
	_install_current_treasure_node(run)
	var choices: Array[NodeChoiceRule] = [
		_choice(
			&"choice.treasure.standard",
			&"reward.standard",
			NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
		),
		_choice(
			&"choice.treasure.gold",
			&"",
			NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE
		),
	]
	var choice_set := NodeChoiceSetRule.new(
		&"choice_set.treasure",
		&"loc.choice_set_treasure",
		&"treasure",
		choices
	)
	var service := CommitNodeChoiceService.new()
	var begun := service.begin(
		run,
		StringName(run.current_node_id.value),
		choice_set,
		"0123456789abcdef"
	)
	assert_true(begun.ok)
	if not begun.ok:
		return
	var catalog := EconomyTestFixture.settlement_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var committed := service.commit(
		begun.run_state,
		choice_set,
		&"choice.treasure.standard",
		catalog
	)
	assert_true(
		committed.ok,
		"%s:%s" % [
			String(committed.error.code) if committed.error != null else "",
			String(committed.error.field_path) if committed.error != null else "",
		]
	)
	if not committed.ok:
		return
	assert_eq(committed.run_state.run_phase, RunState.RunPhase.REWARD)
	assert_true(
		committed.run_state.resolution_state is RewardPendingResolutionState
	)
	var pending := (
		committed.run_state.resolution_state as RewardPendingResolutionState
	).pending_reward
	assert_eq(pending.stage_id, PendingRewardState.StageId.STANDARD)
	assert_eq(pending.offers.size(), 3)
	assert_eq(committed.run_state.node_choice_receipts.size(), 1)
	assert_true(
		committed.run_state.node_choice_receipts[0].result_acknowledged
	)
	assert_eq(run.run_phase, RunState.RunPhase.PREPARE)
	assert_true(run.resolution_state is IdleResolutionState)
	assert_true(run.node_choice_receipts.is_empty())


func _choice(
	choice_id: StringName,
	reward_table_ref: StringName,
	outcome: int
) -> NodeChoiceRule:
	var operations: Array[NodeChoiceOperationRule] = []
	if outcome == NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE:
		operations.append(NodeChoiceOperationRule.new(
			NodeChoiceOperationRule.Kind.ADD_GOLD,
			1,
			0,
			&"once_per_node"
		))
	return NodeChoiceRule.new(
		choice_id,
		0,
		&"loc.choice_title",
		&"loc.choice_description",
		&"loc.choice_preview",
		&"loc.choice_result",
		operations,
		reward_table_ref,
		not reward_table_ref.is_empty(),
		outcome,
		true
	)


func _install_current_treasure_node(run: RunState) -> void:
	var old := run.map_state.nodes[0]
	var built := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id),
		old.act_index,
		&"treasure",
		old.layer_index,
		old.slot_index
	)
	assert_true(built.ok)
	var key := built.key_state as NodeKeyState
	var node := MapNodeState.new(
		String(key.digest),
		key,
		&"mapnode.fixture",
		old.act_index,
		old.layer_index,
		old.slot_index,
		MapNodeState.NodeKind.TREASURE,
		old.generated_payload_digest,
		null,
		false
	)
	run.map_state.nodes = [node]
	run.current_node_id = OptionalStringValue.new(node.node_id)
	run.map_state.current_node_id = OptionalStringValue.new(node.node_id)


func _install_codec3_content_snapshot(run: RunState) -> void:
	var source := SaveRootFixture.create_receipt()
	var receipt := PinnedCatalogBuildReceipt.new(
		2,
		3,
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
	var built := ContentSnapshotState.from_pinned_receipt(receipt)
	assert_true(built.ok)
	if built.ok:
		run.content_snapshot = built.snapshot

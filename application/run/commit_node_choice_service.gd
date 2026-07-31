class_name CommitNodeChoiceService
extends RefCounted

const OUTCOME_APPLY_AND_COMPLETE := 1
const OUTCOME_OPEN_DISMANTLE_SERVICE := 2
const OUTCOME_OPEN_REWARD_STAGE := 3


func begin(
	source: RunState,
	node_id: StringName,
	choice_set: NodeChoiceSetRule,
	lifecycle_nonce: String
) -> ExpeditionActionResult:
	if (
		source == null
		or source.content_snapshot == null
		or choice_set == null
		or choice_set.choices.size() < 2
	):
		return _failure(ExpeditionActionError.INPUT_INVALID, &"choice_set")
	if (
		source.run_phase != RunState.RunPhase.PREPARE
		or not source.resolution_state is IdleResolutionState
	):
		return _failure(ExpeditionActionError.PHASE_INVALID, &"resolution_state")
	var choice_ids: Array[StringName] = []
	for choice: NodeChoiceRule in choice_set.choices:
		if choice == null or choice.choice_id.is_empty() or choice_ids.has(choice.choice_id):
			return _failure(ExpeditionActionError.INPUT_INVALID, &"choice_set.choices")
		choice_ids.append(choice.choice_id)
	var draft := source.deep_clone()
	draft.resolution_state = NodeChoicePendingState.new(
		node_id,
		choice_set.choice_set_id,
		choice_ids,
		draft.content_snapshot.content_version_value(),
		draft.content_snapshot.catalog_schema_version_value(),
		draft.content_snapshot.content_codec_version_value(),
		draft.content_snapshot.manifest_digest_value(),
		lifecycle_nonce
	)
	if not (draft.resolution_state as NodeChoicePendingState).is_valid():
		return _failure(ExpeditionActionError.INPUT_INVALID, &"lifecycle_nonce")
	return ExpeditionActionResult.success(draft)


func cancel(source: RunState) -> ExpeditionActionResult:
	if source == null or not source.resolution_state is NodeChoicePendingState:
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state")
	var pending := source.resolution_state as NodeChoicePendingState
	if not pending.is_valid():
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"pending_digest")
	var draft := source.deep_clone()
	draft.resolution_state = IdleResolutionState.new()
	return ExpeditionActionResult.success(draft)


func commit(
	source: RunState,
	choice_set: NodeChoiceSetRule,
	choice_id: StringName,
	catalog: EconomyExpeditionCatalog = null
) -> ExpeditionActionResult:
	if source == null or choice_set == null:
		return _failure(ExpeditionActionError.INPUT_INVALID, &"source")
	if not source.resolution_state is NodeChoicePendingState:
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state")
	var pending := source.resolution_state as NodeChoicePendingState
	if (
		not pending.is_valid()
		or pending.choice_set_id != choice_set.choice_set_id
		or not pending.choice_ids.has(choice_id)
	):
		return _failure(ExpeditionActionError.RESULT_INVALID, &"choice_id")
	for ledger_entry: NodeChoiceReceiptLedgerEntry in source.node_choice_receipts:
		if (
			ledger_entry != null
			and ledger_entry.receipt != null
			and ledger_entry.receipt.pending_digest == pending.pending_digest
		):
			return _failure(ExpeditionActionError.RESULT_INVALID, &"pending_digest")
	var selected := _find_choice(choice_set, choice_id)
	if selected == null:
		return _failure(ExpeditionActionError.RESULT_INVALID, &"choice_id")
	var draft := source.deep_clone()
	var operation_error := _apply_operations(draft, selected.operations)
	if operation_error != null:
		return ExpeditionActionResult.failure(
			operation_error.code, operation_error.field_path
		)
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return _failure(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_transaction_serial"
		)
	var serial_bits := draft.next_transaction_serial.deep_clone()
	var serial := serial_bits.to_hex()
	var built_key := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id),
		pending.node_id,
		&"commit_node_choice",
		serial_bits
	)
	if not built_key.ok:
		return _failure(
			ExpeditionActionError.KEY_FAILED, &"transaction_digest"
		)
	var transaction_digest := String(built_key.key_state.digest)
	var receipt := NodeChoiceCommitReceiptState.new()
	receipt.run_id = StringName(draft.run_id)
	receipt.node_id = pending.node_id
	receipt.choice_set_id = pending.choice_set_id
	receipt.choice_id = choice_id
	receipt.pending_digest = pending.pending_digest
	receipt.lifecycle_nonce = pending.lifecycle_nonce
	receipt.transaction_serial = serial
	receipt.transaction_digest = transaction_digest
	receipt.result_key = selected.result_key
	receipt.outcome_kind = selected.outcome_kind
	receipt.refresh_digest()
	if not receipt.is_valid():
		return _failure(
			ExpeditionActionError.DIGEST_FAILED, &"receipt_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft,
		TransactionReceiptState.new(
			built_key.key_state as TransactionKeyState,
			receipt.receipt_digest
		)
	)
	draft.node_choice_receipts.append(
		NodeChoiceReceiptLedgerEntry.new(receipt, false)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	match selected.outcome_kind:
		OUTCOME_OPEN_DISMANTLE_SERVICE:
			draft.resolution_state = NodeServicePendingResolutionState.new(
				&"dismantle", pending.node_id, receipt.receipt_digest
			)
		OUTCOME_OPEN_REWARD_STAGE:
			var reward_stage := _reward_stage(selected, catalog)
			if reward_stage < 0:
				return _failure(
					ExpeditionActionError.REWARD_CONFIG_INVALID,
					&"choice.reward_table_ref"
				)
			draft.resolution_state = IdleResolutionState.new()
			var generated := RewardService.new().generate_stage(
				draft,
				reward_stage,
				catalog
			)
			if not generated.ok:
				return generated
			draft = generated.run_state
			_acknowledge_receipt(draft, receipt.receipt_digest)
		_:
			_complete_current_node(draft)
			draft.resolution_state = IdleResolutionState.new()
			draft.run_phase = RunState.RunPhase.MAP
	return ExpeditionActionResult.success(draft)


func _reward_stage(
	choice: NodeChoiceRule,
	catalog: EconomyExpeditionCatalog
) -> int:
	if (
		choice == null
		or not choice.has_reward_table_ref
		or catalog == null
	):
		return -1
	var table := catalog.try_reward_table_by_id(choice.reward_table_ref)
	if table == null:
		return -1
	if table.supports_stage(PendingRewardState.StageId.RELIC):
		return PendingRewardState.StageId.RELIC
	if table.supports_stage(PendingRewardState.StageId.STANDARD):
		return PendingRewardState.StageId.STANDARD
	if table.supports_stage(PendingRewardState.StageId.EVENT_GRANT):
		return PendingRewardState.StageId.EVENT_GRANT
	return -1


func _acknowledge_receipt(draft: RunState, receipt_digest: String) -> void:
	for entry: NodeChoiceReceiptLedgerEntry in draft.node_choice_receipts:
		if (
			entry != null
			and entry.receipt != null
			and entry.receipt.receipt_digest == receipt_digest
		):
			entry.result_acknowledged = true
			return


func _find_choice(
	choice_set: NodeChoiceSetRule,
	choice_id: StringName
) -> NodeChoiceRule:
	for choice: NodeChoiceRule in choice_set.choices:
		if choice != null and choice.choice_id == choice_id:
			return choice
	return null


func _apply_operations(
	draft: RunState,
	operations: Array[NodeChoiceOperationRule]
) -> ExpeditionActionError:
	for operation: NodeChoiceOperationRule in operations:
		if operation.kind == NodeChoiceOperationRule.Kind.ADD_GOLD:
			draft.economy_state.gold += operation.amount
		elif operation.kind == NodeChoiceOperationRule.Kind.HEAL_EXPEDITION_HP:
			draft.expedition_hp = mini(
				100,
				draft.expedition_hp + operation.amount
			)
		elif operation.kind == NodeChoiceOperationRule.Kind.DRAIN_EXPEDITION_HP:
			draft.expedition_hp = maxi(
				1,
				draft.expedition_hp - operation.amount
			)
		else:
			return ExpeditionActionError.new(
				ExpeditionActionError.INPUT_INVALID, &"choice.operations"
			)
	return null


func _complete_current_node(draft: RunState) -> void:
	if draft.current_node_id == null:
		return
	for node: MapNodeState in draft.map_state.nodes:
		if node.node_id != draft.current_node_id.value:
			continue
		node.completed = true
		if not draft.map_state.completed_node_ids.has(node.node_id):
			draft.map_state.completed_node_ids.append(node.node_id)
			draft.map_state.completed_node_ids.sort()
		return


func _failure(code: StringName, path: StringName) -> ExpeditionActionResult:
	return ExpeditionActionResult.failure(code, path)

class_name NonCombatNodeService
extends RefCounted

func resolve(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	if source == null or catalog == null or source.content_snapshot == null:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.INPUT_INVALID, &"source"
		)
	if catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.GENERATION_MISMATCH,
			&"content_snapshot.manifest_digest"
		)
	if source.run_phase != RunState.RunPhase.PREPARE \
		or not source.resolution_state is IdleResolutionState:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	# Hard gate (design §5.4): leaving PREPARE via a non-combat node is refused
	# while the item-overflow tray is non-empty, mirroring the StartCombatEvent
	# gate so the tray can never be bypassed into a softlock.
	if source.roster_state != null \
		and not source.roster_state.pending_item_overflow.is_empty():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.OVERFLOW_PENDING, &"roster_state.pending_item_overflow"
		)
	var node := _current_node(source)
	if node == null or node.node_kind in [
		MapNodeState.NodeKind.NORMAL,
		MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.BOSS,
	]:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	if node.node_kind in [MapNodeState.NodeKind.EVENT, MapNodeState.NodeKind.TREASURE]:
		return RewardService.new().generate_stage(
			source, PendingRewardState.StageId.EVENT_GRANT, catalog
		)
	var draft := source.deep_clone()
	if node.node_kind == MapNodeState.NodeKind.REST:
		draft.expedition_hp = mini(100, draft.expedition_hp + 20)
	var release_error := RewardService.new().try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(
			release_error.code, release_error.field_path
		)
	var current := _current_node(draft)
	current.completed = true
	if not draft.map_state.completed_node_ids.has(current.node_id):
		draft.map_state.completed_node_ids.append(current.node_id)
		draft.map_state.completed_node_ids.sort()
	var receipt_error := _commit(draft, &"non_combat_resolve")
	if receipt_error != null:
		return ExpeditionActionResult.failure(
			receipt_error.code, receipt_error.field_path
		)
	draft.run_phase = RunState.RunPhase.MAP
	return ExpeditionActionResult.success(draft)

func _commit(draft: RunState, kind: StringName) -> ExpeditionActionError:
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return ExpeditionActionError.new(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_transaction_serial"
		)
	var built := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		kind, draft.next_transaction_serial
	)
	if not built.ok:
		return ExpeditionActionError.new(
			ExpeditionActionError.KEY_FAILED, built.error.field_path
		)
	var payload := EconomyPayloadDigest.sha256([
		"EXP1", String(kind), String(built.key_state.digest),
		str(draft.expedition_hp),
	])
	if payload.is_empty():
		return ExpeditionActionError.new(
			ExpeditionActionError.DIGEST_FAILED, &"transaction.payload_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft, TransactionReceiptState.new(
			built.key_state as TransactionKeyState, payload
		)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	return null

func _current_node(run: RunState) -> MapNodeState:
	if run.current_node_id == null:
		return null
	for node: MapNodeState in run.map_state.nodes:
		if node.node_id == run.current_node_id.value:
			return node
	return null

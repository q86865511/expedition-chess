class_name BattleSettlementService
extends RefCounted

const EXPEDITION_HP_CAP: int = 100

var _reward_service: RewardService

func _init(p_reward_service: RewardService = null) -> void:
	_reward_service = p_reward_service if p_reward_service != null else RewardService.new()

func settle(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate(source, catalog)
	if input_error != null:
		return ExpeditionActionResult.failure(input_error.code, input_error.field_path)
	var draft := source.deep_clone()
	var pending := draft.resolution_state as BattleResultPendingResolutionState
	var result := pending.battle_result
	var node := _current_node(draft)
	if node == null or not node.node_kind in [
		MapNodeState.NodeKind.NORMAL,
		MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.BOSS,
	]:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	if result.outcome == &"player_loss":
		return _settle_loss(draft, node, result, catalog)
	if result.outcome != &"player_win":
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RESULT_INVALID, &"battle_result.outcome"
		)
	var proposal_error := _apply_proposals(draft, result, catalog.config())
	if proposal_error != null:
		return ExpeditionActionResult.failure(
			proposal_error.code, proposal_error.field_path
		)
	draft.economy_state.win_streak += 1
	draft.economy_state.loss_streak = 0
	match node.node_kind:
		MapNodeState.NodeKind.NORMAL:
			draft.cleared_normal_count += 1
		MapNodeState.NodeKind.ELITE:
			draft.cleared_elite_count += 1
		MapNodeState.NodeKind.BOSS:
			draft.defeated_boss_count += 1
	var receipt_error := _append_settlement_receipt(
		draft, &"battle_settle_win", result.result_hash
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(
			receipt_error.code, receipt_error.field_path
		)
	var stage := PendingRewardState.StageId.RELIC \
		if node.node_kind == MapNodeState.NodeKind.BOSS \
		else PendingRewardState.StageId.STANDARD
	return _reward_service.generate_stage(draft, stage, catalog)

func abandon_boss_retry(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	if source == null or catalog == null or source.content_snapshot == null \
		or source.run_phase != RunState.RunPhase.PREPARE \
		or not source.resolution_state is IdleResolutionState \
		or catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	var draft := source.deep_clone()
	var node := _current_node(draft)
	if node == null or node.node_kind != MapNodeState.NodeKind.BOSS \
		or not draft.income_claimed_node_ids.has(node.node_id):
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	draft.expedition_hp = 0
	var release_error := _reward_service.try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(release_error.code, release_error.field_path)
	_mark_node_complete(draft, node)
	draft.run_phase = RunState.RunPhase.RESULTS
	draft.resolution_state = IdleResolutionState.new()
	var receipt_error := _append_settlement_receipt(
		draft, &"expedition_abandon", &"abandoned"
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(receipt_error.code, receipt_error.field_path)
	return ExpeditionActionResult.success(draft)

func _settle_loss(
	draft: RunState,
	node: MapNodeState,
	result: BattleResult,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	draft.expedition_hp = maxi(0, draft.expedition_hp - result.expedition_damage)
	draft.economy_state.loss_streak += 1
	draft.economy_state.win_streak = 0
	if draft.economy_state.loss_streak >= 2 \
		and not draft.loss_stipend_claimed_act_ids.has(draft.act_index):
		var stipend := catalog.config().loss_stipend(draft.economy_state.loss_streak)
		if stipend > 0:
			draft.economy_state.gold = mini(
				catalog.config().gold_cap,
				draft.economy_state.gold + stipend
			)
			draft.loss_stipend_claimed_act_ids.append(draft.act_index)
			draft.loss_stipend_claimed_act_ids.sort()
	var receipt_error := _append_settlement_receipt(
		draft, &"battle_settle_loss", result.result_hash
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(
			receipt_error.code, receipt_error.field_path
		)
	draft.resolution_state = IdleResolutionState.new()
	if node.node_kind == MapNodeState.NodeKind.BOSS and draft.expedition_hp > 0:
		draft.run_phase = RunState.RunPhase.PREPARE
		return ExpeditionActionResult.success(draft)
	var release_error := _reward_service.try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(
			release_error.code, release_error.field_path
		)
	_mark_node_complete(draft, node)
	draft.run_phase = RunState.RunPhase.RESULTS \
		if draft.expedition_hp == 0 else RunState.RunPhase.MAP
	return ExpeditionActionResult.success(draft)

func _apply_proposals(
	draft: RunState,
	result: BattleResult,
	config: EconomyConfigRule
) -> ExpeditionActionError:
	for proposal: RunMutationProposal in result.run_mutation_proposals:
		var key_result := RuntimeKeySchemaRegistry.new().build_effect_claim(
			StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
			proposal.claim_scope, StringName(proposal.source_instance_or_slot),
			proposal.effect_id, proposal.operation_index
		)
		if not key_result.ok:
			return ExpeditionActionError.new(
				ExpeditionActionError.KEY_FAILED, key_result.error.field_path
			)
		var existing := _find_claim(draft.claim_receipts, key_result.key_state.digest)
		if existing != null:
			if existing.payload_digest != proposal.payload_digest:
				return ExpeditionActionError.new(
					ExpeditionActionError.RESULT_INVALID,
					&"claim_receipts.payload_digest"
				)
			continue
		match proposal.operation_kind:
			&"add_gold":
				draft.economy_state.gold = mini(
					config.gold_cap,
					draft.economy_state.gold + proposal.amount
				)
			&"add_xp":
				var xp_error := _add_xp(draft.economy_state, proposal.amount, config)
				if xp_error != null:
					return xp_error
			&"heal_expedition_hp":
				draft.expedition_hp = mini(
					EXPEDITION_HP_CAP,
					draft.expedition_hp + proposal.amount
				)
			_:
				return ExpeditionActionError.new(
					ExpeditionActionError.RESULT_INVALID,
					&"run_mutation_proposals.operation_kind"
				)
		draft.claim_receipts.append(ClaimReceiptState.new(
			key_result.key_state as EffectClaimKeyState,
			proposal.payload_digest
		))
	draft.claim_receipts.sort_custom(func(
		left: ClaimReceiptState,
		right: ClaimReceiptState
	) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)
	return null

func _add_xp(
	economy: EconomyState,
	amount: int,
	config: EconomyConfigRule
) -> ExpeditionActionError:
	economy.xp += amount
	while economy.level < 9:
		var threshold := config.value_for(config.xp_thresholds, economy.level, -1)
		if threshold < 1:
			return ExpeditionActionError.new(
				ExpeditionActionError.REWARD_CONFIG_INVALID, &"xp_thresholds"
			)
		if economy.xp < threshold:
			break
		economy.xp -= threshold
		economy.level += 1
	if economy.level == 9:
		economy.xp = 0
	return null

func _append_settlement_receipt(
	draft: RunState,
	kind: StringName,
	result_hash: StringName
) -> ExpeditionActionError:
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return ExpeditionActionError.new(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_transaction_serial"
		)
	var key_result := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		kind, draft.next_transaction_serial
	)
	if not key_result.ok:
		return ExpeditionActionError.new(
			ExpeditionActionError.KEY_FAILED, key_result.error.field_path
		)
	var payload := EconomyPayloadDigest.sha256([
		"BSE1", String(key_result.key_state.digest), String(result_hash),
		str(draft.expedition_hp), str(draft.economy_state.win_streak),
		str(draft.economy_state.loss_streak)
	])
	if payload.is_empty():
		return ExpeditionActionError.new(
			ExpeditionActionError.DIGEST_FAILED, &"transaction.payload_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft, TransactionReceiptState.new(
			key_result.key_state as TransactionKeyState, payload
		)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	return null

func _validate(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionError:
	if source == null or catalog == null or source.content_snapshot == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.INPUT_INVALID, &"source"
		)
	if source.run_phase != RunState.RunPhase.COMBAT:
		return ExpeditionActionError.new(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	if not source.resolution_state is BattleResultPendingResolutionState:
		return ExpeditionActionError.new(
			ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state"
		)
	if catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionError.new(
			ExpeditionActionError.GENERATION_MISMATCH,
			&"content_snapshot.manifest_digest"
		)
	var result := (source.resolution_state as BattleResultPendingResolutionState).battle_result
	if result == null or result.validate() != null:
		return ExpeditionActionError.new(
			ExpeditionActionError.RESULT_INVALID, &"battle_result"
		)
	return null

func _current_node(draft: RunState) -> MapNodeState:
	if draft.current_node_id == null:
		return null
	for node: MapNodeState in draft.map_state.nodes:
		if node.node_id == draft.current_node_id.value:
			return node
	return null

func _mark_node_complete(draft: RunState, node: MapNodeState) -> void:
	node.completed = true
	if not draft.map_state.completed_node_ids.has(node.node_id):
		draft.map_state.completed_node_ids.append(node.node_id)
		draft.map_state.completed_node_ids.sort()

func _find_claim(
	receipts: Array[ClaimReceiptState],
	digest: StringName
) -> ClaimReceiptState:
	for receipt: ClaimReceiptState in receipts:
		if receipt.key.digest == digest:
			return receipt
	return null

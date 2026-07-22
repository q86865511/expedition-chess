class_name RewardService
extends RefCounted

const INVENTORY_CAPACITY: int = 16
const RELIC_CAPACITY: int = 5
const EXPEDITION_HP_CAP: int = 100

func generate_stage(
	source: RunState,
	stage: PendingRewardState.StageId,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_source(source, catalog)
	if input_error != null:
		return ExpeditionActionResult.failure(input_error.code, input_error.field_path)
	var from_battle_result := source.run_phase == RunState.RunPhase.COMBAT \
		and source.resolution_state is BattleResultPendingResolutionState
	var from_completed_stage := source.run_phase == RunState.RunPhase.REWARD \
		and source.resolution_state is RewardPendingResolutionState \
		and (source.resolution_state as RewardPendingResolutionState).pending_reward.phase \
			== PendingRewardState.Phase.READY_TO_ADVANCE
	var event_node := _current_node(source)
	var from_event_node := stage == PendingRewardState.StageId.EVENT_GRANT \
		and source.run_phase == RunState.RunPhase.PREPARE \
		and source.resolution_state is IdleResolutionState \
		and event_node != null and event_node.node_kind in [
			MapNodeState.NodeKind.EVENT, MapNodeState.NodeKind.TREASURE,
		]
	if not from_battle_result and not from_completed_stage and not from_event_node:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.REWARD_PHASE_INVALID, &"resolution_state"
		)
	var table := catalog.try_reward_table(stage)
	if table == null or table.draw_count < 1 or table.candidates.is_empty():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.REWARD_CONFIG_INVALID, &"reward_table"
		)
	var draft := source.deep_clone()
	var snapshot := EconomyCommandSupport.try_reward_rng(draft)
	if snapshot == null:
		var derived := RngService.new().derive_stream(
			draft.run_seed, &"reward",
			StringName("%s:reward_v1" % draft.run_id)
		)
		if not derived.ok:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.RNG_FAILED, &"reward_rng"
			)
		snapshot = derived.snapshot
	var restored := Pcg32Stream.from_snapshot(snapshot)
	if not restored.ok:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RNG_FAILED, &"reward_rng"
		)
	var key_result := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		&"reward_generate", draft.next_transaction_serial
	)
	if not key_result.ok:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.KEY_FAILED, key_result.error.field_path
		)
	var transaction_key := key_result.key_state as TransactionKeyState
	var offers: Array[RewardOfferState] = []
	var reserved: Array[ReservedCopyState] = []
	var stage_token := _stage_token(stage)
	var offer_count := 1 \
		if stage == PendingRewardState.StageId.EVENT_GRANT else table.draw_count
	var has_non_unit_offer := false
	for slot_index: int in range(offer_count):
		var require_non_unit := stage == PendingRewardState.StageId.STANDARD \
			and slot_index == offer_count - 1 and not has_non_unit_offer
		var eligible := _eligible_candidates(
			table, draft, stage, require_non_unit
		)
		if eligible.is_empty() \
			and stage == PendingRewardState.StageId.EVENT_GRANT \
			and _has_unconditional_unit_candidate(table):
			# A forced unit event remains committable when its physical pool is
			# exhausted. Persist a deterministic no-op choice instead of leaving
			# the node stuck in PREPARE or fabricating a copy outside the ledger.
			eligible.append(RewardCandidateRule.new(&"heal", null, 1, 0))
		if eligible.is_empty():
			return ExpeditionActionResult.failure(
				ExpeditionActionError.REWARD_CONFIG_INVALID,
				&"reward_table.candidates"
			)
		var total_weight := 0
		for candidate: RewardCandidateRule in eligible:
			total_weight += candidate.weight
		var draw := restored.stream.next_bounded(total_weight)
		if not draw.ok:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.RNG_FAILED, &"reward_rng"
			)
		var selected := _select_candidate(eligible, draw.value_u32.low_u32())
		if selected == null:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.REWARD_CONFIG_INVALID,
				&"reward_table.weights"
			)
		if selected.kind != &"unit":
			has_non_unit_offer = true
		var owner_key: ReservationOwnerKeyState = null
		if selected.kind == &"unit":
			var owner_result := RuntimeKeySchemaRegistry.new().build_reservation_owner(
				StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
				&"reward", StringName("%s_%s" % [stage_token, draft.next_transaction_serial.to_hex()]),
				slot_index
			)
			if not owner_result.ok:
				return ExpeditionActionResult.failure(
					ExpeditionActionError.KEY_FAILED,
					owner_result.error.field_path
				)
			owner_key = owner_result.key_state as ReservationOwnerKeyState
			var entry := _find_pool(draft.unit_pool_state, selected.content_id.value)
			if entry == null or entry.remaining_copies < 1:
				return ExpeditionActionResult.failure(
					ExpeditionActionError.UNIT_POOL_INVALID,
					&"unit_pool_state"
				)
			entry.remaining_copies -= 1
			entry.reserved_copies += 1
			var owner_payload := EconomyPayloadDigest.sha256([
				"RSV1", String(owner_key.digest),
				String(selected.content_id.value), "1"
			])
			if owner_payload.is_empty():
				return ExpeditionActionResult.failure(
					ExpeditionActionError.DIGEST_FAILED,
					&"reservation_owner.payload_digest"
				)
			draft.reservation_owners.append(ReservationOwnerState.new(
				owner_key, selected.content_id.value, 1,
				ReservationOwnerState.Status.ACTIVE, owner_payload
			))
			reserved.append(ReservedCopyState.new(
				selected.content_id.value, 1, owner_key
			))
		var choice_id := "choice_%s_%s_%d" % [
			stage_token, draft.next_transaction_serial.to_hex(), slot_index
		]
		var offer_digest := EconomyPayloadDigest.sha256([
			"RWO1", choice_id, String(selected.kind),
			String(selected.content_id.value) if selected.content_id != null else "",
			str(selected.amount), String(transaction_key.digest)
		])
		if offer_digest.is_empty():
			return ExpeditionActionResult.failure(
				ExpeditionActionError.DIGEST_FAILED, &"reward_offer.payload_digest"
			)
		offers.append(RewardOfferState.new(
			choice_id, _offer_kind(selected.kind), selected.content_id,
			selected.amount, owner_key, offer_digest
		))
	EconomyCommandSupport.sort_owners(draft.reservation_owners)
	var payload := EconomyPayloadDigest.sha256([
		"RWG1", String(transaction_key.digest), String(table.table_id),
		stage_token, str(offers.size()), restored.stream.snapshot().counter.to_hex()
	])
	if payload.is_empty():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.DIGEST_FAILED, &"reward_transaction.payload_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft, TransactionReceiptState.new(transaction_key, payload)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	EconomyCommandSupport.set_reward_rng(draft, restored.stream.snapshot())
	draft.resolution_state = RewardPendingResolutionState.new(PendingRewardState.new(
		String(EconomyCommandSupport.current_node_id(draft)), stage,
		PendingRewardState.Phase.CHOOSING, offers, reserved,
		null, null, transaction_key
	))
	draft.run_phase = RunState.RunPhase.REWARD
	return ExpeditionActionResult.success(draft)

func choose(
	source: RunState,
	choice_id: String,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_reward_phase(
		source, catalog, PendingRewardState.Phase.CHOOSING
	)
	if input_error != null:
		return ExpeditionActionResult.failure(input_error.code, input_error.field_path)
	var draft := source.deep_clone()
	var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
	var selected := _find_offer(pending.offers, choice_id)
	if selected == null:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.REWARD_CHOICE_INVALID, &"choice_id"
		)
	var release_error := _release_unselected_reward_owners(
		draft, pending, selected.reservation_owner_key
	)
	if release_error != null:
		return ExpeditionActionResult.failure(
			release_error.code, release_error.field_path
		)
	var kept_reserved: Array[ReservedCopyState] = []
	if selected.reservation_owner_key != null:
		for reserved: ReservedCopyState in pending.reserved_copies:
			if reserved.reservation_owner_key.digest == selected.reservation_owner_key.digest:
				kept_reserved.append(reserved.deep_clone())
	pending.reserved_copies = kept_reserved
	pending.selected_choice_id = OptionalStringValue.new(choice_id)
	match selected.reward_kind:
		RewardOfferState.RewardKind.UNIT:
			if selected.reservation_owner_key == null:
				return ExpeditionActionResult.failure(
					ExpeditionActionError.RESERVATION_INVALID,
					&"selected_unit_reservation"
				)
			pending.selected_unit_reservation = selected.reservation_owner_key.deep_clone()
			pending.phase = PendingRewardState.Phase.UNIT_RESOLUTION
		RewardOfferState.RewardKind.ITEM:
			var item_error := _grant_item(draft, selected)
			if item_error != null:
				return ExpeditionActionResult.failure(item_error.code, item_error.field_path)
			pending.phase = PendingRewardState.Phase.ITEM_RESOLUTION \
				if not draft.roster_state.pending_item_overflow.is_empty() \
				else PendingRewardState.Phase.READY_TO_ADVANCE
		RewardOfferState.RewardKind.RELIC:
			var empty_slot := _first_empty_relic_slot(draft.roster_state)
			if empty_slot >= 0:
				draft.roster_state.active_relic_slots[empty_slot].relic_id = selected.content_id.deep_clone()
				pending.phase = PendingRewardState.Phase.READY_TO_ADVANCE
			else:
				pending.phase = PendingRewardState.Phase.RELIC_RESOLUTION
		RewardOfferState.RewardKind.GOLD:
			draft.economy_state.gold = mini(
				catalog.config().gold_cap,
				draft.economy_state.gold + selected.amount
			)
			pending.phase = PendingRewardState.Phase.READY_TO_ADVANCE
		RewardOfferState.RewardKind.EVENT:
			draft.expedition_hp = mini(
				EXPEDITION_HP_CAP, draft.expedition_hp + selected.amount
			)
			pending.phase = PendingRewardState.Phase.READY_TO_ADVANCE
	var commit_error := _commit_operation(draft, &"reward_choose", [choice_id])
	if commit_error != null:
		return ExpeditionActionResult.failure(commit_error.code, commit_error.field_path)
	return ExpeditionActionResult.success(draft)

func resolve_unit(
	source: RunState,
	accept: bool,
	catalog: EconomyExpeditionCatalog,
	battle_catalog: BattleRuleCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_reward_phase(
		source, catalog, PendingRewardState.Phase.UNIT_RESOLUTION
	)
	if input_error != null or battle_catalog == null \
		or battle_catalog.manifest_digest_value() != catalog.manifest_digest_value():
		return ExpeditionActionResult.failure(
			input_error.code if input_error != null else ExpeditionActionError.GENERATION_MISMATCH,
			input_error.field_path if input_error != null else &"battle_catalog"
		)
	var draft := source.deep_clone()
	var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
	if pending.selected_unit_reservation == null:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RESERVATION_INVALID,
			&"selected_unit_reservation"
		)
	var owner := _find_owner(draft.reservation_owners, pending.selected_unit_reservation)
	var entry := _find_pool(draft.unit_pool_state, owner.unit_def_id) if owner != null else null
	if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
		or entry == null or entry.reserved_copies < 1:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RESERVATION_INVALID, &"reservation_owner"
		)
	if accept:
		if draft.roster_state.bench_unit_instance_ids.size() >= 9:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.ROSTER_FULL,
				&"roster_state.bench_unit_instance_ids"
			)
		var created := InstanceIdFactory.new().create(&"u", draft.next_unit_serial)
		if not created.ok:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.SERIAL_EXHAUSTED, &"next_unit_serial"
			)
		var no_equipment: Array[String] = []
		draft.roster_state.unit_instances.append(UnitInstance.new(
			String(created.instance_id), owner.unit_def_id, 1,
			no_equipment, draft.next_unit_serial
		))
		draft.roster_state.bench_unit_instance_ids.append(String(created.instance_id))
		entry.reserved_copies -= 1
		entry.held_copies += 1
		owner.status = ReservationOwnerState.Status.CONSUMED
		var merged := UnitMergeService.new().merge_all(draft.roster_state, battle_catalog)
		if not merged.ok or merged.roster.bench_unit_instance_ids.size() > 9:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.MERGE_FAILED,
				merged.error.field_path if merged.error != null else &"roster_state"
			)
		draft.roster_state = merged.roster.deep_clone()
		draft.next_unit_serial = created.next_serial.deep_clone()
	else:
		entry.reserved_copies -= 1
		entry.remaining_copies += 1
		owner.status = ReservationOwnerState.Status.RELEASED
	pending.selected_unit_reservation = null
	pending.reserved_copies.clear()
	pending.phase = PendingRewardState.Phase.ITEM_RESOLUTION \
		if not draft.roster_state.pending_item_overflow.is_empty() \
		else PendingRewardState.Phase.READY_TO_ADVANCE
	var commit_error := _commit_operation(
		draft, &"reward_unit_resolve", ["accept" if accept else "abandon"]
	)
	if commit_error != null:
		return ExpeditionActionResult.failure(commit_error.code, commit_error.field_path)
	return ExpeditionActionResult.success(draft)

func resolve_item(
	source: RunState,
	item_instance_id: String,
	abandon: bool,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_reward_phase(
		source, catalog, PendingRewardState.Phase.ITEM_RESOLUTION
	)
	if input_error != null or item_instance_id.is_empty():
		return ExpeditionActionResult.failure(
			input_error.code if input_error != null else ExpeditionActionError.ITEM_INVALID,
			input_error.field_path if input_error != null else &"item_instance_id"
		)
	var draft := source.deep_clone()
	if not draft.roster_state.pending_item_overflow.has(item_instance_id):
		return ExpeditionActionResult.failure(
			ExpeditionActionError.ITEM_INVALID, &"pending_item_overflow"
		)
	if abandon:
		_remove_string(draft.roster_state.pending_item_overflow, item_instance_id)
		_remove_item(draft.roster_state.item_instances, item_instance_id)
	else:
		if draft.roster_state.inventory_item_instance_ids.size() >= INVENTORY_CAPACITY:
			return ExpeditionActionResult.failure(
				ExpeditionActionError.ITEM_INVALID,
				&"inventory_item_instance_ids"
			)
		_remove_string(draft.roster_state.pending_item_overflow, item_instance_id)
		draft.roster_state.inventory_item_instance_ids.append(item_instance_id)
		draft.roster_state.inventory_item_instance_ids.sort()
	if draft.roster_state.pending_item_overflow.is_empty():
		var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
		pending.phase = PendingRewardState.Phase.UNIT_RESOLUTION \
			if pending.selected_unit_reservation != null \
			else PendingRewardState.Phase.READY_TO_ADVANCE
	var commit_error := _commit_operation(
		draft, &"reward_item_resolve", [item_instance_id, "abandon" if abandon else "keep"]
	)
	if commit_error != null:
		return ExpeditionActionResult.failure(commit_error.code, commit_error.field_path)
	return ExpeditionActionResult.success(draft)

func resolve_relic(
	source: RunState,
	slot_index: int,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_reward_phase(
		source, catalog, PendingRewardState.Phase.RELIC_RESOLUTION
	)
	if input_error != null or slot_index < -1 or slot_index >= RELIC_CAPACITY:
		return ExpeditionActionResult.failure(
			input_error.code if input_error != null else ExpeditionActionError.RELIC_INVALID,
			input_error.field_path if input_error != null else &"slot_index"
		)
	var draft := source.deep_clone()
	var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
	var selected := _find_offer(pending.offers, pending.selected_choice_id.value)
	if selected == null or selected.reward_kind != RewardOfferState.RewardKind.RELIC \
		or selected.content_id == null:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RELIC_INVALID, &"selected_choice_id"
		)
	if slot_index >= 0:
		draft.roster_state.active_relic_slots[slot_index].relic_id = selected.content_id.deep_clone()
	pending.phase = PendingRewardState.Phase.READY_TO_ADVANCE
	var commit_error := _commit_operation(
		draft, &"reward_relic_resolve", [str(slot_index)]
	)
	if commit_error != null:
		return ExpeditionActionResult.failure(commit_error.code, commit_error.field_path)
	return ExpeditionActionResult.success(draft)

func advance(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	var input_error := _validate_reward_phase(
		source, catalog, PendingRewardState.Phase.READY_TO_ADVANCE
	)
	if input_error != null:
		return ExpeditionActionResult.failure(input_error.code, input_error.field_path)
	if not source.roster_state.pending_item_overflow.is_empty():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.REWARD_PHASE_INVALID,
			&"pending_item_overflow"
		)
	var draft := source.deep_clone()
	var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
	var node := _current_node(draft)
	if node == null:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	if node.node_kind == MapNodeState.NodeKind.ELITE \
		and pending.stage_id == PendingRewardState.StageId.STANDARD:
		var generated := generate_stage(draft, PendingRewardState.StageId.RELIC, catalog)
		return generated
	var release_error := try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(release_error.code, release_error.field_path)
	_mark_node_complete(draft, node)
	draft.resolution_state = IdleResolutionState.new()
	draft.run_phase = RunState.RunPhase.RESULTS \
		if node.node_kind == MapNodeState.NodeKind.BOSS and node.act_index == 3 \
		else RunState.RunPhase.MAP
	var commit_error := _commit_operation(draft, &"reward_advance", [node.node_id])
	if commit_error != null:
		return ExpeditionActionResult.failure(commit_error.code, commit_error.field_path)
	return ExpeditionActionResult.success(draft)

func try_release_shop_offers(draft: RunState) -> ExpeditionActionError:
	for offer: ShopOffer in draft.economy_state.shop_offers:
		var owner := _find_owner(draft.reservation_owners, offer.reservation_owner_key)
		var entry := _find_pool(draft.unit_pool_state, offer.unit_def_id)
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or entry == null or entry.reserved_copies < offer.reserved_copies:
			return ExpeditionActionError.new(
				ExpeditionActionError.RESERVATION_INVALID, &"shop_offers"
			)
		entry.reserved_copies -= offer.reserved_copies
		entry.remaining_copies += offer.reserved_copies
		owner.status = ReservationOwnerState.Status.RELEASED
	draft.economy_state.shop_offers.clear()
	return null

func _validate_source(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionError:
	if source == null or catalog == null or source.content_snapshot == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.INPUT_INVALID, &"source"
		)
	if catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionError.new(
			ExpeditionActionError.GENERATION_MISMATCH,
			&"content_snapshot.manifest_digest"
		)
	if source.next_transaction_serial.equals(U64Bits.max_value()):
		return ExpeditionActionError.new(
			ExpeditionActionError.SERIAL_EXHAUSTED,
			&"next_transaction_serial"
		)
	return null

func _validate_reward_phase(
	source: RunState,
	catalog: EconomyExpeditionCatalog,
	expected_phase: PendingRewardState.Phase
) -> ExpeditionActionError:
	var base := _validate_source(source, catalog)
	if base != null:
		return base
	if source.run_phase != RunState.RunPhase.REWARD \
		or not source.resolution_state is RewardPendingResolutionState:
		return ExpeditionActionError.new(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	var pending := (source.resolution_state as RewardPendingResolutionState).pending_reward
	if pending == null or pending.phase != expected_phase:
		return ExpeditionActionError.new(
			ExpeditionActionError.REWARD_PHASE_INVALID,
			&"resolution_state.pending_reward.phase"
		)
	return null

func _eligible_candidates(
	table: RewardTableRule,
	draft: RunState,
	stage: PendingRewardState.StageId,
	non_unit_only: bool = false
) -> Array[RewardCandidateRule]:
	var result: Array[RewardCandidateRule] = []
	var has_non_unit := false
	for candidate: RewardCandidateRule in table.candidates:
		if candidate.weight <= 0:
			continue
		if not _reward_conditions_met(candidate.conditions, draft):
			continue
		if stage == PendingRewardState.StageId.RELIC and candidate.kind != &"relic":
			continue
		if stage != PendingRewardState.StageId.RELIC and candidate.kind == &"relic":
			continue
		if non_unit_only and candidate.kind == &"unit":
			continue
		if candidate.kind == &"unit":
			if candidate.content_id == null:
				continue
			var entry := _find_pool(draft.unit_pool_state, candidate.content_id.value)
			if entry == null or entry.remaining_copies < 1:
				continue
		else:
			has_non_unit = true
		result.append(candidate.deep_clone())
	if stage == PendingRewardState.StageId.STANDARD and not has_non_unit:
		result.clear()
	return result

func _has_unconditional_unit_candidate(table: RewardTableRule) -> bool:
	for candidate: RewardCandidateRule in table.candidates:
		if candidate.kind == &"unit" and candidate.conditions.is_empty():
			return true
	return false

func _reward_conditions_met(
	conditions: Array[RewardConditionRule],
	draft: RunState
) -> bool:
	for condition: RewardConditionRule in conditions:
		match condition.kind:
			&"roster_space_at_least":
				if 9 - draft.roster_state.bench_unit_instance_ids.size() < condition.int_value:
					return false
			&"inventory_space_at_least":
				if INVENTORY_CAPACITY - draft.roster_state.inventory_item_instance_ids.size() \
					< condition.int_value:
					return false
			&"expedition_hp_below":
				if draft.expedition_hp >= condition.int_value:
					return false
			&"pool_copies_at_least":
				if condition.stable_id_value == null:
					return false
				var entry := _find_pool(
					draft.unit_pool_state, condition.stable_id_value.value
				)
				if entry == null or entry.remaining_copies < condition.int_value:
					return false
			_:
				return false
	return true

func _select_candidate(
	candidates: Array[RewardCandidateRule],
	roll: int
) -> RewardCandidateRule:
	var cursor := roll
	for candidate: RewardCandidateRule in candidates:
		if cursor < candidate.weight:
			return candidate.deep_clone()
		cursor -= candidate.weight
	return null

func _offer_kind(kind: StringName) -> RewardOfferState.RewardKind:
	match kind:
		&"unit": return RewardOfferState.RewardKind.UNIT
		&"item": return RewardOfferState.RewardKind.ITEM
		&"relic": return RewardOfferState.RewardKind.RELIC
		&"gold": return RewardOfferState.RewardKind.GOLD
	return RewardOfferState.RewardKind.EVENT

func _stage_token(stage: PendingRewardState.StageId) -> String:
	return ["standard", "relic", "event_grant"][stage]

func _release_unselected_reward_owners(
	draft: RunState,
	pending: PendingRewardState,
	kept_key: ReservationOwnerKeyState
) -> ExpeditionActionError:
	for reserved: ReservedCopyState in pending.reserved_copies:
		if kept_key != null and reserved.reservation_owner_key.digest == kept_key.digest:
			continue
		var owner := _find_owner(draft.reservation_owners, reserved.reservation_owner_key)
		var entry := _find_pool(draft.unit_pool_state, reserved.unit_def_id)
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or entry == null or entry.reserved_copies < reserved.copies:
			return ExpeditionActionError.new(
				ExpeditionActionError.RESERVATION_INVALID, &"reserved_copies"
			)
		entry.reserved_copies -= reserved.copies
		entry.remaining_copies += reserved.copies
		owner.status = ReservationOwnerState.Status.RELEASED
	return null

func _grant_item(
	draft: RunState,
	offer: RewardOfferState
) -> ExpeditionActionError:
	if offer.content_id == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.ITEM_INVALID, &"reward_offer.content_id"
		)
	var created := InstanceIdFactory.new().create(&"it", draft.next_item_serial)
	if not created.ok:
		return ExpeditionActionError.new(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_item_serial"
		)
	var item_id := String(created.instance_id)
	draft.roster_state.item_instances.append(ItemInstanceState.new(
		item_id, offer.content_id.value, null, draft.next_item_serial
	))
	if draft.roster_state.inventory_item_instance_ids.size() < INVENTORY_CAPACITY:
		draft.roster_state.inventory_item_instance_ids.append(item_id)
		draft.roster_state.inventory_item_instance_ids.sort()
	else:
		draft.roster_state.pending_item_overflow.append(item_id)
		draft.roster_state.pending_item_overflow.sort()
	draft.next_item_serial = created.next_serial.deep_clone()
	return null

func _commit_operation(
	draft: RunState,
	kind: StringName,
	parts: Array[String]
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
	var payload_parts: Array[String] = [
		"EXP1", String(kind), String(key_result.key_state.digest)
	]
	payload_parts.append_array(parts)
	var payload := EconomyPayloadDigest.sha256(payload_parts)
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

func _find_offer(
	offers: Array[RewardOfferState],
	choice_id: String
) -> RewardOfferState:
	for offer: RewardOfferState in offers:
		if offer.choice_id == choice_id:
			return offer
	return null

func _find_owner(
	owners: Array[ReservationOwnerState],
	key: ReservationOwnerKeyState
) -> ReservationOwnerState:
	if key == null:
		return null
	for owner: ReservationOwnerState in owners:
		if owner.key.digest == key.digest:
			return owner
	return null

func _find_pool(
	pool: UnitPoolState,
	unit_id: StringName
) -> UnitPoolEntryState:
	for entry: UnitPoolEntryState in pool.entries:
		if entry.unit_def_id == unit_id:
			return entry
	return null

func _first_empty_relic_slot(roster: RosterState) -> int:
	for slot: RelicSlotState in roster.active_relic_slots:
		if slot.relic_id == null:
			return slot.slot_index
	return -1

func _remove_string(values: Array[String], target: String) -> void:
	var index := values.find(target)
	if index >= 0:
		values.remove_at(index)

func _remove_item(values: Array[ItemInstanceState], target: String) -> void:
	for index: int in range(values.size() - 1, -1, -1):
		if values[index].instance_id == target:
			values.remove_at(index)
			return

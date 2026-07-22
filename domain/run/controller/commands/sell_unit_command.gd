class_name SellUnitCommand
extends RunCommand

var _unit_instance_id: String
var _catalog: EconomyExpeditionCatalog
var _service: ShopService

func _init(p_unit_instance_id: String, p_catalog: EconomyExpeditionCatalog, p_service: ShopService = null) -> void:
	_unit_instance_id = p_unit_instance_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else ShopService.new()

func is_concrete() -> bool:
	return not _unit_instance_id.is_empty() and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or not draft.run_phase in [
		RunState.RunPhase.PREPARE, RunState.RunPhase.REWARD
	]:
		return _failure(ShopError.INPUT_INVALID, &"run_phase")
	if draft.run_phase == RunState.RunPhase.REWARD:
		if not draft.resolution_state is RewardPendingResolutionState:
			return _failure(ShopError.INPUT_INVALID, &"resolution_state")
		var pending := (draft.resolution_state as RewardPendingResolutionState).pending_reward
		if pending.phase not in [
			PendingRewardState.Phase.UNIT_RESOLUTION,
			PendingRewardState.Phase.ITEM_RESOLUTION,
		]:
			return _failure(ShopError.INPUT_INVALID, &"pending_reward.phase")
	if draft.content_snapshot == null or _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _failure(ShopError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	var result := _service.quote_sell(SellUnitRequest.new(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft), _unit_instance_id,
		draft.economy_state, draft.unit_pool_state, draft.roster_state,
		draft.reservation_owners, EconomyCommandSupport.try_shop_rng(draft),
		draft.next_transaction_serial, draft.next_unit_serial, _catalog
	))
	if not result.ok: return _failure(result.error.code, result.error.field_path)
	EconomyCommandSupport.apply_shop_transaction(draft, result.transaction)
	if draft.run_phase == RunState.RunPhase.REWARD \
		and not draft.roster_state.pending_item_overflow.is_empty():
		((draft.resolution_state as RewardPendingResolutionState).pending_reward).phase = \
			PendingRewardState.Phase.ITEM_RESOLUTION
	return CommandApplyResult.success(draft)

func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [DiagnosticValue.from_string(&"source_code", String(code))]
	return CommandApplyResult.failure(CommandApplyError.new(CommandApplyError.APPLY_REJECTED, path, null, diagnostics))

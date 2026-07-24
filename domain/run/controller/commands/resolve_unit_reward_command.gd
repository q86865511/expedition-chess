class_name ResolveUnitRewardCommand
extends RunCommand

var _accept: bool
var _catalog: EconomyExpeditionCatalog
var _battle_catalog: BattleRuleCatalog
var _service: RewardService

func _init(
	p_accept: bool,
	p_catalog: EconomyExpeditionCatalog,
	p_battle_catalog: BattleRuleCatalog,
	p_service: RewardService = null
) -> void:
	_accept = p_accept
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_service = p_service if p_service != null else RewardService.new()

func is_concrete() -> bool:
	return _catalog != null and _battle_catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	# Captured before the transaction consumes the reservation (owner.status
	# flips to CONSUMED), mirroring buy_offer_command.gd's capture-before-mark
	# convention.
	var reserved_unit_def_id := _reserved_unit_def_id(draft)
	var result := _service.resolve_unit(
		draft, _accept, _catalog, _battle_catalog
	)
	if result.ok and _accept:
		# T09 / S5-AC-012 (design.md §8): 上場/購得棋子 -> once the accepted
		# unit has successfully entered the bench (reward_service.gd:294), it
		# is discovered in the same copy-validate-save-swap transaction.
		RunDiscoveryLog.mark(result.run_state, reserved_unit_def_id)
	return _convert(result)

func _reserved_unit_def_id(draft: RunState) -> StringName:
	var resolution := draft.resolution_state as RewardPendingResolutionState
	if resolution == null or resolution.pending_reward == null:
		return &""
	var reservation_key := resolution.pending_reward.selected_unit_reservation
	if reservation_key == null:
		return &""
	for owner: ReservationOwnerState in draft.reservation_owners:
		if owner.key.digest == reservation_key.digest:
			return owner.unit_def_id
	return &""

func _convert(result: ExpeditionActionResult) -> CommandApplyResult:
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code))
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

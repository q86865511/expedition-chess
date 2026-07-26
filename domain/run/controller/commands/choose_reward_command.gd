class_name ChooseRewardCommand
extends RunCommand

var _choice_id: String
var _catalog: EconomyExpeditionCatalog
var _service: RewardService

func _init(
	p_choice_id: String,
	p_catalog: EconomyExpeditionCatalog,
	p_service: RewardService = null
) -> void:
	_choice_id = p_choice_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else RewardService.new()

func is_concrete() -> bool:
	return not _choice_id.is_empty() and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var result := _service.choose(draft, _choice_id, _catalog)
	if result.ok:
		_mark_relic_discovery(result.run_state)
	return _convert(result)

## T09 / S5-AC-012 (design.md §8): 取得遺物/裝備 -> when the chosen reward is a
## relic, or an item (direct-grant equipment; see reward_service.gd _grant_item's
## identical offer.content_id.value source, reward_service.gd:598-622), discover
## its content id in the same copy-validate-save-swap transaction. Units are
## discovered at their own acquisition points (buy/deploy, forge).
func _mark_relic_discovery(draft: RunState) -> void:
	var resolution := draft.resolution_state as RewardPendingResolutionState
	if resolution == null or resolution.pending_reward == null \
		or resolution.pending_reward.selected_choice_id == null:
		return
	var pending := resolution.pending_reward
	for offer: RewardOfferState in pending.offers:
		if offer.choice_id != pending.selected_choice_id.value:
			continue
		if offer.content_id != null and offer.reward_kind in [
			RewardOfferState.RewardKind.RELIC, RewardOfferState.RewardKind.ITEM
		]:
			RunDiscoveryLog.mark(draft, offer.content_id.value)
		return

func _convert(result: ExpeditionActionResult) -> CommandApplyResult:
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code))
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

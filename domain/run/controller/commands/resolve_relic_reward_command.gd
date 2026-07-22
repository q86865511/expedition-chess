class_name ResolveRelicRewardCommand
extends RunCommand

var _slot_index: int
var _catalog: EconomyExpeditionCatalog
var _service: RewardService

func _init(
	p_slot_index: int,
	p_catalog: EconomyExpeditionCatalog,
	p_service: RewardService = null
) -> void:
	_slot_index = p_slot_index
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else RewardService.new()

func is_concrete() -> bool:
	return _slot_index >= -1 and _slot_index < 5 and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	return _convert(_service.resolve_relic(draft, _slot_index, _catalog))

func _convert(result: ExpeditionActionResult) -> CommandApplyResult:
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code))
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

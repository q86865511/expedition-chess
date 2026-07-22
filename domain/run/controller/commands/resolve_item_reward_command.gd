class_name ResolveItemRewardCommand
extends RunCommand

var _item_instance_id: String
var _abandon: bool
var _catalog: EconomyExpeditionCatalog
var _service: RewardService

func _init(
	p_item_instance_id: String,
	p_abandon: bool,
	p_catalog: EconomyExpeditionCatalog,
	p_service: RewardService = null
) -> void:
	_item_instance_id = p_item_instance_id
	_abandon = p_abandon
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else RewardService.new()

func is_concrete() -> bool:
	return not _item_instance_id.is_empty() and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	return _convert(_service.resolve_item(
		draft, _item_instance_id, _abandon, _catalog
	))

func _convert(result: ExpeditionActionResult) -> CommandApplyResult:
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code))
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

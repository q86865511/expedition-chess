class_name SettleBattleResultCommand
extends RunCommand

var _catalog: EconomyExpeditionCatalog
var _service: BattleSettlementService

func _init(
	p_catalog: EconomyExpeditionCatalog,
	p_service: BattleSettlementService = null
) -> void:
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else BattleSettlementService.new()

func is_concrete() -> bool:
	return _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var result := _service.settle(draft, _catalog)
	return _convert(result)

func _convert(result: ExpeditionActionResult) -> CommandApplyResult:
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code))
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path,
		null, diagnostics
	))

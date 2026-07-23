class_name SettleBattleResultCommand
extends RunCommand

var _catalog: EconomyExpeditionCatalog
var _service: BattleSettlementService
var _relic_table: RunRelicTable

func _init(
	p_catalog: EconomyExpeditionCatalog,
	p_service: BattleSettlementService = null,
	p_relic_table: RunRelicTable = null
) -> void:
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else BattleSettlementService.new()
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null

func is_concrete() -> bool:
	return _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var active_relic_ids := RunRelicActivation.active_ids_in_slot_order(
		draft.roster_state.active_relic_slots
	)
	var result := _service.settle(draft, _catalog, _relic_table, active_relic_ids)
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

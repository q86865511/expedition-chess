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
	return _convert(_service.resolve_unit(
		draft, _accept, _catalog, _battle_catalog
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

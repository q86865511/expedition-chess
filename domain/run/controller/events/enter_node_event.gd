class_name EnterNodeEvent
extends RunEvent

var _target_node_id: String
var _catalog: EconomyExpeditionCatalog
var _battle_catalog: BattleRuleCatalog
var _relic_table: RunRelicTable
var _service: NodeEntryService

func _init(
	p_target_node_id: String, p_catalog: EconomyExpeditionCatalog,
	p_battle_catalog: BattleRuleCatalog = null,
	p_service: NodeEntryService = null,
	p_relic_table: RunRelicTable = null
) -> void:
	super(RunState.RunPhase.PREPARE)
	_target_node_id = p_target_node_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	_service = p_service if p_service != null else NodeEntryService.new()

func is_concrete() -> bool:
	return not _target_node_id.is_empty() and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var result := _service.enter(
		draft, _target_node_id, _catalog, _battle_catalog, _relic_table
	)
	if result.ok:
		return CommandApplyResult.success(result.draft)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code)),
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

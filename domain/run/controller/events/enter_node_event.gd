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
		var entered := result.draft
		_mark_encounter_discovery(entered)
		_mark_shop_discovery(entered)
		return CommandApplyResult.success(entered)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code)),
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

## T09 / S5-AC-012 (design.md §8): 遭遇敵人 -> every enemy unit in the entered
## node's encounter preview is discovered in the same copy-validate-save-swap
## transaction. Non-combat nodes carry no preview and mark nothing.
func _mark_encounter_discovery(draft: RunState) -> void:
	for node: MapNodeState in draft.map_state.nodes:
		if node.node_id != _target_node_id or node.encounter_preview == null:
			continue
		for enemy: UnitBattleSnapshot in node.encounter_preview.enemy_units:
			RunDiscoveryLog.mark(draft, enemy.unit_id)
		return

## T09 / S5-AC-012 (design.md §8): 商店出現 -> node entry also (re)generates the
## node's shop offers (NodeEntryService.enter); every freshly-offered unit is
## discovered in the same copy-validate-save-swap transaction (mirrors
## refresh_shop_command.gd's identical loop over economy_state.shop_offers).
func _mark_shop_discovery(draft: RunState) -> void:
	for offer: ShopOffer in draft.economy_state.shop_offers:
		RunDiscoveryLog.mark(draft, offer.unit_def_id)

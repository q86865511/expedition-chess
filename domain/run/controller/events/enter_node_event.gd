class_name EnterNodeEvent
extends RunEvent

var _target_node_id: String
var _catalog: EconomyExpeditionCatalog
var _battle_catalog: BattleRuleCatalog
var _relic_table: RunRelicTable
## design §6.3 軌 A（S5-AC-010）：本次遠征生效的敵方挑戰詞綴 effect id（由呼叫端以
## ChallengeAffixResolver 依 challenge_level 解出，與 relic_table 同一「預先解析後傳入」慣例）。
var _challenge_affix_effect_ids: Array[StringName] = []
var _service: NodeEntryService

func _init(
	p_target_node_id: String, p_catalog: EconomyExpeditionCatalog,
	p_battle_catalog: BattleRuleCatalog = null,
	p_service: NodeEntryService = null,
	p_relic_table: RunRelicTable = null,
	p_challenge_affix_effect_ids: Array[StringName] = []
) -> void:
	super(RunState.RunPhase.PREPARE)
	_target_node_id = p_target_node_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	_challenge_affix_effect_ids = p_challenge_affix_effect_ids.duplicate()
	_service = p_service if p_service != null else NodeEntryService.new()

func is_concrete() -> bool:
	return not _target_node_id.is_empty() and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var result := _service.enter(
		draft, _target_node_id, _catalog, _battle_catalog, _relic_table,
		_challenge_affix_effect_ids
	)
	if result.ok:
		var entered := result.draft
		_mark_encounter_discovery(entered)
		_mark_shop_discovery(entered)
		var choice_error := _begin_node_choice_if_required(entered)
		if choice_error != null:
			var choice_diagnostics: Array[DiagnosticValue] = [
				DiagnosticValue.from_string(
					&"source_code", String(choice_error.code)
				),
			]
			return CommandApplyResult.failure(
				CommandApplyError.new(
					CommandApplyError.APPLY_REJECTED,
					choice_error.field_path,
					null,
					choice_diagnostics
				)
			)
		return CommandApplyResult.success(entered)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(result.error.code)),
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, result.error.field_path, null, diagnostics
	))

func _begin_node_choice_if_required(
	entered: RunState
) -> ExpeditionActionError:
	if entered == null or entered.current_node_id == null:
		return null
	var current: MapNodeState = null
	for node: MapNodeState in entered.map_state.nodes:
		if node.node_id == entered.current_node_id.value:
			current = node
			break
	if current == null or current.node_kind not in [
		MapNodeState.NodeKind.EVENT,
		MapNodeState.NodeKind.REST,
		MapNodeState.NodeKind.TREASURE,
	]:
		return null
	var choice_set := _catalog.node_choice_set_for_map_node(current.def_id)
	if choice_set == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.NODE_INVALID,
			&"map_node.generator_id"
		)
	entered.run_phase = RunState.RunPhase.PREPARE
	var lifecycle_nonce := (
		"node-choice|%s|%s|%s" % [
			entered.run_id,
			current.node_id,
			entered.content_snapshot.manifest_digest_value(),
		]
	).sha256_text().left(16)
	var begun := CommitNodeChoiceService.new().begin(
		entered,
		StringName(current.node_id),
		choice_set,
		lifecycle_nonce
	)
	if not begun.ok:
		return begun.error
	var pending_run := begun.run_state
	entered.resolution_state = pending_run.resolution_state.deep_clone()
	return null

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

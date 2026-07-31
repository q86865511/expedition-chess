class_name RunCommandFactory
extends RefCounted

## T11 (specs/meta-progression/design.md §3、§4.4；requirements.md S5-AC-014)：
## GenerateExpeditionMapCommand／RefreshShopCommand／SettleBattleResultCommand／
## EnterNodeEvent 的唯一建構點，一律注入本 run 的**非 null** RunRelicTable
## （§6.1 含指揮官被動與 challenge 規則）。
##
## 為什麼需要這個型別：四個命令的 relic_table 參數各自帶預設 null（見
## refresh_shop_command.gd:8-12 等），忘傳不會報錯、只會讓 always-active 貢獻靜默消失
## （HANDOFF §3 的「S5 接手檢查項」）。relic_table 在此為**必要參數、無預設值**——
## 這是「一律注入非 null relic_table」在型別層面能給的最強保證。
##
## battle_catalog 只有 enter_node_event()／commit_board_layout_command() 需要，故給
## 預設 null，避免另外三個建構方法為不相關欄位被迫傳值。
##
## 世代一致性（tasks.md T11 末句）：本 factory 只是原樣轉呈建構子收到的 catalog／
## relic_table／battle_catalog，不自行重指世代——四個命令因此必然共用呼叫端（composition
## root）挑定的那一個 content_snapshot.manifest_digest。

var _catalog: EconomyExpeditionCatalog
var _relic_table: RunRelicTable
var _battle_catalog: BattleRuleCatalog
var _forge_table: ForgeRecipeTable
var _consumable_rules: ConsumableRuleTable
var _challenge_affix_effect_ids: Array[StringName] = []
## 缺口 2（commit_board_layout_command.gd:71-76）：RunState 不持久化 population source
## 台帳，故由建構命令的人依 (run.commander_id, pinned CommanderDef.population_bonus)
## 決定性重建。兩者皆為可選——只建構前四個命令的呼叫端不必知道指揮官人口加成。
var _commander_id: StringName
var _commander_population_bonus: int

func _init(
	p_catalog: EconomyExpeditionCatalog,
	p_relic_table: RunRelicTable,
	p_battle_catalog: BattleRuleCatalog = null,
	p_challenge_affix_effect_ids: Array[StringName] = [],
	p_commander_id: StringName = &"",
	p_commander_population_bonus: int = 0,
	p_forge_table: ForgeRecipeTable = null,
	p_consumable_rules: ConsumableRuleTable = null
) -> void:
	# clone in：factory 存活整個 run，不能保留呼叫端可變物件的引用（同 RunController
	# 對 battle_catalog 的既有慣例，run_controller.gd:31）。四個命令建構子自己還會再
	# clone 一次，故命令之間也不共用同一份物件圖。
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_forge_table = p_forge_table.deep_clone() if p_forge_table != null else null
	_consumable_rules = (
		p_consumable_rules.deep_clone() if p_consumable_rules != null else null
	)
	_challenge_affix_effect_ids = p_challenge_affix_effect_ids.duplicate()
	_commander_id = p_commander_id
	_commander_population_bonus = p_commander_population_bonus

## 建構出來的命令是否具備完整的注入依賴（catalog 與 relic_table 皆非 null）。
func is_concrete() -> bool:
	return _catalog != null and _relic_table != null

func generate_expedition_map_command() -> GenerateExpeditionMapCommand:
	return GenerateExpeditionMapCommand.new(_catalog, null, _relic_table)

func refresh_shop_command() -> RefreshShopCommand:
	return RefreshShopCommand.new(_catalog, null, _relic_table)

func buy_offer_command(offer_id: String) -> BuyOfferCommand:
	return BuyOfferCommand.new(offer_id, _catalog, _battle_catalog)

func buy_xp_command() -> BuyXpCommand:
	return BuyXpCommand.new(_catalog)

func sell_unit_command(unit_instance_id: String) -> SellUnitCommand:
	return SellUnitCommand.new(unit_instance_id, _catalog)

func forge_equipment_command(
	component_instance_id_a: String,
	component_instance_id_b: String
) -> ForgeEquipmentCommand:
	return ForgeEquipmentCommand.new(
		component_instance_id_a, component_instance_id_b, _forge_table
	)

func equip_item_command(
	unit_instance_id: String,
	item_instance_id: String
) -> EquipItemCommand:
	return EquipItemCommand.new(unit_instance_id, item_instance_id, _battle_catalog)

func dismantle_equipment_command(
	equipment_item_instance_id: String,
	consumable_item_instance_id: String
) -> DismantleEquipmentCommand:
	return DismantleEquipmentCommand.new(
		equipment_item_instance_id, consumable_item_instance_id, _consumable_rules
	)

func settle_battle_result_command() -> SettleBattleResultCommand:
	return SettleBattleResultCommand.new(_catalog, null, _relic_table)

func enter_node_event(target_node_id: String) -> EnterNodeEvent:
	return EnterNodeEvent.new(
		target_node_id, _catalog, _battle_catalog, null, _relic_table,
		_challenge_affix_effect_ids
	)

func start_combat_event(sources: BattleSetupSourceBundle) -> StartCombatEvent:
	return StartCombatEvent.new(_battle_catalog, sources)

func resolve_non_combat_node_command() -> ResolveNonCombatNodeCommand:
	return ResolveNonCombatNodeCommand.new(_catalog)

func try_node_choice_set(choice_set_id: StringName) -> NodeChoiceSetRule:
	return (
		_catalog.try_node_choice_set(choice_set_id)
		if _catalog != null
		else null
	)

## design.md §5:177「factory 不得以 latest state 覆蓋」：payload 原樣轉呈，
## factory 只負責把 payload 自己宣告的 choice_set_id 解析成 pinned rule。
func commit_node_choice_command(
	payload: NodeChoiceCommitPayload
) -> CommitNodeChoiceCommand:
	return CommitNodeChoiceCommand.new(
		payload,
		try_node_choice_set(
			payload.choice_set_id if payload != null else &""
		),
		_catalog
	)

func acknowledge_node_choice_result_command(
	expected_run_id: String,
	receipt_digest: String
) -> AcknowledgeNodeChoiceResultCommand:
	return AcknowledgeNodeChoiceResultCommand.new(
		expected_run_id, receipt_digest
	)

func dismantle_with_node_service_command(
	expected_run_id: String,
	node_id: StringName,
	choice_receipt_digest: String,
	equipment_item_instance_id: String
) -> DismantleWithNodeServiceCommand:
	return DismantleWithNodeServiceCommand.new(
		expected_run_id,
		node_id,
		choice_receipt_digest,
		equipment_item_instance_id
	)

func exit_node_service_command(
	expected_run_id: String,
	node_id: StringName,
	choice_receipt_digest: String
) -> ExitNodeServiceCommand:
	return ExitNodeServiceCommand.new(
		expected_run_id, node_id, choice_receipt_digest
	)

func choose_reward_command(choice_id: String) -> ChooseRewardCommand:
	return ChooseRewardCommand.new(choice_id, _catalog)

func resolve_unit_reward_command(accept: bool) -> ResolveUnitRewardCommand:
	return ResolveUnitRewardCommand.new(accept, _catalog, _battle_catalog)

func resolve_item_reward_command(
	item_instance_id: String,
	abandon: bool
) -> ResolveItemRewardCommand:
	return ResolveItemRewardCommand.new(item_instance_id, abandon, _catalog)

func resolve_relic_reward_command(slot_index: int) -> ResolveRelicRewardCommand:
	return ResolveRelicRewardCommand.new(slot_index, _catalog)

func advance_reward_command() -> AdvanceRewardCommand:
	return AdvanceRewardCommand.new(_catalog)

func resolve_unit_overflow_command(
	overflow_item_instance_id: String
) -> ResolveOverflowCommand:
	return ResolveOverflowCommand.abandon(overflow_item_instance_id)

func resolve_item_overflow_command(
	overflow_item_instance_id: String,
	target_unit_instance_id: String = ""
) -> ResolveOverflowCommand:
	if not target_unit_instance_id.is_empty():
		return ResolveOverflowCommand.equip(
			overflow_item_instance_id, target_unit_instance_id, _battle_catalog
		)
	return ResolveOverflowCommand.abandon(overflow_item_instance_id)

func replace_relic_command(slot_index: int) -> ResolveRelicRewardCommand:
	return ResolveRelicRewardCommand.new(slot_index, _catalog)

func abandon_relic_command() -> ResolveRelicRewardCommand:
	return ResolveRelicRewardCommand.new(-1, _catalog)

func abandon_boss_retry_command() -> AbandonExpeditionCommand:
	return AbandonExpeditionCommand.new(_catalog)

## Terminal gameplay phase is reached by the existing battle-settlement command.
## Meta settlement remains an AppRoot-owned transaction and is intentionally not
## duplicated in presentation.
func settle_terminal_run_command() -> SettleBattleResultCommand:
	return SettleBattleResultCommand.new(_catalog, null, _relic_table)

## 缺口 2 的正式建構點：PREPARE 階段的 board commit 必須帶上指揮官人口加成來源，
## 否則 board population cap 只有 base level（design.md §4.2）。
func commit_board_layout_command(
	board: BoardState,
	bench_unit_instance_ids: Array[String]
) -> CommitBoardLayoutCommand:
	return CommitBoardLayoutCommand.new(
		board,
		bench_unit_instance_ids,
		_battle_catalog,
		_population_sources()
	)


## PREPARE consumes the same authoritative population-source reconstruction as
## CommitBoardLayoutCommand. The validator and its report both clone their
## inputs/outputs, so presentation never retains the canonical roster graph.
func board_validation_report(
	roster: RosterState,
	economy_level: int
) -> BoardValidationReport:
	if roster == null:
		var issues: Array[BoardValidationIssue] = [
			BoardValidationIssue.new(BoardValidationIssue.REQUEST_INVALID),
		]
		return BoardValidationReport.new(-1, issues)
	var request := BoardPreparationRequest.new(
		roster.board,
		roster.bench_unit_instance_ids,
		roster.unit_instances,
		economy_level,
		_population_sources()
	)
	return BoardPreparationValidator.new().validate(request).deep_clone()


func _population_sources() -> Array[PopulationSourceSnapshot]:
	return RunCompositionSupport.population_sources(
		_commander_id,
		_commander_population_bonus
	)

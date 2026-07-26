class_name RunLabSession
extends RefCounted

## S5 wave5 修正 A4（specs/meta-progression/design.md §4.4）：RUN 狀態的最小灰盒驅動端。
##
## 與被它取代的 S3 expedition_lab 的差別是全部：expedition_lab 是一份純記憶體 demo
## （expedition_lab_session.gd 自己加加減減幾個 int），本類別**只**透過 composition root
## 交下來的真 RunController／RunCommandFactory 推動一局真的 RunState——每一次操作都是
## 一次 copy-validate-save-swap 交易（run_controller.gd:147-210），落存檔、可續跑。
##
## 五個 factory 建構方法（S5-AC-014）在這條鏈上全部有真實呼叫端：
##   generate_expedition_map_command() → generate_map()
##   enter_node_event()                → enter_node()
##   refresh_shop_command()            → refresh_shop()
##   commit_board_layout_command()     → commit_board()（含指揮官人口加成來源注入）
##   settle_battle_result_command()    → settle_battle()
## factory 沒有涵蓋的操作（買棋／獎勵／非戰鬥節點／放棄 Boss 重戰）沿用既有 S3/S4 命令，
## 它們不帶 relic_table 參數，沒有「忘傳就靜默失效」的問題（見 run_command_factory.gd 檔頭）。
##
## 灰盒定位：純功能載體，不做美術、不做 UI 自動化測試。所有方法回 &"" 表成功，否則為具名
## 失敗碼（domain 命令／轉移的 error.code 原樣轉呈），由 RunScreen 直接顯示。

## 一場戰鬥的模擬步數上限：純防呆（BattleSimulation 自己有終局條件），避免灰盒卡在無窮迴圈。
const COMBAT_STEP_LIMIT: int = 100000
## 一個節點的獎勵階段最多推進幾步（choose→advance 交替，多階段獎勵亦足夠）。
const REWARD_STEP_LIMIT: int = 32

const ERROR_NO_CONTROLLER: StringName = &"RUN_LAB_CONTROLLER_MISSING"
const ERROR_NO_REACHABLE_NODE: StringName = &"RUN_LAB_NO_REACHABLE_NODE"
const ERROR_NO_SHOP_OFFER: StringName = &"RUN_LAB_NO_SHOP_OFFER"
const ERROR_NO_PENDING_REWARD: StringName = &"RUN_LAB_NO_PENDING_REWARD"
const ERROR_COMBAT_STEP_LIMIT: StringName = &"RUN_LAB_COMBAT_STEP_LIMIT"
const ERROR_REWARD_STEP_LIMIT: StringName = &"RUN_LAB_REWARD_STEP_LIMIT"
const ERROR_ITEM_REWARD_UNSUPPORTED: StringName = &"RUN_LAB_ITEM_REWARD_UNSUPPORTED"

var _controller: RunController
var _factory: RunCommandFactory
var _economy_catalog: EconomyExpeditionCatalog
var _battle_catalog: BattleRuleCatalog
var _commander_passive_effect_ids: Array[StringName] = []


func _init(
	p_controller: RunController,
	p_factory: RunCommandFactory,
	p_economy_catalog: EconomyExpeditionCatalog,
	p_battle_catalog: BattleRuleCatalog,
	p_commander_passive_effect_ids: Array[StringName] = []
) -> void:
	_controller = p_controller
	_factory = p_factory
	_economy_catalog = p_economy_catalog
	_battle_catalog = p_battle_catalog
	_commander_passive_effect_ids = p_commander_passive_effect_ids.duplicate()


func is_concrete() -> bool:
	return _controller != null and _factory != null and _factory.is_concrete() \
		and _economy_catalog != null and _battle_catalog != null


func view() -> RunViewState:
	return _controller.view_state()


func map() -> MapState:
	return _controller.map_snapshot()


func economy() -> EconomyState:
	return _controller.economy_snapshot()


## 目前可進入的節點（與 NodeEntryService._reachable 同一判準的唯讀投影：尚未開圖時是
## 第一幕第 0 層，否則是「與任一已完成節點相鄰且自己未完成」的節點）。
func reachable_node_ids() -> Array[String]:
	var result: Array[String] = []
	var map_state := map()
	if map_state == null:
		return result
	for node: MapNodeState in map_state.nodes:
		if node.completed or map_state.completed_node_ids.has(node.node_id):
			continue
		if map_state.completed_node_ids.is_empty():
			if node.act_index == 1 and node.layer_index == 0:
				result.append(node.node_id)
			continue
		for completed_id: String in map_state.completed_node_ids:
			for edge: MapEdgeState in map_state.edges:
				if edge.from_node_id == completed_id and edge.to_node_id == node.node_id:
					result.append(node.node_id)
					break
			if result.has(node.node_id):
				break
	return result


func try_node(node_id: String) -> MapNodeState:
	for node: MapNodeState in map().nodes:
		if node.node_id == node_id:
			return node
	return null


func current_node() -> MapNodeState:
	var current := view().current_node_id
	return try_node(current.value) if current != null else null


# --- 地圖 / 節點 -------------------------------------------------------------

func generate_map() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _dispatch(_factory.generate_expedition_map_command())


func enter_node(node_id: String) -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _transition(_factory.enter_node_event(node_id))


func enter_first_reachable_node() -> StringName:
	var reachable := reachable_node_ids()
	if reachable.is_empty():
		return ERROR_NO_REACHABLE_NODE
	return enter_node(reachable[0])


## 非戰鬥節點（merchant/event/rest/treasure）的結算，回到 MAP。
func resolve_non_combat_node() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _dispatch(ResolveNonCombatNodeCommand.new(_economy_catalog))


# --- 商店 -------------------------------------------------------------------

func refresh_shop() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _dispatch(_factory.refresh_shop_command())


## 買下第一個報價（灰盒不做選單，只驗證「買得到」這條鏈）。
func buy_first_offer() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	var offers := economy().shop_offers
	if offers.is_empty():
		return ERROR_NO_SHOP_OFFER
	return _dispatch(BuyOfferCommand.new(
		offers[0].offer_id, _economy_catalog, _battle_catalog
	))


# --- 備戰 / 戰鬥 -------------------------------------------------------------

## 把現有 board（依 y、x 排序）與 bench 組成決定性、去重的 roster 聯集，再依序
## 排進玩家半場（y 由 0 起、每列 8 格），數量取 min(roster 數, economy level)。
## 人口上限是 level ＋指揮官加成，取 level 必然合法，灰盒不需要重算上限；
## 超出可部署數量的棋回到 bench，故重複備戰不會遺失已在 board 上的棋。
## 命令一律由 factory 建構，指揮官人口加成來源因此隨命令一起注入（缺口 2）。
func commit_board() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	var roster := _controller.roster_snapshot()
	var existing_placements: Array[BoardPlacementState] = roster.board.placements.duplicate()
	existing_placements.sort_custom(
		func(left: BoardPlacementState, right: BoardPlacementState) -> bool:
			if left.logical_y != right.logical_y:
				return left.logical_y < right.logical_y
			if left.logical_x != right.logical_x:
				return left.logical_x < right.logical_x
			return left.unit_instance_id < right.unit_instance_id
	)
	var ordered_instance_ids: Array[String] = []
	var seen_instance_ids: Dictionary = {}
	for placement: BoardPlacementState in existing_placements:
		if seen_instance_ids.has(placement.unit_instance_id):
			continue
		seen_instance_ids[placement.unit_instance_id] = true
		ordered_instance_ids.append(placement.unit_instance_id)
	for instance_id: String in roster.bench_unit_instance_ids:
		if seen_instance_ids.has(instance_id):
			continue
		seen_instance_ids[instance_id] = true
		ordered_instance_ids.append(instance_id)
	var deployable: int = mini(
		ordered_instance_ids.size(), maxi(0, view().economy.level)
	)
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	for index: int in range(ordered_instance_ids.size()):
		var instance_id := ordered_instance_ids[index]
		if index < deployable:
			@warning_ignore("integer_division")
			var row: int = index / BoardPreparationValidator.BOARD_WIDTH
			placements.append(BoardPlacementState.new(
				row, index % BoardPreparationValidator.BOARD_WIDTH, instance_id
			))
		else:
			bench.append(instance_id)
	return _dispatch(_factory.commit_board_layout_command(
		BoardState.new(placements), bench
	))


## 開戰並把整場模擬推到終局：StartCombatEvent 凍結 BattleSetup，CombatCoordinator 跑
## BattleSimulation 並在終局以 RecordBattleResultCommand 提交結果（S2 既有鏈）。
func start_combat() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	var committed := _controller.committed_combat_snapshot()
	var resumes_pending_combat: bool = committed != null \
		and committed.run_phase == RunState.RunPhase.COMBAT \
		and (
			committed.resolution_state is CombatPendingResolutionState
			or committed.resolution_state is BattleResultPendingResolutionState
		)
	if not resumes_pending_combat:
		var sources := BattleSetupSourceCompiler.new().compile(
			_controller.roster_snapshot(), _battle_catalog, _commander_passive_effect_ids
		)
		var started := _controller.transition(StartCombatEvent.new(_battle_catalog, sources))
		if not started.ok:
			return started.error.code
	var coordinator := CombatCoordinator.new(_controller)
	var begun := coordinator.begin_or_resume()
	if not begun.ok:
		return begun.error.code
	if begun.resumed_committed_result:
		return &""
	for _step: int in range(COMBAT_STEP_LIMIT):
		var advanced := coordinator.advance()
		if not advanced.ok:
			return advanced.error.code
		if advanced.result_committed:
			return &""
	return ERROR_COMBAT_STEP_LIMIT


## 戰果結算（勝→REWARD／敗→MAP 或 RESULTS／Boss 敗且未死→PREPARE 重戰）。
func settle_battle() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _dispatch(_factory.settle_battle_result_command())


## Boss 重戰放棄（S3 既有路徑）：遠征 HP 歸零、run_phase → RESULTS。
func abandon_boss_retry() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	return _dispatch(AbandonExpeditionCommand.new(_economy_catalog))


# --- 獎勵 -------------------------------------------------------------------

## 待決獎勵一路推到底：未選就選第一個 offer，選完就 advance，直到離開 REWARD 階段。
func resolve_rewards() -> StringName:
	if not is_concrete():
		return ERROR_NO_CONTROLLER
	if view().run_phase != RunState.RunPhase.REWARD:
		return ERROR_NO_PENDING_REWARD
	for _step: int in range(REWARD_STEP_LIMIT):
		var pending := _controller.pending_reward_snapshot()
		if pending == null:
			return ERROR_NO_PENDING_REWARD
		var error := _resolve_reward_step(pending)
		if not error.is_empty():
			return error
		if view().run_phase != RunState.RunPhase.REWARD:
			return &""
	return ERROR_REWARD_STEP_LIMIT


## 單一獎勵階段的推進：灰盒一律採「接受第一個選項」的固定策略（決定性、零 entropy）。
## ITEM_RESOLUTION 需要指定要處置的物品實例——溢出盤裡有東西就處置它，否則具名回報，
## 由 Codex 的正式獎勵 UI 提供真正的選擇（灰盒已知邊界）。
func _resolve_reward_step(pending: PendingRewardState) -> StringName:
	match pending.phase:
		PendingRewardState.Phase.CHOOSING:
			if pending.offers.is_empty():
				return ERROR_NO_PENDING_REWARD
			return _dispatch(ChooseRewardCommand.new(
				pending.offers[0].choice_id, _economy_catalog
			))
		PendingRewardState.Phase.UNIT_RESOLUTION:
			return _dispatch(ResolveUnitRewardCommand.new(
				true, _economy_catalog, _battle_catalog
			))
		PendingRewardState.Phase.ITEM_RESOLUTION:
			var overflow := _controller.roster_snapshot().pending_item_overflow
			if overflow.is_empty():
				return ERROR_ITEM_REWARD_UNSUPPORTED
			return _dispatch(ResolveItemRewardCommand.new(
				overflow[0], false, _economy_catalog
			))
		PendingRewardState.Phase.RELIC_RESOLUTION:
			return _dispatch(ResolveRelicRewardCommand.new(0, _economy_catalog))
	return _dispatch(AdvanceRewardCommand.new(_economy_catalog))


# --- dispatch helpers -------------------------------------------------------

func _dispatch(command: RunCommand) -> StringName:
	var result := _controller.dispatch(command)
	return &"" if result.ok else _code(result.error.code, result.error.diagnostic_values)


func _transition(event: RunEvent) -> StringName:
	var result := _controller.transition(event)
	return &"" if result.ok else _code(result.error.code, result.error.diagnostic_values)


## 失敗碼帶上 domain 端的 source_code（APPLY_FAILED 本身說不出被誰拒絕），灰盒才診斷得動。
func _code(code: StringName, diagnostics: Array[DiagnosticValue]) -> StringName:
	for diagnostic: DiagnosticValue in diagnostics:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return StringName("%s/%s" % [String(code), diagnostic.string_value.value])
	return code

class_name RunPresentationSession
extends RefCounted

signal snapshot_committed(snapshot: RunPresentationSnapshot)
signal presentation_error(error: DiagnosticError)

const NOT_IMPLEMENTED: StringName = &"RUN_PRESENTATION_SESSION_NOT_IMPLEMENTED"
const DEPENDENCY_MISSING: StringName = &"RUN_PRESENTATION_DEPENDENCY_MISSING"
const INTENT_INVALID: StringName = &"RUN_PRESENTATION_INTENT_INVALID"
const PLAYBACK_NOT_AVAILABLE: StringName = &"PLAYBACK_NOT_AVAILABLE"
const PENDING_TRANSCRIPT_REVOKED: StringName = &"PENDING_TRANSCRIPT_REVOKED"
const PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED: StringName = \
	&"PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED"
const COMBAT_STEP_LIMIT: StringName = &"RUN_PRESENTATION_COMBAT_STEP_LIMIT"
## commit-before-present（design.md §10）：START_OR_RESUME_COMBAT 一定把 canonical
## simulation 跑到 result 提交才回應，presentation 之後只重播已提交 transcript。
const COMBAT_COMMIT_STEP_LIMIT: int = 100000
const MapNodePresentationType = preload(
	"res://presentation/run/map_node_presentation.gd"
)

var _controller: RunController
var _factory: RunCommandFactory
var _combat: CombatCoordinator
var _battle_catalog: BattleRuleCatalog
var _commander_passive_effect_ids: Array[StringName] = []
var _snapshot := RunPresentationSnapshot.new()
var _combat_result_already_committed: bool = false
var _battle_transcript_buffer: BattleTranscriptBuffer
var _battle_playback_controller: BattlePlaybackController
var _committed_summary_only: bool = false
var _playback_warning: DiagnosticError
## 戰鬥檢視只能由 COMBAT_PENDING 的 battle_setup 建；result 提交後 canonical 只留
## BattleResultPendingResolutionState（無 setup），故 COMBAT 期間保留最後一份投影。
var _retained_combat_inspections: Array[CombatUnitInspectionSnapshot] = []
## 同一份 battle_setup 的召喚模板（IRH-REQ-007）：spawn 事件只帶身分與格位，血條與
## 魔力上限的權威只有 pinned battle_rules，故與檢視投影同進同出地保留。
var _retained_summoned_unit_templates: Array[SummonedUnitRuleSnapshot] = []
## in-run-hud T10：備戰期的鍛造預覽與商店報價供給。兩者都是「畫面要問、但公式在
## domain」的讀取面（spec §10.3 禁止呈現層自行換算），所以 session 在建構邊界收下
## pinned 供給，畫面只經下面的唯讀方法取值，不自行接 catalog 或 Autoload。
var _forge_table: ForgeRecipeTable
## ShopEconomyViewModel 每次查詢都重新向 RunSession 取 run_snapshot() deep clone，
## 自身只持 catalog／relic_table 的私有 clone，因此可以隨 session（＝單一 pinned
## 世代）存活一次建構；catalog 世代更換必然伴隨新的 session。
var _shop_economy: ShopEconomyViewModel


func _init(
	p_controller: RunController = null,
	p_factory: RunCommandFactory = null,
	p_battle_catalog: BattleRuleCatalog = null,
	p_commander_passive_effect_ids: Array[StringName] = [],
	p_combat: CombatCoordinator = null,
	p_run_session: RunSession = null,
	p_forge_table: ForgeRecipeTable = null,
	p_economy_catalog: EconomyExpeditionCatalog = null,
	p_relic_table: RunRelicTable = null
) -> void:
	_controller = p_controller
	_factory = p_factory
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_commander_passive_effect_ids.assign(p_commander_passive_effect_ids)
	_forge_table = p_forge_table.deep_clone() if p_forge_table != null else null
	# 供給缺席（既有呼叫端只傳前五個參數）時同樣建得起來：ShopEconomyViewModel 對
	# null session／catalog 一律回空狀態或具名 rejection_code，不會 crash。
	_shop_economy = ShopEconomyViewModel.new(
		p_run_session, p_economy_catalog, p_relic_table
	)
	_combat = p_combat if p_combat != null else (
		CombatCoordinator.new(_controller) if _controller != null else null
	)
	if _combat != null and _combat.has_method(&"bind_presentation_session"):
		_combat.call(&"bind_presentation_session", self)
	if _controller != null:
		_snapshot = _build_snapshot()


func is_concrete() -> bool:
	return _controller != null and _factory != null and _factory.is_concrete()


func snapshot() -> RunPresentationSnapshot:
	return _snapshot.deep_clone()


## 目前可選節點（frontier）：自 current_node_id 出發、下一步合法可進入的節點集合；
## 還沒進過任何節點時＝ act 1 / layer 0 的起始集合。判準與 domain 的
## NodeEntryService 同源（MapFrontier），因此節點圖亮起的集合恆等於 domain 會受理
## 的集合，不會出現「亮著卻進不去」或「進得去卻沒亮」。回傳 clone。
func frontier_nodes() -> Array[MapNodePresentation]:
	var result: Array[MapNodePresentation] = []
	if _snapshot.map == null:
		return result
	for node: MapNodeState in MapFrontier.frontier_nodes(_snapshot.map):
		result.append(MapNodePresentationType.from_state(node, true))
	return result


## frontier 節點的 id 清單（順序同 frontier_nodes()）。只要 id 的呼叫端用這個，
## 不必自行過濾整張節點表。
func frontier_node_ids() -> Array[String]:
	return MapFrontier.frontier_node_ids(_snapshot.map)


## 既有呼叫端（balance driver、dev run lab）的保留別名。C-1 之前它回的是「拓撲
## 可達」的寬鬆集合——含上一層沒選走的兄弟分支；判準收斂到 MapFrontier 之後，
## 它與 frontier_nodes() 同義。新程式碼直接用 frontier_nodes()。
func reachable_nodes() -> Array:
	var result: Array = []
	result.assign(frontier_nodes())
	return result


## 備戰期鍛造面板的零件清單（inventory 內的物品快照，clone-only）。未注入
## ForgeRecipeTable 或無 controller 時回空陣列——「沒有可顯示的零件」與「鍛造供給
## 缺席」在畫面上都是同一件事：沒有可鍛造的東西。
func forge_inventory_components() -> Array[ItemInstanceState]:
	var view_model := _try_forge_view_model()
	if view_model == null:
		return []
	return view_model.inventory_components()


## 含指定零件 def_id 的所有已註冊配方（自配＋交叉配方）。配方權威只有 pinned
## ForgeRecipeTable 一處，呈現層不得自行組合零件。
func forge_recipes_containing(component_def_id: StringName) -> Array[ForgeRecipeRule]:
	var view_model := _try_forge_view_model()
	if view_model == null or component_def_id.is_empty():
		return []
	return view_model.recipe_preview(component_def_id)


## 拖曳合成的即時預覽：兩個 inventory 零件 instance 配得出來的成品規則，配不出來
## （或其中一個不是可用零件）時回 null。可用性判準與 ForgeEquipmentCommand 同源：
## 兩個相異 instance、都在 inventory、都未綁在單位上；成品仍由 table.try_recipe()
## 決定，本方法不複製任何配方規則。真正的鍛造一律走 FORGE_EQUIPMENT intent。
func try_forge_pair_recipe(
	component_instance_id_a: String,
	component_instance_id_b: String
) -> ForgeRecipeRule:
	if (
		_forge_table == null
		or component_instance_id_a.is_empty()
		or component_instance_id_b.is_empty()
		or component_instance_id_a == component_instance_id_b
	):
		return null
	var components := forge_inventory_components()
	var def_a := _try_available_component_def_id(
		components, component_instance_id_a
	)
	var def_b := _try_available_component_def_id(
		components, component_instance_id_b
	)
	if def_a.is_empty() or def_b.is_empty():
		return null
	return _forge_table.try_recipe(def_a, def_b)


## 經濟資訊列（金幣／等級經驗／連勝連敗／目前等級費用機率）。供給缺席時為全零快照。
func shop_economy_status() -> ShopEconomySnapshot:
	return _shop_economy.economy_status()


## 刷新商店的報價（實際扣款、可否負擔、不可用時的 domain 具名原因）。
func shop_refresh_quote() -> ShopQuoteSnapshot:
	return _shop_economy.refresh_quote()


## 購買經驗的報價（花費、獲得經驗、折算後等級／經驗、MAX 狀態）。
func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
	return _shop_economy.buy_xp_quote()


## 指定單位的出售報價（實際入袋金幣，含 gold_cap 夾擠）。
func shop_sell_quote(unit_instance_id: String) -> ShopQuoteSnapshot:
	return _shop_economy.sell_quote(unit_instance_id)


## 拖曳草稿的人口／合法性／羈絆變化預覽（IRH-REQ-008）。人口與合法性一律經
## BoardPreparationValidator、羈絆經 compile_trait_progress()——本方法只轉發，
## 零複製。草稿是完整指派（缺漏由 validator 以 BOARD_UNIT_UNASSIGNED 如實回報）。
## 供給缺席時回 null。
func try_board_draft_preview(
	draft_placements: Array[BoardPlacementState],
	draft_bench_unit_instance_ids: Array[String]
) -> BoardDraftPreviewSnapshot:
	var view_model := _try_board_draft_view_model()
	if view_model == null:
		return null
	return view_model.preview(draft_placements, draft_bench_unit_instance_ids)


## 已提交佈局的同構預覽（拖曳前的基準值，供畫面顯示「變化前→變化後」）。
func try_committed_board_preview() -> BoardDraftPreviewSnapshot:
	var view_model := _try_board_draft_view_model()
	if view_model == null:
		return null
	return view_model.committed_preview()


## 戰鬥中被召喚實體的呈現權威（IRH-REQ-007）：與 combat_inspections 同一份
## COMBAT_PENDING battle_setup 的 pinned 召喚模板，clone-only。transcript 的 spawn
## 事件只帶身分、陣營與格位，血條／魔力上限只能來自這裡；缺模板的 unit_id 由呈現層
## fail closed 為不可渲染，不得虛構。供給缺席或已離開 COMBAT 時回空陣列。
func combat_summoned_unit_templates() -> Array[SummonedUnitRuleSnapshot]:
	var result: Array[SummonedUnitRuleSnapshot] = []
	for template: SummonedUnitRuleSnapshot in _retained_summoned_unit_templates:
		if template != null:
			result.append(template.deep_clone())
	return result


## 羈絆進度唯一權威的轉發（IRH-REQ-013）：含場上 0 隻的 inactive 列、distinct_count、
## active_tier、next_required_count 與完整門檻階梯，trait_id 字典序。
## 供給缺席時回空陣列。取代只涵蓋 active 的 snapshot 投影作為面板資料來源。
func trait_progress() -> Array[TraitProgressSnapshot]:
	if _controller == null or _battle_catalog == null:
		return []
	return TraitPreviewViewModel.new(_controller, _battle_catalog).trait_progress()


## ViewModel 只在讀取邊界存活（同 _build_snapshot 的既有範式）：回傳值本身已是
## clone，畫面因此拿不到 RunController。
func _try_board_draft_view_model() -> BoardDraftPreviewViewModel:
	if _controller == null or _factory == null or _battle_catalog == null:
		return null
	return BoardDraftPreviewViewModel.new(_controller, _factory, _battle_catalog)


func _try_forge_view_model() -> ForgeViewModel:
	if _controller == null or _forge_table == null:
		return null
	return ForgeViewModel.new(_controller, _forge_table)


func _try_available_component_def_id(
	components: Array[ItemInstanceState],
	item_instance_id: String
) -> StringName:
	for item: ItemInstanceState in components:
		if (
			item != null
			and item.instance_id == item_instance_id
			and item.bound_unit_instance_id == null
		):
			return item.def_id
	return &""


func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
	if not is_concrete():
		return _precommit_failure(_error(
			DEPENDENCY_MISSING, &"error.presentation.run_dependency_missing"
		))
	if intent == null:
		return _precommit_failure(_error(
			INTENT_INVALID, &"error.presentation.run_intent_invalid"
		))
	match intent.kind:
		RunPresentationIntent.Kind.GENERATE_MAP:
			return _dispatch_command(_factory.generate_expedition_map_command())
		RunPresentationIntent.Kind.ENTER_NODE:
			return _dispatch_transition(_factory.enter_node_event(intent.target_node_id))
		RunPresentationIntent.Kind.REFRESH_SHOP:
			return _dispatch_command(_factory.refresh_shop_command())
		RunPresentationIntent.Kind.BUY_UNIT:
			return _dispatch_command(_factory.buy_offer_command(intent.offer_id))
		RunPresentationIntent.Kind.BUY_XP:
			return _dispatch_command(_factory.buy_xp_command())
		RunPresentationIntent.Kind.SELL_UNIT:
			return _dispatch_command(_factory.sell_unit_command(intent.unit_instance_id))
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT:
			return _dispatch_command(_factory.commit_board_layout_command(
				intent.board, intent.bench_unit_instance_ids
			))
		RunPresentationIntent.Kind.FORGE_EQUIPMENT:
			return _dispatch_command(_factory.forge_equipment_command(
				intent.item_instance_id, intent.secondary_item_instance_id
			))
		RunPresentationIntent.Kind.EQUIP_ITEM:
			return _dispatch_command(_factory.equip_item_command(
				intent.unit_instance_id, intent.item_instance_id
			))
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT:
			return _dispatch_command(_factory.dismantle_equipment_command(
				intent.item_instance_id, intent.secondary_item_instance_id
			))
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT:
			return _start_or_resume_combat(intent)
		RunPresentationIntent.Kind.SETTLE_BATTLE:
			return _dispatch_command(_factory.settle_battle_result_command())
		RunPresentationIntent.Kind.RESOLVE_NON_COMBAT:
			return _dispatch_command(_factory.resolve_non_combat_node_command())
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD:
			return _dispatch_command(_factory.choose_reward_command(intent.choice_id))
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD:
			return _dispatch_command(_factory.resolve_unit_reward_command(intent.accept))
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD:
			return _dispatch_command(_factory.resolve_item_reward_command(
				intent.item_instance_id, intent.abandon
			))
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD:
			return _dispatch_command(_factory.resolve_relic_reward_command(
				intent.relic_slot_index
			))
		RunPresentationIntent.Kind.ADVANCE_REWARD:
			return _dispatch_command(_factory.advance_reward_command())
		RunPresentationIntent.Kind.RESOLVE_UNIT_OVERFLOW:
			return _dispatch_command(_factory.resolve_unit_overflow_command(
				intent.item_instance_id
			))
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW:
			return _dispatch_command(_factory.resolve_item_overflow_command(
				intent.item_instance_id, intent.target_unit_instance_id
			))
		RunPresentationIntent.Kind.REPLACE_RELIC:
			return _dispatch_command(_factory.replace_relic_command(intent.relic_slot_index))
		RunPresentationIntent.Kind.ABANDON_RELIC:
			return _dispatch_command(_factory.abandon_relic_command())
		RunPresentationIntent.Kind.ABANDON_BOSS_RETRY:
			return _dispatch_command(_factory.abandon_boss_retry_command())
		RunPresentationIntent.Kind.SETTLE_TERMINAL_RUN:
			return _dispatch_command(_factory.settle_terminal_run_command())
		RunPresentationIntent.Kind.COMMIT_NODE_CHOICE:
			# design :177「factory 不得以 latest state 覆蓋」：payload 是 UI 在
			# overlay 建立當下抄下的那一份，dispatch 只原樣轉呈。
			return _dispatch_command(_factory.commit_node_choice_command(
				intent.node_choice_payload
			))
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT:
			return _dispatch_command(
				_factory.acknowledge_node_choice_result_command(
					intent.expected_run_id,
					intent.receipt_digest
				)
			)
		RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE:
			return _dispatch_command(
				_factory.dismantle_with_node_service_command(
					intent.expected_run_id,
					intent.node_id,
					intent.choice_receipt_digest,
					intent.item_instance_id
				)
			)
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE:
			return _dispatch_command(_factory.exit_node_service_command(
				intent.expected_run_id,
				intent.node_id,
				intent.choice_receipt_digest
			))
	return _precommit_failure(_error(
		INTENT_INVALID, &"error.presentation.run_intent_invalid"
	))


func try_playback() -> BattlePlaybackStateResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackStateResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return BattlePlaybackStateResult.new(
		true,
		_battle_playback_controller.snapshot(),
		null
	)


func set_playback_speed(multiplier: int) -> BattlePlaybackCommandResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return _battle_playback_controller.set_speed(multiplier)


func set_playback_paused(paused: bool) -> BattlePlaybackCommandResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return _battle_playback_controller.set_paused(paused)


func drain_playback_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int
) -> BattleEventWindowResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattleEventWindowResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	var cursor := _battle_playback_controller.snapshot().cursor
	var result := _battle_transcript_buffer.drain_window(
		expected_identity,
		max_count,
		cursor
	)
	if result.ok:
		_battle_playback_controller._consume_events(result.window.events.size())
	return result


## 每 frame 的播放推進：presentation 時鐘走到哪個 canonical tick，就取到哪裡的事件，
## 再由同一個 private cursor 前進。暫停時不推進時鐘也不回 exhausted，故暫停不會結算。
func advance_playback(delta_ms: float) -> BattleEventWindowResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattleEventWindowResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	if _battle_playback_controller.is_paused():
		return BattleEventWindowResult.new(true, _idle_playback_window(false), null)
	var max_tick := _battle_playback_controller._advance_presentation_tick(delta_ms)
	var state := _battle_playback_controller.snapshot()
	var budget := _battle_transcript_buffer._events_through_tick(state.cursor, max_tick)
	if budget <= 0:
		return BattleEventWindowResult.new(
			true,
			_idle_playback_window(_battle_playback_controller.has_reached_end()),
			null
		)
	var result := _battle_transcript_buffer.drain_window(
		state.transcript_identity,
		budget,
		state.cursor
	)
	if result.ok:
		_battle_playback_controller._consume_events(result.window.events.size())
	return result


func _idle_playback_window(exhausted: bool) -> BattleEventWindow:
	var window := BattleEventWindow.new()
	window.identity = _battle_playback_controller.snapshot().transcript_identity
	window.exhausted = exhausted
	return window


## 離開 run 範疇時的顯式解綁。session 與 CombatCoordinator 互持強引用（皆為
## RefCounted），沒有這一步整組 run 物件圖永不釋放。
func release() -> void:
	release_playback(&"run_scope_released")
	if _combat != null and _combat.has_method(&"unbind_presentation_session"):
		_combat.call(&"unbind_presentation_session")
	_combat = null
	_controller = null
	_factory = null
	_battle_catalog = null
	_forge_table = null
	# 供給一併解除，讓 RunSession／catalog clone 隨 run 範疇結束釋放；後續查詢
	# 走的是與「從未注入供給」相同的空狀態路徑。
	_shop_economy = ShopEconomyViewModel.new(null, null, null)
	_retained_combat_inspections.clear()
	_retained_summoned_unit_templates.clear()
	_snapshot = RunPresentationSnapshot.new()


## Internal final-save boundary called only by CombatCoordinator. This method
## receives the sole precommit owner, seals/transfers its storage, and never
## exposes the buffer or raw array through the returned result.
func _accept_committed_transcript(
	accumulator: Variant,
	transcript_identity: BattleTranscriptIdentity,
	encoded_byte_count: int
) -> BattleTranscriptInstallResult:
	if (
		accumulator == null
		or not accumulator.has_method(&"is_revoked")
		or not accumulator.has_method(&"event_budget")
		or not accumulator.has_method(&"_seal_and_transfer")
		or bool(accumulator.call(&"is_revoked"))
	):
		return BattleTranscriptInstallResult.failure(_error(
			PENDING_TRANSCRIPT_REVOKED,
			&"error.presentation.pending_transcript_revoked"
		))
	var event_budget: int = int(accumulator.call(&"event_budget"))
	var transferred: Array = accumulator.call(&"_seal_and_transfer")
	release_playback(&"committed_transcript_replaced")
	var candidate := BattleTranscriptBuffer.new(
		transcript_identity,
		transferred,
		event_budget,
		encoded_byte_count
	)
	if not candidate.is_within_budget():
		candidate.revoke()
		_committed_summary_only = true
		_playback_warning = _error(
			PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED,
			&"warning.presentation.transcript_memory_budget_exceeded"
		)
		return BattleTranscriptInstallResult.summary_fallback(_playback_warning)
	_battle_transcript_buffer = candidate
	_battle_playback_controller = BattlePlaybackController.new(
		transcript_identity,
		candidate.event_count()
	)
	_committed_summary_only = false
	_playback_warning = null
	return BattleTranscriptInstallResult.installed()


func release_playback(_reason: StringName = &"") -> void:
	if _battle_transcript_buffer != null:
		_battle_transcript_buffer.revoke()
	_battle_transcript_buffer = null
	_battle_playback_controller = null
	_committed_summary_only = false
	_playback_warning = null


func is_committed_summary_only() -> bool:
	return _committed_summary_only


func playback_warning() -> DiagnosticError:
	return _playback_warning.deep_clone() if _playback_warning != null else null


func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult:
	if (
		unit_serial <= 0
		or _snapshot == null
		or _snapshot.app_phase != &"COMBAT"
		or unit_serial > _snapshot.combat_inspections.size()
	):
		return CombatUnitInspectionResult.failure(_error(
			&"COMBAT_UNIT_NOT_FOUND",
			&"error.presentation.combat_unit_not_found"
		))
	var inspection := _snapshot.combat_inspections[unit_serial - 1]
	if inspection == null or inspection.unit_serial != unit_serial:
		return CombatUnitInspectionResult.failure(_error(
			&"COMBAT_UNIT_NOT_FOUND",
			&"error.presentation.combat_unit_not_found"
		))
	return CombatUnitInspectionResult.new(
		true,
		inspection.deep_clone(),
		null
	)


func _first_target_serial(
	source: UnitBattleSnapshot,
	serial_by_instance: Dictionary
) -> int:
	for assignment: BattleEffectSnapshot in source.effect_assignments:
		for target_id: StringName in assignment.target_ids:
			if serial_by_instance.has(target_id):
				return int(serial_by_instance[target_id])
	return 0


## COMBAT 期間的檢視投影：COMBAT_PENDING 有 battle_setup 時重建並保留，result 提交後
## canonical 只剩 BattleResultPendingResolutionState，改用保留的同一份；離開 COMBAT 即清空。
func _resolve_combat_inspections(
	view: RunViewState
) -> Array[CombatUnitInspectionSnapshot]:
	var result: Array[CombatUnitInspectionSnapshot] = []
	if view == null or view.run_phase != RunState.RunPhase.COMBAT:
		_retained_combat_inspections.clear()
		_retained_summoned_unit_templates.clear()
		return result
	var built := _build_combat_inspections()
	if not built.is_empty():
		_retained_combat_inspections = built
		# 兩者讀的是同一份 COMBAT_PENDING battle_setup；分開更新會讓重播期間的
		# spawn 事件配到上一場戰鬥的召喚權威。
		_retained_summoned_unit_templates = _build_summoned_unit_templates()
	for inspection: CombatUnitInspectionSnapshot in _retained_combat_inspections:
		result.append(inspection.deep_clone())
	return result


func _build_combat_inspections() -> Array[CombatUnitInspectionSnapshot]:
	var result: Array[CombatUnitInspectionSnapshot] = []
	if _controller == null:
		return result
	var committed := _controller.committed_combat_snapshot()
	if (
		committed == null
		or committed.run_phase != RunState.RunPhase.COMBAT
		or not committed.resolution_state is CombatPendingResolutionState
	):
		return result
	var pending := committed.resolution_state as CombatPendingResolutionState
	if (
		pending.battle_setup == null
		or pending.battle_setup.inputs == null
		or pending.battle_setup.inputs.encounter_snapshot == null
	):
		return result
	var inputs := pending.battle_setup.inputs.deep_clone()
	var units: Array[UnitBattleSnapshot] = []
	# 陣營旗標與單位同步 append：以索引界線判陣營會在跳過 null 後把敵方誤判成我方。
	var player_flags: Array[bool] = []
	for player: UnitBattleSnapshot in inputs.player_units:
		if player != null:
			units.append(player.deep_clone())
			player_flags.append(true)
	for enemy: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		if enemy != null:
			units.append(enemy.deep_clone())
			player_flags.append(false)
	var serial_by_instance: Dictionary = {}
	for index: int in units.size():
		var unit := units[index]
		if not unit.instance_id.is_empty():
			serial_by_instance[unit.instance_id] = index + 1
	var empty_equipment_effects: Array[BattleEffectSnapshot] = []
	for index: int in units.size():
		var unit := units[index]
		var is_player := player_flags[index]
		var traits: Array[TraitBattleSnapshot] = (
			inputs.player_active_traits
			if is_player
			else inputs.encounter_snapshot.active_traits
		)
		var equipment_effects: Array[BattleEffectSnapshot] = (
			inputs.player_equipment_effects
			if is_player
			else empty_equipment_effects
		)
		result.append(_build_combat_inspection(
			index + 1,
			unit,
			traits,
			equipment_effects,
			serial_by_instance
		))
	return result


## 與 _build_combat_inspections() 同源、同守衛：只讀 COMBAT_PENDING battle_setup 的
## pinned battle_rules，逐一 clone 出召喚模板。result 提交後 setup 不在了會回空，
## 由呼叫端的保留規則決定是否沿用上一份。
func _build_summoned_unit_templates() -> Array[SummonedUnitRuleSnapshot]:
	var result: Array[SummonedUnitRuleSnapshot] = []
	if _controller == null:
		return result
	var committed := _controller.committed_combat_snapshot()
	if (
		committed == null
		or committed.run_phase != RunState.RunPhase.COMBAT
		or not committed.resolution_state is CombatPendingResolutionState
	):
		return result
	var pending := committed.resolution_state as CombatPendingResolutionState
	if (
		pending.battle_setup == null
		or pending.battle_setup.inputs == null
		or pending.battle_setup.inputs.battle_rules == null
	):
		return result
	for template: SummonedUnitRuleSnapshot in \
		pending.battle_setup.inputs.battle_rules.summoned_unit_templates:
		if template != null:
			result.append(template.deep_clone())
	return result


func _build_combat_inspection(
	unit_serial: int,
	unit: UnitBattleSnapshot,
	trait_snapshots: Array[TraitBattleSnapshot],
	equipment_effects: Array[BattleEffectSnapshot],
	serial_by_instance: Dictionary
) -> CombatUnitInspectionSnapshot:
	var inspection := CombatUnitInspectionSnapshot.new()
	inspection.unit_serial = unit_serial
	inspection.presentation_instance_id = unit.instance_id
	inspection.source_id = unit.unit_id
	inspection.side_id = unit.side
	inspection.logical_cell = Vector2i(unit.logical_x, unit.logical_y)
	inspection.target_serial = _first_target_serial(
		unit,
		serial_by_instance
	)
	inspection.stats = {
		"star": unit.star,
		"health": unit.health,
		"attack": unit.attack,
		"armor": unit.armor,
		"magic_resist": unit.magic_resist,
		"attack_speed_milli": unit.attack_speed_milli,
		"attack_range_cells": unit.attack_range_cells,
		"start_mana": unit.start_mana,
		"max_mana": unit.max_mana,
		"move_speed_milli": unit.move_speed_milli,
	}
	_append_equipment_ids(
		inspection.equipment_ids,
		equipment_effects,
		unit.instance_id
	)
	_append_equipment_ids(
		inspection.equipment_ids,
		unit.effect_assignments,
		unit.instance_id
	)
	for trait_entry: TraitBattleSnapshot in trait_snapshots:
		if (
			trait_entry != null
			and trait_entry.member_instance_ids.has(unit.instance_id)
			and not inspection.trait_ids.has(trait_entry.trait_id)
		):
			inspection.trait_ids.append(trait_entry.trait_id)
	inspection.status_ids.assign(unit.effect_ids)
	for assignment: BattleEffectSnapshot in unit.effect_assignments:
		if (
			assignment != null
			and not assignment.effect_id.is_empty()
			and not inspection.status_ids.has(assignment.effect_id)
		):
			inspection.status_ids.append(assignment.effect_id)
	# StringName 的裸 sort() 依 interned 指標序排序（受 process 歷史影響，BP-SI-007）；
	# 檢視面板顯示順序須具決定性，改用字典序。
	inspection.equipment_ids.sort_custom(StableNameSort.id_less)
	inspection.trait_ids.sort_custom(StableNameSort.id_less)
	inspection.status_ids.sort_custom(StableNameSort.id_less)
	return inspection


func _append_equipment_ids(
	target: Array[StringName],
	effects: Array[BattleEffectSnapshot],
	unit_instance_id: StringName
) -> void:
	for effect: BattleEffectSnapshot in effects:
		if (
			effect == null
			or effect.source_category != &"equipment"
			or effect.source_stable_id.is_empty()
			or not effect.target_ids.has(unit_instance_id)
			or target.has(effect.source_stable_id)
		):
			continue
		target.append(effect.source_stable_id)


## Compatibility surface for the dev Run Lab. Production screens bind only typed
## lease ports; the dev wrapper is deliberately a consumer of this facade.
func view_state() -> RunViewState:
	return _controller.view_state() if _controller != null else null


func map_state() -> MapState:
	return _controller.map_snapshot() if _controller != null else null


func economy_state() -> EconomyState:
	return _controller.economy_snapshot() if _controller != null else null


func roster_state() -> RosterState:
	return _controller.roster_snapshot() if _controller != null else null


func pending_reward_state() -> PendingRewardState:
	return _controller.pending_reward_snapshot() if _controller != null else null


func drive_current_combat_to_commit(step_limit: int) -> StringName:
	if _combat == null:
		return DEPENDENCY_MISSING
	if _combat_result_already_committed:
		_combat_result_already_committed = false
		return &""
	var error_code := _drive_to_commit(step_limit)
	if error_code.is_empty():
		_snapshot = _build_snapshot()
		snapshot_committed.emit(_snapshot.deep_clone())
	return error_code


## 只跑 canonical simulation 到 result 提交為止，不發 snapshot signal——提交時機由
## 呼叫端決定（intent 路徑統一在 _commit_success 發一次）。
func _drive_to_commit(step_limit: int) -> StringName:
	for _step: int in range(step_limit):
		var advanced := _combat.advance()
		if not advanced.ok:
			return _combat_error_code(advanced.error)
		if advanced.result_committed:
			return &""
	return COMBAT_STEP_LIMIT


func _start_or_resume_combat(intent: RunPresentationIntent) -> RunPresentationResult:
	var view := _controller.view_state()
	var start_committed: bool = false
	if view.run_phase != RunState.RunPhase.COMBAT:
		var sources := intent.battle_sources
		if sources == null and _battle_catalog != null:
			sources = BattleSetupSourceCompiler.new().compile(
				_controller.roster_snapshot(),
				_battle_catalog,
				_commander_passive_effect_ids
			)
		var transitioned := _controller.transition(_factory.start_combat_event(sources))
		if not transitioned.ok:
			return _precommit_failure(_transition_error(transitioned.error))
		start_committed = true
	if _combat == null:
		var dependency_error := _error(
			DEPENDENCY_MISSING, &"error.presentation.combat_dependency_missing"
		)
		return (
			RunPresentationResult.postcommit_failure(dependency_error, _build_snapshot())
			if start_committed
			else _precommit_failure(dependency_error)
		)
	var begun := _combat.begin_or_resume()
	if not begun.ok:
		var combat_error := _error(
			_combat_error_code(begun.error), &"error.presentation.combat_start_failed"
		)
		if start_committed:
			_snapshot = _build_snapshot()
			presentation_error.emit(combat_error.deep_clone())
			return RunPresentationResult.postcommit_failure(combat_error, _snapshot)
		return _precommit_failure(combat_error)
	if not begun.resumed_committed_result:
		# 檢視投影只在 COMBAT_PENDING（有 battle_setup）時建得起來，驅動到 result 提交後
		# canonical 就只剩 BattleResultPendingResolutionState，故先取一份留給整個 COMBAT。
		_retained_combat_inspections = _build_combat_inspections()
		_retained_summoned_unit_templates = _build_summoned_unit_templates()
		var drive_code := _drive_to_commit(COMBAT_COMMIT_STEP_LIMIT)
		if not drive_code.is_empty():
			var drive_error := _error(
				drive_code, &"error.presentation.combat_drive_failed"
			)
			# 驅動失敗前沒有 result 落檔；只有本次已提交的 COMBAT 轉場算 postcommit。
			if not start_committed:
				return _precommit_failure(drive_error)
			_snapshot = _build_snapshot()
			presentation_error.emit(drive_error.deep_clone())
			return RunPresentationResult.postcommit_failure(drive_error, _snapshot)
	# 灰盒 consumer 隨後仍會呼叫 drive_current_combat_to_commit()：旗標讓那一次成為
	# 冪等的 no-op，而不是對已結束的 simulation 再 advance。
	_combat_result_already_committed = true
	return _commit_success()


func _dispatch_command(command: RunCommand) -> RunPresentationResult:
	var result := _controller.dispatch(command)
	if not result.ok:
		return _precommit_failure(_command_error(result.error))
	return _commit_success()


func _dispatch_transition(event: RunEvent) -> RunPresentationResult:
	var result := _controller.transition(event)
	if not result.ok:
		return _precommit_failure(_transition_error(result.error))
	return _commit_success()


func _commit_success() -> RunPresentationResult:
	_snapshot = _build_snapshot()
	snapshot_committed.emit(_snapshot.deep_clone())
	return RunPresentationResult.success(_snapshot)


func _precommit_failure(error: DiagnosticError) -> RunPresentationResult:
	presentation_error.emit(error.deep_clone())
	return RunPresentationResult.precommit_failure(error, _snapshot)


func _build_snapshot() -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	if _controller == null:
		return result
	var view := _controller.view_state()
	result.run_id = StringName(view.run_id)
	result.app_phase = StringName(RunState.RunPhase.keys()[view.run_phase])
	result.manifest_digest = view.content_manifest_digest
	result.view = view.deep_clone()
	result.map = _controller.map_snapshot()
	_mark_progress_transitions(result, _snapshot)
	result.economy = _controller.economy_snapshot()
	result.roster = _controller.roster_snapshot()
	result.pending_reward = _controller.pending_reward_snapshot()
	var pending_choice := _controller.node_choice_pending_snapshot()
	if pending_choice != null and _factory != null:
		var choice_set := _factory.try_node_choice_set(
			pending_choice.choice_set_id
		)
		if choice_set != null:
			result.node_choice_overlay = NodeChoiceOverlaySnapshot.from_rule(
				choice_set, pending_choice
			)
	result.node_service_overlay = NodeServiceOverlaySnapshot.from_state(
		_controller.node_service_pending_snapshot()
	)
	for receipt: NodeChoiceCommitReceiptState in \
		_controller.unacknowledged_node_choice_receipts():
		result.pending_node_choice_results.append(
			NodeChoiceResultSnapshot.from_receipt(receipt)
		)
	if (
		_factory != null
		and result.roster != null
		and result.economy != null
	):
		result.board_validation_report = _factory.board_validation_report(
			result.roster,
			result.economy.level
		)
	if _battle_catalog != null:
		# ViewModel 僅在 snapshot 建立邊界存活；回傳值會再由
		# RunPresentationSnapshot.deep_clone() clone-out，畫面不保留 controller。
		result.unit_stats_previews.assign(
			UnitStatsPreviewViewModel.new(
				_controller, _battle_catalog
			).all_stats()
		)
		result.prepare_unit_inspections.assign(
			_build_prepare_unit_inspections(result)
		)
		result.active_trait_previews.assign(
			TraitPreviewViewModel.new(
				_controller, _battle_catalog
			).trait_snapshots()
		)
		result.active_trait_progress.assign(
			_build_active_trait_progress(result)
		)
		if result.roster != null and result.economy != null:
			result.shop_offer_previews.assign(
				ShopOfferPreviewViewModel.new(
					result.roster, _battle_catalog
				).previews(result.economy)
			)
	result.combat_inspections = _resolve_combat_inspections(view)
	for kind_name: String in RunPresentationIntent.Kind.keys():
		result.available_actions.append(StringName(kind_name))
	return result


func _build_active_trait_progress(
	snapshot: RunPresentationSnapshot
) -> Array[TraitProgressPresentationSnapshot]:
	var result: Array[TraitProgressPresentationSnapshot] = []
	if (
		snapshot == null
		or _battle_catalog == null
		or snapshot.manifest_digest.is_empty()
		or _battle_catalog.manifest_digest_value() != snapshot.manifest_digest
	):
		return result
	for active: TraitBattleSnapshot in snapshot.active_trait_previews:
		if active == null or active.trait_id.is_empty():
			result.clear()
			return result
		var rule := _battle_catalog.try_trait_rule(active.trait_id)
		if rule == null:
			result.clear()
			return result
		var progress := TraitProgressPresentationSnapshot.new()
		progress.trait_id = active.trait_id
		progress.current_tier = active.tier
		progress.member_count = active.member_instance_ids.size()
		for index: int in range(rule.thresholds.size()):
			var authored := rule.thresholds[index]
			if authored == null:
				result.clear()
				return result
			var threshold := TraitThresholdPresentationSnapshot.new()
			threshold.tier = index + 1
			threshold.required_count = authored.required_count
			threshold.effect_ids.assign(authored.effect_ids)
			progress.thresholds.append(threshold)
		if progress.thresholds.is_empty():
			result.clear()
			return result
		result.append(progress)
	return result


func _build_prepare_unit_inspections(
	snapshot: RunPresentationSnapshot
) -> Array[PrepareUnitInspectionSnapshot]:
	var result: Array[PrepareUnitInspectionSnapshot] = []
	if (
		snapshot == null
		or snapshot.roster == null
		or _battle_catalog == null
		or snapshot.manifest_digest.is_empty()
		or _battle_catalog.manifest_digest_value() != snapshot.manifest_digest
	):
		return result
	for unit: UnitInstance in snapshot.roster.unit_instances:
		if unit == null:
			continue
		var preview := _find_prepare_stats(
			snapshot.unit_stats_previews, unit.instance_id
		)
		var rule := _battle_catalog.try_unit_rule(unit.def_id)
		if (
			preview == null
			or rule == null
			or preview.unit_id != unit.def_id
			or preview.star != unit.star
			or preview.equipment_instance_ids != unit.equipment_instance_ids
		):
			continue
		var inspection := PrepareUnitInspectionSnapshot.new()
		inspection.unit_instance_id = StringName(unit.instance_id)
		inspection.unit_id = preview.unit_id
		inspection.unit_def_id = unit.def_id
		inspection.star = unit.star
		inspection.cost_tier = rule.cost_tier
		inspection.trait_ids.assign(rule.trait_ids)
		inspection.ability_id = (
			rule.ability_id.value if rule.ability_id != null else &""
		)
		inspection.ai_profile = rule.ai_profile
		inspection.equipment_instance_ids.assign(unit.equipment_instance_ids)
		inspection.stats = preview.deep_clone()
		result.append(inspection)
	result.sort_custom(_prepare_inspection_precedes)
	return result


func _find_prepare_stats(
	previews: Array[UnitStatsPreviewSnapshot],
	unit_instance_id: String
) -> UnitStatsPreviewSnapshot:
	for preview: UnitStatsPreviewSnapshot in previews:
		if preview != null and String(preview.instance_id) == unit_instance_id:
			return preview
	return null


func _prepare_inspection_precedes(
	left: PrepareUnitInspectionSnapshot,
	right: PrepareUnitInspectionSnapshot
) -> bool:
	return String(left.unit_instance_id) < String(right.unit_instance_id)


## Transition banners are committed-snapshot events, not phase guesses. A new
## session (or a changed run id) has no previous sample and therefore emits no
## banner. Invalid current-node data is rejected by progress_current_node_id().
func _mark_progress_transitions(
	result: RunPresentationSnapshot,
	previous: RunPresentationSnapshot
) -> void:
	if (
		result == null
		or result.view == null
		or previous == null
		or previous.view == null
		or previous.run_id.is_empty()
		or previous.run_id != result.run_id
	):
		return
	result.progress_act_transitioned = (
		previous.view.act_index != result.view.act_index
	)
	var current_node_id := result.progress_current_node_id()
	result.progress_node_transitioned = (
		not current_node_id.is_empty()
		and current_node_id != previous.progress_current_node_id()
	)


## Kept as a thin alias: the shared rule lives on MapNodePresentation
## (presentation/run/map_node_presentation.gd) so RunMapScreen can call it
## without a presentation/screens/*.gd file naming RunPresentationSession,
## which the PUI_SCREEN_WRITER_DEPENDENCY static gate treats as a canonical
## writer dependency. C-1 起這條規則的權威是 domain 的 MapFrontier——判的是
## 「目前可選（frontier）」而非「拓撲可達」。
static func node_is_reachable(map_state: MapState, node: MapNodeState) -> bool:
	return MapNodePresentationType.is_reachable(map_state, node)


func _command_error(value: CommandError) -> DiagnosticError:
	if value == null:
		return _error(&"RUN_COMMAND_FAILED", &"error.presentation.run_command_failed")
	return _error(
		_source_code(&"RUN_COMMAND_FAILED", value.diagnostic_values),
		&"error.presentation.run_command_failed"
	)


func _transition_error(value: RunTransitionError) -> DiagnosticError:
	if value == null:
		return _error(&"RUN_TRANSITION_FAILED", &"error.presentation.run_transition_failed")
	return _error(
		_source_code(value.code, value.diagnostic_values),
		&"error.presentation.run_transition_failed"
	)


func _source_code(
	fallback: StringName,
	diagnostics: Array[DiagnosticValue]
) -> StringName:
	for diagnostic: DiagnosticValue in diagnostics:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			var source_code := StringName(diagnostic.string_value.value)
			if not source_code.is_empty():
				return source_code
	return fallback


func _combat_error_code(value: CombatCoordinatorError) -> StringName:
	if value == null:
		return &"COMBAT_COORDINATOR_FAILED"
	return value.source_code if not value.source_code.is_empty() else value.code


func _error(code: StringName, message_key: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, message_key)

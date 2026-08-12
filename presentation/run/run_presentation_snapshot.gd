class_name RunPresentationSnapshot
extends RefCounted

var run_id: StringName
var app_phase: StringName
var manifest_digest: String
var available_actions: Array[StringName] = []
var view: RunViewState
var map: MapState
var economy: EconomyState
var roster: RosterState
var pending_reward: PendingRewardState
var node_choice_overlay: NodeChoiceOverlaySnapshot
var node_service_overlay: NodeServiceOverlaySnapshot
## design :201「UI 只由 unacknowledged committed receipt 顯示 result」。
var pending_node_choice_results: Array[NodeChoiceResultSnapshot] = []
var board_validation_report: BoardValidationReport
var combat_inspections: Array[CombatUnitInspectionSnapshot] = []
## 局內 HUD 消費的 pinned-generation 預覽。由 RunPresentationSession 在 snapshot
## 建立邊界透過既有 ViewModel 產生；畫面只持 clone，不保留 RunController 引用。
var unit_stats_previews: Array[UnitStatsPreviewSnapshot] = []
var prepare_unit_inspections: Array[PrepareUnitInspectionSnapshot] = []
## T16 completeness amendment 尚未到位前，此欄只含既有 API 能提供的 active traits；
## 畫面不得據此自行推算 inactive trait 或下一門檻。
var active_trait_previews: Array[TraitBattleSnapshot] = []
## 已啟用 trait 的 clone-only 完整 authored threshold 階梯。此欄不包含
## inactive trait，也不推算 distinct count 或下一門檻。
var active_trait_progress: Array[TraitProgressPresentationSnapshot] = []
var shop_offer_previews: Array[ShopOfferPreviewSnapshot] = []
## Transient presentation events. RunPresentationSession compares only two
## committed snapshot clones; screens never infer a transition from domain phase.
var progress_act_transitioned: bool = false
var progress_node_transitioned: bool = false


## Deterministic presentation order from the map's explicit coordinates. This
## deliberately does not calculate reachability or choose a route through the
## graph: every not-completed, not-current node remains an unreached node.
func progress_nodes() -> Array[MapNodePresentation]:
	var result: Array[MapNodePresentation] = []
	if map == null:
		return result
	for state: MapNodeState in map.nodes:
		if state == null:
			continue
		var projected := MapNodePresentation.from_state(state, false)
		projected.completed = (
			state.completed or map.completed_node_ids.has(state.node_id)
		)
		result.append(projected)
	result.sort_custom(_progress_node_precedes)
	return result


## A current node is publishable only when view and map agree and the node is
## present in the cloned map. Incomplete/mismatched snapshots fail closed.
func progress_current_node_id() -> String:
	if (
		view == null
		or map == null
		or view.current_node_id == null
		or map.current_node_id == null
	):
		return ""
	var view_id := view.current_node_id.value
	if view_id.is_empty() or view_id != map.current_node_id.value:
		return ""
	for state: MapNodeState in map.nodes:
		if state != null and state.node_id == view_id:
			return view_id
	return ""


func deep_clone() -> RunPresentationSnapshot:
	var clone := RunPresentationSnapshot.new()
	clone.run_id = run_id
	clone.app_phase = app_phase
	clone.manifest_digest = manifest_digest
	clone.available_actions.assign(available_actions)
	clone.view = view.deep_clone() if view != null else null
	clone.map = map.deep_clone() if map != null else null
	clone.economy = economy.deep_clone() if economy != null else null
	clone.roster = roster.deep_clone() if roster != null else null
	clone.pending_reward = pending_reward.deep_clone() if pending_reward != null else null
	clone.node_choice_overlay = (
		node_choice_overlay.deep_clone()
		if node_choice_overlay != null
		else null
	)
	clone.node_service_overlay = (
		node_service_overlay.deep_clone()
		if node_service_overlay != null
		else null
	)
	for result: NodeChoiceResultSnapshot in pending_node_choice_results:
		clone.pending_node_choice_results.append(
			result.deep_clone() if result != null else null
		)
	clone.board_validation_report = (
		board_validation_report.deep_clone()
		if board_validation_report != null
		else null
	)
	for inspection: CombatUnitInspectionSnapshot in combat_inspections:
		clone.combat_inspections.append(
			inspection.deep_clone() if inspection != null else null
		)
	for preview: UnitStatsPreviewSnapshot in unit_stats_previews:
		clone.unit_stats_previews.append(
			preview.deep_clone() if preview != null else null
		)
	for inspection: PrepareUnitInspectionSnapshot in prepare_unit_inspections:
		clone.prepare_unit_inspections.append(
			inspection.deep_clone() if inspection != null else null
		)
	for trait_preview: TraitBattleSnapshot in active_trait_previews:
		clone.active_trait_previews.append(
			trait_preview.deep_clone() if trait_preview != null else null
		)
	for progress: TraitProgressPresentationSnapshot in active_trait_progress:
		clone.active_trait_progress.append(
			progress.deep_clone() if progress != null else null
		)
	for shop_preview: ShopOfferPreviewSnapshot in shop_offer_previews:
		clone.shop_offer_previews.append(
			shop_preview.deep_clone() if shop_preview != null else null
		)
	clone.progress_act_transitioned = progress_act_transitioned
	clone.progress_node_transitioned = progress_node_transitioned
	return clone


func _progress_node_precedes(
	left: MapNodePresentation,
	right: MapNodePresentation
) -> bool:
	if left.act_index != right.act_index:
		return left.act_index < right.act_index
	if left.layer_index != right.layer_index:
		return left.layer_index < right.layer_index
	if left.slot_index != right.slot_index:
		return left.slot_index < right.slot_index
	return left.node_id < right.node_id

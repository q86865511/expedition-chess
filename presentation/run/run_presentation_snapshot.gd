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
	return clone

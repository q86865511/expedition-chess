class_name RunPrepareScreenModel
extends RefCounted

const RECOVERY_ACTION_KINDS: Array[int] = [
	RunPresentationIntent.Kind.SELL_UNIT,
	RunPresentationIntent.Kind.EQUIP_ITEM,
	RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT,
	RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW,
]
const RESOLVE_OVERFLOW_FOCUS: StringName = &"run.prepare.resolve_overflow"

var _snapshot: RunPresentationSnapshot
var _report: BoardValidationReport


func _init(
	snapshot: RunPresentationSnapshot,
	report: BoardValidationReport
) -> void:
	_snapshot = snapshot.deep_clone() if snapshot != null else null
	_report = report.deep_clone() if report != null else null


func replace_snapshot(snapshot: RunPresentationSnapshot) -> void:
	_snapshot = snapshot.deep_clone() if snapshot != null else null


func snapshot_clone() -> RunPresentationSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null


func deployment_issue_codes() -> Array[StringName]:
	var result: Array[StringName] = []
	if _report == null:
		return result
	for issue: BoardValidationIssue in _report.issues:
		result.append(issue.code)
	return result


func deployment_issue_message_keys() -> Array[StringName]:
	var result: Array[StringName] = []
	for code: StringName in deployment_issue_codes():
		result.append(
			StringName("error.board.%s" % String(code).to_lower())
		)
	return result


func displayed_capacity() -> int:
	return _report.derived_capacity if _report != null else 0


func start_enabled() -> bool:
	return _report != null and _report.valid


func recovery_action_kinds() -> Array[int]:
	var result: Array[int] = []
	result.assign(RECOVERY_ACTION_KINDS)
	return result


func overflow_ids() -> Array[String]:
	var result: Array[String] = []
	if _snapshot != null and _snapshot.roster != null:
		result.assign(_snapshot.roster.pending_item_overflow)
	return result


func focused_action_id() -> StringName:
	return RESOLVE_OVERFLOW_FOCUS if not overflow_ids().is_empty() else &""

class_name PresentationErrorMapper
extends RefCounted

const DEFAULT_MESSAGE_KEY: StringName = &"error.presentation.failure"
const _MESSAGE_KEYS: Dictionary = {
	&"SAVE_IO_FAILURE": &"error.save.io_failure",
	&"ROUTE_BIND_FAILED": &"error.presentation.route_bind_failed",
	&"SCENE_BIND_FAILED": &"error.presentation.scene_bind_failed",
	&"RENDER_FAILED": &"error.presentation.render_failed",
	# G2 H3：玩家實際撞得到的操作失敗碼各自要有可讀訊息。AppRoot 的
	# `_action_failure` 一律帶泛用 message_key，只靠它畫面上每種失敗都同一句話。
	&"SCREEN_NOT_ACTIVE": &"error.presentation.screen_not_active",
	&"ACTION_NOT_AVAILABLE": &"error.presentation.action_not_available",
	&"APP_ACTION_NOT_AVAILABLE": &"error.presentation.action_not_available",
	&"CAMP_EXPEDITION_SELECTION_REQUIRED":
		&"error.presentation.camp_selection_required",
	&"APP_RETAINED_RUN_EXISTS": &"error.presentation.retained_run_exists",
	&"APP_PREPARED_RUN_STALE": &"error.presentation.prepared_run_stale",
	&"EXIT_REQUEST_ALREADY_PENDING":
		&"error.presentation.exit_already_pending",
	&"RESULTS_ACTION_IN_PROGRESS":
		&"error.presentation.results_action_in_progress",
	&"APP_ROUTE_PREPARE_INVALID": &"error.presentation.route_prepare_invalid",
	&"APP_ROUTE_ACTIVATION_INVALID": &"error.presentation.route_commit_failed",
	&"SETTINGS_DRAFT_INVALID": &"error.settings.draft_invalid",
	&"SETTINGS_INVALID_ENUM": &"error.settings.invalid_enum",
	&"SETTINGS_FIELD_OUT_OF_RANGE": &"error.settings.field_out_of_range",
	&"APP_SETTINGS_RUNTIME_MISSING": &"error.settings.runtime_missing",
	&"APP_SETTINGS_REBUILD_FAILED": &"error.settings.rebuild_failed",
}


## 具名碼是否有專屬訊息鍵；沒有時回 &""（呼叫端才能決定要不要改用
## DiagnosticError 自帶的鍵）。
func message_key_for(source_code: StringName) -> StringName:
	return StringName(_MESSAGE_KEYS.get(source_code, &""))


func map_failure(
	source_code: StringName,
	committed: bool,
	authoritative_state: Dictionary
) -> Dictionary:
	var normalized_source := source_code
	if normalized_source.is_empty():
		normalized_source = &"PRESENTATION_FAILURE_UNKNOWN"
	var message_key: StringName = _MESSAGE_KEYS.get(
		normalized_source,
		DEFAULT_MESSAGE_KEY
	)
	return {
		"committed": committed,
		"presentation_ok": false,
		"fallback_active": committed,
		"retryable": committed,
		"source_code": normalized_source,
		"message_key": message_key,
		"authoritative_state": authoritative_state.duplicate(true),
	}

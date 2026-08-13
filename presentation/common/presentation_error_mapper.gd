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
	&"EXPEDITION_CHALLENGE_PREREQUISITE_UNMET":
		&"error.presentation.expedition_challenge_prerequisite_unmet",
	&"APP_RETAINED_RUN_EXISTS": &"error.presentation.retained_run_exists",
	&"APP_PREPARED_RUN_STALE": &"error.presentation.prepared_run_stale",
	&"EXIT_REQUEST_ALREADY_PENDING":
		&"error.presentation.exit_already_pending",
	&"EQUIP_ITEM_SLOTS_FULL":
		&"error.presentation.equip_item_slots_full",
	&"RESULTS_ACTION_IN_PROGRESS":
		&"error.presentation.results_action_in_progress",
	&"APP_ROUTE_PREPARE_INVALID": &"error.presentation.route_prepare_invalid",
	&"APP_ROUTE_ACTIVATION_INVALID": &"error.presentation.route_commit_failed",
	&"SETTINGS_DRAFT_INVALID": &"error.settings.draft_invalid",
	&"SETTINGS_INVALID_ENUM": &"error.settings.invalid_enum",
	&"SETTINGS_FIELD_OUT_OF_RANGE": &"error.settings.field_out_of_range",
	&"APP_SETTINGS_RUNTIME_MISSING": &"error.settings.runtime_missing",
	&"APP_SETTINGS_REBUILD_FAILED": &"error.settings.rebuild_failed",
	&"SETTINGS_ADAPTER_ACTIVATION_DIAGNOSTIC":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_ACCESSIBILITY_ACTIVATION_FAILED":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_THEME_ACTIVATION_FAILED":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_VIEWPORT_ACTIVATION_FAILED":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_LOCALIZATION_ACTIVATION_FAILED":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_AUDIO_ACTIVATION_FAILED":
		&"error.settings.activation_diagnostic",
	&"SETTINGS_ACCESSIBILITY_BINDING_INVALID":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_SETTINGS_INPUT_INVALID":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_SETTINGS_APPLY_FAILED":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_ROOT_SIZE_INVALID":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_DAMAGE_DENSITY_INVALID":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_RUNTIME_NODE_MISSING":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_LOCALIZATION_MISSING":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_TYPOGRAPHY_APPLY_FAILED":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_FONT_UNAVAILABLE":
		&"error.settings.activation_diagnostic",
	&"ACCESSIBILITY_REQUIRED_GLYPH_MISSING":
		&"error.settings.activation_diagnostic",
	&"PRODUCTION_VIEWPORT_TREE_INVALID":
		&"error.settings.activation_diagnostic",
	&"RUN_MAP_NODE_SELECTION_UNAVAILABLE":
		&"error.presentation.run_map_node_selection_unavailable",
	&"RUN_PREPARE_START_NOT_READY":
		&"error.presentation.prepare_start_not_ready",
	&"PREPARE_BOARD_FULL": &"error.presentation.prepare_board_full",
	&"PREPARE_BENCH_FULL": &"error.presentation.prepare_bench_full",
	&"PREPARE_SELECTION_REQUIRED":
		&"error.presentation.prepare_selection_required",
	&"RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY":
		&"error.presentation.resolve_overflow_item_not_in_tray",
	&"RUN_COMMAND_FAILED": &"error.presentation.run_command_failed",
	&"RUN_TRANSITION_FAILED": &"error.presentation.run_transition_failed",
	&"SHOP_GOLD_INSUFFICIENT": &"error.shop.gold_insufficient",
	&"SHOP_LEVEL_MAX": &"error.shop.level_max",
	&"SHOP_OFFER_STALE": &"error.shop.offer_stale",
	&"SHOP_ROSTER_FULL": &"error.shop.roster_full",
	&"SHOP_UNIT_MISSING": &"error.shop.unit_missing",
	&"SHOP_UNIT_RULE_MISSING": &"error.shop.unit_rule_missing",
	&"SHOP_UNIT_POOL_INVALID": &"error.shop.unit_pool_invalid",
	&"SHOP_RESERVATION_INVALID": &"error.shop.reservation_invalid",
	&"SHOP_CATALOG_GENERATION_MISMATCH": &"error.shop.generation_mismatch",
	&"SHOP_INPUT_INVALID": &"error.shop.input_invalid",
	&"SHOP_RNG_FAILED": &"error.shop.internal_failure",
	&"SHOP_KEY_FAILED": &"error.shop.internal_failure",
	&"SHOP_DIGEST_FAILED": &"error.shop.internal_failure",
	&"SHOP_CONFIG_INVALID": &"error.shop.internal_failure",
	&"SHOP_SERIAL_EXHAUSTED": &"error.shop.internal_failure",
	&"SHOP_MERGE_FAILED": &"error.shop.internal_failure",
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

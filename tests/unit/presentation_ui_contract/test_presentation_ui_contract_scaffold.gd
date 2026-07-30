extends GutTest

## G2 presentation-ui T00 contract-red.
##
## This test intentionally never refers to a not-yet-created class_name in a
## static type position.  T00 may therefore fail only through assertions about
## the production contract map below, rather than through a parser/import abort.

var _contracts: Array[Dictionary] = [
	{
		"path": "res://presentation/common/diagnostic_error.gd",
		"class_name": "DiagnosticError",
		"tokens": PackedStringArray([
			"class_name DiagnosticError",
			"extends RefCounted",
			"var source_code: StringName",
			"var message_key: StringName",
		]),
	},
	{
		"path": "res://app/state/app_action_result.gd",
		"class_name": "AppActionResult",
		"tokens": PackedStringArray([
			"class_name AppActionResult",
			"extends RefCounted",
			"var ok: bool",
			"var committed: bool",
			"var presentation_ok: bool",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://app/state/start_expedition_request.gd",
		"class_name": "StartExpeditionRequest",
		"tokens": PackedStringArray([
			"class_name StartExpeditionRequest",
			"var commander_id: StringName",
			"var challenge_level: int",
		]),
	},
	{
		"path": "res://app/state/main_menu_snapshot.gd",
		"class_name": "MainMenuSnapshot",
		"tokens": PackedStringArray([
			"class_name MainMenuSnapshot",
			"var can_continue: bool",
			"var can_start: bool",
			"var has_recovery: bool",
			"var active_run_id_display: String",
			"var warning_key: StringName",
		]),
	},
	{
		"path": "res://app/state/retained_run_recovery_token.gd",
		"class_name": "RetainedRunRecoveryToken",
		"tokens": PackedStringArray([
			"class_name RetainedRunRecoveryToken",
			"_repository_identity",
			"_operation_epoch",
			"_committed_file_digest",
			"_expected_run_id",
			"_use_nonce",
		]),
	},
	{
		"path": "res://app/state/prepared_run_capability.gd",
		"class_name": "PreparedRunCapability",
		"tokens": PackedStringArray([
			"class_name PreparedRunCapability",
			"_repository_identity",
			"_operation_epoch",
			"_committed_file_digest",
			"_run_id",
			"_manifest_digest",
			"_use_nonce",
		]),
	},
	{
		"path": "res://app/state/terminal_settlement_presentation_capability.gd",
		"class_name": "TerminalSettlementPresentationCapability",
		"tokens": PackedStringArray([
			"class_name TerminalSettlementPresentationCapability",
			"_repository_identity",
			"_operation_epoch",
			"_committed_file_digest",
			"_run_id",
			"_receipt_id",
			"_use_nonce",
		]),
	},
	{
		"path": "res://app/state/results_presentation_snapshot.gd",
		"class_name": "ResultsPresentationSnapshot",
		"tokens": PackedStringArray([
			"class_name ResultsPresentationSnapshot",
			"var receipt_id: StringName",
			"var committed_file_digest: String",
			"var can_exit_results: bool",
			"func deep_clone() -> ResultsPresentationSnapshot",
		]),
	},
	{
		"path": "res://app/state/terminal_presentation_handoff_port.gd",
		"class_name": "TerminalPresentationHandoffPort",
		"tokens": PackedStringArray([
			"class_name TerminalPresentationHandoffPort",
			"func commit_handoff(",
			"capability: TerminalSettlementPresentationCapability",
			"snapshot: ResultsPresentationSnapshot",
			") -> AppActionResult",
		]),
	},
	{
		"path": "res://services/settings/settings_snapshot.gd",
		"class_name": "SettingsSnapshot",
		"tokens": PackedStringArray([
			"class_name SettingsSnapshot",
			"var schema_version: int = 1",
			"var locale: StringName = &\"zh_TW\"",
			"var ui_scale_percent: int = 100",
			"var color_vision_mode: StringName = &\"default\"",
			"var reduced_motion: bool = false",
			"var reduced_flash: bool = false",
			"var reduced_particles: bool = false",
			"var damage_number_density: StringName = &\"full\"",
			"var master_volume_bps: int = 10000",
			"var master_muted: bool = false",
			"var music_volume_bps: int = 10000",
			"var music_muted: bool = false",
			"var sfx_volume_bps: int = 10000",
			"var sfx_muted: bool = false",
			"var ui_volume_bps: int = 10000",
			"var ui_muted: bool = false",
			"func deep_clone() -> SettingsSnapshot",
		]),
	},
	{
		"path": "res://services/settings/settings_application_result.gd",
		"class_name": "SettingsApplicationResult",
		"tokens": PackedStringArray([
			"class_name SettingsApplicationResult",
			"var ok: bool",
			"var committed: bool",
			"var presentation_ok: bool",
			"var snapshot: SettingsSnapshot",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://services/settings/settings_application_port.gd",
		"class_name": "SettingsApplicationPort",
		"tokens": PackedStringArray([
			"class_name SettingsApplicationPort",
			"func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult",
		]),
	},
	{
		"path": "res://presentation/run/run_presentation_session.gd",
		"class_name": "RunPresentationSession",
		"tokens": PackedStringArray([
			"class_name RunPresentationSession",
			"signal snapshot_committed(snapshot: RunPresentationSnapshot)",
			"signal presentation_error(error: DiagnosticError)",
			"func snapshot() -> RunPresentationSnapshot",
			"func dispatch(intent: RunPresentationIntent) -> RunPresentationResult",
			"func try_playback() -> BattlePlaybackStateResult",
			"func drain_playback_window(",
			"func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult",
		]),
	},
	{
		"path": "res://presentation/run/run_presentation_session_result.gd",
		"class_name": "RunPresentationSessionResult",
		"tokens": PackedStringArray([
			"class_name RunPresentationSessionResult",
			"var ok: bool",
			"var session: RunPresentationSession",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://presentation/run/run_presentation_snapshot.gd",
		"class_name": "RunPresentationSnapshot",
		"tokens": PackedStringArray([
			"class_name RunPresentationSnapshot",
			"var run_id: StringName",
			"var app_phase: StringName",
			"var manifest_digest: String",
			"var available_actions: Array[StringName]",
			"func deep_clone() -> RunPresentationSnapshot",
		]),
	},
	{
		"path": "res://presentation/run/run_presentation_intent.gd",
		"class_name": "RunPresentationIntent",
		"tokens": PackedStringArray([
			"class_name RunPresentationIntent",
			"enum Kind",
			"GENERATE_MAP",
			"ENTER_NODE",
			"REFRESH_SHOP",
			"BUY_UNIT",
			"BUY_XP",
			"SELL_UNIT",
			"COMMIT_BOARD_LAYOUT",
			"FORGE_EQUIPMENT",
			"EQUIP_ITEM",
			"DISMANTLE_EQUIPMENT",
			"START_OR_RESUME_COMBAT",
			"SETTLE_BATTLE",
			"RESOLVE_NON_COMBAT",
			"CHOOSE_STANDARD_REWARD",
			"RESOLVE_UNIT_REWARD",
			"RESOLVE_ITEM_REWARD",
			"RESOLVE_RELIC_REWARD",
			"ADVANCE_REWARD",
			"RESOLVE_UNIT_OVERFLOW",
			"RESOLVE_ITEM_OVERFLOW",
			"REPLACE_RELIC",
			"ABANDON_RELIC",
			"ABANDON_BOSS_RETRY",
			"SETTLE_TERMINAL_RUN",
			"var kind: Kind",
		]),
	},
	{
		"path": "res://presentation/run/run_presentation_result.gd",
		"class_name": "RunPresentationResult",
		"tokens": PackedStringArray([
			"class_name RunPresentationResult",
			"var ok: bool",
			"var committed: bool",
			"var presentation_ok: bool",
			"var snapshot: RunPresentationSnapshot",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://presentation/run/battle_transcript_identity.gd",
		"class_name": "BattleTranscriptIdentity",
		"tokens": PackedStringArray([
			"class_name BattleTranscriptIdentity",
			"var run_id: StringName",
			"var battle_setup_hash: String",
			"var committed_result_digest: String",
			"var resolution_identity: StringName",
			"func deep_clone() -> BattleTranscriptIdentity",
		]),
	},
	{
		"path": "res://presentation/run/battle_transcript_buffer.gd",
		"class_name": "BattleTranscriptBuffer",
		"tokens": PackedStringArray([
			"class_name BattleTranscriptBuffer",
			"const MAX_PUBLIC_WINDOW: int = 4096",
			"const MAX_BYTE_BUDGET: int = 64 * 1024 * 1024",
			"_identity",
			"_events",
			"func drain_window(",
		]),
	},
	{
		"path": "res://presentation/run/battle_playback_state_result.gd",
		"class_name": "BattlePlaybackStateResult",
		"tokens": PackedStringArray([
			"class_name BattlePlaybackStateResult",
			"var ok: bool",
			"var state: BattlePlaybackState",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://presentation/run/battle_event_window_result.gd",
		"class_name": "BattleEventWindowResult",
		"tokens": PackedStringArray([
			"class_name BattleEventWindowResult",
			"var ok: bool",
			"var window: BattleEventWindow",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://presentation/run/combat_unit_inspection_result.gd",
		"class_name": "CombatUnitInspectionResult",
		"tokens": PackedStringArray([
			"class_name CombatUnitInspectionResult",
			"var ok: bool",
			"var snapshot: CombatUnitInspectionSnapshot",
			"var error: DiagnosticError",
		]),
	},
	{
		"path": "res://presentation/screens/live_screen_lease.gd",
		"class_name": "LiveScreenLease",
		"tokens": PackedStringArray([
			"class_name LiveScreenLease",
			"var lease_id: StringName",
			"var parent_state: int",
			"var route_generation: int",
		]),
	},
	{
		"path": "res://presentation/screens/live_screen_intent_port.gd",
		"class_name": "LiveScreenIntentPort",
		"tokens": PackedStringArray([
			"class_name LiveScreenIntentPort",
			"func dispatch(intent: RunPresentationIntent) -> RunPresentationResult",
			"func begin_confirmation(",
			"func confirm(",
			"func cancel(",
		]),
	},
	{
		"path": "res://presentation/screens/live_screen_navigation_port.gd",
		"class_name": "LiveScreenNavigationPort",
		"tokens": PackedStringArray([
			"class_name LiveScreenNavigationPort",
			"func navigate(",
		]),
	},
	{
		"path": "res://presentation/screens/screen_activation_capability.gd",
		"class_name": "ScreenActivationCapability",
		"tokens": PackedStringArray([
			"class_name ScreenActivationCapability",
			"_lease_id",
			"_parent_state",
			"_route_generation",
			"_use_nonce",
		]),
	},
	{
		"path": "res://presentation/screens/results_render_retry_capability.gd",
		"class_name": "ResultsRenderRetryCapability",
		"tokens": PackedStringArray([
			"class_name ResultsRenderRetryCapability",
			"_repository_identity",
			"_receipt_id",
			"_committed_file_digest",
			"_fallback_route_generation",
			"_retry_attempt_generation",
			"_use_nonce",
		]),
	},
	{
		"path": "res://presentation/screens/results_fallback_navigation_port.gd",
		"class_name": "ResultsFallbackNavigationPort",
		"tokens": PackedStringArray([
			"class_name ResultsFallbackNavigationPort",
			"func retry_installed() -> AppActionResult",
			"func return_to_camp() -> AppActionResult",
			"func return_to_menu() -> AppActionResult",
		]),
	},
]

var _existing_contract_tokens: Array[Dictionary] = [
	{
		"path": "res://app/state/app_event.gd",
		"tokens": PackedStringArray([
			"CONTINUE_RUN",
			"RETURN_RESULTS_TO_CAMP",
			"RETURN_RESULTS_TO_MENU",
		]),
	},
]

var _stable_wire_tokens: Array[Dictionary] = [
	{
		"path": "res://services/settings/settings_snapshot.gd",
		"tokens": PackedStringArray([
			"&\"zh_TW\"",
			"&\"en\"",
			"&\"default\"",
			"&\"protanopia\"",
			"&\"deuteranopia\"",
			"&\"tritanopia\"",
			"&\"off\"",
			"&\"reduced\"",
			"&\"full\"",
		]),
	},
]

func test_t00_contract_files_exist_and_are_loadable() -> void:
	for contract: Dictionary in _contracts:
		var path: String = str(contract["path"])
		var expected_class_name: String = str(contract["class_name"])
		var exists := FileAccess.file_exists(path)
		assert_true(
			exists,
			"T00 requires %s at %s" % [expected_class_name, path]
		)
		if not exists:
			continue
		var script_resource := load(path)
		assert_not_null(
			script_resource,
			"%s must be a loadable, compile-safe GDScript contract" % path
		)

func test_t00_contract_sources_expose_required_typed_shape() -> void:
	assert_gt(_contracts.size(), 0, "T00 production ownership map must not be empty")
	for contract: Dictionary in _contracts:
		var path: String = str(contract["path"])
		if not FileAccess.file_exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		assert_false(source.is_empty(), "%s must not be empty" % path)
		for token: String in contract["tokens"]:
			assert_true(
				source.contains(token),
				"%s must declare token `%s`" % [path, token]
			)

func test_t00_existing_app_event_declares_new_stable_kinds() -> void:
	for contract: Dictionary in _existing_contract_tokens:
		var path: String = str(contract["path"])
		assert_true(FileAccess.file_exists(path), "existing contract missing: %s" % path)
		if not FileAccess.file_exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		for token: String in contract["tokens"]:
			assert_true(
				source.contains(token),
				"%s must declare stable event kind `%s`" % [path, token]
			)

func test_t00_settings_wire_values_are_stable_strings() -> void:
	for contract: Dictionary in _stable_wire_tokens:
		var path: String = str(contract["path"])
		if not FileAccess.file_exists(path):
			assert_true(false, "settings wire contract missing: %s" % path)
			continue
		var source := FileAccess.get_file_as_string(path)
		for token: String in contract["tokens"]:
			assert_true(
				source.contains(token),
				"%s must preserve stable string wire token `%s`" % [path, token]
			)

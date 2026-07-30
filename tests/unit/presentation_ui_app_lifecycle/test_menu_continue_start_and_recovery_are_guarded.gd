extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")
const ROOT_PATH := "res://app/app_root.gd"
const STATE_MACHINE_PATH := "res://app/state/app_state_machine.gd"
const PREPARATION_PATH := "res://app/state/run_preparation_service.gd"
const CAPABILITY_PATH := "res://app/state/prepared_run_capability.gd"
const RECOVERY_PATH := "res://app/state/retained_run_recovery_token.gd"
const REPOSITORY_PATH := "res://services/save/save_repository.gd"


func test_menu_continue_start_and_recovery_are_guarded() -> void:
	var root_source := Support.source(ROOT_PATH)
	var machine_source := Support.source(STATE_MACHINE_PATH)
	var preparation_source := Support.source(PREPARATION_PATH)
	var capability_source := Support.source(CAPABILITY_PATH)
	var recovery_source := Support.source(RECOVERY_PATH)
	var repository_source := Support.source(REPOSITORY_PATH)

	for method_name: String in [
		"open_main_menu",
		"continue_active_run",
		"open_camp",
		"return_to_menu",
		"discard_retained_run",
		"current_menu_snapshot",
	]:
		assert_true(
			root_source.contains("func %s(" % method_name),
			"ApplicationRoot must expose typed lifecycle action: %s" % method_name
		)
	assert_true(
		root_source.contains("-> AppActionResult"),
		"menu lifecycle actions must return AppActionResult, not StringName/null"
	)
	assert_true(
		machine_source.contains("AppEvent.Kind.CONTINUE_RUN"),
		"Continue must be an explicit MENU→RUN event"
	)
	assert_false(
		machine_source.contains(
			"AppEvent.Kind.START_RUN, AppEvent.Kind.ACTIVE_RUN_LOADED"
		),
		"ACTIVE_RUN_LOADED must no longer auto-route boot into RUN"
	)

	assert_false(preparation_source.is_empty(), "RunPreparationService is required")
	assert_true(
		preparation_source.contains("func prepare(")
			and preparation_source.contains("func consume(")
			and preparation_source.contains("func revoke("),
		"prepared Continue must have explicit prepare/consume/revoke lifecycle"
	)
	for field_name: String in [
		"_repository_identity",
		"_operation_epoch",
		"_committed_file_digest",
		"_run_id",
		"_manifest_digest",
	]:
		assert_true(
			capability_source.contains(field_name),
			"PreparedRunCapability must bind %s" % field_name
		)
	for repository_marker: String in [
		"_repository_identity",
		"_operation_epoch",
		"_claim_operation_if_epoch",
		"_load_while_owned",
	]:
		assert_true(
			repository_source.contains(repository_marker),
			"SaveRepository must own freshness marker %s" % repository_marker
		)
	assert_true(
		repository_source.contains("_operation_epoch += 1"),
		"every public repository operation must advance the epoch"
	)

	assert_true(
		recovery_source.contains("_repository_identity")
			and recovery_source.contains("_operation_epoch")
			and recovery_source.contains("_committed_file_digest"),
		"decoded and opaque recovery tokens must bind identity/epoch/full-file digest"
	)
	assert_false(
		recovery_source.contains("_run_bytes_digest"),
		"opaque recovery must not invent a second run-bytes digest"
	)
	assert_true(
		root_source.contains("RunStatus.NONE")
			and root_source.contains("RunStatus.LOADED")
			and root_source.contains("INCOMPATIBLE_PRESERVED"),
		"menu snapshot/action guards must distinguish all retained-run states"
	)

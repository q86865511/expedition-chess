extends GutTest

const SESSION_PATH := "res://presentation/run/run_presentation_session.gd"
const FACTORY_PATH := "res://domain/run/controller/run_command_factory.gd"


func test_run_presentation_session_dispatch_is_not_the_t00_placeholder() -> void:
	var session := RunPresentationSession.new()
	var before := session.snapshot()
	var result := session.dispatch(
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)

	assert_not_null(result, "dispatch must always return a typed result")
	if result == null:
		return
	assert_not_null(result.error, "an invalid/default session must fail with a source diagnostic")
	if result.error == null:
		return
	assert_ne(
		result.error.source_code,
		RunPresentationSession.NOT_IMPLEMENTED,
		"T04 must replace the T00 placeholder with a lifecycle/dependency diagnostic"
	)
	assert_false(result.committed, "pre-commit failure must remain uncommitted")
	assert_false(result.presentation_ok, "failed presentation must be explicit")
	assert_eq(
		session.snapshot().run_id,
		before.run_id,
		"pre-commit failure must preserve the prior presentation snapshot"
	)


func test_public_snapshots_results_and_signal_contract_are_clone_only() -> void:
	var source := RunPresentationSnapshot.new()
	source.run_id = &"run-clone"
	source.app_phase = &"PREPARE"
	source.manifest_digest = "manifest-a"
	source.available_actions.assign([&"BUY_UNIT", &"SELL_UNIT"])

	var result_a := RunPresentationResult.new(true, true, true, source)
	var result_b := RunPresentationResult.new(true, true, true, source)
	source.available_actions.append(&"MUTATED_SOURCE")
	result_a.snapshot.available_actions.append(&"MUTATED_CONSUMER_A")

	assert_eq(
		result_b.snapshot.available_actions,
		[&"BUY_UNIT", &"SELL_UNIT"],
		"two result consumers must not alias source or each other"
	)
	assert_ne(
		result_a.snapshot,
		result_b.snapshot,
		"each result boundary must own a distinct snapshot object"
	)

	var session_source := _source(SESSION_PATH)
	assert_true(
		session_source.contains("snapshot_committed.emit(")
			and session_source.contains(".deep_clone()"),
		"snapshot_committed must emit a deep clone rather than the session-owned snapshot"
	)


func test_no_playback_is_a_named_typed_result_not_null() -> void:
	var result := RunPresentationSession.new().try_playback()

	assert_not_null(result, "try_playback must always return BattlePlaybackStateResult")
	if result == null:
		return
	assert_false(result.ok, "a non-COMBAT/default session has no playback")
	assert_null(result.state, "no-playback must not leak a stale playback controller/state")
	assert_not_null(result.error, "no-playback must carry a named diagnostic")
	if result.error == null:
		return
	assert_eq(
		result.error.source_code,
		&"PLAYBACK_NOT_AVAILABLE",
		"legal no-playback state must not use NOT_IMPLEMENTED or silent null"
	)


func test_command_error_prefers_diagnostic_source_code_without_wrapper_prefix() -> void:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", "EQUIP_ITEM_SLOTS_FULL"),
	]
	var command_error := CommandError.new(
		CommandError.APPLY_FAILED,
		RunState.RunPhase.PREPARE,
		&"inventory",
		null,
		diagnostics
	)
	var mapped := RunPresentationSession.new().call(
		&"_command_error",
		command_error
	) as DiagnosticError

	assert_not_null(mapped)
	if mapped == null:
		return
	assert_eq(
		mapped.source_code,
		&"EQUIP_ITEM_SLOTS_FULL",
		"presentation must consume diagnostic_values[source_code] directly"
	)


func test_session_routes_every_writer_through_factory_and_controller() -> void:
	var session_source := _source(SESSION_PATH)
	var factory_source := _source(FACTORY_PATH)

	assert_true(
		session_source.contains("RunCommandFactory"),
		"production facade must consume RunCommandFactory"
	)
	assert_true(
		session_source.contains("RunController"),
		"production facade must dispatch through RunController"
	)
	assert_false(
		session_source.contains("RunState.new("),
		"presentation facade must never construct canonical RunState"
	)
	assert_false(
		session_source.contains("SaveRepository"),
		"presentation facade must not bypass RunController into the repository"
	)
	assert_true(
		factory_source.contains("func buy_offer_command("),
		"RunCommandFactory must be the BUY_UNIT construction point"
	)
	assert_true(
		factory_source.contains("func forge_equipment_command("),
		"RunCommandFactory must be the forge construction point"
	)


func test_result_shape_distinguishes_precommit_and_postcommit_failure() -> void:
	var result_source := _source("res://presentation/run/run_presentation_result.gd")

	assert_true(
		result_source.contains("static func precommit_failure("),
		"typed result must expose an unambiguous pre-commit failure constructor"
	)
	assert_true(
		result_source.contains("static func postcommit_failure("),
		"typed result must expose committed presentation-failure construction"
	)
	assert_true(
		result_source.contains("committed")
			and result_source.contains("presentation_ok")
			and result_source.contains("source"),
		"result must preserve commit boundary and source diagnostics"
	)


func _source(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "required source missing: %s" % path)
	return FileAccess.get_file_as_string(path)

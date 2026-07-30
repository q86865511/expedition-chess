extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_terminal/"
	+ "r15_terminal_test_support.gd"
)


func test_fallback_capability_issue_fault_still_seals_results_and_revokes_run() -> void:
	_assert_postcommit_fallback_authority_is_no_fail(&"issue")


func test_fallback_capability_consume_fault_still_seals_results_and_revokes_run() -> void:
	_assert_postcommit_fallback_authority_is_no_fail(&"consume")


func _assert_postcommit_fallback_authority_is_no_fail(
	fault_kind: StringName
) -> void:
	var repository := Support.repository_with_fallback_authority_fault(
		fault_kind
	)
	add_child_autofree(repository)
	var root := ApplicationRoot.new()
	var presentation_host := Control.new()
	presentation_host.name = "PresentationHost"
	root.add_child(presentation_host)
	add_child_autofree(root)
	root._app_state_machine._state = AppStateMachine.State.RUN
	var lease := root._live_lease_registry.activate(
		AppStateMachine.State.RUN,
		93
	)
	assert_not_null(lease)
	var session := Support.RecordingRunSession.new()
	var intent_port := LiveScreenIntentPort.new(
		lease,
		root._live_lease_registry,
		session
	)
	var intent := Support.enter_node_intent()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"INJECTED_PRIMARY_INSTALL_FAULT",
					&"error.presentation.results_fallback"
				)
			),
		null,
		Callable(root, "_commit_fail_closed_terminal_handoff")
	)
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		application_port,
		Callable(root, "_revoke_run_writers"),
		Callable(root, "_invalidate_run_session"),
		Callable(root, "_release_active_run")
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_true(settled.committed)
	assert_eq(
		root.app_state(),
		AppStateMachine.State.RESULTS,
		"postcommit fallback authority faults cannot leave AppRoot in RUN"
	)
	assert_null(root._live_lease_registry.active_lease())
	assert_false(root._live_lease_registry.is_active(lease))
	var stale := intent_port.dispatch(intent)
	assert_false(stale.ok)
	assert_eq(
		Support.source_code(stale),
		LiveScreenIntentPort.SCREEN_NOT_ACTIVE
	)
	assert_eq(session.dispatch_count, 0)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(loaded.profile.settlement_receipts.size(), 1)

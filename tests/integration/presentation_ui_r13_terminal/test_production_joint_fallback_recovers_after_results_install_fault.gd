extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


func test_real_application_install_and_concrete_adapter_atomically_install_fallback() -> void:
	var repository := Support.repository_with_terminal_root()
	add_child_autofree(repository)
	var root := ApplicationRoot.new()
	var presentation_host := Control.new()
	presentation_host.name = "PresentationHost"
	root.add_child(presentation_host)
	add_child_autofree(root)
	root._app_state_machine._state = AppStateMachine.State.RUN
	var router := Support.FaultInjectingSceneRouter.new()
	add_child_autofree(router)
	var leases := LiveScreenLeaseRegistry.new()
	var old_run_lease := leases.activate(AppStateMachine.State.RUN, 44)
	var adapter := SceneRouterTerminalPresentationHandoffAdapter.new(
		router,
		leases,
		SaveRepositoryResultsRenderRetryAuthority.new(repository),
		Callable(root, "_terminal_presentation_snapshot_clone"),
		Callable(root, "return_results_to_camp"),
		Callable(root, "return_results_to_menu")
	)
	var application_port := ApplicationTerminalHandoffPort.new(
		Callable(root, "_commit_terminal_handoff"),
		adapter
	)
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		application_port,
		func() -> void: root._revoke_run_writers(),
		func() -> void: root._invalidate_run_session(),
		func() -> void: root._release_active_run()
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_false(settled.ok, "RESULTS bind fault remains an observable presentation failure")
	assert_true(settled.committed)
	assert_eq(root._app_state_machine.state(), AppStateMachine.State.RESULTS)
	assert_not_null(root._terminal_presentation_snapshot)
	assert_eq(
		router.routes,
		[&"RESULTS", &"RESULTS_FALLBACK"],
		"adapter must atomically replace the dead RUN screen with production fallback"
	)
	assert_false(leases.is_active(old_run_lease), "old RUN callback lease is revoked")
	var fallback_lease := adapter.active_results_lease()
	assert_not_null(fallback_lease)
	if fallback_lease != null:
		assert_eq(fallback_lease.parent_state, AppStateMachine.State.RESULTS)
		assert_true(leases.is_active(fallback_lease))

	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_eq(
		loaded.profile.settlement_receipts.size(),
		1,
		"terminal reward/save remains exactly once after presentation failure"
	)
	var replay := coordinator.settle(Support.reward_table())
	assert_false(replay.ok)
	var after_replay := repository.load()
	assert_eq(after_replay.profile.settlement_receipts.size(), 1)
	assert_eq(
		router.routes,
		[&"RESULTS", &"RESULTS_FALLBACK"],
		"replay cannot rotate the unique fallback lease"
	)

	var navigation: Variant = (
		adapter.call("fallback_navigation_port")
		if adapter.has_method("fallback_navigation_port")
		else null
	)
	assert_not_null(
		navigation,
		"concrete adapter must expose the results-only fallback navigation port"
	)
	if navigation == null:
		return
	var retried: Variant = navigation.call("retry_installed")
	assert_true(retried is AppActionResult)
	assert_true(
		retried.ok,
		"production composition must execute the installed retry atomically"
	)
	assert_ne(
		retried.error.source_code if not retried.ok else &"",
		ResultsFallbackNavigationPort.NOT_IMPLEMENTED
	)

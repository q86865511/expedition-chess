extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_terminal/"
	+ "r15_terminal_test_support.gd"
)


func test_results_and_fallback_double_fault_fail_closed_and_allow_fresh_host_recovery() -> void:
	var repository := Support.repository_with_terminal_root()
	add_child_autofree(repository)
	var root := ApplicationRoot.new()
	var old_host := Control.new()
	old_host.name = "PresentationHost"
	root.add_child(old_host)
	add_child_autofree(root)
	root._app_state_machine._state = AppStateMachine.State.RUN

	var router := Support.DoubleFaultSceneRouter.new()
	add_child_autofree(router)
	router.bind_presentation_host(old_host)
	assert_eq(router.bind_production_catalog(ProductionSceneCatalog.new()), &"")
	var old_screen := ProductionSceneCatalog.new().instantiate(&"RUN_MAP")
	assert_not_null(old_screen)
	if old_screen != null:
		old_host.add_child(old_screen)

	var leases := LiveScreenLeaseRegistry.new()
	var old_lease := leases.activate(AppStateMachine.State.RUN, 44)
	assert_not_null(old_lease)
	var session := Support.RecordingRunSession.new()
	var intent_port := LiveScreenIntentPort.new(old_lease, leases, session)
	var navigation_calls: int = 0
	var navigation_port := LiveScreenNavigationPort.new(
		old_lease,
		leases,
		func(_target: StringName) -> AppActionResult:
			navigation_calls += 1
			return AppActionResult.success(false)
	)
	var intent := Support.enter_node_intent()
	var issued := intent_port.begin_confirmation(intent)
	assert_true(issued.ok)
	assert_not_null(issued.draft)
	if not issued.ok or issued.draft == null:
		return

	# Preserve the exact callbacks a retired production screen could still hold.
	var gameplay_callback := Callable(intent_port, "dispatch").bind(intent)
	var navigation_callback := Callable(
		navigation_port,
		"navigate"
	).bind(&"RUN_PREPARE")
	var confirmation_begin_callback := Callable(
		intent_port,
		"begin_confirmation"
	).bind(intent)
	var confirmation_confirm_callback := Callable(
		intent_port,
		"confirm"
	).bind(issued.draft)
	var confirmation_cancel_callback := Callable(
		intent_port,
		"cancel"
	).bind(issued.draft)

	var adapter := SceneRouterTerminalPresentationHandoffAdapter.new(
		router,
		leases,
		SaveRepositoryResultsRenderRetryAuthority.new(repository),
		Callable(root, "_terminal_presentation_snapshot_clone"),
		Callable(root, "return_results_to_camp"),
		Callable(root, "return_results_to_menu"),
		Callable(root, "_begin_results_action"),
		Callable(root, "_end_results_action"),
		Callable(root, "_terminal_staged_context")
	)
	var application_port := ApplicationTerminalHandoffPort.new(
		Callable(root, "_commit_terminal_handoff"),
		adapter,
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

	assert_false(settled.ok)
	assert_true(settled.committed)
	assert_eq(
		Support.source_code(settled),
		Support.DoubleFaultSceneRouter.FALLBACK_FAULT
	)
	assert_eq(root.app_state(), AppStateMachine.State.RESULTS)
	assert_eq(router.routes, [&"RESULTS", &"RESULTS_FALLBACK"])
	assert_null(
		adapter.active_results_lease(),
		"no RESULTS lease may be published when both hosts fail"
	)
	assert_null(leases.active_lease())
	assert_false(
		leases.is_active(old_lease),
		"the RUN lease is revoked before either postcommit route attempt"
	)

	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(
		loaded.profile.settlement_receipts.size(),
		1,
		"terminal receipt remains exactly once after presentation double fault"
	)
	var replay := coordinator.settle(Support.reward_table())
	assert_false(replay.ok)
	var after_replay := repository.load()
	assert_eq(after_replay.profile.settlement_receipts.size(), 1)

	var stale_results: Array = [
		gameplay_callback.call(),
		navigation_callback.call(),
		confirmation_begin_callback.call(),
		confirmation_confirm_callback.call(),
		confirmation_cancel_callback.call(),
	]
	for stale: Variant in stale_results:
		assert_eq(
			Support.source_code(stale),
			LiveScreenIntentPort.SCREEN_NOT_ACTIVE,
			"every preserved RUN callback must fail against the revoked lease"
		)
	assert_eq(session.dispatch_count, 0)
	assert_eq(navigation_calls, 0)

	_assert_fresh_host_recovery(root, repository)


func _assert_fresh_host_recovery(
	root: ApplicationRoot,
	repository: SaveRepository
) -> void:
	var snapshot := root.call(
		&"_terminal_presentation_snapshot_clone"
	) as ResultsPresentationSnapshot
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var fresh_host := Control.new()
	fresh_host.name = "FreshPresentationHost"
	add_child_autofree(fresh_host)
	var fresh_router := Support.FreshHostRecoveryRouter.new()
	add_child_autofree(fresh_router)
	fresh_router.bind_presentation_host(fresh_host)
	assert_eq(
		fresh_router.bind_production_catalog(ProductionSceneCatalog.new()),
		&""
	)
	var fresh_leases := LiveScreenLeaseRegistry.new()
	var fresh_adapter := SceneRouterTerminalPresentationHandoffAdapter.new(
		fresh_router,
		fresh_leases,
		SaveRepositoryResultsRenderRetryAuthority.new(repository),
		Callable(root, "_terminal_presentation_snapshot_clone"),
		Callable(root, "return_results_to_camp"),
		Callable(root, "return_results_to_menu"),
		Callable(root, "_begin_results_action"),
		Callable(root, "_end_results_action"),
		Callable(Support, "results_context")
	)
	var generation := fresh_adapter.prepare_results_route_generation()
	var fresh_capability := InstalledResultsPresentationCapability.new(
		snapshot.presentation_digest(),
		AppStateMachine.State.RESULTS,
		generation
	)
	var recovered := fresh_adapter.commit_installed_handoff(
		fresh_capability,
		snapshot
	)
	assert_false(
		recovered.ok,
		"primary RESULTS remains observable as failed while fallback recovers"
	)
	assert_true(recovered.committed)
	assert_eq(
		fresh_router.routes,
		[&"RESULTS", &"RESULTS_FALLBACK"]
	)
	assert_eq(fresh_host.get_child_count(), 1)
	if fresh_host.get_child_count() == 1:
		var screen := fresh_host.get_child(0) as ProductionScreen
		assert_not_null(screen)
		if screen != null:
			assert_eq(screen.route_kind, &"RESULTS_FALLBACK")
	var fresh_lease := fresh_adapter.active_results_lease()
	assert_not_null(fresh_lease)
	if fresh_lease != null:
		assert_true(fresh_leases.is_active(fresh_lease))
		assert_eq(fresh_lease.parent_state, AppStateMachine.State.RESULTS)
	var retry := fresh_adapter.fallback_navigation_port().retry_installed()
	assert_true(
		retry is AppActionResult,
		"fresh production host must expose one root-owned atomic retry control"
	)
	assert_ne(
		retry.error.source_code if retry.error != null else &"",
		ResultsFallbackNavigationPort.NOT_IMPLEMENTED
	)

extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)


func test_committed_start_route_failure_revokes_run_and_camp_writers() -> void:
	var harness: Variant = RouteSupport.boot(self)
	assert_eq(harness.boot_error, &"")
	assert_true(harness.root.open_camp().ok)
	var leases := harness.root.get("_live_lease_registry") as LiveScreenLeaseRegistry
	var old_camp_lease := leases.active_lease()
	assert_not_null(old_camp_lease)
	assert_eq(
		harness.router.bind_production_catalog(
			RouteSupport.RouteFaultCatalog.new(&"RUN_MAP")
		),
		&""
	)
	var commander_id := RouteSupport.first_commander(harness.root)
	assert_false(commander_id.is_empty())
	var result: AppActionResult = harness.root.start_expedition(
		StartExpeditionRequest.new(commander_id, 0)
	)

	assert_false(result.ok)
	assert_true(result.committed, "Camp save already committed the active run")
	assert_eq(result.error.source_code, &"R14_INJECTED_BIND_FAULT")
	assert_eq(
		harness.root.app_state(),
		AppStateMachine.State.MENU,
		"committed route failure must enter the live recovery surface"
	)
	assert_false(
		harness.root.current_run_presentation().ok,
		"failed presentation activation must release the live RUN session/writers"
	)
	assert_false(
		leases.is_active(old_camp_lease),
		"the old CAMP action lease must be revoked after committed start"
	)
	assert_true(harness.root.has_unresumable_active_run())
	assert_not_null(
		harness.root.get("_retained_run_recovery_token"),
		"committed run requires an explicit recovery/discard capability"
	)
	assert_not_null(
		harness.root.try_camp_view_model(),
		"CAMP projection must refresh from the committed profile"
	)
	var recovery_screen := RouteSupport.active_screen(harness)
	assert_not_null(recovery_screen)
	if recovery_screen != null:
		assert_eq(recovery_screen.route_kind, &"MENU_MAIN")
		assert_true(
			RouteSupport.action_ids(recovery_screen).has(&"menu.recovery"),
			"fail-closed MENU must expose a real recovery control"
		)
	var loaded: LoadResult = harness.repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)

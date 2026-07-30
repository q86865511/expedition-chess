extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)


func test_menu_to_camp_bind_fault_preserves_state_scene_and_live_identity() -> void:
	var harness: Variant = Support.boot(self)
	assert_eq(harness.boot_error, &"")
	assert_eq(harness.root.app_state(), AppStateMachine.State.MENU)
	var menu_screen := Support.active_screen(harness)
	assert_not_null(menu_screen)
	if menu_screen == null:
		return
	var menu_identity := menu_screen.get_instance_id()
	var bind_error: StringName = harness.router.bind_production_catalog(
		Support.RouteFaultCatalog.new(&"CAMP_WORLD")
	)
	assert_eq(bind_error, &"")

	var result: AppActionResult = harness.root.open_camp()

	assert_false(result.ok, "candidate bind fault must remain a precommit failure")
	assert_false(result.committed)
	assert_eq(result.error.source_code, &"R14_INJECTED_BIND_FAULT")
	assert_eq(
		harness.root.app_state(),
		AppStateMachine.State.MENU,
		"App state must not move before a route candidate is fully bound"
	)
	var retained := Support.active_screen(harness)
	assert_not_null(retained)
	if retained != null:
		assert_eq(retained.get_instance_id(), menu_identity)
		assert_eq(retained.route_kind, &"MENU_MAIN")


func test_run_to_menu_bind_fault_keeps_run_session_and_old_live_port() -> void:
	var harness: Variant = Support.boot(self)
	var started: AppActionResult = Support.start_run(harness)
	assert_true(started.ok)
	assert_eq(harness.root.app_state(), AppStateMachine.State.RUN)
	var old_screen := Support.active_screen(harness)
	assert_not_null(old_screen)
	if old_screen == null:
		return
	var old_identity := old_screen.get_instance_id()
	var session_before: RunPresentationSessionResult = (
		harness.root.current_run_presentation()
	)
	assert_true(session_before.ok)
	assert_eq(
		harness.router.bind_production_catalog(
			Support.RouteFaultCatalog.new(&"MENU_MAIN")
		),
		&""
	)

	var result: AppActionResult = harness.root.return_to_menu()

	assert_false(result.ok)
	assert_false(result.committed)
	assert_eq(harness.root.app_state(), AppStateMachine.State.RUN)
	assert_true(
		harness.root.current_run_presentation().ok,
		"precommit route failure must retain the active RUN session"
	)
	var retained := Support.active_screen(harness)
	assert_not_null(retained)
	if retained != null:
		assert_eq(retained.get_instance_id(), old_identity)


func test_results_exit_actions_share_root_guard_and_both_install_target_scene() -> void:
	var source := FileAccess.get_file_as_string("res://app/app_root.gd")
	assert_ne(
		source.find("RESULTS_ACTION_IN_PROGRESS"),
		-1,
		"AppRoot must own the results-action single-flight error"
	)
	assert_ne(
		source.find("_begin_results_action"),
		-1,
		"retry, Camp, and Menu must enter one AppRoot guard before validation"
	)
	assert_ne(
		source.find("_prepare_route"),
		-1,
		"both RESULTS exits must stage their target before the typed state commit"
	)
	assert_ne(
		source.find("&\"CAMP_WORLD\""),
		-1,
		"Return to Camp must install CAMP_WORLD"
	)
	assert_ne(
		source.find("&\"MENU_MAIN\""),
		-1,
		"Return to Menu must install MENU_MAIN"
	)

extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_scene_routing/scene_routing_test_support.gd"
)


func test_parent_bound_subroute_tokens_and_screen_leases() -> void:
	var coordinator_script := Support.load_script(self, Support.ROUTE_COORDINATOR_PATH)
	if coordinator_script == null:
		return
	var coordinator: Variant = coordinator_script.new()
	for method_name: StringName in [
		&"install_initial",
		&"prepare_subroute",
		&"commit_subroute",
		&"current_state",
		&"active_lease",
		&"lease_is_active",
	]:
		if not Support.require_method(self, coordinator, method_name):
			return

	var installed: Variant = coordinator.call(
		&"install_initial",
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		&"screen.menu"
	)
	assert_true(bool(installed.get("ok")), "initial route must install")
	var initial_state: Variant = coordinator.call(&"current_state")
	var old_lease: Variant = coordinator.call(&"active_lease")
	assert_eq(initial_state.get("parent_state"), AppStateMachine.State.MENU)
	assert_eq(initial_state.get("route_kind"), &"MENU_MAIN")
	assert_true(bool(coordinator.call(&"lease_is_active", old_lease)))

	var prepared: Variant = coordinator.call(
		&"prepare_subroute",
		AppStateMachine.State.MENU,
		int(initial_state.get("route_generation")),
		&"SETTINGS",
		&""
	)
	assert_true(bool(prepared.get("ok")), "MENU_MAIN→SETTINGS must prepare")
	var committed: Variant = coordinator.call(
		&"commit_subroute",
		prepared.get("token"),
		&"screen.settings"
	)
	assert_true(bool(committed.get("ok")), "prepared same-state route must commit")
	var settings_state: Variant = coordinator.call(&"current_state")
	var settings_lease: Variant = coordinator.call(&"active_lease")
	assert_eq(settings_state.get("route_kind"), &"SETTINGS")
	assert_gt(
		int(settings_state.get("route_generation")),
		int(initial_state.get("route_generation")),
		"route generation must advance on atomic swap"
	)
	assert_false(
		bool(coordinator.call(&"lease_is_active", old_lease)),
		"old screen lease must be revoked in the same commit"
	)
	assert_true(bool(coordinator.call(&"lease_is_active", settings_lease)))

	var stale: Variant = coordinator.call(
		&"prepare_subroute",
		AppStateMachine.State.MENU,
		int(initial_state.get("route_generation")),
		&"MENU_MAIN",
		&""
	)
	assert_false(bool(stale.get("ok")), "old route generation must be rejected")
	assert_eq(Support.error_code(stale), &"ROUTE_GENERATION_STALE")
	var wrong_parent: Variant = coordinator.call(
		&"prepare_subroute",
		AppStateMachine.State.CAMP,
		int(settings_state.get("route_generation")),
		&"CAMP_WORLD",
		&""
	)
	assert_false(bool(wrong_parent.get("ok")), "parent state is part of the token")
	assert_eq(Support.error_code(wrong_parent), &"ROUTE_PARENT_STALE")
	var already_active: Variant = coordinator.call(
		&"prepare_subroute",
		AppStateMachine.State.MENU,
		int(settings_state.get("route_generation")),
		&"SETTINGS",
		&""
	)
	assert_false(bool(already_active.get("ok")))
	assert_eq(Support.error_code(already_active), &"ROUTE_ALREADY_ACTIVE")


func test_run_subroute_keeps_session_until_parent_changes() -> void:
	var coordinator_script := Support.load_script(self, Support.ROUTE_COORDINATOR_PATH)
	if coordinator_script == null:
		return
	var coordinator: Variant = coordinator_script.new()
	for method_name: StringName in [
		&"install_initial",
		&"prepare_subroute",
		&"commit_subroute",
		&"current_state",
		&"has_active_run_session",
		&"leave_parent",
	]:
		if not Support.require_method(self, coordinator, method_name):
			return
	var session := RunPresentationSession.new()
	var installed: Variant = coordinator.call(
		&"install_initial",
		AppStateMachine.State.RUN,
		&"RUN_MAP",
		&"screen.run.map",
		session,
		&"run.snapshot.1"
	)
	assert_true(bool(installed.get("ok")))
	var state: Variant = coordinator.call(&"current_state")
	var prepared: Variant = coordinator.call(
		&"prepare_subroute",
		AppStateMachine.State.RUN,
		int(state.get("route_generation")),
		&"RUN_PREPARE",
		&"run.snapshot.2"
	)
	assert_true(bool(prepared.get("ok")))
	var committed: Variant = coordinator.call(
		&"commit_subroute",
		prepared.get("token"),
		&"screen.run.prepare",
		session
	)
	assert_true(bool(committed.get("ok")))
	assert_true(
		bool(coordinator.call(&"has_active_run_session")),
		"RUN→RUN must preserve an internally owned RunPresentationSession"
	)
	var leave_result: Variant = coordinator.call(
		&"leave_parent",
		AppStateMachine.State.RUN,
		int(coordinator.call(&"current_state").get("route_generation")),
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		&"screen.menu"
	)
	assert_true(bool(leave_result.get("ok")))
	assert_false(
		bool(coordinator.call(&"has_active_run_session")),
		"session must be released only after leaving RUN"
	)

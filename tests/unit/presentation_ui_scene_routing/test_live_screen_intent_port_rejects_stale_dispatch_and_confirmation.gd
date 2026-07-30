extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_scene_routing/scene_routing_test_support.gd"
)


class SpyRunPresentationSession:
	extends RunPresentationSession

	var dispatch_count: int = 0

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		var snapshot := RunPresentationSnapshot.new()
		snapshot.run_id = &"run.test"
		return RunPresentationResult.success(snapshot)


func test_live_screen_intent_port_rejects_stale_dispatch_and_confirmation() -> void:
	var registry_script := Support.load_script(self, Support.LEASE_REGISTRY_PATH)
	var intent_port_script := Support.load_script(self, Support.INTENT_PORT_PATH)
	var navigation_port_script := Support.load_script(self, Support.NAVIGATION_PORT_PATH)
	if registry_script == null or intent_port_script == null or navigation_port_script == null:
		return
	var registry: Variant = registry_script.new()
	for method_name: StringName in [&"activate", &"revoke", &"is_active"]:
		if not Support.require_method(self, registry, method_name):
			return
	var session := SpyRunPresentationSession.new()
	var old_lease: Variant = registry.call(
		&"activate", AppStateMachine.State.RUN, 1
	)
	var old_port: Variant = intent_port_script.new(old_lease, registry, session)
	var old_navigation: Variant = navigation_port_script.new(
		old_lease,
		registry,
		func(_target: StringName) -> AppActionResult:
			return AppActionResult.success(false)
	)
	var new_lease: Variant = registry.call(
		&"activate", AppStateMachine.State.RUN, 2
	)
	assert_false(bool(registry.call(&"is_active", old_lease)))
	assert_true(bool(registry.call(&"is_active", new_lease)))

	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	var dispatch_result: Variant = old_port.call(&"dispatch", intent)
	assert_false(bool(dispatch_result.get("ok")))
	assert_eq(Support.error_code(dispatch_result), &"SCREEN_NOT_ACTIVE")
	assert_eq(session.dispatch_count, 0, "stale port must not reach command session")

	var begin_result: Variant = old_port.call(&"begin_confirmation", intent)
	assert_false(bool(begin_result.get("ok")))
	assert_eq(Support.error_code(begin_result), &"SCREEN_NOT_ACTIVE")
	var draft := ConfirmationDraft.new()
	var confirm_result: Variant = old_port.call(&"confirm", draft)
	assert_false(bool(confirm_result.get("ok")))
	assert_eq(Support.error_code(confirm_result), &"SCREEN_NOT_ACTIVE")
	var cancel_result: Variant = old_port.call(&"cancel", draft)
	assert_false(bool(cancel_result.get("ok")))
	assert_eq(Support.error_code(cancel_result), &"SCREEN_NOT_ACTIVE")

	var navigation_result: Variant = old_navigation.call(&"navigate", &"RUN_PREPARE")
	assert_false(bool(navigation_result.get("ok")))
	assert_eq(
		Support.app_action_error_code(navigation_result),
		&"SCREEN_NOT_ACTIVE",
		"stale navigation callback must be rejected"
	)


func test_new_live_port_dispatches_only_while_lease_is_current() -> void:
	var registry_script := Support.load_script(self, Support.LEASE_REGISTRY_PATH)
	var intent_port_script := Support.load_script(self, Support.INTENT_PORT_PATH)
	if registry_script == null or intent_port_script == null:
		return
	var registry: Variant = registry_script.new()
	if not Support.require_method(self, registry, &"activate"):
		return
	var session := SpyRunPresentationSession.new()
	var lease: Variant = registry.call(&"activate", AppStateMachine.State.RUN, 7)
	var port: Variant = intent_port_script.new(lease, registry, session)
	var result: Variant = port.call(
		&"dispatch",
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)
	assert_true(bool(result.get("ok")))
	assert_eq(session.dispatch_count, 1)
	registry.call(&"revoke", lease)
	var stale: Variant = port.call(
		&"dispatch",
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)
	assert_false(bool(stale.get("ok")))
	assert_eq(Support.error_code(stale), &"SCREEN_NOT_ACTIVE")
	assert_eq(session.dispatch_count, 1)

extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)


class SnapshotSession:
	extends RunPresentationSession

	var current: RunPresentationSnapshot
	var dispatch_count: int = 0

	func _init(snapshot: RunPresentationSnapshot) -> void:
		current = snapshot.deep_clone()

	func snapshot() -> RunPresentationSnapshot:
		return current.deep_clone()

	func dispatch(_intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		return RunPresentationResult.success(current)


func test_joint_route_fault_installs_retryable_live_fallback_without_redispatch() -> void:
	var harness: Variant = RouteSupport.boot(self)
	assert_true(RouteSupport.start_run(harness).ok)
	var old_screen := RouteSupport.active_screen(harness)
	var leases := harness.root.get("_live_lease_registry") as LiveScreenLeaseRegistry
	var old_lease := leases.active_lease()
	var current: RunPresentationSnapshot = (
		harness.root.current_run_presentation().session.snapshot()
	)
	var committed_next: RunPresentationSnapshot = current.deep_clone()
	committed_next.app_phase = &"PREPARE"
	var session := SnapshotSession.new(committed_next)
	harness.root.set("_run_presentation_session", session)
	assert_eq(
		harness.router.bind_production_catalog(
			RouteSupport.RouteFaultCatalog.new(&"RUN_PREPARE")
		),
		&""
	)

	var result: AppActionResult = harness.root.call(
		&"_handle_run_route_after_intent",
		RunPresentationResult.success(committed_next)
	)
	assert_false(result.ok)
	assert_true(result.committed)
	assert_eq(result.error.source_code, &"R14_INJECTED_BIND_FAULT")
	assert_eq(harness.root.app_state(), AppStateMachine.State.RUN)
	assert_eq(
		harness.root.current_run_presentation().session.snapshot().app_phase,
		&"PREPARE"
	)
	assert_false(leases.is_active(old_lease))
	var fallback := RouteSupport.active_screen(harness)
	assert_not_null(fallback)
	if fallback == null:
		return
	assert_ne(fallback.get_instance_id(), old_screen.get_instance_id())
	assert_eq(fallback.route_kind, &"RUN_ROUTE_FALLBACK")
	assert_true(RouteSupport.action_ids(fallback).has(&"run.retry_route"))
	assert_true(RouteSupport.action_ids(fallback).has(&"run.menu"))

	assert_eq(
		harness.router.bind_production_catalog(ProductionSceneCatalog.new()),
		&""
	)
	var retry := _button(fallback, &"run.retry_route")
	assert_not_null(retry)
	if retry != null:
		retry.pressed.emit()
	assert_eq(RouteSupport.active_screen(harness).route_kind, &"RUN_PREPARE")
	assert_eq(session.dispatch_count, 0, "Retry must not redispatch domain intent")
	fallback = null


func _button(screen: ProductionScreen, action_id: StringName) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null

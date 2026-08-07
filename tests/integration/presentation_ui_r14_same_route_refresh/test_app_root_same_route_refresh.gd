extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)
const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)


class RefreshingSession:
	extends RunPresentationSession

	var current: RunPresentationSnapshot
	var next: RunPresentationSnapshot
	var trigger_kind: int
	var dispatch_count: int = 0

	func _init(
		source: RunPresentationSnapshot,
		target: RunPresentationSnapshot,
		p_trigger_kind: int
	) -> void:
		current = source.deep_clone()
		next = target.deep_clone()
		trigger_kind = p_trigger_kind

	func snapshot() -> RunPresentationSnapshot:
		return current.deep_clone()

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		if intent.kind == trigger_kind:
			current = next.deep_clone()
		return RunPresentationResult.success(current)


func test_generate_map_atomically_refreshes_same_route_and_old_control_is_stale() -> void:
	var source := RunPresentationSnapshot.new()
	source.run_id = &"run.r14.same-route.map"
	source.app_phase = &"MAP"
	source.manifest_digest = "before-map"
	var target := CompositionSupport.combat_snapshot()
	target.run_id = source.run_id
	target.app_phase = &"MAP"
	target.manifest_digest = "after-map"
	# The same-route fixture represents a freshly generated map, so its first
	# node must satisfy the same entry-layer reachability guard as production.
	target.map.nodes[0].layer_index = 0
	var fixture := _install(source, target, RunPresentationIntent.Kind.GENERATE_MAP)
	if fixture.is_empty():
		return
	var session := fixture.get("session") as RefreshingSession
	var old_screen := fixture.get("screen") as ProductionScreen
	var select := _button(old_screen, &"map.select")
	assert_not_null(select)
	if select == null:
		return
	select.pressed.emit()
	var fresh := RouteSupport.active_screen(fixture.get("harness"))
	assert_ne(fresh, old_screen, "same-route commit must replace the live lease/screen")
	assert_eq(fresh.route_kind, &"RUN_MAP")
	assert_eq(session.dispatch_count, 1, "domain intent is exactly-once")
	var composition := fresh.get_node_or_null("Composition")
	assert_true(
		composition != null and composition.has_method(&"select_first_node"),
		"generated authoritative map must be visible/selectable on the fresh screen"
	)
	if composition != null and composition.has_method(&"select_first_node"):
		assert_ne(String(composition.call(&"select_first_node")), "")
	select.pressed.emit()
	assert_eq(
		session.dispatch_count,
		1,
		"old same-route control must be stale after atomic replacement"
	)


func test_prepare_board_commit_atomically_refreshes_same_route_once() -> void:
	var source := CompositionSupport.prepare_snapshot()
	source.run_id = &"run.r14.same-route.prepare"
	source.manifest_digest = "before-board"
	var target := source.deep_clone()
	target.manifest_digest = "after-board"
	var fixture := _install(
		source,
		target,
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
	)
	if fixture.is_empty():
		return
	var session := fixture.get("session") as RefreshingSession
	var old_screen := fixture.get("screen") as ProductionScreen
	var commit := _button(old_screen, &"prepare.unit")
	assert_not_null(commit)
	if commit == null:
		return
	commit.pressed.emit()
	var fresh := RouteSupport.active_screen(fixture.get("harness"))
	assert_ne(fresh, old_screen)
	assert_eq(fresh.route_kind, &"RUN_PREPARE")
	assert_eq(session.dispatch_count, 1)
	commit.pressed.emit()
	assert_eq(session.dispatch_count, 1, "retired prepare controls cannot redispatch")


func _install(
	source: RunPresentationSnapshot,
	target: RunPresentationSnapshot,
	trigger_kind: int
) -> Dictionary:
	var harness: Variant = RouteSupport.boot(self)
	assert_true(RouteSupport.start_run(harness).ok)
	var session := RefreshingSession.new(source, target, trigger_kind)
	harness.root.set("_run_presentation_session", session)
	var prepared: Dictionary = harness.root.call(
		&"_prepare_route",
		AppStateMachine.State.RUN,
		StringName("RUN_%s" % String(source.app_phase)),
		session.snapshot()
	)
	assert_true(bool(prepared.get("ok", false)))
	if not bool(prepared.get("ok", false)):
		return {}
	assert_eq(StringName(harness.root.call(&"_commit_route", prepared)), &"")
	return {
		"harness": harness,
		"session": session,
		"screen": RouteSupport.active_screen(harness),
	}


func _button(screen: ProductionScreen, action_id: StringName) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null

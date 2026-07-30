extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)
const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)


class AdvancingSession:
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


func test_real_buttons_advance_joint_app_root_router_and_stale_controls_do_not_dispatch() -> void:
	var map := CompositionSupport.combat_snapshot()
	map.app_phase = &"MAP"
	var prepare := CompositionSupport.prepare_snapshot()
	prepare.run_id = map.run_id
	var combat := CompositionSupport.combat_snapshot()
	combat.run_id = map.run_id
	var reward := CompositionSupport.reward_snapshot(PendingRewardState.Phase.CHOOSING)
	reward.run_id = map.run_id
	var cases: Array[Dictionary] = [
		{
			"route": &"RUN_MAP",
			"source": map,
			"target": prepare,
			"select": &"map.select",
			"confirm": &"map.confirm",
			"intent": RunPresentationIntent.Kind.ENTER_NODE,
		},
		{
			"route": &"RUN_PREPARE",
			"source": prepare,
			"target": combat,
			"select": &"prepare.unit",
			"confirm": &"prepare.start",
			"intent": RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
		},
		{
			"route": &"RUN_REWARD",
			"source": reward,
			"target": map,
			"select": &"reward.select",
			"confirm": &"reward.confirm",
			"intent": RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD,
		},
	]
	for item: Dictionary in cases:
		var harness: Variant = RouteSupport.boot(self)
		assert_true(RouteSupport.start_run(harness).ok)
		var session := AdvancingSession.new(
			item.get("source") as RunPresentationSnapshot,
			item.get("target") as RunPresentationSnapshot,
			int(item.get("intent"))
		)
		harness.root.set("_run_presentation_session", session)
		var prepared: Dictionary = harness.root.call(
			&"_prepare_route",
			AppStateMachine.State.RUN,
			StringName(item.get("route")),
			session.snapshot()
		)
		assert_true(bool(prepared.get("ok", false)))
		if not bool(prepared.get("ok", false)):
			continue
		harness.root.call(&"_commit_route", prepared)
		var old_screen := RouteSupport.active_screen(harness)
		var select := _button(old_screen, StringName(item.get("select")))
		var confirm := _button(old_screen, StringName(item.get("confirm")))
		assert_not_null(select)
		assert_not_null(confirm)
		if select == null or confirm == null:
			continue
		select.pressed.emit()
		confirm.pressed.emit()
		assert_eq(
			RouteSupport.active_screen(harness).route_kind,
			_route_for_phase(session.snapshot().app_phase)
		)
		var count_after_route := session.dispatch_count
		confirm.pressed.emit()
		assert_eq(
			session.dispatch_count,
			count_after_route,
			"old screen control must be stale after atomic route replacement"
		)
		var loaded: LoadResult = harness.repository.load()
		assert_true(loaded.ok)
		assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)


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


func _route_for_phase(phase: StringName) -> StringName:
	match phase:
		&"MAP":
			return &"RUN_MAP"
		&"PREPARE":
			return &"RUN_PREPARE"
		&"COMBAT":
			return &"RUN_COMBAT"
		&"REWARD":
			return &"RUN_REWARD"
	return &""

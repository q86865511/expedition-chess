extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_run_screens/run_screens_test_support.gd"
)

const ROUTE_INTENTS: Dictionary = {
	&"RUN_MAP": [
		RunPresentationIntent.Kind.GENERATE_MAP,
		RunPresentationIntent.Kind.ENTER_NODE,
	],
	&"RUN_PREPARE": [
		RunPresentationIntent.Kind.REFRESH_SHOP,
		RunPresentationIntent.Kind.BUY_UNIT,
		RunPresentationIntent.Kind.BUY_XP,
		RunPresentationIntent.Kind.SELL_UNIT,
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT,
		RunPresentationIntent.Kind.EQUIP_ITEM,
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT,
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
	],
	&"RUN_COMBAT": [
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
		RunPresentationIntent.Kind.SETTLE_BATTLE,
	],
	&"RUN_REWARD": [
		RunPresentationIntent.Kind.RESOLVE_NON_COMBAT,
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD,
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD,
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD,
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD,
		RunPresentationIntent.Kind.ADVANCE_REWARD,
		RunPresentationIntent.Kind.RESOLVE_UNIT_OVERFLOW,
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW,
	],
}


func test_run_screen_command_only_flow_maps_all_facade_intents() -> void:
	var presenter_script := Support.load_script(
		self, Support.RUN_SCREEN_PRESENTER_PATH
	)
	if presenter_script == null:
		return
	var registry := LiveScreenLeaseRegistry.new()
	var session := Support.SpyRunPresentationSession.new()
	var expected_kinds: Array[int] = []

	for route_kind: StringName in ROUTE_INTENTS:
		var lease := registry.activate(AppStateMachine.State.RUN, expected_kinds.size() + 1)
		var intent_port := LiveScreenIntentPort.new(lease, registry, session)
		var presenter: Variant = presenter_script.new(route_kind, intent_port)
		if not Support.require_method(self, presenter, &"request"):
			return
		for kind: int in ROUTE_INTENTS[route_kind]:
			var result: Variant = presenter.call(
				&"request", RunPresentationIntent.new(kind)
			)
			assert_true(bool(result.get("ok")), "%s must dispatch" % kind)
			expected_kinds.append(kind)

	assert_eq(session.dispatched_kinds, expected_kinds)

	var illegal_lease := registry.activate(AppStateMachine.State.RUN, 50)
	var illegal_port := LiveScreenIntentPort.new(illegal_lease, registry, session)
	var map_presenter: Variant = presenter_script.new(&"RUN_MAP", illegal_port)
	var before_illegal := session.dispatch_count
	var illegal: Variant = map_presenter.call(
		&"request",
		RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_UNIT)
	)
	assert_false(bool(illegal.get("ok")))
	assert_eq(Support.error_code(illegal), &"ACTION_NOT_AVAILABLE")
	assert_eq(session.dispatch_count, before_illegal)

	registry.activate(AppStateMachine.State.RUN, 51)
	var stale: Variant = map_presenter.call(
		&"request",
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)
	assert_false(bool(stale.get("ok")))
	assert_eq(Support.error_code(stale), &"SCREEN_NOT_ACTIVE")
	assert_eq(session.dispatch_count, before_illegal)

	# R12-A01/A02 terminal settlement and Results ownership remain deferred.

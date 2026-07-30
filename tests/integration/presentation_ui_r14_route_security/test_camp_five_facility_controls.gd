extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)

const CASES: Dictionary = {
	&"camp.expedition_gate": &"FACILITY_EXPEDITION_GATE",
	&"camp.commander_hall": &"FACILITY_COMMANDER_HALL",
	&"camp.collection": &"COLLECTION",
	&"camp.forge": &"FACILITY_UNLOCK_WORKSHOP",
	&"camp.challenge_monument": &"FACILITY_CHALLENGE_MONUMENT",
}


func test_five_real_focusable_controls_open_composed_facilities_and_back() -> void:
	for action_id: StringName in CASES:
		var harness: Variant = RouteSupport.boot(self)
		assert_true(harness.root.open_camp().ok)
		var camp := RouteSupport.active_screen(harness)
		var button := _button(camp, action_id)
		assert_not_null(button, "missing real facility Button: %s" % action_id)
		if button == null:
			continue
		assert_eq(button.focus_mode, Control.FOCUS_ALL)
		button.grab_focus()
		button.pressed.emit()
		var facility := RouteSupport.active_screen(harness)
		assert_not_null(facility)
		if facility == null:
			continue
		assert_eq(facility.route_kind, StringName(CASES[action_id]))
		assert_not_null(facility.get_node_or_null("Composition"))
		var back := _button(facility, &"camp.back")
		assert_not_null(back)
		if back != null:
			back.pressed.emit()
		assert_eq(RouteSupport.active_screen(harness).route_kind, &"CAMP_WORLD")
		var retained_route := RouteSupport.active_screen(harness).route_kind
		button.pressed.emit()
		assert_eq(
			RouteSupport.active_screen(harness).route_kind,
			retained_route,
			"stale facility control must not navigate after its lease is revoked"
		)


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

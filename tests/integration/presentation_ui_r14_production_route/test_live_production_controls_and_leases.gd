extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)


func test_real_menu_and_camp_scenes_expose_localized_keyboard_controls() -> void:
	var harness: Variant = Support.boot(self)
	var menu := Support.active_screen(harness)
	assert_not_null(menu)
	if menu == null:
		return
	var menu_actions := Support.action_ids(menu)
	for required: StringName in [
		&"menu.start",
		&"menu.settings",
		&"menu.exit",
	]:
		assert_has(menu_actions, required)
	assert_false(
		menu_actions.has(&"menu.continue"),
		"a fresh profile must not expose Continue before a run is retained"
	)
	for button: Button in Support.action_buttons(menu):
		assert_false(button.text.strip_edges().is_empty())
		assert_true(button.focus_mode != Control.FOCUS_NONE)

	var opened: AppActionResult = harness.root.open_camp()
	assert_true(opened.ok)
	var camp := Support.active_screen(harness)
	assert_not_null(camp)
	if camp == null:
		return
	var camp_actions := Support.action_ids(camp)
	for required: StringName in [
		&"camp.collection",
		&"camp.forge",
		&"camp.settings",
		&"camp.start",
	]:
		assert_has(camp_actions, required)


func test_real_camp_composition_uses_live_navigation_and_old_port_becomes_stale() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(harness.root.open_camp().ok)
	var old_composition := Support.composition(harness) as CampWorldScreen
	assert_not_null(old_composition)
	if old_composition == null:
		return

	var opened: AppActionResult = old_composition.open_facility(&"COLLECTION")

	assert_true(opened.ok, "real CAMP_WORLD child must receive its live navigation port")
	assert_eq(Support.active_screen(harness).route_kind, &"COLLECTION")
	var stale: AppActionResult = old_composition.open_facility(
		&"FACILITY_EXPEDITION_GATE"
	)
	assert_false(stale.ok)
	assert_eq(
		Support.error_code(stale),
		LiveScreenNavigationPort.SCREEN_NOT_ACTIVE,
		"atomic swap must revoke every callback held by the old screen"
	)


func test_real_run_screen_receives_intent_and_combat_playback_ports() -> void:
	var harness: Variant = Support.boot(self)
	var started: AppActionResult = Support.start_run(harness)
	assert_true(started.ok)
	var run_screen := Support.active_screen(harness)
	assert_not_null(run_screen)
	if run_screen == null:
		return
	assert_true(
		run_screen.has_method(&"live_binding_report"),
		"production route must expose a clone-only typed activation report"
	)
	if not run_screen.has_method(&"live_binding_report"):
		return
	var report: Variant = run_screen.call(&"live_binding_report")
	assert_true(report != null and bool(report.get("active")))
	assert_true(bool(report.get("intent")))
	assert_false(bool(report.get("raw_session")))

	var root_source := FileAccess.get_file_as_string("res://app/app_root.gd")
	assert_ne(
		root_source.find("LiveScreenPlaybackPort.new"),
		-1,
		"real RUN_COMBAT activation must build the lease-bound playback port"
	)
	assert_ne(
		root_source.find("LiveScreenIntentPort.new"),
		-1,
		"real RUN routes must build the lease-bound gameplay intent port"
	)


func test_staged_context_and_route_coordinator_expose_no_raw_session_surface() -> void:
	var context := StagedScreenContext.new(&"RUN_MAP", RunPresentationSnapshot.new())
	assert_false(
		_has_property(context, &"run_session"),
		"staged context may carry only cloned read data"
	)
	assert_false(
		_has_property(context, &"intent_port"),
		"writer ports are injected only by one-shot live activation"
	)
	assert_false(
		PresentationRouteCoordinator.new().has_method(&"active_session"),
		"route coordinator must not expose the raw RunPresentationSession"
	)


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false

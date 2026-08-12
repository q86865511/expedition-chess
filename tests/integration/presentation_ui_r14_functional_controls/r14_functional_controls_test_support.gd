extends RefCounted

const LifecycleSupport = preload(
	"res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd"
)
const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)
const PlaybackSupport = preload(
	"res://tests/integration/presentation_ui_r13_playback_port/"
	+ "r13_playback_port_test_support.gd"
)


static func boot(test: GutTest) -> Variant:
	return LifecycleSupport.boot(test, FakeSaveStorage.new())


static func active_screen(harness: Variant) -> ProductionScreen:
	if harness == null or harness.host == null or harness.host.get_child_count() != 1:
		return null
	return harness.host.get_child(0) as ProductionScreen


static func composition(screen: ProductionScreen) -> Node:
	return screen.get_node_or_null("Composition") if screen != null else null


static func button(
	test: GutTest,
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	if screen == null:
		test.assert_not_null(screen, "active production screen is required")
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var candidate := node as Button
		if (
			candidate != null
			and candidate.has_meta(&"action_id")
			and StringName(candidate.get_meta(&"action_id")) == action_id
		):
			return candidate
	test.assert_true(false, "missing real Button for %s" % String(action_id))
	return null


static func press(
	test: GutTest,
	screen: ProductionScreen,
	action_id: StringName
) -> bool:
	if (
		action_id == &"run.menu"
		and screen != null
		and screen.system_menu_state() == &"CLOSED"
	):
		var menu_button := screen.system_menu_button()
		test.assert_not_null(
			menu_button,
			"live run routes expose SystemMenuButton instead of resident run.menu"
		)
		if menu_button == null:
			return false
		menu_button.pressed.emit()
	var control := button(test, screen, action_id)
	if control == null:
		return false
	control.pressed.emit()
	return true


static func last_control_result(
	test: GutTest,
	screen: ProductionScreen
) -> Variant:
	var present := screen != null and screen.has_method(&"last_control_result")
	test.assert_true(
		present,
		"functional controls must retain a clone-safe typed result for diagnostics"
	)
	return screen.call(&"last_control_result") if present else null


static func error_code(result: Variant) -> StringName:
	if result == null or not result is Object:
		return &""
	var error: Variant = (result as Object).get("error")
	if error == null:
		return &""
	var source: Variant = (error as Object).get("source_code")
	return StringName(source) if source != null else &""


static func first_commander(root: ApplicationRoot) -> StringName:
	var view_model := root.try_camp_view_model()
	if view_model == null:
		return &""
	var commanders: Array[StringName] = (
		view_model.commander_hall_unlocked_commander_ids()
	)
	return commanders[0] if not commanders.is_empty() else &""


static func localized(action_ids: Array[StringName]) -> Dictionary:
	var values: Dictionary = {}
	for action_id: StringName in action_ids:
		values[action_id] = String(action_id)
	return values


static func live_run_screen(
	test: GutTest,
	route_kind: StringName,
	snapshot: RunPresentationSnapshot,
	session: RunPresentationSession,
	playback_port: LiveScreenPlaybackPort = null
) -> ProductionScreen:
	var screen := ProductionSceneCatalog.new().instantiate(route_kind)
	test.assert_not_null(screen)
	if screen == null:
		return null
	var action_ids: Array[StringName] = []
	for value: Variant in [
		&"map.select",
		&"map.confirm",
		&"prepare.unit",
		&"prepare.start",
		&"combat.pause",
		&"combat.inspect",
		&"combat.speed",
		&"reward.select",
		&"reward.confirm",
		&"run.menu",
	]:
		action_ids.append(StringName(value))
	var staged := StagedScreenContext.new(
		route_kind,
		snapshot,
		null,
		&"zh_TW",
		localized(action_ids)
	)
	test.assert_eq(screen.bind(staged), &"")
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 71)
	var intent_port := LiveScreenIntentPort.new(lease, registry, session)
	var live := ProductionLiveScreenContext.new(
		route_kind,
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		intent_port,
		playback_port
	)
	test.assert_eq(screen.prepare_live_binding(live), &"")
	test.add_child_autofree(screen)
	screen.activate_live()
	return screen


static func playback_fixture(
	test: GutTest
) -> Dictionary:
	var session := PlaybackSupport.SaveSpySession.new()
	var identity := PlaybackSupport.identity()
	PlaybackSupport.install_transcript(
		test,
		session,
		PlaybackSupport.events(4),
		identity
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 72)
	var port := LiveScreenPlaybackPort.new(lease, registry, session)
	return {
		"session": session,
		"identity": identity,
		"registry": registry,
		"lease": lease,
		"port": port,
	}

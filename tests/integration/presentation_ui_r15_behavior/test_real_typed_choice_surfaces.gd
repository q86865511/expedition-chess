extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_behavior/"
	+ "r15_behavior_test_support.gd"
)
const INSPECTION_PORT_PATH := \
	"res://presentation/screens/live_screen_inspection_port.gd"


func test_app_root_camp_and_map_use_visible_typed_selections() -> void:
	var harness: Variant = Support.RouteSupport.boot(self)
	assert_true(harness.root.open_camp().ok)
	var camp_screen := Support.active_screen(harness)
	assert_not_null(camp_screen)
	if camp_screen == null:
		return
	var composition := (
		camp_screen.get_node_or_null(^"Composition") as CampWorldScreen
	)
	var commander := (
		camp_screen.get_node_or_null(^"Composition/CommanderSelector")
		as OptionButton
	)
	var challenge := (
		camp_screen.get_node_or_null(^"Composition/ChallengeSelector")
		as SpinBox
	)
	assert_not_null(
		commander,
		"CAMP must expose a visible keyboard/mouse commander selector"
	)
	assert_not_null(
		challenge,
		"CAMP must expose a visible typed challenge selector"
	)
	if composition == null or commander == null or challenge == null:
		return
	assert_true(commander.visible)
	assert_true(commander.focus_mode == Control.FOCUS_ALL)
	assert_gt(commander.item_count, 0)
	var commander_id := StringName(commander.get_item_metadata(0))
	assert_false(
		commander_id.is_empty(),
		"the visible option must carry its typed commander id"
	)
	commander.select(0)
	commander.item_selected.emit(0)
	challenge.value = 0.0
	challenge.value_changed.emit(0.0)
	await wait_process_frames(1)
	var request := composition.selected_expedition_request()
	assert_not_null(request)
	if request == null:
		return
	assert_eq(request.commander_id, commander_id)
	assert_eq(request.challenge_level, 0)

	var start := Support.action_button(camp_screen, &"camp.start")
	assert_not_null(start)
	if start == null:
		return
	assert_false(start.disabled)
	start.pressed.emit()
	await wait_process_frames(2)
	var map_screen := Support.active_screen(harness)
	assert_not_null(map_screen)
	if map_screen == null:
		return
	assert_eq(map_screen.route_kind, &"RUN_MAP")

	# The first confirm is an explicit player action that generates the map. The
	# replacement RUN_MAP scene must then render the committed selectable nodes.
	var generate := Support.action_button(map_screen, &"map.confirm")
	assert_not_null(generate)
	if generate == null:
		return
	generate.pressed.emit()
	await wait_process_frames(2)
	map_screen = Support.active_screen(harness)
	var node_selector := (
		map_screen.get_node_or_null(^"Composition/NodeSelector") as ItemList
		if map_screen != null
		else null
	)
	assert_not_null(
		node_selector,
		"RUN_MAP must render committed nodes instead of select-first"
	)
	if map_screen == null or node_selector == null:
		return
	assert_true(node_selector.visible)
	assert_true(node_selector.focus_mode == Control.FOCUS_ALL)
	assert_gt(node_selector.item_count, 0)
	var selected_index := node_selector.item_count - 1
	var selected_node_id := String(node_selector.get_item_metadata(selected_index))
	assert_false(selected_node_id.is_empty())
	node_selector.select(selected_index)
	node_selector.item_selected.emit(selected_index)
	await wait_process_frames(1)
	var map_composition := (
		map_screen.get_node_or_null(^"Composition") as RunMapScreen
	)
	assert_not_null(map_composition)
	if map_composition != null:
		assert_eq(map_composition.selected_node_id(), selected_node_id)


func test_reward_offer_and_combat_inspection_are_real_typed_controls() -> void:
	var reward_session := Support.SpyTypedSession.new()
	reward_session.current_snapshot = Support.CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	var reward_screen := Support.FunctionalSupport.live_run_screen(
		self,
		&"RUN_REWARD",
		reward_session.snapshot(),
		reward_session
	)
	if reward_screen == null:
		return
	var offers := (
		reward_screen.get_node_or_null(^"Composition/OfferSelector")
		as ItemList
	)
	assert_not_null(
		offers,
		"RUN_REWARD must render every authoritative offer as a selectable control"
	)
	if offers == null:
		return
	assert_eq(offers.item_count, 3)
	for index: int in offers.item_count:
		assert_eq(
			String(offers.get_item_metadata(index)),
			"choice.%d" % index
		)
	var chosen_index := 2
	offers.select(chosen_index)
	offers.item_selected.emit(chosen_index)
	await wait_process_frames(1)
	var reward_composition := (
		reward_screen.get_node_or_null(^"Composition") as RunRewardScreen
	)
	assert_not_null(reward_composition)
	if reward_composition == null:
		return
	assert_eq(reward_composition.selected_reward_id(), "choice.2")
	var confirm := Support.action_button(reward_screen, &"reward.confirm")
	assert_not_null(confirm)
	if confirm == null:
		return
	confirm.pressed.emit()
	assert_not_null(reward_session.last_intent)
	if reward_session.last_intent != null:
		assert_eq(reward_session.last_intent.choice_id, "choice.2")
		assert_eq(reward_session.last_intent.offer_id, "choice.2")

	var inspection_port_exists := ResourceLoader.exists(INSPECTION_PORT_PATH)
	assert_true(
		inspection_port_exists,
		"RUN_COMBAT requires a lease-bound clone-only inspection port"
	)
	if not inspection_port_exists:
		return
	var inspection_script := load(INSPECTION_PORT_PATH) as Script
	assert_not_null(inspection_script)
	if inspection_script == null:
		return
	var combat_session := Support.SpyTypedSession.new()
	combat_session.current_snapshot = Support.CompositionSupport.combat_snapshot()
	combat_session.inspections[1] = Support.InspectionSupport.inspection(
		1,
		&"unit.enemy.alpha",
		2
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 151)
	var intent_port := LiveScreenIntentPort.new(
		lease,
		registry,
		combat_session
	)
	var inspection_port: Variant = inspection_script.new(
		lease,
		registry,
		combat_session
	)
	var playback := Support.FunctionalSupport.playback_fixture(self)
	var combat_screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(combat_screen)
	if combat_screen == null:
		return
	var staged := StagedScreenContext.new(
		&"RUN_COMBAT",
		combat_session.snapshot(),
		null,
		&"zh_TW",
		{
			&"combat.pause": "暫停",
			&"combat.inspect": "檢視",
			&"combat.speed": "速度",
			&"run.menu": "選單",
		}
	)
	assert_eq(combat_screen.bind(staged), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_COMBAT",
		combat_session.snapshot(),
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		intent_port,
		playback.get("port") as LiveScreenPlaybackPort
	)
	assert_true(
		Support.has_property(live, &"inspection_port"),
		"live context must carry typed read-only inspection authority"
	)
	if not Support.has_property(live, &"inspection_port"):
		combat_screen.free()
		return
	live.set(&"inspection_port", inspection_port)
	assert_eq(combat_screen.prepare_live_binding(live), &"")
	add_child_autofree(combat_screen)
	combat_screen.activate_live()

	var units := (
		combat_screen.get_node_or_null(^"Composition/UnitSelector")
		as ItemList
	)
	assert_not_null(units, "RUN_COMBAT must render selectable typed units")
	if units == null:
		return
	assert_gt(units.item_count, 0)
	assert_eq(int(units.get_item_metadata(0)), 1)
	units.select(0)
	units.item_selected.emit(0)
	var inspect_button := Support.action_button(
		combat_screen,
		&"combat.inspect"
	)
	assert_not_null(inspect_button)
	if inspect_button == null:
		return
	inspect_button.pressed.emit()
	var inspection: Variant = combat_screen.last_control_result()
	assert_true(
		inspection is CombatUnitInspectionResult,
		"combat.inspect must not alias playback state"
	)
	if inspection is CombatUnitInspectionResult:
		assert_true((inspection as CombatUnitInspectionResult).ok)
		assert_eq(
			(inspection as CombatUnitInspectionResult).snapshot.source_id,
			&"unit.enemy.alpha"
		)
	assert_eq(combat_session.inspection_count, 1)
	assert_eq(
		combat_session.dispatch_count,
		0,
		"inspection is clone-only and must never dispatch gameplay intent"
	)
	for path: NodePath in [
		^"Composition/InspectionPanel/SourceValue",
		^"Composition/InspectionPanel/TargetValue",
		^"Composition/InspectionPanel/StatsValue",
		^"Composition/InspectionPanel/EquipmentValue",
		^"Composition/InspectionPanel/TraitsValue",
		^"Composition/InspectionPanel/StatusesValue",
	]:
		var label := combat_screen.get_node_or_null(path) as Label
		assert_not_null(label, "%s must be player-visible" % path)
		if label != null:
			assert_false(label.text.strip_edges().is_empty())

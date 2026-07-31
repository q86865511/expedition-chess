extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)


func test_map_buttons_generate_select_and_confirm_through_typed_intents() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = RunPresentationSnapshot.new()
	session.current_snapshot.run_id = &"run.r14.functional.map"
	session.current_snapshot.app_phase = &"MAP"
	session.current_snapshot.manifest_digest = "manifest.r14.functional.map"
	var screen := Support.live_run_screen(
		self,
		&"RUN_MAP",
		session.current_snapshot,
		session
	)
	if screen == null:
		return

	assert_true(Support.press(self, screen, &"map.confirm"))
	assert_eq(
		session.dispatched_kinds,
		[RunPresentationIntent.Kind.GENERATE_MAP],
		"first confirm without a generated map must dispatch GENERATE_MAP"
	)
	assert_true(Support.press(self, screen, &"map.select"))
	var composition := Support.composition(screen)
	var selected := (
		String(composition.call(&"selected_node_id"))
		if composition != null and composition.has_method(&"selected_node_id")
		else ""
	)
	assert_false(selected.is_empty(), "map.select must update only the consumer draft")
	assert_true(Support.press(self, screen, &"map.confirm"))
	var map_last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		map_last_kind,
		RunPresentationIntent.Kind.ENTER_NODE,
		"confirm with a selection must dispatch ENTER_NODE"
	)


func test_prepare_and_reward_controls_dispatch_route_specific_intents() -> void:
	var prepare_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	prepare_session.current_snapshot = Support.CompositionSupport.prepare_snapshot()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		prepare_session.current_snapshot,
		prepare_session
	)
	if prepare == null:
		return
	assert_true(Support.press(self, prepare, &"prepare.unit"))
	assert_true(
		prepare_session.dispatched_kinds.has(
			RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
		),
		"prepare.unit must dispatch a typed board draft, not a generic app action"
	)
	assert_true(Support.press(self, prepare, &"prepare.start"))
	var prepare_last_kind: int = (
		-1
		if prepare_session.dispatched_kinds.is_empty()
		else int(prepare_session.dispatched_kinds.back())
	)
	assert_eq(
		prepare_last_kind,
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	)

	var reward_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	reward_session.current_snapshot = Support.CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	var reward := Support.live_run_screen(
		self,
		&"RUN_REWARD",
		reward_session.current_snapshot,
		reward_session
	)
	if reward == null:
		return
	assert_true(Support.press(self, reward, &"reward.select"))
	var reward_composition := Support.composition(reward)
	assert_false(
		String(
			reward_composition.call(&"selected_reward_id")
			if (
				reward_composition != null
				and reward_composition.has_method(&"selected_reward_id")
			)
			else ""
		).is_empty()
	)
	assert_true(Support.press(self, reward, &"reward.confirm"))
	var reward_last_kind: int = (
		-1
		if reward_session.dispatched_kinds.is_empty()
		else int(reward_session.dispatched_kinds.back())
	)
	assert_eq(
		reward_last_kind,
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
	)


func test_route_preconditions_never_collapse_to_generic_action_not_available() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = Support.CompositionSupport.prepare_snapshot()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	assert_true(Support.press(self, prepare, &"prepare.start"))
	var result: Variant = Support.last_control_result(self, prepare)
	if result == null:
		return
	assert_ne(
		Support.error_code(result),
		ApplicationRoot.ERROR_ACTION_NOT_AVAILABLE,
		"route controls require an exact domain/precondition error"
	)


func test_service_dismantle_and_exit_dispatch_node_service_intents() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	var overlay := NodeServiceOverlaySnapshot.new()
	overlay.service_kind = &"dismantle"
	overlay.node_id = &"node.service.r14"
	overlay.choice_receipt_digest = "receipt.digest.r14"
	snapshot.node_service_overlay = overlay
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return

	var composition := Support.composition(prepare)
	var inventory := composition.get_node_or_null(^"InventorySelector") as ItemList
	assert_not_null(inventory)
	if inventory == null:
		return
	inventory.select(0)

	assert_true(Support.press(self, prepare, &"service.dismantle"))
	assert_true(
		session.dispatched_kinds.has(
			RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE
		),
		"service.dismantle must dispatch DISMANTLE_WITH_NODE_SERVICE"
	)

	assert_true(Support.press(self, prepare, &"service.exit"))
	var last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		last_kind,
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE,
		"service.exit must dispatch EXIT_NODE_SERVICE"
	)


func test_choice_ack_dispatches_acknowledge_node_choice_result_intent() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	var pending_result := NodeChoiceResultSnapshot.new()
	pending_result.node_id = &"node.choice.r14"
	pending_result.choice_set_id = &"choice_set.r14"
	pending_result.choice_id = &"choice.r14.option"
	pending_result.result_key = &"result.r14"
	pending_result.outcome_kind = 0
	pending_result.receipt_digest = "receipt.digest.ack.r14"
	snapshot.pending_node_choice_results.append(pending_result)
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return

	assert_true(Support.press(self, prepare, &"choice.ack"))
	var last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		last_kind,
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT,
		"choice.ack must dispatch ACKNOWLEDGE_NODE_CHOICE_RESULT"
	)

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

	assert_true(Support.press(self, screen, &"map.select"))
	assert_eq(
		session.dispatched_kinds,
		[RunPresentationIntent.Kind.GENERATE_MAP],
		"select node without a generated map must dispatch GENERATE_MAP"
	)
	var composition := Support.composition(screen)
	var selected := (
		String(composition.call(&"selected_node_id"))
		if composition != null and composition.has_method(&"selected_node_id")
		else ""
	)
	assert_false(
		selected.is_empty(),
		"map.select must expose a visible consumer selection after generation"
	)
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
	var inventory := composition.find_child("InventorySelector", true, false) as ItemList
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


## T25 review N1：三種 outcome 的落點不同（design :206-209）——APPLY 完成節點後停在
## MAP、REWARD 出口停在 REWARD、DISMANTLE 留在 PREPARE。ack 只由 unacknowledged
## ledger 驅動（design :201-204），因此三個 route 都要能送出它，否則 3 種 outcome
## 有 2 種的 receipt 永遠翻不成 true。
func test_choice_ack_is_reachable_on_the_map_and_reward_routes() -> void:
	var map_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var map_snapshot := RunPresentationSnapshot.new()
	map_snapshot.run_id = &"run.r14.functional.map.ack"
	map_snapshot.app_phase = &"MAP"
	map_snapshot.manifest_digest = "manifest.r14.functional.map.ack"
	map_snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.map.ack", &"result.map.ack")
	)
	map_session.current_snapshot = map_snapshot
	var map_screen := Support.live_run_screen(
		self,
		&"RUN_MAP",
		map_session.current_snapshot,
		map_session
	)
	if map_screen == null:
		return
	assert_true(Support.press(self, map_screen, &"choice.ack"))
	assert_eq(
		_last_ack_digest(map_session),
		"receipt.digest.map.ack",
		"RUN_MAP must acknowledge the receipt it is replaying"
	)

	var reward_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var reward_snapshot := Support.CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	reward_snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.reward.ack", &"result.reward.ack")
	)
	reward_session.current_snapshot = reward_snapshot
	var reward_screen := Support.live_run_screen(
		self,
		&"RUN_REWARD",
		reward_session.current_snapshot,
		reward_session
	)
	if reward_screen == null:
		return
	assert_true(Support.press(self, reward_screen, &"choice.ack"))
	assert_eq(
		_last_ack_digest(reward_session),
		"receipt.digest.reward.ack",
		"RUN_REWARD must acknowledge the receipt it is replaying"
	)


## T25 review N2：ledger 有多筆未確認結果時，畫面顯示的文字與 ack 掉的 receipt
## 必須是同一筆（升冪 ledger 的最舊一筆），否則玩家確認的是別的節點的結果。
func test_choice_ack_targets_the_result_that_is_displayed() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.older", &"result.older")
	)
	snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.newer", &"result.newer")
	)
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	prepare.relocalize(&"zh_TW", {
		&"result.older": "較舊的事件結果",
		&"result.newer": "較新的事件結果",
	})
	var label := prepare.get_node_or_null(
		ProductionScreen.NODE_CHOICE_RESULT_NODE
	) as Label
	assert_not_null(label, "unacknowledged result must have a render surface")
	if label == null:
		return
	assert_true(label.visible)
	assert_eq(label.text, "較舊的事件結果")
	assert_true(Support.press(self, prepare, &"choice.ack"))
	assert_eq(_last_ack_digest(session), "receipt.digest.older")


## 沒有未確認結果時：ack 停用、顯示面收起（design :201「只由 unacknowledged
## committed receipt 顯示 result」）。缺文案的 key 則 fail-soft 顯示鍵名本身。
func test_result_surface_is_hidden_without_a_receipt_and_fails_soft_on_missing_text() -> void:
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
	var label := prepare.get_node_or_null(
		ProductionScreen.NODE_CHOICE_RESULT_NODE
	) as Label
	assert_not_null(label)
	if label == null:
		return
	assert_false(label.visible)
	var ack := Support.button(self, prepare, &"choice.ack")
	assert_not_null(ack)
	if ack != null:
		assert_true(ack.disabled, "ack must be unavailable without a receipt")

	var replayed := Support.CompositionSupport.prepare_snapshot()
	replayed.pending_node_choice_results.append(
		_pending_result("receipt.digest.unlocalized", &"result.without.text")
	)
	session.current_snapshot = replayed
	# 任何一次成功的 dispatch 都會換掉畫面持有的 snapshot，結果面隨之出現。
	assert_true(Support.press(self, prepare, &"prepare.refresh"))
	assert_true(label.visible)
	assert_eq(
		label.text,
		"result.without.text",
		"missing localization must surface the key instead of a blank line"
	)


func _pending_result(
	receipt_digest: String,
	result_key: StringName
) -> NodeChoiceResultSnapshot:
	var pending_result := NodeChoiceResultSnapshot.new()
	pending_result.node_id = &"node.choice.r14"
	pending_result.choice_set_id = &"choice_set.r14"
	pending_result.choice_id = &"choice.r14.option"
	pending_result.result_key = result_key
	pending_result.outcome_kind = 1
	pending_result.receipt_digest = receipt_digest
	return pending_result


func _last_ack_digest(session: Variant) -> String:
	var ack_kind := RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT
	var intents: Array = session.dispatched_intents
	for index: int in range(intents.size() - 1, -1, -1):
		var intent := intents[index] as RunPresentationIntent
		if intent != null and intent.kind == ack_kind:
			return intent.receipt_digest
	return ""

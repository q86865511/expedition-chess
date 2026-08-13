extends RefCounted

## G2 H1：正式路徑（production facade ＋ formal screen，不經 scripts/dev）把一局遠征
## 推到戰鬥的共用步驟。每一步都走 ProductionScreen.request_intent()，也就是正式畫面
## 按鈕背後的同一個 lease-bound intent port。

const MAIN_SCENE := preload("res://app/main.tscn")


class BootHarness:
	extends RefCounted

	var main: Node
	var registry: ContentRegistryService
	var repository: SaveRepository
	var router: SceneRouterService
	var root: ApplicationRoot
	var host: Control
	var viewport_coordinator: ProductionViewportCoordinator
	var world_surface: ProductionWorldSurface
	var boot_error: StringName = &""


static func boot(test: GutTest) -> Variant:
	# G2 exercises the formal world-board mount and first-draw settlement gate.
	# The generic lifecycle fixture intentionally owns only AppRoot + a route
	# host, so it cannot represent production after the board moved into the
	# world SubViewport. Instantiate the actual main composition instead: this
	# gives every G2 route exactly one surface, its real viewport coordinator,
	# and the route-local HUD overlay mount created by RunCombatScreen.
	var harness := BootHarness.new()
	harness.main = MAIN_SCENE.instantiate()
	harness.root = harness.main.get_node_or_null(^"AppRoot") as ApplicationRoot
	harness.host = harness.main.get_node_or_null(
		^"AppRoot/UiLayer/UiRoot/PresentationHost"
	) as Control
	harness.viewport_coordinator = harness.main.get_node_or_null(
		^"AppRoot/ViewportCoordinator"
	) as ProductionViewportCoordinator
	harness.world_surface = harness.main.get_node_or_null(
		^"AppRoot/WorldViewportContainer/WorldViewport/ProductionWorld"
	) as ProductionWorldSurface
	test.assert_not_null(harness.root)
	test.assert_not_null(harness.host)
	test.assert_not_null(harness.viewport_coordinator)
	test.assert_not_null(harness.world_surface)
	if (
		harness.root == null
		or harness.host == null
		or harness.viewport_coordinator == null
		or harness.world_surface == null
	):
		return harness

	harness.registry = ContentRegistryService.new()
	test.add_child_autofree(harness.registry)
	harness.repository = SaveRepository.new(FakeSaveStorage.new())
	test.add_child_autofree(harness.repository)
	harness.router = SceneRouterService.new()
	test.add_child_autofree(harness.router)
	harness.root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	var bind_error := harness.root.bind_services(
		harness.registry,
		harness.repository,
		harness.router
	)
	test.assert_eq(bind_error, &"", "test graph must bind before tree entry")
	test.add_child_autofree(harness.main)
	# Pin the same supported baseline used by the production viewport contract.
	# The coordinator's deferred visible-window refresh may run later, but the
	# mapper is already valid before any route schedules its deferred board mount.
	test.assert_eq(
		harness.viewport_coordinator.synchronize(Vector2i(1280, 720)),
		&""
	)
	test.assert_eq(
		test.get_tree().get_nodes_in_group(
			ProductionWorldSurface.MOUNT_GROUP
		).size(),
		1,
		"the production fixture must expose exactly one world surface"
	)
	test.assert_eq(
		test.get_tree().get_nodes_in_group(
			ProductionViewportCoordinator.COORDINATOR_GROUP
		).size(),
		1,
		"the production fixture must expose exactly one viewport coordinator"
	)
	return harness


static func active_screen(harness: Variant) -> ProductionScreen:
	if harness == null or harness.host == null or harness.host.get_child_count() != 1:
		return null
	return harness.host.get_child(0) as ProductionScreen


static func composition(harness: Variant) -> Node:
	var screen := active_screen(harness)
	return screen.get_node_or_null("Composition") if screen != null else null


static func button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var candidate := node as Button
		if (
			candidate != null
			and candidate.has_meta(&"action_id")
			and StringName(candidate.get_meta(&"action_id")) == action_id
		):
			return candidate
	return null


static func first_commander(root: ApplicationRoot) -> StringName:
	var view_model: CampViewModel = root.try_camp_view_model()
	if view_model == null:
		return &""
	var commanders: Array[StringName] = (
		view_model.commander_hall_unlocked_commander_ids()
	)
	return commanders[0] if not commanders.is_empty() else &""


static func start_run(harness: Variant) -> AppActionResult:
	var opened: AppActionResult = harness.root.open_camp()
	if not opened.ok:
		return opened
	var commander_id := first_commander(harness.root)
	if commander_id.is_empty():
		return AppActionResult.failure(DiagnosticError.new(
			&"G2_COMMANDER_MISSING",
			&"error.presentation.g2_commander_missing"
		))
	return harness.root.start_expedition(
		StartExpeditionRequest.new(commander_id, 0)
	)


static func snapshot(harness: Variant) -> RunPresentationSnapshot:
	var session: Variant = harness.root.get("_run_presentation_session")
	return session.snapshot() if session != null else null


static func request(
	harness: Variant,
	intent: RunPresentationIntent
) -> RunPresentationResult:
	var screen := active_screen(harness)
	if screen == null:
		return RunPresentationResult.failure(DiagnosticError.new(
			&"G2_SCREEN_MISSING",
			&"error.presentation.g2_screen_missing"
		))
	return screen.request_intent(intent)


static func request_kind(
	harness: Variant,
	kind: RunPresentationIntent.Kind
) -> RunPresentationResult:
	return request(harness, RunPresentationIntent.new(kind))


static func first_reachable_node_id(harness: Variant) -> String:
	var current := snapshot(harness)
	if current == null or current.map == null:
		return ""
	for node: MapNodeState in current.map.nodes:
		if node.completed or current.map.completed_node_ids.has(node.node_id):
			continue
		if current.map.completed_node_ids.is_empty():
			if node.act_index == 1 and node.layer_index == 0:
				return node.node_id
			continue
		for completed_id: String in current.map.completed_node_ids:
			for edge: MapEdgeState in current.map.edges:
				if (
					edge.from_node_id == completed_id
					and edge.to_node_id == node.node_id
				):
					return node.node_id
	return ""


## MAP → PREPARE → 買滿買得起的棋 → 全部上場 → COMBAT。回傳空字串代表成功，
## 否則是卡住那一步的具名錯誤碼（測試據此明確失敗，而不是靜默走偏）。
static func drive_to_combat(harness: Variant) -> StringName:
	var generated := request_kind(harness, RunPresentationIntent.Kind.GENERATE_MAP)
	if not generated.ok:
		return error_code(generated)
	var node_id := first_reachable_node_id(harness)
	if node_id.is_empty():
		return &"G2_NO_REACHABLE_NODE"
	var enter := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
	enter.target_node_id = node_id
	var entered := request(harness, enter)
	if not entered.ok:
		return error_code(entered)
	request_kind(harness, RunPresentationIntent.Kind.REFRESH_SHOP)
	_buy_affordable_units(harness)
	var committed := request(harness, full_board_intent(harness))
	if not committed.ok:
		return error_code(committed)
	var started := request_kind(
		harness,
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	)
	if not started.ok:
		return error_code(started)
	return &""


static func _buy_affordable_units(harness: Variant) -> void:
	for _attempt: int in range(8):
		var current := snapshot(harness)
		if current == null or current.economy == null:
			return
		var bought := false
		for offer: ShopOffer in current.economy.shop_offers:
			var intent := RunPresentationIntent.new(
				RunPresentationIntent.Kind.BUY_UNIT
			)
			intent.offer_id = offer.offer_id
			if request(harness, intent).ok:
				bought = true
				break
		if not bought:
			return


static func full_board_intent(harness: Variant) -> RunPresentationIntent:
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
	)
	var current := snapshot(harness)
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	if current == null or current.roster == null:
		intent.board = BoardState.new(placements)
		return intent
	var ordered: Array[String] = []
	for placement: BoardPlacementState in current.roster.board.placements:
		if not ordered.has(placement.unit_instance_id):
			ordered.append(placement.unit_instance_id)
	for instance_id: String in current.roster.bench_unit_instance_ids:
		if not ordered.has(instance_id):
			ordered.append(instance_id)
	var capacity := maxi(0, current.economy.level if current.economy != null else 0)
	var deployable := mini(ordered.size(), capacity)
	for index: int in range(ordered.size()):
		if index < deployable:
			@warning_ignore("integer_division")
			var row: int = index / BoardPreparationValidator.BOARD_WIDTH
			placements.append(BoardPlacementState.new(
				row,
				index % BoardPreparationValidator.BOARD_WIDTH,
				ordered[index]
			))
		else:
			bench.append(ordered[index])
	intent.board = BoardState.new(placements)
	intent.bench_unit_instance_ids.assign(bench)
	return intent


## 播放節奏測試用的合成 transcript：每個 canonical tick 恰一個事件，
## 讓「倍率只改 presentation 消費速率」可以被精確斷言。
static func identity() -> BattleTranscriptIdentity:
	var value := BattleTranscriptIdentity.new()
	value.run_id = &"run.g2.combat-flow"
	value.battle_setup_hash = (
		"cccccccccccccccccccccccccccccccc"
		+ "cccccccccccccccccccccccccccccccc"
	)
	value.committed_result_digest = "result.digest.g2.combat-flow"
	value.resolution_identity = &"resolution.g2.combat-flow"
	return value


static func tick_events(count: int) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for index: int in range(count):
		var event := BattleEvent.new()
		event.tick = index
		event.sequence = index
		event.type = &"damage"
		event.target_instance_ids.assign([&"u_0000000000000001"])
		var payload := DamageEventPayload.new()
		payload.damage_type = &"physical"
		payload.raw_amount = 10 + index
		payload.post_resistance_amount = 10 + index
		payload.health_damage = 10 + index
		payload.health_after = 500 - index
		event.payload = payload
		result.append(event)
	return result


static func install_transcript(
	test: GutTest,
	session: RunPresentationSession,
	source: Array[BattleEvent],
	transcript_identity: BattleTranscriptIdentity
) -> void:
	var accumulator := PendingBattleTranscriptAccumulator.new(source.size())
	test.assert_true(accumulator.append_events(source))
	var installed: Variant = session.call(
		&"_accept_committed_transcript",
		accumulator,
		transcript_identity,
		accumulator.encoded_byte_count()
	)
	test.assert_true(installed != null and bool(installed.get("ok")))


static func cursor(session: RunPresentationSession) -> int:
	var state := session.try_playback()
	return state.state.cursor if state.ok and state.state != null else -1


static func error_code(result: Variant) -> StringName:
	if result == null or not result is Object:
		return &""
	var error: Variant = (result as Object).get("error")
	if error == null:
		return &""
	var source: Variant = (error as Object).get("source_code")
	return StringName(source) if source != null else &""

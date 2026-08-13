extends GutTest

## G2 F3（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## 自動 SETTLE 失敗以前完全沒有出口——`_settle_requested` 已為 true，`_process`
## 之後永遠 early-return；`_settle_result` 全庫只有測試在讀，不進狀態列、不重試。
## 玩家停在一場播完的戰鬥前面，零錯誤訊息，唯一出路是放棄整場 run
## （RUN_COMBAT 的常駐動作只有 pause／inspect／speed；離場在系統選單，沒有手動 settle）。
##
## 修法：失敗接進狀態列，並以固定間隔重試。exactly-once 由 domain 端保證，
## 呈現層的重試在第一次成功之後就停止——本檔第三個斷言段落證明它不會二次結算。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)
## 重試間隔（毫秒）。與 RunCombatScreen.SETTLE_RETRY_INTERVAL_MS 同值，
## 由 test_retry_interval_matches_the_screen_contract 釘住。
const RETRY_MS: float = 500.0


## 播放一律回「已耗盡」，讓畫面立刻走到 SETTLE。
class ExhaustedPlaybackPort:
	extends LiveScreenPlaybackPort
	var paused: bool = false
	var exhausted: bool = true
	var queued_events: Array = []

	func try_playback() -> BattlePlaybackStateResult:
		var state := BattlePlaybackState.new()
		state.paused = paused
		return BattlePlaybackStateResult.new(true, state, null)

	func advance_playback(_delta_ms: float) -> BattleEventWindowResult:
		var window := BattleEventWindow.new()
		window.events = queued_events.duplicate(true)
		queued_events.clear()
		window.exhausted = exhausted and not paused
		return BattleEventWindowResult.new(true, window, null)

	func set_paused(value: bool) -> BattlePlaybackCommandResult:
		paused = value
		return BattlePlaybackCommandResult.success()


## 前 `failures` 次 SETTLE 具名失敗，之後成功；全程計次。
class CountingIntentPort:
	extends LiveScreenIntentPort

	var failures_remaining: int = 0
	var settle_dispatches: int = 0
	var snapshot: RunPresentationSnapshot

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		if intent == null \
			or intent.kind != RunPresentationIntent.Kind.SETTLE_BATTLE:
			return RunPresentationResult.failure(DiagnosticError.new(
				&"G2_UNEXPECTED_INTENT",
				&"error.presentation.app_action"
			))
		settle_dispatches += 1
		if failures_remaining > 0:
			failures_remaining -= 1
			return RunPresentationResult.precommit_failure(
				DiagnosticError.new(
					&"SETTLE_SAVE_FAULT",
					&"error.presentation.app_action"
				),
				snapshot
			)
		return RunPresentationResult.success(snapshot)


func test_retry_interval_matches_the_screen_contract() -> void:
	assert_eq(RunCombatScreen.SETTLE_RETRY_INTERVAL_MS, RETRY_MS)
	assert_eq(RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS, 750.0)


func test_visibility_contract_settles_at_750ms_not_749ms() -> void:
	var fixture := _combat_fixture(0)
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	if combat == null or port == null:
		return
	assert_true(await _await_world_frame(combat))
	combat.advance_playback_frame(749.0)
	assert_eq(port.settle_dispatches, 0)
	assert_eq(combat.visible_playback_elapsed_ms(), 749.0)
	combat.advance_playback_frame(1.0)
	assert_eq(port.settle_dispatches, 1)
	assert_not_null(combat.settle_result())


func test_invalid_world_projection_fails_composition_before_playback() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var snapshot := Support.snapshot(harness)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var invalid := snapshot.deep_clone()
	invalid.combat_inspections.append(null)
	var combat := RunCombatScreen.new()
	assert_eq(
		combat.compose(invalid, LiveScreenIntentPort.new()),
		CombatWorldEventProjection.INITIAL_SNAPSHOT_INVALID
	)
	assert_eq(
		combat.world_board_mount_error(),
		CombatWorldEventProjection.INITIAL_SNAPSHOT_INVALID
	)
	assert_false(combat.world_board_ready())
	combat.free()


func test_mount_must_succeed_before_first_frame_clock_and_settlement() -> void:
	var fixture := _combat_fixture(0, false, true)
	var screen := fixture.get("screen") as ProductionScreen
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	var surface := fixture.get("disabled_surface") as ProductionWorldSurface
	if screen == null or combat == null or port == null or surface == null:
		return
	await wait_process_frames(2)
	assert_false(combat.world_board_ready())
	assert_false(combat.has_presented_first_frame())
	assert_eq(combat.world_board_mount_error(), WorldBoardMountAdapter.SURFACE_MISSING)

	combat.advance_playback_frame(1000.0)
	assert_eq(combat.visible_playback_elapsed_ms(), 0.0)
	assert_eq(port.settle_dispatches, 0)

	# Recover the exact world consumer. A successful mount clears only the render
	# report this combat composition emitted and schedules a real draw latch.
	surface.add_to_group(ProductionWorldSurface.MOUNT_GROUP)
	combat.call(&"_mount_world_board")
	assert_true(await _await_world_frame(combat))
	assert_true(combat.world_board_ready())
	assert_true(combat.has_presented_first_frame())
	assert_eq(combat.world_board_mount_error(), &"")
	assert_true(screen.status_message_text().is_empty())
	combat.advance_playback_frame(749.0)
	assert_eq(port.settle_dispatches, 0)
	combat.advance_playback_frame(1.0)
	assert_eq(port.settle_dispatches, 1)


func test_mount_recovery_does_not_clear_a_newer_action_status() -> void:
	var fixture := _combat_fixture(0, false, true)
	var screen := fixture.get("screen") as ProductionScreen
	var combat := fixture.get("combat") as RunCombatScreen
	var surface := fixture.get("disabled_surface") as ProductionWorldSurface
	if screen == null or combat == null or surface == null:
		return
	await wait_process_frames(2)
	assert_eq(
		StringName(screen.status_report().get("source_code", &"")),
		&"RENDER_FAILED"
	)
	screen.report_composition_result(AppActionResult.failure(DiagnosticError.new(
		&"NEWER_ACTION_FAILED",
		&"error.presentation.app_action"
	)))
	var newer_report := screen.status_report().duplicate(true)
	surface.add_to_group(ProductionWorldSurface.MOUNT_GROUP)
	combat.call(&"_mount_world_board")
	assert_true(await _await_world_frame(combat))
	assert_true(combat.world_board_ready())
	assert_eq(screen.status_report(), newer_report)


func test_advance_playback_window_reduces_and_mounts_authoritative_event() -> void:
	var fixture := _combat_fixture(0)
	var combat := fixture.get("combat") as RunCombatScreen
	var playback_port := fixture.get("playback_port") as ExhaustedPlaybackPort
	var snapshot := fixture.get("snapshot") as RunPresentationSnapshot
	var surface := _world_surface()
	assert_not_null(
		surface,
		"the production fixture must retain its unique world surface in COMBAT"
	)
	if surface == null:
		return
	if combat == null or playback_port == null or snapshot == null:
		return
	assert_true(await _await_world_frame(combat))
	assert_false(snapshot.combat_inspections.is_empty())
	if snapshot.combat_inspections.is_empty():
		return
	var inspection := snapshot.combat_inspections[0]
	assert_not_null(inspection)
	if inspection == null:
		return
	var target_id := inspection.presentation_instance_id
	var original_health := int(inspection.stats.get("health", -1))
	assert_false(target_id.is_empty())
	assert_gt(original_health, 0)
	playback_port.exhausted = false
	playback_port.queued_events.append(_damage_event(target_id, 0))

	var result := combat.advance_playback_frame(1.0)
	assert_true(result.ok)
	assert_eq(result.window.events.size(), 1)
	assert_eq(combat.world_board_mount_error(), &"")
	var mounted := surface.snapshot_clone()
	var rendered_health := -1
	for unit: WorldBoardUnitSnapshot in mounted.units:
		if unit.presentation_instance_id == target_id:
			rendered_health = unit.health
			break
	assert_eq(rendered_health, 0)
	assert_eq(
		int(inspection.stats.get("health", 0)),
		original_health,
		"the authoritative setup clone must not be mutated by presentation"
	)


func test_paused_playback_does_not_advance_visibility_clock() -> void:
	var fixture := _combat_fixture(0, true)
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	var playback_port := fixture.get("playback_port") as ExhaustedPlaybackPort
	if combat == null or port == null or playback_port == null:
		return
	assert_true(await _await_world_frame(combat))
	combat.advance_playback_frame(1000.0)
	assert_eq(combat.visible_playback_elapsed_ms(), 0.0)
	assert_eq(port.settle_dispatches, 0)
	playback_port.paused = false
	combat.advance_playback_frame(749.0)
	assert_eq(port.settle_dispatches, 0)
	combat.advance_playback_frame(1.0)
	assert_eq(port.settle_dispatches, 1)


func test_settle_retry_freezes_while_paused_or_system_menu_blocks_background() -> void:
	var fixture := _combat_fixture(2)
	var screen := fixture.get("screen") as ProductionScreen
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	var playback_port := fixture.get("playback_port") as ExhaustedPlaybackPort
	if screen == null or combat == null or port == null or playback_port == null:
		return
	assert_true(await _await_world_frame(combat))
	combat.advance_playback_frame(RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS)
	assert_eq(port.settle_dispatches, 1)
	assert_true(combat.settle_retry_pending())

	playback_port.paused = true
	combat.advance_presentation_frame(RETRY_MS * 4.0)
	assert_eq(port.settle_dispatches, 1)
	playback_port.paused = false

	assert_true(screen.open_system_menu())
	assert_true(screen.is_background_input_blocked())
	combat.advance_presentation_frame(RETRY_MS * 4.0)
	assert_eq(port.settle_dispatches, 1)
	assert_true(screen.close_system_menu())
	assert_false(screen.is_background_input_blocked())

	combat.advance_presentation_frame(RETRY_MS - 1.0)
	assert_eq(port.settle_dispatches, 1)
	combat.advance_presentation_frame(1.0)
	assert_eq(port.settle_dispatches, 2)


func test_initial_settle_waits_for_every_system_menu_state_and_confirmation_modal() -> void:
	for menu_state: int in [
		SystemMenuOverlay.State.ROOT,
		SystemMenuOverlay.State.SETTINGS_EMBEDDED,
		SystemMenuOverlay.State.CONFIRM_MENU,
		SystemMenuOverlay.State.CONFIRM_EXIT,
	]:
		var fixture := _combat_fixture(0)
		var screen := fixture.get("screen") as ProductionScreen
		var combat := fixture.get("combat") as RunCombatScreen
		var port := fixture.get("intent_port") as CountingIntentPort
		var playback := fixture.get("playback_port") as ExhaustedPlaybackPort
		if screen == null or combat == null or port == null or playback == null:
			return
		assert_true(await _await_world_frame(combat))
		playback.exhausted = false
		combat.advance_playback_frame(RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS)
		assert_eq(port.settle_dispatches, 0)
		assert_true(screen.open_system_menu())
		var overlay := screen.system_menu_overlay()
		assert_not_null(overlay)
		if overlay == null:
			return
		overlay.call(&"_set_state", menu_state)
		combat.set(&"_settlement_pending_visibility_contract", true)
		combat.advance_presentation_frame(RETRY_MS * 4.0)
		assert_eq(
			port.settle_dispatches,
			0,
			"initial settlement must stay blocked in system-menu state %d"
				% menu_state
		)
		assert_true(screen.close_system_menu())
		playback.exhausted = true
		combat.advance_presentation_frame(0.0)
		assert_eq(port.settle_dispatches, 1)
		await _dispose_combat_fixture(fixture)

	var modal_fixture := _combat_fixture(0)
	var modal_screen := modal_fixture.get("screen") as ProductionScreen
	var modal_combat := modal_fixture.get("combat") as RunCombatScreen
	var modal_port := modal_fixture.get("intent_port") as CountingIntentPort
	if modal_screen == null or modal_combat == null or modal_port == null:
		return
	assert_true(await _await_world_frame(modal_combat))
	modal_screen.set(&"_modal_open", true)
	modal_combat.advance_playback_frame(
		RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS
	)
	assert_eq(modal_port.settle_dispatches, 0)
	modal_screen.set(&"_modal_open", false)
	modal_combat.advance_presentation_frame(0.0)
	assert_eq(modal_port.settle_dispatches, 1)
	await _dispose_combat_fixture(modal_fixture)


func test_failed_settle_is_visible_and_retries_until_it_lands_exactly_once() -> void:
	var fixture := _combat_fixture(2)
	var screen := fixture.get("screen") as ProductionScreen
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	if screen == null or combat == null or port == null:
		return
	assert_true(await _await_world_frame(combat))

	# 播放耗盡 → 第一次 SETTLE，失敗。
	combat.advance_playback_frame(RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS)
	assert_eq(port.settle_dispatches, 1)
	var first_settle := combat.settle_result()
	assert_not_null(first_settle)
	if first_settle == null:
		return
	assert_false(first_settle.ok)
	assert_true(combat.settle_retry_pending(), "a failed settle must stay retryable")
	assert_false(
		screen.status_message_text().is_empty(),
		"a failed settle must reach the player-visible status surface"
	)
	assert_eq(
		StringName(screen.status_report().get("source_code", &"")),
		&"SETTLE_SAVE_FAULT"
	)

	# 冷卻未到不重送（否則每一影格都在重送被拒絕的命令）。
	combat.advance_presentation_frame(RETRY_MS * 0.5)
	assert_eq(port.settle_dispatches, 1)

	# 冷卻到期 → 第二次，仍失敗，訊息還在。
	combat.advance_presentation_frame(RETRY_MS)
	assert_eq(port.settle_dispatches, 2)
	assert_true(combat.settle_retry_pending())
	assert_false(screen.status_message_text().is_empty())

	# 第三次成功：狀態列清空，且之後再多影格也不會有第四次 dispatch。
	combat.advance_presentation_frame(RETRY_MS)
	assert_eq(port.settle_dispatches, 3)
	assert_true(combat.settle_result().ok)
	assert_false(combat.settle_retry_pending())
	assert_eq(
		screen.status_message_text(),
		"",
		"a successful retry must clear the error surface"
	)
	for _frame: int in 10:
		combat.advance_presentation_frame(RETRY_MS * 2.0)
	assert_eq(
		port.settle_dispatches,
		3,
		"exactly-once: a settled battle must never be dispatched again"
	)


func test_playback_stops_driving_once_settle_is_requested() -> void:
	var fixture := _combat_fixture(1)
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	if combat == null or port == null:
		return
	assert_true(await _await_world_frame(combat))
	combat.advance_playback_frame(RunCombatScreen.MIN_VISIBLE_PLAYBACK_MS)
	assert_eq(port.settle_dispatches, 1)
	# single-flight 仍然成立：SETTLE 已請求後，播放推進一律具名拒絕。
	var stale := combat.advance_playback_frame(RETRY_MS)
	assert_false(stale.ok)
	assert_eq(
		Support.error_code(stale),
		ProductionScreen.SCREEN_NOT_ACTIVE
	)
	assert_eq(port.settle_dispatches, 1)


## 用真實 COMBAT snapshot（走完整 MAP→PREPARE→COMBAT）組一個獨立的 RUN_COMBAT
## 畫面，只有 playback／intent 兩個 port 換成可控樁——SETTLE 的失敗與成功都要能
## 精確安排，真實 run 做不到。
func _combat_fixture(
	settle_failures: int,
	playback_paused: bool = false,
	disable_world_surface: bool = false
) -> Dictionary:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var production_combat := Support.composition(harness) as RunCombatScreen
	assert_not_null(
		production_combat,
		"the formal RUN_COMBAT route must own a RunCombatScreen composition"
	)
	if production_combat == null:
		return {}
	# This fixture replaces the formal playback/intent ports with controlled
	# test doubles. Keep the production composition mounted, but prevent its
	# real driver from advancing the same run behind the controlled screen.
	production_combat.set_process(false)
	var snapshot := Support.snapshot(harness)
	assert_not_null(snapshot)
	if snapshot == null:
		return {}
	assert_eq(snapshot.app_phase, &"COMBAT")
	if snapshot.app_phase != &"COMBAT":
		return {}

	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(screen)
	if screen == null:
		return {}
	var localized: Dictionary = {}
	for action_id: StringName in [
		&"combat.pause",
		&"combat.inspect",
		&"combat.speed",
		&"system_menu.open",
		&"system_menu.title",
		&"system_menu.continue",
		&"system_menu.settings",
	]:
		localized[action_id] = String(action_id)
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"RUN_COMBAT",
				snapshot,
				null,
				&"zh_TW",
				localized
			)
		),
		&""
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 908)
	var intent_port := CountingIntentPort.new(lease, registry, null, Callable())
	intent_port.failures_remaining = settle_failures
	intent_port.snapshot = snapshot
	var playback_port := ExhaustedPlaybackPort.new(lease, registry, null)
	playback_port.paused = playback_paused
	var disabled_surface := _world_surface() if disable_world_surface else null
	if disable_world_surface:
		assert_not_null(
			disabled_surface,
			"the production fixture must retain its unique world surface in COMBAT"
		)
		if disabled_surface == null:
			return {}
		disabled_surface.remove_from_group(ProductionWorldSurface.MOUNT_GROUP)
	assert_eq(
		screen.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"RUN_COMBAT",
				snapshot,
				null,
				ProductionScreenActionPort.new(lease, registry, {}),
				LiveScreenNavigationPort.new(),
				intent_port,
				playback_port
			)
		),
		&""
	)
	add_child_autofree(screen)
	screen.activate_live()
	var combat := screen.get_node_or_null("Composition") as RunCombatScreen
	assert_not_null(combat)
	if combat == null:
		return {}
	# 影格驅動改由測試以固定 delta 呼叫，避免真實影格時間讓重試次數不可預期。
	combat.set_process(false)
	return {
		"harness": harness,
		"screen": screen,
		"combat": combat,
		"intent_port": intent_port,
		"playback_port": playback_port,
		"snapshot": snapshot.deep_clone(),
		"disabled_surface": disabled_surface,
	}


func _world_surface() -> ProductionWorldSurface:
	for node: Node in get_tree().get_nodes_in_group(
		ProductionWorldSurface.MOUNT_GROUP
	):
		if node is ProductionWorldSurface:
			return node as ProductionWorldSurface
	return null


func _dispose_combat_fixture(fixture: Dictionary) -> void:
	var screen := fixture.get("screen") as ProductionScreen
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	var harness: Variant = fixture.get("harness")
	if (
		harness != null
		and harness.main is Node
		and is_instance_valid(harness.main)
	):
		(harness.main as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _await_world_frame(combat: RunCombatScreen) -> bool:
	if combat == null:
		return false
	for _frame: int in 12:
		if combat.world_board_ready() and combat.has_presented_first_frame():
			return true
		await wait_process_frames(1)
	return combat.world_board_ready() and combat.has_presented_first_frame()


func _damage_event(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"damage"
	event.target_instance_ids.assign([target_id])
	var payload := DamageEventPayload.new()
	payload.damage_type = &"physical"
	payload.health_after = health_after
	event.payload = payload
	return event

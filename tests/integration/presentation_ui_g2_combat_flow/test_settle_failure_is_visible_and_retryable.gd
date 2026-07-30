extends GutTest

## G2 F3（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## 自動 SETTLE 失敗以前完全沒有出口——`_settle_requested` 已為 true，`_process`
## 之後永遠 early-return；`_settle_result` 全庫只有測試在讀，不進狀態列、不重試。
## 玩家停在一場播完的戰鬥前面，零錯誤訊息，唯一出路是放棄整場 run
## （RUN_COMBAT 的動作只有 pause／inspect／speed／run.menu，沒有手動 settle）。
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

	func advance_playback(_delta_ms: float) -> BattleEventWindowResult:
		var window := BattleEventWindow.new()
		window.exhausted = true
		return BattleEventWindowResult.new(true, window, null)


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


func test_failed_settle_is_visible_and_retries_until_it_lands_exactly_once() -> void:
	var fixture := _combat_fixture(2)
	var screen := fixture.get("screen") as ProductionScreen
	var combat := fixture.get("combat") as RunCombatScreen
	var port := fixture.get("intent_port") as CountingIntentPort
	if screen == null or combat == null or port == null:
		return

	# 播放耗盡 → 第一次 SETTLE，失敗。
	combat.advance_playback_frame(RETRY_MS)
	assert_eq(port.settle_dispatches, 1)
	assert_false(combat.settle_result().ok)
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
	combat.advance_playback_frame(RETRY_MS)
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
func _combat_fixture(settle_failures: int) -> Dictionary:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
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
		&"run.menu",
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
	assert_eq(
		screen.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"RUN_COMBAT",
				snapshot,
				null,
				ProductionScreenActionPort.new(lease, registry, {}),
				LiveScreenNavigationPort.new(),
				intent_port,
				ExhaustedPlaybackPort.new(lease, registry, null)
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
	}

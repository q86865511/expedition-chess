extends GutTest

## G2 H1：merge 9362e7d 後的獨立審查確認正式 UI 的戰鬥流程是死結——
## drive_current_combat_to_commit() 唯一非測試呼叫者是 dev 灰盒、SETTLE_BATTLE 只有灰盒
## dispatch、presentation 全樹沒有任何 _process／Timer，玩家進 COMBAT 後永遠停在 tick 0、
## REWARD 不可達。本檔把整條正式路徑（AppRoot ＋ production facade ＋ formal screen，
## 不經 scripts/dev）從開局推到 SETTLE 後的 REWARD 路由。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)
const DRIVE_STEP_MS: float = 500.0
const DRIVE_STEP_LIMIT: int = 200


func test_formal_combat_screen_drives_playback_and_settles_into_reward() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var screen := Support.active_screen(harness)
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.route_kind,
		&"RUN_COMBAT",
		"START_OR_RESUME_COMBAT must route the formal path into RUN_COMBAT"
	)
	var composition := screen.get_node_or_null("Composition") as RunCombatScreen
	assert_not_null(composition)
	if composition == null:
		return

	# commit-before-present：模擬已在 intent 內跑到 result 提交，畫面拿到的是已提交
	# transcript，而不是一場還沒開始的戰鬥。
	var playback := composition.try_playback()
	assert_true(playback.ok, "the formal combat screen must own a committed transcript")
	if not playback.ok:
		return
	assert_eq(playback.state.cursor, 0)
	assert_not_null(playback.state.transcript_identity)

	# 真的有 frame 驅動器：不需要任何測試專用呼叫，光是進樹跑 frame 就會推進 cursor。
	assert_true(
		composition.is_processing(),
		"the formal combat screen must drive playback from the scene tree"
	)
	await wait_process_frames(6)
	assert_gt(
		composition.try_playback().state.cursor,
		0,
		"scene-tree frames alone must advance the committed playback cursor"
	)

	var settled := false
	for _step: int in range(DRIVE_STEP_LIMIT):
		var window := composition.advance_playback_frame(DRIVE_STEP_MS)
		if not window.ok:
			settled = true
			break
		if window.window != null and window.window.exhausted:
			settled = true
			break
	assert_true(settled, "playback must reach the end of the committed transcript")

	var settle_result: RunPresentationResult = composition.settle_result()
	assert_not_null(
		settle_result,
		"finished playback must dispatch SETTLE_BATTLE through the typed intent port"
	)
	if settle_result != null:
		assert_true(settle_result.ok, String(Support.error_code(settle_result)))
	var after := Support.active_screen(harness)
	assert_not_null(after)
	if after == null:
		return
	# difficulty-curve 之後首戰勝負依內容 TUNE 而定（多敵編成）：勝→REWARD、
	# 非 Boss 敗且遠征 HP>0→MAP，兩者都是 settle 的合法路由。REWARD 畫面本身的
	# 覆蓋在 presentation_ui_run_screens／nonterminal_scene_composition 等套件。
	var after_snapshot := Support.snapshot(harness)
	if after.route_kind == &"RUN_REWARD":
		assert_eq(after_snapshot.app_phase, &"REWARD")
	else:
		assert_eq(
			after.route_kind,
			&"RUN_MAP",
			"settling must route to REWARD (win) or MAP (non-boss loss), got %s"
				% String(after.route_kind)
		)
		assert_eq(after_snapshot.app_phase, &"MAP")
	var stale := composition.advance_playback_frame(DRIVE_STEP_MS)
	assert_false(stale.ok, "the replaced screen must not keep draining after the route swap")
	assert_eq(Support.error_code(stale), LiveScreenPlaybackPort.SCREEN_NOT_ACTIVE)


func test_committed_result_without_transcript_still_reaches_reward() -> void:
	# design.md §10：已提交 result 重載時沒有 transcript authority，只顯示 committed
	# summary。這條路徑同樣需要驅動器，否則續跑進 COMBAT 的玩家一樣卡死。
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var session: Variant = harness.root.get("_run_presentation_session")
	assert_not_null(session)
	if session == null:
		return
	session.release_playback(&"g2_reload_without_transcript")
	var composition := Support.composition(harness) as RunCombatScreen
	assert_not_null(composition)
	if composition == null:
		return
	var window := composition.advance_playback_frame(DRIVE_STEP_MS)
	assert_false(window.ok)
	assert_eq(
		Support.error_code(window),
		RunPresentationSession.PLAYBACK_NOT_AVAILABLE
	)
	var settle_result: RunPresentationResult = composition.settle_result()
	assert_not_null(settle_result)
	if settle_result != null:
		assert_true(settle_result.ok, String(Support.error_code(settle_result)))
	# 同上：settle 後的合法路由依實際戰果為 REWARD（勝）或 MAP（非 Boss 敗）。
	assert_true(
		Support.active_screen(harness).route_kind in [&"RUN_REWARD", &"RUN_MAP"],
		"settling a committed result must route to REWARD or MAP, got %s"
			% String(Support.active_screen(harness).route_kind)
	)


func test_combat_intel_star_comes_from_the_committed_battle_snapshot() -> void:
	# H4：star 只存在於 UnitBattleSnapshot，之前的投影從未把它寫進 inspection stats，
	# 真實戰鬥資料下 RaritySemantics 恆空。
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var snapshot: RunPresentationSnapshot = Support.snapshot(harness)
	assert_false(
		snapshot.combat_inspections.is_empty(),
		"COMBAT must keep the committed setup projection after the result is recorded"
	)
	if snapshot.combat_inspections.is_empty():
		return
	for inspection: CombatUnitInspectionSnapshot in snapshot.combat_inspections:
		assert_true(
			inspection.stats.has("star"),
			"every inspected unit must expose its committed star tier"
		)
		assert_gt(int(inspection.stats.get("star", 0)), 0)

	var model := RunCombatIntelModel.new()
	assert_eq(model.compose(snapshot), &"")
	var rows := model.inspection_rows()
	assert_false(rows.is_empty())
	if rows.is_empty():
		return
	assert_gt(
		rows[0].star,
		0,
		"the intel model must read star from the real pipeline, not a missing key"
	)
	var composition := Support.composition(harness) as RunCombatScreen
	assert_not_null(composition)
	if composition == null:
		return
	var rarity := composition.get_node_or_null(^"RaritySemantics") as Control
	assert_not_null(rarity)
	if rarity != null:
		assert_gt(
			rarity.get_child_count(),
			0,
			"real combat data must produce non-colour rarity cues"
		)

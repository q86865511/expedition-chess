extends GutTest

## G2 H1（R7）：正式驅動器上線後，1×／2×／4× 與 pause 必須是「presentation 消費速率」
## 的可觀察差異，非法倍率仍是 typed reject 且不動 cursor；暫停時不得判定播放結束
## （否則暫停會自己把戰鬥結算掉）。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)
const TICK_COUNT: int = 200
const ONE_SECOND_MS: float = 1000.0


func _session_with_transcript() -> RunPresentationSession:
	var session := RunPresentationSession.new()
	Support.install_transcript(
		self,
		session,
		Support.tick_events(TICK_COUNT),
		Support.identity()
	)
	return session


func test_speed_multiplier_only_changes_the_presentation_consumption_rate() -> void:
	var base := _session_with_transcript()
	assert_true(base.advance_playback(ONE_SECOND_MS).ok)
	var at_1x := Support.cursor(base)
	assert_eq(
		at_1x,
		BattlePlaybackController.CANONICAL_TICK_RATE + 1,
		"1x must present exactly one canonical second of committed ticks"
	)

	var fast := _session_with_transcript()
	assert_true(fast.set_playback_speed(4).ok)
	assert_true(fast.advance_playback(ONE_SECOND_MS).ok)
	assert_eq(
		Support.cursor(fast),
		BattlePlaybackController.CANONICAL_TICK_RATE * 4 + 1,
		"4x must consume four canonical seconds in the same wall-clock second"
	)
	assert_gt(Support.cursor(fast), at_1x)

	var doubled := _session_with_transcript()
	assert_true(doubled.set_playback_speed(2).ok)
	assert_true(doubled.advance_playback(ONE_SECOND_MS).ok)
	assert_eq(Support.cursor(doubled), BattlePlaybackController.CANONICAL_TICK_RATE * 2 + 1)


func test_paused_playback_freezes_the_cursor_and_never_reports_exhausted() -> void:
	var session := _session_with_transcript()
	assert_true(session.advance_playback(ONE_SECOND_MS).ok)
	var frozen := Support.cursor(session)
	assert_true(session.set_playback_paused(true).ok)
	for _step: int in range(20):
		var window := session.advance_playback(ONE_SECOND_MS)
		assert_true(window.ok)
		if window.window != null:
			assert_false(
				window.window.exhausted,
				"a paused screen must not settle the battle by itself"
			)
			assert_true(window.window.events.is_empty())
	assert_eq(Support.cursor(session), frozen, "pause must only stop the presentation cursor")
	assert_true(session.set_playback_paused(false).ok)
	assert_true(session.advance_playback(ONE_SECOND_MS).ok)
	assert_gt(Support.cursor(session), frozen)


func test_invalid_multiplier_is_typed_and_leaves_playback_untouched() -> void:
	var session := _session_with_transcript()
	assert_true(session.advance_playback(ONE_SECOND_MS).ok)
	var before := session.try_playback().state
	for multiplier: int in [0, -1, -4, 3, 5, 8]:
		var rejected := session.set_playback_speed(multiplier)
		assert_false(rejected.ok, "multiplier %d must be rejected" % multiplier)
		assert_eq(
			Support.error_code(rejected),
			BattlePlaybackController.PLAYBACK_SPEED_INVALID
		)
	var after := session.try_playback().state
	assert_eq(after.cursor, before.cursor)
	assert_eq(after.speed, before.speed)
	assert_eq(after.paused, before.paused)


func test_exhausted_transcript_is_reported_once_the_last_tick_is_presented() -> void:
	var session := _session_with_transcript()
	var exhausted := false
	for _step: int in range(TICK_COUNT + 8):
		var window := session.advance_playback(ONE_SECOND_MS)
		assert_true(window.ok)
		if window.window != null and window.window.exhausted:
			exhausted = true
			break
	assert_true(exhausted)
	assert_eq(Support.cursor(session), TICK_COUNT)


func test_lease_bound_port_forwards_frame_advance_and_goes_stale_with_the_route() -> void:
	var session := _session_with_transcript()
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 2601)
	var port := LiveScreenPlaybackPort.new(lease, registry, session)
	var window := port.advance_playback(ONE_SECOND_MS)
	assert_true(window.ok)
	assert_gt(Support.cursor(session), 0)
	registry.revoke_active()
	var stale := port.advance_playback(ONE_SECOND_MS)
	assert_false(stale.ok)
	assert_eq(Support.error_code(stale), LiveScreenPlaybackPort.SCREEN_NOT_ACTIVE)


func test_frame_advance_without_a_committed_transcript_is_typed() -> void:
	var session := RunPresentationSession.new()
	var window := session.advance_playback(ONE_SECOND_MS)
	assert_false(window.ok)
	assert_eq(
		Support.error_code(window),
		RunPresentationSession.PLAYBACK_NOT_AVAILABLE
	)

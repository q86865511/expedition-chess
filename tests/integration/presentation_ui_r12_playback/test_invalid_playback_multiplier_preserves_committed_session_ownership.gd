extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r12_playback/"
	+ "r12_playback_test_support.gd"
)

const INVALID_MULTIPLIERS: Array[int] = [
	0,
	-1,
	-4,
	3,
	5,
	8,
]


func test_invalid_multiplier_matrix_preserves_committed_session_ownership() -> void:
	var session: Variant = Support.SaveSpySession.new()
	var transcript_identity: BattleTranscriptIdentity = Support.identity()
	var canonical_events: Array[BattleEvent] = Support.events(6)
	var canonical_event_hash: String = Support.event_hash(canonical_events)
	var accumulator: PendingBattleTranscriptAccumulator = (
		Support.install_transcript(
			self,
			session,
			canonical_events,
			transcript_identity
		)
	)
	assert_true(accumulator.is_revoked())
	assert_eq(accumulator.pending_count(), 0)
	assert_eq(accumulator.public_event_count(), 0)

	if not Support.require_session_speed_api(self, session):
		return

	var baseline_command: Variant = session.call(
		Support.SESSION_SPEED_METHOD,
		2
	)
	assert_true(bool(baseline_command.get("ok")))
	var before_playback: BattlePlaybackStateResult = session.try_playback()
	assert_true(before_playback.ok)
	assert_eq(before_playback.state.speed, &"x2")
	var before_cursor: int = before_playback.state.cursor
	var before_paused: bool = before_playback.state.paused
	var before_save_fingerprint: String = Support.snapshot_fingerprint(
		session.snapshot()
	)

	for multiplier: int in INVALID_MULTIPLIERS:
		var rejected: Variant = session.call(
			Support.SESSION_SPEED_METHOD,
			multiplier
		)
		assert_false(
			bool(rejected.get("ok")),
			"invalid playback multiplier %d must be rejected" % multiplier
		)
		assert_eq(
			Support.error_code(rejected),
			&"PLAYBACK_SPEED_INVALID",
			"all invalid multiplier categories use one stable named error"
		)
		var after: BattlePlaybackStateResult = session.try_playback()
		assert_true(after.ok)
		assert_eq(after.state.speed, &"x2")
		assert_eq(after.state.cursor, before_cursor)
		assert_eq(after.state.paused, before_paused)
		assert_true(
			Support.same_identity(
				after.state.transcript_identity,
				transcript_identity
			)
		)
		assert_eq(
			after.state.transcript_identity.committed_result_digest,
			transcript_identity.committed_result_digest
		)
		assert_eq(
			Support.snapshot_fingerprint(session.snapshot()),
			before_save_fingerprint,
			"presentation speed rejection must not change save-facing state"
		)
		assert_eq(
			session.dispatch_count,
			0,
			"presentation speed rejection must dispatch zero gameplay writes"
		)
		assert_true(accumulator.is_revoked())
		assert_eq(accumulator.pending_count(), 0)

	before_playback.state.transcript_identity.run_id = &"consumer.mutation"
	assert_true(
		Support.same_identity(
			session.try_playback().state.transcript_identity,
			transcript_identity
		),
		"try_playback must keep returning clone-only transcript identity"
	)

	var drained: BattleEventWindowResult = session.drain_playback_window(
		transcript_identity,
		canonical_events.size()
	)
	assert_true(drained.ok)
	assert_eq(drained.window.events.size(), canonical_events.size())
	assert_eq(
		Support.event_hash(drained.window.events),
		canonical_event_hash,
		"rejected speed commands must preserve committed event bytes and order"
	)
	assert_eq(
		Support.event_hash(canonical_events),
		canonical_event_hash,
		"transcript ownership transfer must not alias the fixture producer"
	)
	assert_eq(session.dispatch_count, 0)

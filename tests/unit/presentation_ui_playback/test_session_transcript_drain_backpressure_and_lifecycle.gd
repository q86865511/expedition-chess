extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_playback/playback_test_support.gd"
)


func test_session_drain_is_identity_checked_clone_only_and_backpressured() -> void:
	var accumulator_script := Support.load_script(self, Support.ACCUMULATOR_PATH)
	if accumulator_script == null:
		return
	var source := Support.events(5000)
	var expected_signatures := Support.event_signatures(source)
	var accumulator: Variant = accumulator_script.new(6000)
	if not Support.append_events(self, accumulator, source):
		return
	source[0].sequence = 999
	source.clear()
	var session := RunPresentationSession.new()
	var transcript_identity := Support.identity("drain")
	var installed: Variant = Support.install_transcript(
		self,
		session,
		accumulator,
		transcript_identity,
		5000 * 32
	)
	if installed == null or not bool(installed.get("ok")):
		assert_true(false, "within-budget committed transcript must install")
		return

	var playback_a := session.try_playback()
	var playback_b := session.try_playback()
	assert_true(playback_a.ok)
	assert_true(playback_b.ok)
	assert_ne(playback_a.state, playback_b.state)
	assert_ne(
		playback_a.state.transcript_identity,
		playback_b.state.transcript_identity
	)
	playback_a.state.transcript_identity.run_id = &"consumer.mutation"
	assert_true(Support.same_identity(
		session.try_playback().state.transcript_identity,
		transcript_identity
	))

	for invalid_count: int in [0, -1, 4097]:
		var invalid := session.drain_playback_window(
			transcript_identity,
			invalid_count
		)
		assert_false(invalid.ok)
		assert_eq(
			Support.error_code(invalid),
			&"PLAYBACK_WINDOW_COUNT_INVALID"
		)
	assert_eq(
		session.try_playback().state.cursor,
		0,
		"rejected drains must not advance the private cursor"
	)

	var stale_identities: Array[BattleTranscriptIdentity] = []
	var wrong_run := transcript_identity.deep_clone()
	wrong_run.run_id = &"run.stale"
	stale_identities.append(wrong_run)
	var wrong_setup := transcript_identity.deep_clone()
	wrong_setup.battle_setup_hash = "setup-stale"
	stale_identities.append(wrong_setup)
	var wrong_result := transcript_identity.deep_clone()
	wrong_result.committed_result_digest = "result-stale"
	stale_identities.append(wrong_result)
	var wrong_resolution := transcript_identity.deep_clone()
	wrong_resolution.resolution_identity = &"resolution.stale"
	stale_identities.append(wrong_resolution)
	for stale_identity: BattleTranscriptIdentity in stale_identities:
		var stale := session.drain_playback_window(stale_identity, 1)
		assert_false(stale.ok)
		assert_eq(Support.error_code(stale), &"PLAYBACK_IDENTITY_MISMATCH")
		assert_eq(session.try_playback().state.cursor, 0)

	var first := session.drain_playback_window(transcript_identity, 4096)
	var second := session.drain_playback_window(transcript_identity, 4096)
	assert_true(first.ok)
	assert_true(second.ok)
	assert_eq(first.window.events.size(), 4096)
	assert_eq(second.window.events.size(), 904)
	assert_false(first.window.exhausted)
	assert_true(second.window.exhausted)
	var combined: Array = []
	combined.append_array(first.window.events)
	combined.append_array(second.window.events)
	assert_eq(
		Support.event_signatures(combined),
		expected_signatures,
		"backpressure windows must not lose, duplicate, or reorder rule events"
	)
	first.window.events[0].sequence = 777
	assert_eq(
		expected_signatures[0],
		"0:0:move",
		"drain windows must be deep-cloned consumer values"
	)


func test_new_battle_leave_revoke_acknowledge_and_reload_have_no_transcript() -> void:
	var accumulator_script := Support.load_script(self, Support.ACCUMULATOR_PATH)
	if accumulator_script == null:
		return
	for reason: StringName in [
		&"new_battle",
		&"leave_combat",
		&"session_revoke",
		&"result_acknowledge",
	]:
		var accumulator: Variant = accumulator_script.new(4)
		if not Support.append_events(self, accumulator, Support.events(1)):
			return
		var session := RunPresentationSession.new()
		var installed: Variant = Support.install_transcript(
			self,
			session,
			accumulator,
			Support.identity(String(reason)),
			64
		)
		if installed == null:
			return
		assert_true(bool(installed.get("ok")))
		assert_true(session.try_playback().ok)
		session.release_playback(reason)
		var released := session.try_playback()
		assert_false(released.ok, "%s must release transcript" % String(reason))
		assert_eq(Support.error_code(released), &"PLAYBACK_NOT_AVAILABLE")

	var reloaded_session := RunPresentationSession.new()
	var reloaded := reloaded_session.try_playback()
	assert_false(reloaded.ok)
	assert_eq(
		Support.error_code(reloaded),
		&"PLAYBACK_NOT_AVAILABLE",
		"committed result reload must not synthesize a transcript"
	)
	# R12-A01/A02 terminal/RESULTS ownership is intentionally excluded.

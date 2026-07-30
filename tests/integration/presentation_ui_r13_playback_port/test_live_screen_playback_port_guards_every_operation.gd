extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_playback_port/"
	+ "r13_playback_port_test_support.gd"
)

const INVALID_MULTIPLIERS: Array[int] = [0, -1, -4, 3, 5, 8]
const VALID_MULTIPLIERS: Array[int] = [1, 2, 4]


func test_session_exposes_typed_pause_without_raw_controller_access() -> void:
	var session: Variant = Support.SaveSpySession.new()
	Support.install_transcript(
		self,
		session,
		Support.events(6),
		Support.identity()
	)
	var present: bool = session.has_method(&"set_playback_paused")
	assert_true(
		present,
		"RunPresentationSession must expose typed set_playback_paused(bool)"
	)
	if not present:
		return
	var paused: Variant = session.call(&"set_playback_paused", true)
	assert_true(bool(paused.get("ok")))
	assert_true(session.try_playback().state.paused)
	var resumed: Variant = session.call(&"set_playback_paused", false)
	assert_true(bool(resumed.get("ok")))
	assert_false(session.try_playback().state.paused)
	assert_eq(session.dispatch_count, 0)


func test_live_port_validates_speed_pause_and_clone_only_read() -> void:
	var port_script := Support.require_port_script(self)
	if port_script == null:
		return
	var session: Variant = Support.SaveSpySession.new()
	var transcript_identity: BattleTranscriptIdentity = Support.identity()
	Support.install_transcript(
		self,
		session,
		Support.events(6),
		transcript_identity
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 7)
	var port: Variant = Support.make_port(
		self,
		port_script,
		lease,
		registry,
		session
	)
	if port == null:
		return

	for multiplier: int in VALID_MULTIPLIERS:
		var accepted: Variant = port.call(&"set_speed", multiplier)
		assert_true(bool(accepted.get("ok")))
		var accepted_state: BattlePlaybackStateResult = port.call(&"try_playback")
		assert_true(accepted_state.ok)
		assert_eq(
			accepted_state.state.speed,
			StringName("x%d" % multiplier)
		)

	var baseline: BattlePlaybackStateResult = port.call(&"try_playback")
	assert_true(baseline.ok)
	assert_eq(baseline.state.speed, &"x4")
	var baseline_fingerprint := Support.state_fingerprint(baseline.state)
	var save_fingerprint := Support.snapshot_fingerprint(session.snapshot())
	for multiplier: int in INVALID_MULTIPLIERS:
		var rejected: Variant = port.call(&"set_speed", multiplier)
		assert_false(bool(rejected.get("ok")))
		assert_eq(
			Support.error_code(rejected),
			&"PLAYBACK_SPEED_INVALID"
		)
		assert_eq(
			Support.state_fingerprint(port.call(&"try_playback").state),
			baseline_fingerprint
		)
		assert_eq(
			Support.snapshot_fingerprint(session.snapshot()),
			save_fingerprint
		)

	var paused: Variant = port.call(&"set_paused", true)
	assert_true(bool(paused.get("ok")))
	assert_true(port.call(&"try_playback").state.paused)
	var resumed: Variant = port.call(&"set_paused", false)
	assert_true(bool(resumed.get("ok")))
	assert_false(port.call(&"try_playback").state.paused)
	var consumer_state: BattlePlaybackStateResult = port.call(&"try_playback")
	consumer_state.state.transcript_identity.run_id = &"consumer.mutation"
	assert_true(
		Support.same_identity(
			port.call(&"try_playback").state.transcript_identity,
			transcript_identity
		),
		"live port returns clone-only playback state"
	)
	assert_eq(session.dispatch_count, 0)


func test_stale_lease_rejects_all_operations_without_side_effects() -> void:
	var port_script := Support.require_port_script(self)
	if port_script == null:
		return
	var session: Variant = Support.SaveSpySession.new()
	var transcript_identity: BattleTranscriptIdentity = Support.identity()
	var canonical_events: Array[BattleEvent] = Support.events(6)
	var canonical_hash := Support.event_hash(canonical_events)
	Support.install_transcript(
		self,
		session,
		canonical_events,
		transcript_identity
	)
	assert_true(session.set_playback_speed(2).ok)
	if not session.has_method(&"set_playback_paused"):
		assert_true(false, "typed pause API must exist before stale-port testing")
		return
	assert_true(bool(session.call(&"set_playback_paused", true).get("ok")))
	var registry := LiveScreenLeaseRegistry.new()
	var stale_lease := registry.activate(AppStateMachine.State.RUN, 11)
	var stale_port: Variant = Support.make_port(
		self,
		port_script,
		stale_lease,
		registry,
		session
	)
	if stale_port == null:
		return
	var before_state: BattlePlaybackStateResult = session.try_playback()
	var before_fingerprint := Support.state_fingerprint(before_state.state)
	var before_save := Support.snapshot_fingerprint(session.snapshot())

	var replacement_lease := registry.activate(AppStateMachine.State.RUN, 12)
	var rejected_results: Array = [
		stale_port.call(&"try_playback"),
		stale_port.call(&"set_speed", 4),
		stale_port.call(&"set_paused", false),
		stale_port.call(&"drain_window", transcript_identity, 3),
	]
	for result: Variant in rejected_results:
		assert_false(bool(result.get("ok")))
		assert_eq(
			Support.error_code(result),
			&"SCREEN_NOT_ACTIVE",
			"every stale lease operation uses the stable screen error"
		)
	assert_eq(
		Support.state_fingerprint(session.try_playback().state),
		before_fingerprint,
		"stale operations preserve speed/cursor/pause/result identity"
	)
	assert_eq(Support.snapshot_fingerprint(session.snapshot()), before_save)
	assert_eq(session.dispatch_count, 0, "playback port dispatches zero gameplay writes")

	var replacement_port: Variant = Support.make_port(
		self,
		port_script,
		replacement_lease,
		registry,
		session
	)
	if replacement_port == null:
		return
	var drained: BattleEventWindowResult = replacement_port.call(
		&"drain_window",
		transcript_identity,
		canonical_events.size()
	)
	assert_true(drained.ok)
	assert_eq(
		Support.event_hash(drained.window.events),
		canonical_hash,
		"stale drain preserves committed event bytes and order"
	)
	assert_true(
		Support.same_identity(drained.window.identity, transcript_identity)
	)
	assert_eq(session.dispatch_count, 0)

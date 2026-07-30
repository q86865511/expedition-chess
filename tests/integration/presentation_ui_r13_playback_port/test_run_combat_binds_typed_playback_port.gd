extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_playback_port/"
	+ "r13_playback_port_test_support.gd"
)


func test_production_combat_screen_binds_live_port_without_raw_session() -> void:
	var port_script := Support.require_port_script(self)
	if port_script == null:
		return
	var screen := Support.combat_composition(self)
	if screen == null:
		return
	for method_name: StringName in [
		&"bind_playback_port",
		&"try_playback",
		&"set_playback_speed",
		&"set_playback_paused",
		&"drain_playback_window",
	]:
		var present: bool = screen.has_method(method_name)
		assert_true(
			present,
			"RUN_COMBAT production binding requires %s" % String(method_name)
		)
		if not present:
			return

	var source := FileAccess.get_file_as_string(
		Support.COMBAT_SCREEN_SCRIPT_PATH
	)
	assert_ne(source.find("LiveScreenPlaybackPort"), -1)
	assert_eq(
		source.find("RunPresentationSession"),
		-1,
		"production RUN_COMBAT screen must not receive a raw session"
	)
	assert_eq(
		source.find("BattlePlaybackController"),
		-1,
		"production RUN_COMBAT screen must not receive a raw controller"
	)

	var session: Variant = Support.SaveSpySession.new()
	var transcript_identity := Support.identity()
	Support.install_transcript(
		self,
		session,
		Support.events(4),
		transcript_identity
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 21)
	var port: Variant = Support.make_port(
		self,
		port_script,
		lease,
		registry,
		session
	)
	if port == null:
		return
	assert_eq(screen.call(&"bind_playback_port", port), &"")
	assert_true(bool(screen.call(&"set_playback_speed", 2).get("ok")))
	assert_true(bool(screen.call(&"set_playback_paused", true).get("ok")))
	var playback: BattlePlaybackStateResult = screen.call(&"try_playback")
	assert_true(playback.ok)
	assert_eq(playback.state.speed, &"x2")
	assert_true(playback.state.paused)
	assert_true(bool(screen.call(&"set_playback_paused", false).get("ok")))
	var drained: BattleEventWindowResult = screen.call(
		&"drain_playback_window",
		transcript_identity,
		2
	)
	assert_true(drained.ok)
	assert_eq(drained.window.events.size(), 2)
	assert_eq(session.dispatch_count, 0)

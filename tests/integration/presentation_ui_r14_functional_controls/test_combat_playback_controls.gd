extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)


func test_real_combat_buttons_use_live_playback_port_and_never_gameplay_dispatch() -> void:
	var fixture := Support.playback_fixture(self)
	var session := fixture.get("session") as RunPresentationSession
	var snapshot := Support.CompositionSupport.combat_snapshot()
	snapshot.run_id = &"run.r13.live-playback"
	var screen := Support.live_run_screen(
		self,
		&"RUN_COMBAT",
		snapshot,
		session,
		fixture.get("port") as LiveScreenPlaybackPort
	)
	if screen == null:
		return
	var composition := Support.composition(screen) as RunCombatScreen
	assert_not_null(composition)
	if composition == null:
		return

	assert_true(Support.press(self, screen, &"combat.pause"))
	var paused := composition.try_playback()
	assert_true(paused.ok)
	if paused.ok:
		assert_true(paused.state.paused)
	assert_true(Support.press(self, screen, &"combat.speed"))
	var sped := composition.try_playback()
	assert_true(sped.ok)
	if sped.ok:
		assert_eq(sped.state.speed, &"x2")
	assert_true(Support.press(self, screen, &"combat.inspect"))
	assert_eq(
		(fixture.get("session") as Support.PlaybackSupport.SaveSpySession).dispatch_count,
		0,
		"combat inspection and playback controls are read-only"
	)

	var registry := fixture.get("registry") as LiveScreenLeaseRegistry
	registry.revoke(fixture.get("lease") as LiveScreenLease)
	assert_true(Support.press(self, screen, &"combat.pause"))
	var stale: Variant = Support.last_control_result(self, screen)
	if stale != null:
		assert_eq(
			Support.error_code(stale),
			LiveScreenPlaybackPort.SCREEN_NOT_ACTIVE
		)

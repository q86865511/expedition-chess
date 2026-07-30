extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_playback/playback_test_support.gd"
)


func test_invalid_multiplier_matrix_is_named_and_state_preserving() -> void:
	var controller_script := Support.load_script(self, Support.CONTROLLER_PATH)
	if controller_script == null:
		return
	var transcript_identity := Support.identity("speed")
	var controller: Variant = controller_script.new(transcript_identity, 32)
	if not Support.require_methods(
		self,
		controller,
		[&"snapshot", &"set_speed", &"set_paused", &"advance"],
		Support.CONTROLLER_PATH
	):
		return

	for multiplier: int in [0, -1, 3, 8]:
		var before: Variant = controller.call(&"snapshot")
		var rejected: Variant = controller.call(&"set_speed", multiplier)
		assert_false(bool(rejected.get("ok")), "%dx must be rejected" % multiplier)
		assert_eq(
			Support.error_code(rejected),
			&"PLAYBACK_SPEED_INVALID",
			"invalid multiplier must use one stable named error"
		)
		var after: Variant = controller.call(&"snapshot")
		assert_eq(after.get("speed"), before.get("speed"))
		assert_eq(after.get("cursor"), before.get("cursor"))
		assert_eq(after.get("paused"), before.get("paused"))
		assert_true(Support.same_identity(
			after.get("transcript_identity"),
			before.get("transcript_identity")
		))


func test_pause_and_1x_2x_4x_only_move_the_presentation_cursor() -> void:
	var controller_script := Support.load_script(self, Support.CONTROLLER_PATH)
	if controller_script == null:
		return
	var canonical_events := Support.events(12)
	var canonical_signatures := Support.event_signatures(canonical_events)
	var transcript_identity := Support.identity("cursor")
	var controller: Variant = controller_script.new(transcript_identity, 12)
	if not Support.require_methods(
		self,
		controller,
		[&"snapshot", &"set_speed", &"set_paused", &"advance"],
		Support.CONTROLLER_PATH
	):
		return

	assert_true(bool(controller.call(&"set_speed", 1).get("ok")))
	assert_true(bool(controller.call(&"advance", 1).get("ok")))
	assert_eq(controller.call(&"snapshot").get("cursor"), 1)
	assert_true(bool(controller.call(&"set_speed", 2).get("ok")))
	assert_true(bool(controller.call(&"advance", 1).get("ok")))
	assert_eq(controller.call(&"snapshot").get("cursor"), 3)
	assert_true(bool(controller.call(&"set_speed", 4).get("ok")))
	assert_true(bool(controller.call(&"set_paused", true).get("ok")))
	assert_true(bool(controller.call(&"advance", 2).get("ok")))
	assert_eq(
		controller.call(&"snapshot").get("cursor"),
		3,
		"pause must stop only the presentation cursor"
	)
	assert_true(bool(controller.call(&"set_paused", false).get("ok")))
	assert_true(bool(controller.call(&"advance", 1).get("ok")))
	assert_eq(controller.call(&"snapshot").get("cursor"), 7)

	var returned_state: Variant = controller.call(&"snapshot")
	assert_true(Support.same_identity(
		returned_state.get("transcript_identity"),
		transcript_identity
	))
	returned_state.get("transcript_identity").run_id = &"consumer.mutation"
	assert_true(
		Support.same_identity(
			controller.call(&"snapshot").get("transcript_identity"),
			transcript_identity
		),
		"controller snapshots must deep-clone transcript identity"
	)
	assert_eq(
		Support.event_signatures(canonical_events),
		canonical_signatures,
		"speed and pause must not mutate canonical event identity or order"
	)

extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_run_screens/run_screens_test_support.gd"
)

const CONFIRMATION_CASES: Dictionary = {
	RunPresentationIntent.Kind.FORGE_EQUIPMENT: &"RUN_PREPARE",
	RunPresentationIntent.Kind.REPLACE_RELIC: &"RUN_REWARD",
	RunPresentationIntent.Kind.ABANDON_RELIC: &"RUN_REWARD",
	RunPresentationIntent.Kind.ABANDON_BOSS_RETRY: &"RUN_REWARD",
}


func test_irreversible_confirmation_cancel_and_exactly_once() -> void:
	var presenter_script := Support.load_script(
		self, Support.RUN_SCREEN_PRESENTER_PATH
	)
	if presenter_script == null:
		return

	for kind: int in CONFIRMATION_CASES:
		var registry := LiveScreenLeaseRegistry.new()
		var session := Support.SpyRunPresentationSession.new()
		var lease := registry.activate(AppStateMachine.State.RUN, kind + 1)
		var intent_port := LiveScreenIntentPort.new(lease, registry, session)
		var presenter: Variant = presenter_script.new(
			CONFIRMATION_CASES[kind], intent_port
		)
		for method_name: StringName in [
			&"begin_confirmation",
			&"cancel_confirmation",
			&"confirm_confirmation",
		]:
			if not Support.require_method(self, presenter, method_name):
				return

		var intent := RunPresentationIntent.new(kind)
		var cancel_begin: Variant = presenter.call(&"begin_confirmation", intent)
		assert_true(bool(cancel_begin.get("ok")))
		assert_eq(session.dispatch_count, 0, "begin must not dispatch")
		var cancelled: Variant = presenter.call(
			&"cancel_confirmation", cancel_begin.get("draft")
		)
		assert_true(bool(cancelled.get("ok")))
		assert_eq(session.dispatch_count, 0, "cancel must not dispatch")

		var confirm_begin: Variant = presenter.call(&"begin_confirmation", intent)
		var draft: Variant = confirm_begin.get("draft")
		var confirmed: Variant = presenter.call(&"confirm_confirmation", draft)
		assert_true(bool(confirmed.get("ok")))
		assert_eq(session.dispatch_count, 1, "confirm must dispatch exactly once")
		var repeated: Variant = presenter.call(&"confirm_confirmation", draft)
		assert_false(bool(repeated.get("ok")))
		assert_eq(
			Support.error_code(repeated),
			&"CONFIRMATION_ALREADY_RESOLVED"
		)
		assert_eq(session.dispatch_count, 1, "repeat must not dispatch")

		var stale_begin: Variant = presenter.call(&"begin_confirmation", intent)
		registry.activate(AppStateMachine.State.RUN, kind + 100)
		var stale: Variant = presenter.call(
			&"confirm_confirmation", stale_begin.get("draft")
		)
		assert_false(bool(stale.get("ok")))
		assert_eq(Support.error_code(stale), &"SCREEN_NOT_ACTIVE")
		assert_eq(session.dispatch_count, 1, "stale lease must not dispatch")

	# R12-A01/A02 terminal/results lifecycle is deliberately outside this test.

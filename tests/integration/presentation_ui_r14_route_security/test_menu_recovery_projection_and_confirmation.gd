extends GutTest


class FakeRecoveryPort:
	extends RefCounted

	var submit_count: int = 0

	func submit_discard(_token: RetainedRunRecoveryToken) -> SaveResult:
		submit_count += 1
		return SaveResult.success("r14-recovery-discard")


func test_menu_actions_are_conditional_on_typed_snapshot_state() -> void:
	var none := MainMenuSnapshot.new()
	none.can_start = true
	_assert_menu_actions(
		none,
		[&"menu.exit", &"menu.settings", &"menu.start"]
	)
	var loaded := MainMenuSnapshot.new()
	loaded.can_continue = true
	_assert_menu_actions(
		loaded,
		[&"menu.continue", &"menu.exit", &"menu.settings"]
	)
	for warning: StringName in [
		&"error.presentation.run_recovery",
		&"error.presentation.run_incompatible",
	]:
		var recovery := MainMenuSnapshot.new()
		recovery.has_recovery = true
		recovery.warning_key = warning
		_assert_menu_actions(
			recovery,
			[&"menu.exit", &"menu.recovery", &"menu.settings"]
		)


func test_decoded_and_opaque_recovery_confirm_exactly_once() -> void:
	for token: RetainedRunRecoveryToken in [
		RetainedRunRecoveryToken.new(
			RefCounted.new(), 3, "decoded.digest", &"run.decoded", &"decoded.nonce"
		),
		RetainedRunRecoveryToken.new(
			RefCounted.new(), 4, "opaque.digest", &"", &"opaque.nonce"
		),
	]:
		var presenter := RecoveryConfirmationPresenter.new()
		var port := FakeRecoveryPort.new()
		assert_eq(presenter.bind(port), &"")
		assert_eq(
			presenter.begin_confirmation(token, &"menu.recovery.available"),
			&""
		)
		assert_eq(port.submit_count, 0)
		assert_eq(presenter.cancel_confirmation(), &"")
		assert_eq(port.submit_count, 0, "begin/cancel must be zero dispatch")
		assert_eq(
			presenter.begin_confirmation(token, &"menu.recovery.available"),
			&""
		)
		if not presenter.has_method(&"confirm_confirmation"):
			assert_true(false, "recovery presenter requires a typed confirm action")
			continue
		var confirmed: Variant = presenter.call(&"confirm_confirmation")
		assert_true(confirmed is SaveResult and bool(confirmed.get("ok")))
		assert_eq(port.submit_count, 1)
		var replay: Variant = presenter.call(&"confirm_confirmation")
		assert_true(replay is SaveResult and not bool(replay.get("ok")))
		assert_eq(port.submit_count, 1, "replay must not dispatch twice")


func _assert_menu_actions(
	snapshot: MainMenuSnapshot,
	expected: Array[StringName]
) -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"MENU_MAIN")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var localized: Dictionary = {
		&"menu.continue": "Continue",
		&"menu.start": "Start",
		&"menu.settings": "Settings",
		&"menu.recovery": "Recovery",
		&"menu.exit": "Exit",
	}
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"MENU_MAIN",
				snapshot,
				null,
				&"en",
				localized
			)
		),
		&""
	)
	var actual: Array[StringName] = []
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.has_meta(&"action_id"):
			var action_id := StringName(button.get_meta(&"action_id"))
			actual.append(action_id)
			assert_eq(button.text, String(localized.get(action_id, "")))
	actual.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	expected.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	assert_eq(actual, expected)

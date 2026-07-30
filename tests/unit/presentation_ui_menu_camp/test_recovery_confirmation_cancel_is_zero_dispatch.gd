extends GutTest

const PRESENTER_PATH := "res://presentation/screens/recovery_confirmation_presenter.gd"


class FakeRecoveryPort:
	extends RefCounted

	var submit_count: int = 0
	var clear_count: int = 0

	func submit_discard(_token: RetainedRunRecoveryToken) -> SaveResult:
		submit_count += 1
		return SaveResult.success("fake-recovery-discard")

	func clear_intent() -> void:
		clear_count += 1


func test_recovery_confirmation_cancel_is_zero_dispatch() -> void:
	var script := _load_script(PRESENTER_PATH)
	if script == null:
		return
	var decoded := RetainedRunRecoveryToken.new(
		RefCounted.new(), 3, "decoded-digest", &"run.decoded", &"decoded.nonce"
	)
	var opaque := RetainedRunRecoveryToken.new(
		RefCounted.new(), 4, "opaque-digest", &"", &"opaque.nonce"
	)
	for token: RetainedRunRecoveryToken in [decoded, opaque]:
		var presenter: Object = script.new()
		if not _require_methods(
			presenter,
			[
				&"bind", &"begin_confirmation", &"is_confirmation_open",
				&"cancel_confirmation", &"status_key",
			]
		):
			return
		var port := FakeRecoveryPort.new()
		assert_eq(presenter.call("bind", port), &"")
		assert_eq(
			presenter.call("begin_confirmation", token, &"menu.recovery.available"),
			&""
		)
		assert_true(presenter.call("is_confirmation_open"))
		assert_eq(port.submit_count, 0, "begin is presentation-only")
		assert_eq(port.clear_count, 0, "begin must not clear retained data")
		assert_eq(presenter.call("cancel_confirmation"), &"")
		assert_false(presenter.call("is_confirmation_open"))
		assert_eq(port.submit_count, 0, "cancel is zero dispatch")
		assert_eq(port.clear_count, 0, "cancel is zero clear intent")
		assert_eq(
			presenter.call("status_key"),
			&"menu.recovery.available",
			"localized recovery state remains recoverable after cancel"
		)


func _load_script(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		assert_true(false, "%s must provide decoded/opaque recovery confirmation" % path)
		return null
	var script := load(path) as GDScript
	assert_not_null(script)
	return script


func _require_methods(target: Object, methods: Array[StringName]) -> bool:
	for method: StringName in methods:
		if not target.has_method(method):
			assert_true(false, "%s must implement %s" % [PRESENTER_PATH, method])
			return false
	return true

extends GutTest

const PRESENTER_PATH := "res://presentation/screens/settings_screen_presenter.gd"


class FakeSettingsPort:
	extends SettingsApplicationPort

	var apply_count: int = 0
	var received: SettingsSnapshot

	func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
		apply_count += 1
		received = candidate.deep_clone()
		return SettingsApplicationResult.failure(
			DiagnosticError.new(&"SETTINGS_APPLY_REJECTED", &"error.settings.apply_rejected")
		)


func test_settings_screen_submits_typed_draft_through_injected_port() -> void:
	var script := _load_script(PRESENTER_PATH)
	if script == null:
		return
	var presenter: Object = script.new()
	if not _require_methods(
		presenter,
		[
			&"bind", &"edit_draft", &"submit", &"visible_error_key",
			&"focused_control_id", &"dismiss_error",
		]
	):
		return
	var port := FakeSettingsPort.new()
	var initial := SettingsSnapshot.new()
	initial.locale = &"zh_TW"
	var bind_error: Variant = presenter.call("bind", port, initial)
	assert_eq(bind_error, &"")
	if bind_error != &"":
		return

	var draft := initial.deep_clone()
	draft.locale = &"en"
	draft.ui_scale_percent = 150
	draft.color_vision_mode = &"deuteranopia"
	draft.master_volume_bps = 9100
	draft.master_muted = false
	draft.music_volume_bps = 7200
	draft.music_muted = true
	draft.sfx_volume_bps = 6300
	draft.sfx_muted = false
	draft.ui_volume_bps = 5400
	draft.ui_muted = true
	assert_eq(presenter.call("edit_draft", draft), &"")
	var result: Variant = presenter.call("submit")
	assert_true(result is SettingsApplicationResult)
	assert_eq(port.apply_count, 1, "submit must call only the injected typed port")
	assert_not_null(port.received)
	if port.received == null:
		return
	assert_eq(port.received.locale, &"en")
	assert_eq(port.received.ui_scale_percent, 150)
	assert_eq(port.received.color_vision_mode, &"deuteranopia")
	assert_eq(
		[
			port.received.master_volume_bps, port.received.master_muted,
			port.received.music_volume_bps, port.received.music_muted,
			port.received.sfx_volume_bps, port.received.sfx_muted,
			port.received.ui_volume_bps, port.received.ui_muted,
		],
		[9100, false, 7200, true, 6300, false, 5400, true]
	)
	assert_eq(presenter.call("visible_error_key"), &"error.settings.apply_rejected")
	assert_eq(presenter.call("focused_control_id"), &"settings.apply")
	presenter.call("dismiss_error")
	assert_eq(presenter.call("visible_error_key"), &"")
	assert_eq(presenter.call("focused_control_id"), &"settings.apply")


func _load_script(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		assert_true(false, "%s must provide the T08 typed draft presenter" % path)
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

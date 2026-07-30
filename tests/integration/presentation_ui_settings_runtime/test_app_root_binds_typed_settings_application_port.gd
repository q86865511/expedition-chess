extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_settings_runtime/settings_runtime_test_support.gd"
)
const APP_ROOT_PATH := "res://app/app_root.gd"
const SETTINGS_SCREEN_PATH := "res://presentation/screens/settings_screen_presenter.gd"


func test_app_root_binds_and_exposes_typed_settings_application_port() -> void:
	if not _assert_app_root_source_contract():
		return
	var root_script := load(APP_ROOT_PATH) as GDScript
	assert_not_null(root_script)
	if root_script == null:
		return
	var root: Object = autofree(root_script.new())
	assert_not_null(root)
	if root == null:
		return
	assert_true(root.has_method("bind_settings_runtime"))
	assert_true(root.has_method("settings_application_port"))
	if (
		not root.has_method("bind_settings_runtime")
		or not root.has_method("settings_application_port")
	):
		return
	assert_null(root.call("settings_application_port"))
	assert_eq(
		StringName(root.call("bind_settings_runtime", null, null, null)),
		&"APP_SETTINGS_RUNTIME_MISSING"
	)

	var journal: Array[StringName] = []
	var committed := Support.candidate(&"en", 125)
	var repository := Support.FakeRepository.new(journal, committed)
	var consumer := Support.FakeRuntimeConsumer.new(journal)
	var audio_port := Support.FakeAudioBusPort.new(journal)
	var audio_coordinator := autofree(
		AudioCoordinator.new(audio_port)
	) as AudioCoordinator
	var bind_error := StringName(
		root.call(
			"bind_settings_runtime",
			repository,
			audio_coordinator,
			consumer
		)
	)

	assert_eq(bind_error, &"")
	var port: Variant = root.call("settings_application_port")
	assert_not_null(port)
	assert_true(port is SettingsApplicationPort)
	assert_eq(repository.current_read_count, 1)
	assert_eq(repository.save_count, 0)
	assert_eq(audio_port.apply_count, 1)
	Support.assert_consumer_matches(self, consumer, committed)
	Support.assert_audio_matches(self, audio_port, committed)
	if not port is SettingsApplicationPort:
		return
	var changed := Support.candidate(&"zh_TW", 150)
	var applied: SettingsApplicationResult = port.apply(changed)
	assert_true(applied.ok)
	assert_eq(repository.save_count, 1)
	Support.assert_consumer_matches(self, consumer, changed)
	Support.assert_audio_matches(self, audio_port, changed)
	_assert_rebuild_fault_is_named_and_fail_closed(root_script)


func _assert_rebuild_fault_is_named_and_fail_closed(
	root_script: GDScript
) -> void:
	var journal: Array[StringName] = []
	var repository := Support.FakeRepository.new(journal)
	repository.read_fault = true
	var consumer := Support.FakeRuntimeConsumer.new(journal)
	var audio_port := Support.FakeAudioBusPort.new(journal)
	var root: Object = autofree(root_script.new())
	var audio_coordinator := autofree(
		AudioCoordinator.new(audio_port)
	) as AudioCoordinator

	var bind_error := StringName(
		root.call(
			"bind_settings_runtime",
			repository,
			audio_coordinator,
			consumer
		)
	)

	assert_eq(bind_error, &"APP_SETTINGS_REBUILD_FAILED")
	assert_null(root.call("settings_application_port"))
	assert_eq(repository.save_count, 0)
	assert_eq(audio_port.apply_count, 0)
	assert_eq(consumer.runtime_by_kind, {})


func _assert_app_root_source_contract() -> bool:
	var app_source := FileAccess.get_file_as_string(APP_ROOT_PATH)
	var required_tokens := [
		"ERROR_SETTINGS_RUNTIME_MISSING",
		"ERROR_SETTINGS_REBUILD_FAILED",
		"get_node_or_null(\"/root/SettingsService\")",
		"get_node_or_null(\"/root/AudioService\")",
		"SettingsApplicationCoordinator.new(",
		"rebuild_from_repository()",
		"func bind_settings_runtime(",
		"func settings_application_port() -> SettingsApplicationPort",
	]
	var complete := true
	for token: String in required_tokens:
		var present := app_source.contains(token)
		assert_true(present, "ApplicationRoot settings wiring missing `%s`" % token)
		complete = complete and present
	var screen_source := FileAccess.get_file_as_string(SETTINGS_SCREEN_PATH)
	assert_false(
		screen_source.contains("SettingsRepository"),
		"settings screen must retain only the typed SettingsApplicationPort"
	)
	assert_false(
		screen_source.contains(".save("),
		"settings screen must not bypass the coordinator repository boundary"
	)
	return complete

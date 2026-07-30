extends GutTest

const Support := preload(
	"res://tests/unit/presentation_ui_settings_application/settings_application_test_support.gd"
)


func test_concrete_port_round_trips_locale_and_four_buses_after_rebuild() -> void:
	var presenter_source := FileAccess.get_file_as_string(
		"res://presentation/screens/settings_screen_presenter.gd"
	)
	assert_false(
		presenter_source.contains("SettingsRepository"),
		"settings screen must depend only on SettingsApplicationPort"
	)
	assert_false(
		presenter_source.contains(".save("),
		"settings screen must not call a repository writer"
	)
	var fixture := Support.fixture(self)
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	assert_true(
		coordinator is SettingsApplicationPort,
		"production binding must be directly injectable into SettingsScreenPresenter"
	)
	var candidate := Support.candidate(&"en")
	var applied: Variant = coordinator.call("apply", candidate)
	assert_true(Support.ok(applied), String(Support.error_code(applied)))
	Support.assert_runtime_equals(
		self,
		fixture.adapters[2].get("runtime"),
		candidate
	)
	Support.assert_runtime_equals(
		self,
		fixture.adapters[3].get("runtime"),
		candidate
	)

	var second_fixture := Support.fixture(self)
	if second_fixture.is_empty():
		return
	var second_repository: Object = second_fixture.repository
	second_repository.set(
		"committed",
		fixture.repository.get("committed").deep_clone()
	)
	var second_script := Support.load_coordinator(self)
	if second_script == null:
		return
	var second_coordinator: Object = second_script.new(
		second_repository,
		second_fixture.adapters[0],
		second_fixture.adapters[1],
		second_fixture.adapters[2],
		second_fixture.adapters[3]
	)
	var rebuilt: Variant = second_coordinator.call("rebuild_from_repository")
	assert_true(Support.ok(rebuilt), String(Support.error_code(rebuilt)))
	assert_eq(second_repository.get("current_read_count"), 1)
	Support.assert_runtime_equals(
		self,
		second_fixture.adapters[2].get("runtime"),
		candidate
	)
	Support.assert_runtime_equals(
		self,
		second_fixture.adapters[3].get("runtime"),
		candidate
	)
	_assert_unsupported_locale_is_named_rejected()


func _assert_unsupported_locale_is_named_rejected() -> void:
	var fixture := Support.fixture(self)
	if fixture.is_empty():
		return
	var result: Variant = fixture.coordinator.call(
		"apply",
		Support.candidate(&"ja")
	)

	assert_false(Support.ok(result))
	assert_eq(Support.error_code(result), &"SETTINGS_INVALID_ENUM")
	assert_false(bool(Support.field(result, &"committed")))
	assert_eq(fixture.repository.get("save_count"), 0)
	assert_eq(fixture.journal, [])

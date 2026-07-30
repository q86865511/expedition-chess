extends GutTest

const Support := preload(
	"res://tests/unit/presentation_ui_settings_application/settings_application_test_support.gd"
)


func test_postcommit_activation_diagnostic_keeps_commit_and_rebuilds_all() -> void:
	var fixture := Support.fixture(self)
	if fixture.is_empty():
		return
	fixture.adapters[1].set("activation_fault", true)
	var candidate := Support.candidate(&"en")

	var result: Variant = fixture.coordinator.call("apply", candidate)

	assert_false(Support.ok(result))
	assert_true(bool(Support.field(result, &"committed")))
	assert_false(bool(Support.field(result, &"presentation_ok")))
	assert_false(Support.error_code(result).is_empty())
	assert_eq(fixture.repository.get("save_count"), 1)
	assert_eq(fixture.repository.get("committed").locale, &"en")
	assert_eq(
		fixture.journal,
		[
			&"preflight:theme",
			&"preflight:viewport",
			&"preflight:localization",
			&"preflight:audio",
			&"repository:save",
			&"activate:theme",
			&"activate:viewport",
			&"fallback:theme",
			&"fallback:viewport",
			&"fallback:localization",
			&"fallback:audio",
			&"repository:fresh_read",
			&"rebuild:theme",
			&"rebuild:viewport",
			&"rebuild:localization",
			&"rebuild:audio",
		]
	)
	assert_eq(fixture.repository.get("current_read_count"), 1)
	for adapter: Object in fixture.adapters:
		assert_eq(adapter.get("safe_fallback_count"), 1)
		assert_eq(adapter.get("rebuild_count"), 1)
		Support.assert_runtime_equals(
			self,
			adapter.get("runtime"),
			fixture.repository.get("committed")
		)

	var exposed := Support.field(result, &"snapshot") as SettingsSnapshot
	assert_not_null(exposed)
	if exposed == null:
		return
	exposed.locale = &"zh_TW"
	assert_eq(fixture.repository.get("committed").locale, &"en")

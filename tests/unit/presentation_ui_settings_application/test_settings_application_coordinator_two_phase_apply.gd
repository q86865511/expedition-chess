extends GutTest

const Support := preload(
	"res://tests/unit/presentation_ui_settings_application/settings_application_test_support.gd"
)


func test_entry_clone_private_plans_save_then_fixed_activation_order() -> void:
	var fixture := Support.fixture(self)
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	var repository: Object = fixture.repository
	var adapters: Array = fixture.adapters
	var caller := Support.candidate()

	var result: Variant = coordinator.call("apply", caller)

	assert_true(Support.ok(result), String(Support.error_code(result)))
	assert_true(result is SettingsApplicationResult)
	assert_true(bool(Support.field(result, &"committed")))
	assert_true(bool(Support.field(result, &"presentation_ok")))
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
			&"activate:localization",
			&"activate:audio",
		]
	)
	assert_eq(repository.get("save_count"), 1)
	for adapter: Object in adapters:
		assert_eq(adapter.get("received_plans").size(), 1)
		assert_ne(adapter.get("received_plans")[0], caller)
	for left: int in range(adapters.size()):
		for right: int in range(left + 1, adapters.size()):
			assert_ne(
				adapters[left].get("received_plans")[0],
				adapters[right].get("received_plans")[0],
				"every adapter must receive a private plan clone"
			)

	caller.locale = &"zh_TW"
	caller.ui_volume_bps = 1
	var committed: SettingsSnapshot = repository.get("committed")
	assert_eq(committed.locale, &"en")
	assert_eq(committed.ui_volume_bps, 5400)
	for adapter: Object in adapters:
		Support.assert_runtime_equals(self, adapter.get("runtime"), committed)
	_assert_mutated_plan_and_token_digest_are_rejected()


func _assert_mutated_plan_and_token_digest_are_rejected() -> void:
	for mode: StringName in [&"mutator", &"token_digest"]:
		var fixture := Support.fixture(self)
		if fixture.is_empty():
			return
		var adapters: Array = fixture.adapters
		var target: Object = adapters[1]
		if mode == &"mutator":
			target.set("mutate_plan", true)
		else:
			target.set("wrong_token_digest", true)
		var result: Variant = fixture.coordinator.call(
			"apply",
			Support.candidate()
		)
		assert_false(Support.ok(result), String(mode))
		assert_false(Support.error_code(result).is_empty())
		assert_eq(fixture.repository.get("save_count"), 0)
		for adapter: Object in adapters:
			assert_eq(adapter.get("runtime").locale, &"zh_TW")
			assert_eq(adapter.get("safe_fallback_count"), 0)

extends GutTest

const Support := preload(
	"res://tests/unit/presentation_ui_settings_application/settings_application_test_support.gd"
)


func test_each_adapter_preflight_and_repository_fault_is_zero_runtime_mutation() -> void:
	for fault_index: int in range(5):
		var fixture := Support.fixture(self)
		if fixture.is_empty():
			return
		var adapters: Array = fixture.adapters
		if fault_index < 4:
			adapters[fault_index].set("preflight_fault", true)
		else:
			fixture.repository.set("save_fault", true)

		var result: Variant = fixture.coordinator.call(
			"apply",
			Support.candidate()
		)

		assert_false(Support.ok(result), "fault index %d" % fault_index)
		assert_false(Support.error_code(result).is_empty())
		assert_false(bool(Support.field(result, &"committed")))
		for adapter: Object in adapters:
			assert_eq(adapter.get("runtime").locale, &"zh_TW")
			assert_eq(adapter.get("safe_fallback_count"), 0)
		if fault_index < 4:
			assert_eq(fixture.repository.get("save_count"), 0)
		else:
			assert_eq(fixture.repository.get("save_count"), 1)
	_assert_process_local_competing_apply_is_rejected()


func _assert_process_local_competing_apply_is_rejected() -> void:
	var outer_fixture := Support.fixture(self)
	var competing_fixture := Support.fixture(self)
	if outer_fixture.is_empty() or competing_fixture.is_empty():
		return
	var adapter: Object = outer_fixture.adapters[0]
	adapter.set("coordinator", competing_fixture.coordinator)
	adapter.set("reentrant_candidate", Support.candidate(&"zh_TW"))

	var outer: Variant = outer_fixture.coordinator.call(
		"apply",
		Support.candidate(&"en")
	)

	assert_true(Support.ok(outer), String(Support.error_code(outer)))
	var reentrant: Variant = adapter.get("reentrant_result")
	assert_not_null(reentrant)
	assert_false(Support.ok(reentrant))
	assert_eq(
		Support.error_code(reentrant),
		&"SETTINGS_APPLY_IN_PROGRESS"
	)
	assert_false(bool(Support.field(reentrant, &"committed")))
	assert_eq(outer_fixture.repository.get("save_count"), 1)
	assert_eq(competing_fixture.repository.get("save_count"), 0)
	assert_eq(outer_fixture.repository.get("committed").locale, &"en")

	adapter.set("coordinator", null)
	adapter.set("reentrant_candidate", null)
	var after_release: Variant = competing_fixture.coordinator.call(
		"apply",
		Support.candidate(&"zh_TW")
	)
	assert_true(
		Support.ok(after_release),
		"all exits must release process-local ownership"
	)
	assert_eq(competing_fixture.repository.get("save_count"), 1)

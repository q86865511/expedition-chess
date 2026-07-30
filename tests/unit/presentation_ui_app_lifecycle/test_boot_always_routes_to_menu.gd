extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")


func test_boot_always_routes_to_menu() -> void:
	var storage := FakeSaveStorage.new()
	var first: Variant = Support.boot(self, storage)

	assert_true(first.root.is_booted(), "no-save boot must succeed")
	assert_eq(
		first.root.app_state(),
		AppStateMachine.State.MENU,
		"no-save boot must create the profile but stop at MENU"
	)
	var first_load: LoadResult = first.repository.load()
	assert_true(first_load.ok, "no-save boot must persist the initial profile")
	if first_load.ok:
		assert_eq(first_load.run_status, LoadResult.RunStatus.NONE)

	var run_free: Variant = Support.boot(self, storage)
	assert_true(run_free.root.is_booted(), "run-free committed save must boot")
	assert_eq(
		run_free.root.app_state(),
		AppStateMachine.State.MENU,
		"run-free committed save must still stop at MENU"
	)

	var active_storage := FakeSaveStorage.new()
	var active_seed: Variant = Support.boot(self, active_storage)
	var seeded: bool = _start_one_run_for_fixture(active_seed)
	assert_true(seeded, "active-run fixture must be constructible through production entry")
	if seeded:
		var before: PackedByteArray = Support.main_bytes(active_storage)
		var active: Variant = Support.boot(self, active_storage)
		assert_true(active.root.is_booted(), "active-run save must boot safely")
		assert_eq(
			active.root.app_state(),
			AppStateMachine.State.MENU,
			"boot must prepare Continue but never auto-enter RUN"
		)
		assert_eq(
			Support.main_bytes(active_storage),
			before,
			"booting an active run must not rewrite its committed bytes"
		)

	var fatal_storage := FakeSaveStorage.new()
	fatal_storage.seed_file(StorageFaultKey.MAIN, PackedByteArray([0x80]))
	var fatal: Variant = Support.boot(self, fatal_storage)
	assert_false(fatal.root.is_booted(), "fatal load must fail closed")
	assert_eq(fatal.root.app_state(), AppStateMachine.State.BOOT)
	assert_eq(fatal.boot_error, LoadError.UTF8_INVALID)
	await wait_process_frames(2)


func _start_one_run_for_fixture(harness) -> bool:
	if harness.root.app_state() == AppStateMachine.State.MENU:
		if not harness.root.has_method("open_camp"):
			return false
		var open_result: Variant = harness.root.call("open_camp")
		if not (open_result is AppActionResult) or not open_result.ok:
			return false
	if harness.root.app_state() != AppStateMachine.State.CAMP:
		return false
	var view_model: CampViewModel = harness.root.call("try_camp_view_model")
	if view_model == null:
		return false
	var commanders: Array[StringName] = view_model.commander_hall_unlocked_commander_ids()
	if commanders.is_empty():
		return false
	var required_arguments: int = Support.method_argument_count(
		harness.root,
		&"start_expedition"
	)
	var result: Variant
	if required_arguments == 1:
		result = harness.root.call(
			"start_expedition",
			StartExpeditionRequest.new(commanders[0], 0)
		)
		return result is AppActionResult and result.committed
	if required_arguments == 2:
		result = harness.root.call("start_expedition", commanders[0], 0)
		return result == &""
	return false

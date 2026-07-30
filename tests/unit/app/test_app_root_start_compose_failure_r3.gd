extends GutTest

## W5 R3 projection regression: start_expedition() commits profile' + run before
## composition.  If composition fails, CAMP must project that committed profile'
## (new serial and last selection) while exposing the explicit discard entry.


class CompositionFailingApplicationRoot:
	extends ApplicationRoot

	func _try_compose_active_run(_profile: ProfileState, _run: RunState) -> StringName:
		return ERROR_RUN_BATTLE_CATALOG_FAILED


class BootHarness:
	extends RefCounted

	var app_root: ApplicationRoot
	var repository: SaveRepository
	var boot_error: StringName = &""


func test_start_compose_failure_refreshes_camp_projection_from_committed_profile() -> void:
	var storage := FakeSaveStorage.new()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var repository := SaveRepository.new(storage)
	add_child_autofree(repository)
	var router := SceneRouterService.new()
	add_child_autofree(router)
	var app_root := CompositionFailingApplicationRoot.new()
	app_root.name = "AppRoot"
	var host := Control.new()
	host.name = "PresentationHost"
	app_root.add_child(host)
	assert_eq(app_root.bind_services(registry, repository, router), &"")
	add_child_autofree(app_root)
	assert_true(app_root.is_booted())
	assert_eq(app_root.app_state(), AppStateMachine.State.MENU)
	assert_true(app_root.open_camp().ok)
	assert_eq(app_root.app_state(), AppStateMachine.State.CAMP)
	var initial := app_root.try_camp_view_model()
	assert_not_null(initial)
	if initial == null:
		return
	var commanders := initial.commander_hall_unlocked_commander_ids()
	assert_false(commanders.is_empty())
	if commanders.is_empty():
		return
	var before_profile: ProfileState = initial.get("_profile")
	assert_not_null(before_profile)
	var before_serial := before_profile.next_run_serial.to_hex()
	assert_null(initial.expedition_gate_last_selection())

	var result := app_root.start_expedition(
		StartExpeditionRequest.new(commanders[0], 0)
	)

	assert_false(result.ok)
	assert_true(result.committed)
	assert_eq(
		result.error.source_code,
		ApplicationRoot.ERROR_RUN_BATTLE_CATALOG_FAILED
	)
	assert_eq(
		app_root.app_state(),
		AppStateMachine.State.MENU,
		"a postcommit composition failure returns to the recovery-capable menu"
	)
	assert_true(app_root.current_menu_snapshot().has_recovery)
	assert_true(app_root.has_unresumable_active_run())
	var projected := app_root.try_camp_view_model()
	assert_not_null(projected)
	if projected == null:
		return
	var selection := projected.expedition_gate_last_selection()
	assert_not_null(
		selection,
		"the CAMP projection must use the already-committed profile', not its stale pre-start clone"
	)
	if selection != null:
		assert_eq(selection.commander_id, commanders[0])
		assert_eq(selection.challenge_level, 0)
	var projected_profile: ProfileState = projected.get("_profile")
	assert_not_null(projected_profile)
	if projected_profile != null:
		assert_ne(projected_profile.next_run_serial.to_hex(), before_serial)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
		assert_eq(
			projected_profile.next_run_serial.to_hex(),
			loaded.profile.next_run_serial.to_hex()
		)
		assert_eq(loaded.profile.last_selection.commander_id, commanders[0])
	await wait_process_frames(2)


func test_incompatible_preserved_run_boots_menu_with_recovery_and_preserves_original_bytes() -> void:
	var storage := FakeSaveStorage.new()
	var legacy_text := _legacy_prepare_text()
	storage.seed_file(StorageFaultKey.MAIN, legacy_text.to_utf8_buffer())
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	var harness := _boot(storage)

	assert_true(
		harness.app_root.is_booted(),
		"opaque retained bytes must boot to the recovery-capable MENU"
	)
	assert_eq(harness.boot_error, &"")
	assert_eq(harness.app_root.app_state(), AppStateMachine.State.MENU)
	var menu := harness.app_root.current_menu_snapshot()
	assert_true(menu.has_recovery)
	assert_false(menu.can_start)
	assert_false(menu.can_continue)
	assert_eq(menu.warning_key, &"error.presentation.run_incompatible")
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	var loaded := harness.repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
		assert_null(loaded.run)
	await wait_process_frames(2)


func _boot(storage: FakeSaveStorage) -> BootHarness:
	var harness := BootHarness.new()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	harness.repository = SaveRepository.new(storage)
	add_child_autofree(harness.repository)
	var router := SceneRouterService.new()
	add_child_autofree(router)
	harness.app_root = ApplicationRoot.new()
	harness.app_root.name = "AppRoot"
	var host := Control.new()
	host.name = "PresentationHost"
	harness.app_root.add_child(host)
	harness.app_root.boot_failed.connect(func(error: StringName) -> void:
		harness.boot_error = error
	)
	assert_eq(
		harness.app_root.bind_services(registry, harness.repository, router), &""
	)
	add_child_autofree(harness.app_root)
	return harness


func _legacy_prepare_text() -> String:
	var root := SaveRootFixture.create_valid_root()
	root.run.run_phase = RunState.RunPhase.PREPARE
	var encoded := SaveRootFixture.create_codec().encode(root)
	assert_true(encoded.ok)
	var text := encoded.json_text.value.replace(
		"\"schema_version\":3", "\"schema_version\":1"
	)
	text = text.replace(",\"combat_config_id\":\"config.combat_default\"", "")
	text = text.replace("\"config.combat_default\",", "")
	return text

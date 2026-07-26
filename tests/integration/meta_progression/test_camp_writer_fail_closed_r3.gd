extends GutTest

## W5 R3 regression contract for S5-AC-008:
## every Camp writer must fresh-load the repository and may write only when the
## persisted run status is exactly NONE.  Retained/incompatible runs and load
## failures are data-preservation barriers, never permission to write run=null.

const CAMP_ACTIVE_RUN_EXISTS: StringName = &"CAMP_ACTIVE_RUN_EXISTS"
const CAMP_LOAD_FAILED: StringName = &"CAMP_LOAD_FAILED"


func test_purchase_unlock_rejects_loaded_run_without_clearing_persisted_bytes() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var started := controller.dispatch_start_expedition(_start_command())
	assert_true(started.ok, String(started.error.code) if not started.ok else "ok")
	if not started.ok:
		return
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(bytes_before)
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 0, no_prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_false(result.ok, "a profile-only Camp writer must not erase a retained run")
	if result.ok:
		return
	assert_eq(result.error.code, CAMP_ACTIVE_RUN_EXISTS)
	assert_eq(result.error.field_path, &"save.run")
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
		assert_eq(loaded.run.run_id, started.run.run_id)
		assert_false(loaded.profile.unlocked_content_ids.has(&"commander.mike"))


func test_start_expedition_load_io_failure_is_named_and_writes_nothing() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(bytes_before)
	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.EXISTS, StorageFaultKey.MAIN, 0
	))

	var result := controller.dispatch_start_expedition(_start_command())

	assert_false(result.ok, "a failed active-run guard load must fail closed")
	if result.ok:
		return
	assert_eq(result.error.code, CAMP_LOAD_FAILED)
	assert_eq(result.error.field_path, &"save")
	assert_null(result.run)
	assert_null(result.save_result)
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	assert_eq(
		controller.profile_snapshot().next_run_serial.to_hex(),
		U64Bits.from_u32(0, 5).value.to_hex()
	)
	assert_null(controller.profile_snapshot().last_selection)


func test_start_expedition_incompatible_preserved_run_is_rejected_byte_for_byte() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var legacy_text := _legacy_prepare_text()
	storage.seed_file(StorageFaultKey.MAIN, legacy_text.to_utf8_buffer())
	var guarded := repository.load()
	assert_true(guarded.ok)
	assert_eq(guarded.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
	assert_null(guarded.run)
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)

	var result := controller.dispatch_start_expedition(_start_command())

	assert_false(result.ok, "preserved incompatible run data is still an active-run barrier")
	if result.ok:
		return
	assert_eq(result.error.code, StartExpeditionError.EXPEDITION_ACTIVE_RUN_EXISTS)
	assert_eq(result.error.field_path, &"save.run")
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	var after := repository.load()
	assert_true(after.ok)
	if after.ok:
		assert_eq(after.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
		assert_null(after.run)


func _start_command() -> StartExpeditionCommand:
	return StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)


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

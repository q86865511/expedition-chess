extends GutTest

## W5 R2 #4 / S5-AC-008：無法 composition 的 active run 不可自動刪除，也不可
## 讓玩家永久卡死。玩家明示的 DiscardActiveRunCommand 必須攜 expected_run_id，
## CampController 重新 load 後比對並以單筆 profile+run=null 存檔完成交易。

const DISCARD_COMMAND_PATH: String = "res://domain/run/camp/discard_active_run_command.gd"


func test_matching_expected_run_id_atomically_clears_run_and_preserves_profile() -> void:
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
	var before := repository.load()
	assert_true(before.ok)
	if not before.ok:
		return

	var discarded: Variant = _dispatch_discard(controller, started.run.run_id)
	if discarded == null:
		return
	assert_true(discarded.ok, String(discarded.error.code) if not discarded.ok else "ok")
	if not discarded.ok:
		return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(loaded.profile.profile_id, before.profile.profile_id)
	assert_eq(
		loaded.profile.next_run_serial.to_hex(),
		before.profile.next_run_serial.to_hex()
	)
	assert_eq(loaded.profile.meta_currency, before.profile.meta_currency)
	assert_eq(
		loaded.profile.settlement_receipts.size(),
		before.profile.settlement_receipts.size(),
		"discard is not a settlement and must not author a receipt"
	)


func test_stale_expected_run_id_is_named_rejection_and_byte_for_byte_no_op() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var started := controller.dispatch_start_expedition(_start_command())
	assert_true(started.ok)
	if not started.ok:
		return
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)

	var discarded: Variant = _dispatch_discard(controller, "run_" + "f".repeat(64))
	if discarded == null:
		return
	assert_false(discarded.ok)
	if discarded.ok:
		return
	assert_true(
		String(discarded.error.code).begins_with("DISCARD_ACTIVE_RUN_"),
		"stale-id rejection must carry a discard-domain code"
	)
	assert_eq(discarded.error.field_path, &"save.run.run_id")
	assert_eq(
		storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value,
		"a stale confirmation cannot erase a newer run"
	)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run.run_id, started.run.run_id)


func test_discard_without_active_run_is_named_rejection_and_no_op() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)

	var discarded: Variant = _dispatch_discard(controller, "run_" + "e".repeat(64))
	if discarded == null:
		return
	assert_false(discarded.ok)
	if discarded.ok:
		return
	assert_true(
		String(discarded.error.code).begins_with("DISCARD_ACTIVE_RUN_"),
		"no-run rejection must carry a discard-domain code"
	)
	assert_eq(discarded.error.field_path, &"save.run")
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
		assert_null(loaded.run)


func test_discard_save_failure_keeps_committed_run_and_controller_profile_unchanged() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)
	var started := controller.dispatch_start_expedition(_start_command())
	assert_true(started.ok)
	if not started.ok:
		return
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	var profile_before := controller.profile_snapshot()
	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0
	))

	var discarded: Variant = _dispatch_discard(controller, started.run.run_id)
	if discarded == null:
		return
	assert_false(discarded.ok)
	if discarded.ok:
		return
	assert_eq(discarded.error.code, CampCommandError.SAVE_FAILED)
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value)
	assert_eq(
		controller.profile_snapshot().next_run_serial.to_hex(),
		profile_before.next_run_serial.to_hex(),
		"failed save must not swap the camp-side profile"
	)
	storage.clear_faults()
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
		assert_eq(loaded.run.run_id, started.run.run_id)


func _dispatch_discard(controller: CampController, expected_run_id: String) -> Variant:
	if not ResourceLoader.exists(DISCARD_COMMAND_PATH):
		assert_true(
			false,
			"DiscardActiveRunCommand must exist at the domain/run/camp canonical path"
		)
		return null
	var script := load(DISCARD_COMMAND_PATH) as Script
	assert_not_null(
		script,
		"DiscardActiveRunCommand must exist at the domain/run/camp canonical path"
	)
	if script == null:
		return null
	assert_true(
		controller.has_method("dispatch_discard_active_run"),
		"CampController must expose the explicit discard transaction entrypoint"
	)
	if not controller.has_method("dispatch_discard_active_run"):
		return null
	var command: RefCounted = script.new(expected_run_id)
	return controller.call("dispatch_discard_active_run", command)


func _start_command() -> StartExpeditionCommand:
	return StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

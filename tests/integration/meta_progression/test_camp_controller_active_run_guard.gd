extends GutTest

## S5 wave5 修正 #9（sonnet 審查 #4）：CampController.dispatch_start_expedition() 的
## active-run 前置守衛。
##
## 成功的開遠征會把 profile'＋新 run 寫成**同一筆** SaveRoot（camp_controller.gd:146-165）。
## 沒有守衛時，儲存中已在進行的那一局會被無聲覆蓋——玩家從營地按第二次「開始遠征」
## 就永久失去上一局。守衛以具名碼拒絕（續跑是 boot 分流的職責，不是 camp 的裁決），
## 且必須在任何 clone/validate/save 之前發生：存檔位元組必須完全沒被動過。

func test_second_start_is_rejected_by_name_and_leaves_the_committed_run_untouched() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(
		StartExpeditionTestFixture.base_profile(5), repository
	)

	var first := controller.dispatch_start_expedition(_alpha_command())
	assert_true(first.ok, String(first.error.code) if not first.ok else "ok")
	if not first.ok:
		return
	var committed_run_id := first.run.run_id
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(bytes_before)

	var second := controller.dispatch_start_expedition(_beta_command())
	assert_false(second.ok, "starting a second expedition over a live run must be rejected")
	if second.ok:
		return
	assert_eq(second.error.code, StartExpeditionError.EXPEDITION_ACTIVE_RUN_EXISTS)
	assert_eq(second.error.field_path, &"save.run")
	assert_null(second.run)
	assert_null(second.save_result)

	assert_eq(
		storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value,
		"a rejected start must not touch the committed save at all"
	)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
		assert_eq(loaded.run.run_id, committed_run_id, "the live run must still be the first one")


func _alpha_command() -> StartExpeditionCommand:
	return StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)


func _beta_command() -> StartExpeditionCommand:
	return StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_BETA_ID,
		StartExpeditionTestFixture.commander_beta(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

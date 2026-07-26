extends GutTest

## S5 wave5 修正 A1／A2 的回歸測試（specs/meta-progression/design.md §4.4）。
##
## A1（續跑）：`_boot_route()` 過去先 `SaveRepository.load()` 才（惰性）安裝內容。存檔裡的
## active run 要靠 ContentRegistryReceiptAdapter 把 pinned 內容參照解回 receipt 才解得開，
## registry 是空的時整段會被判成 INCOMPATIBLE_PRESERVED、run 變 null——續跑分支是死碼，玩家
## 一開新遠征就把上一局覆蓋掉。本檔用真的存檔往返釘住順序：存檔含 active run → 重開 →
## app state == RUN，且**存檔位元組完全沒被動過**。
##
## A2（首次啟動）：乾淨環境沒有任何 production 路徑會建 ProfileState，營地永遠停在
## 「尚未載入 profile」。本檔釘住：空 storage boot → CAMP ＋ CampViewModel 非 null ＋
## 起始解鎖集合非空 ＋ 真的開得了遠征。
##
## 注入方式：`ApplicationRoot.bind_services()`（app_root.gd）在 add_child 之前換掉五個
## Autoload 中 boot 會用到的三個。boot 現在會寫存檔，不換 storage 就會動到真實 user:// 檔。

const MAIN_SCENE_PATH: String = "res://app/main.tscn"


class CompositionFailingApplicationRoot:
	extends ApplicationRoot

	func _try_compose_active_run(_profile: ProfileState, _run: RunState) -> StringName:
		return ERROR_RUN_BATTLE_CATALOG_FAILED


class BootHarness:
	extends RefCounted

	var registry: ContentRegistryService
	var repository: SaveRepository
	var router: SceneRouterService
	var main: Node
	var app_root: ApplicationRoot
	var boot_error: StringName = &""


func _boot(test: GutTest, storage: FakeSaveStorage) -> BootHarness:
	var harness := BootHarness.new()
	harness.registry = ContentRegistryService.new()
	test.add_child_autofree(harness.registry)
	harness.repository = SaveRepository.new(storage)
	test.add_child_autofree(harness.repository)
	harness.router = SceneRouterService.new()
	test.add_child_autofree(harness.router)
	harness.main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	harness.app_root = harness.main.get_node("AppRoot") as ApplicationRoot
	harness.app_root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	# bind_services() 必須發生在進入場景樹（_ready）之前。
	harness.app_root.bind_services(harness.registry, harness.repository, harness.router)
	test.add_child_autofree(harness.main)
	return harness


func _boot_with_root(
	test: GutTest,
	storage: FakeSaveStorage,
	app_root: ApplicationRoot
) -> BootHarness:
	var harness := BootHarness.new()
	harness.registry = ContentRegistryService.new()
	test.add_child_autofree(harness.registry)
	harness.repository = SaveRepository.new(storage)
	test.add_child_autofree(harness.repository)
	harness.router = SceneRouterService.new()
	test.add_child_autofree(harness.router)
	harness.main = Node.new()
	harness.app_root = app_root
	harness.app_root.name = "AppRoot"
	var host := Control.new()
	host.name = "PresentationHost"
	harness.app_root.add_child(host)
	harness.main.add_child(harness.app_root)
	harness.app_root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	harness.app_root.bind_services(harness.registry, harness.repository, harness.router)
	test.add_child_autofree(harness.main)
	return harness


## SceneRouterService 換場時對舊畫面用的是 queue_free（scene_router_service.gd:21-23），
## 要等一個 frame 才真的釋放；GUT 的 orphan 計數在測試結束當下發生，故換過場的測試必須
## 讓出一個 frame，否則會以 orphan 判紅（tools/run-tests.ps1 的 orphans != 0 → exit 2）。
func _flush_freed_scenes() -> void:
	await wait_process_frames(2)


func test_first_boot_bootstraps_a_playable_profile_and_opens_camp() -> void:
	var storage := FakeSaveStorage.new()
	var harness := _boot(self, storage)

	assert_true(harness.app_root.is_booted(), "boot must succeed on a clean environment")
	assert_eq(harness.app_root.app_state(), AppStateMachine.State.CAMP)
	var view_model := harness.app_root.try_camp_view_model()
	assert_not_null(view_model, "a clean boot must leave the camp projection usable (A2)")
	if view_model == null:
		return

	var loaded := harness.repository.load()
	assert_true(loaded.ok, "the initial profile must be persisted, not just held in memory")
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE, "a fresh profile has no active run")
	assert_eq(loaded.profile.meta_currency, 0)
	assert_eq(loaded.profile.highest_challenge_level, 0)
	assert_true(loaded.profile.settlement_receipts.is_empty())
	assert_true(loaded.profile.commander_challenge_records.is_empty())
	assert_null(loaded.profile.last_selection)
	assert_false(
		loaded.profile.unlocked_content_ids.is_empty(),
		"the initial unlock set comes from the base_profile unlock content"
	)

	var commanders := view_model.commander_hall_unlocked_commander_ids()
	assert_false(
		commanders.is_empty(),
		"a clean profile must own at least one commander, or the expedition gate can never open"
	)
	if commanders.is_empty():
		return
	assert_eq(
		harness.app_root.start_expedition(commanders[0], 0), &"",
		"the expedition gate must be operable straight after a clean boot"
	)
	assert_eq(harness.app_root.app_state(), AppStateMachine.State.RUN)
	assert_true(harness.app_root.has_active_run())
	assert_not_null(harness.app_root.try_run_command_factory())
	await _flush_freed_scenes()


func test_boot_with_persisted_active_run_resumes_it_without_touching_the_save() -> void:
	var storage := FakeSaveStorage.new()
	var first := _boot(self, storage)
	var commanders := first.app_root.try_camp_view_model().commander_hall_unlocked_commander_ids()
	assert_false(commanders.is_empty())
	if commanders.is_empty():
		return
	assert_eq(first.app_root.start_expedition(commanders[0], 0), &"")
	assert_eq(first.app_root.app_state(), AppStateMachine.State.RUN)

	var before := first.repository.load()
	assert_true(before.ok)
	assert_eq(before.run_status, LoadResult.RunStatus.LOADED)
	if not before.ok or before.run == null:
		return
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(bytes_before)

	# 重開遊戲：全新的 registry／repository，同一份 storage。
	var second := _boot(self, storage)
	assert_true(second.app_root.is_booted())
	assert_eq(
		second.app_root.app_state(), AppStateMachine.State.RUN,
		"a persisted active run must resume straight into RUN (A1)"
	)
	assert_true(second.app_root.has_active_run())
	assert_not_null(
		second.app_root.try_run_command_factory(),
		"resuming must rebuild the run-scoped command factory"
	)

	var after := second.repository.load()
	assert_true(after.ok)
	assert_eq(after.run_status, LoadResult.RunStatus.LOADED)
	if not after.ok or after.run == null:
		return
	assert_eq(after.run.run_id, before.run.run_id, "resume must not start a different run")
	assert_eq(
		after.profile.next_run_serial.to_hex(), before.profile.next_run_serial.to_hex(),
		"resume must not consume another run serial"
	)
	assert_eq(
		storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value,
		"booting into a resumed run must not rewrite the committed save"
	)
	await _flush_freed_scenes()


func test_invalid_save_fails_boot_without_composing_a_null_profile_camp() -> void:
	var storage := FakeSaveStorage.new()
	storage.seed_file(StorageFaultKey.MAIN, PackedByteArray([0x80]))
	var harness := _boot(self, storage)

	assert_false(harness.app_root.is_booted())
	assert_eq(harness.boot_error, LoadError.UTF8_INVALID)
	assert_eq(harness.app_root.app_state(), AppStateMachine.State.BOOT)
	assert_null(harness.app_root.try_camp_view_model())


func test_storage_io_failure_fails_boot_while_not_found_still_bootstraps() -> void:
	var failed_storage := FakeSaveStorage.new()
	failed_storage.inject_fault(StorageFaultKey.new(
		StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0
	))
	var failed := _boot(self, failed_storage)
	assert_false(failed.app_root.is_booted())
	assert_eq(failed.boot_error, &"SAVE_IO_DIRECTORY")
	assert_null(failed.app_root.try_camp_view_model())

	var missing := _boot(self, FakeSaveStorage.new())
	assert_true(missing.app_root.is_booted(), "NOT_FOUND remains the only bootstrap branch")
	assert_eq(missing.app_root.app_state(), AppStateMachine.State.CAMP)
	assert_not_null(missing.app_root.try_camp_view_model())
	await _flush_freed_scenes()


func test_bind_services_succeeds_only_before_tree_entry_and_late_call_keeps_old_services() -> void:
	var first_registry := ContentRegistryService.new()
	add_child_autofree(first_registry)
	var first_repository := SaveRepository.new(FakeSaveStorage.new())
	add_child_autofree(first_repository)
	var first_router := SceneRouterService.new()
	add_child_autofree(first_router)
	var main := (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	var app_root := main.get_node("AppRoot") as ApplicationRoot
	assert_eq(
		app_root.call("bind_services", first_registry, first_repository, first_router), &"",
		"pre-tree dependency binding is the only successful timing"
	)
	add_child_autofree(main)
	assert_true(app_root.is_booted())

	var late_registry := ContentRegistryService.new()
	add_child_autofree(late_registry)
	var late_repository := SaveRepository.new(FakeSaveStorage.new())
	add_child_autofree(late_repository)
	var late_router := SceneRouterService.new()
	add_child_autofree(late_router)
	assert_eq(
		app_root.call("bind_services", late_registry, late_repository, late_router),
		&"APP_SERVICE_BIND_TOO_LATE"
	)
	var commanders := app_root.try_camp_view_model().commander_hall_unlocked_commander_ids()
	assert_false(commanders.is_empty())
	if not commanders.is_empty():
		assert_eq(app_root.start_expedition(commanders[0], 0), &"")
	var original := first_repository.load()
	var untouched_late := late_repository.load()
	assert_true(original.ok)
	assert_eq(original.run_status, LoadResult.RunStatus.LOADED)
	assert_false(untouched_late.ok, "late repository must never replace the boot-bound repository")
	assert_eq(untouched_late.profile_status, LoadResult.ProfileStatus.NOT_FOUND)
	await _flush_freed_scenes()


func test_compose_failure_preserves_run_until_player_explicitly_discards_it() -> void:
	var storage := FakeSaveStorage.new()
	var first := _boot(self, storage)
	var commanders := first.app_root.try_camp_view_model().commander_hall_unlocked_commander_ids()
	assert_false(commanders.is_empty())
	if commanders.is_empty():
		return
	assert_eq(first.app_root.start_expedition(commanders[0], 0), &"")
	var active := first.repository.load()
	assert_true(active.ok)
	if not active.ok or active.run == null:
		return
	var expected_run_id := active.run.run_id
	var bytes_before := storage.file_bytes(StorageFaultKey.MAIN)

	var failed := _boot_with_root(self, storage, CompositionFailingApplicationRoot.new())
	assert_true(failed.app_root.is_booted())
	assert_eq(failed.app_root.app_state(), AppStateMachine.State.CAMP)
	assert_eq(
		storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value,
		"composition failure must not auto-delete the active run"
	)
	assert_true(failed.app_root.has_method("has_unresumable_active_run"))
	assert_true(failed.app_root.has_method("discard_unresumable_active_run"))
	if not failed.app_root.has_method("has_unresumable_active_run") \
		or not failed.app_root.has_method("discard_unresumable_active_run"):
		return
	assert_true(failed.app_root.call("has_unresumable_active_run"))
	assert_eq(failed.app_root.call("discard_unresumable_active_run"), &"")
	var discarded := failed.repository.load()
	assert_true(discarded.ok)
	if discarded.ok:
		assert_eq(discarded.run_status, LoadResult.RunStatus.NONE)
		assert_null(discarded.run)
	assert_false(failed.app_root.call("has_unresumable_active_run"))
	assert_ne(expected_run_id, "")
	await _flush_freed_scenes()

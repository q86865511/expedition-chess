extends GutTest

class ReentrantSaveObserver extends FakeStorageObserver:
	var repository: SaveRepository
	var root: SaveRoot
	var nested_save: SaveResult
	var nested_load: LoadResult
	var call_load: bool = false

	func before_operation(_key: StorageFaultKey) -> void:
		if nested_save != null or nested_load != null:
			return
		if call_load:
			nested_load = repository.load()
		else:
			nested_save = repository.save(root)

func test_first_save_and_load_commit_canonical_main() -> void:
	var storage := FakeSaveStorage.new()
	var repository := _repository(storage)
	var root := SaveRootFixture.create_valid_root()
	var saved := repository.save(root)
	assert_true(saved.ok)
	assert_not_null(storage.file_bytes(StorageFaultKey.MAIN))
	assert_null(storage.file_bytes(StorageFaultKey.TMP))
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_eq(loaded.profile.profile_id, root.profile.profile_id)

func test_second_save_rotates_main_to_backup() -> void:
	var storage := FakeSaveStorage.new()
	var repository := _repository(storage)
	var first := SaveRootFixture.create_valid_root()
	assert_true(repository.save(first).ok)
	var second := first.deep_clone()
	second.profile.meta_currency = 7
	assert_true(repository.save(second).ok)
	assert_not_null(storage.file_bytes(StorageFaultKey.MAIN))
	assert_not_null(storage.file_bytes(StorageFaultKey.BACKUP))
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.profile.meta_currency, 7)

func test_invalid_main_loads_backup_and_repairs_without_moving_only_backup_first() -> void:
	var storage := FakeSaveStorage.new()
	var repository := _repository(storage)
	var first := SaveRootFixture.create_valid_root()
	assert_true(repository.save(first).ok)
	var second := first.deep_clone()
	second.profile.meta_currency = 9
	assert_true(repository.save(second).ok)
	storage.seed_file(StorageFaultKey.MAIN, "{broken".to_utf8_buffer())
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.profile.meta_currency, 0)
	assert_eq(loaded.recovery_diagnostics[0].code, LoadDiagnostic.RECOVERED_BACKUP)
	var repaired := SaveRootFixture.create_codec().decode_bytes(
		storage.file_bytes(StorageFaultKey.MAIN).value
	)
	assert_true(repaired.ok)

func test_invalid_utf8_main_returns_named_error_when_no_backup_exists() -> void:
	var storage := FakeSaveStorage.new()
	storage.seed_file(StorageFaultKey.MAIN, PackedByteArray([0x80]))
	var repository := _repository(storage)
	var loaded := repository.load()
	assert_false(loaded.ok)
	assert_not_null(loaded.error)
	assert_eq(loaded.error.code, LoadError.UTF8_INVALID)

func test_invalid_utf8_backup_returns_named_error_when_main_is_missing() -> void:
	var storage := FakeSaveStorage.new()
	storage.seed_file(StorageFaultKey.BACKUP, PackedByteArray([0xc0, 0xaf]))
	var repository := _repository(storage)
	var loaded := repository.load()
	assert_false(loaded.ok)
	assert_not_null(loaded.error)
	assert_eq(loaded.error.code, LoadError.UTF8_INVALID)

func test_invalid_utf8_main_falls_back_to_valid_backup() -> void:
	var storage := FakeSaveStorage.new()
	var repository := _repository(storage)
	assert_true(repository.save(SaveRootFixture.create_valid_root()).ok)
	var committed := storage.file_bytes(StorageFaultKey.MAIN)
	storage.seed_file(StorageFaultKey.BACKUP, committed.value)
	storage.seed_file(StorageFaultKey.MAIN, PackedByteArray([0xf5, 0x80]))
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_eq(loaded.recovery_diagnostics[0].code, LoadDiagnostic.RECOVERED_BACKUP)


func test_schema_one_prepare_load_preserves_profile_and_original_committed_bytes() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.run_phase = RunState.RunPhase.PREPARE
	var legacy := _legacy_text(root, 1)
	var storage := FakeSaveStorage.new()
	storage.seed_file(StorageFaultKey.MAIN, legacy.to_utf8_buffer())
	var repository := _repository(storage)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
	assert_not_null(loaded.profile)
	assert_null(loaded.run)
	assert_eq(loaded.preserved_source_path.value, String(StorageFaultKey.MAIN))
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, legacy.to_utf8_buffer())


func test_schema_one_idle_load_uses_generation_port_without_mutating_source_file() -> void:
	var target_receipt := _migration_target_receipt()
	var migration_receipt := ContentGenerationMigrationReceipt.new(
		SaveRootFixture.MANIFEST_DIGEST,
		target_receipt.manifest_digest,
		"463ac1f542a942fb1dc8c3dea7f7647295e4635f9b02c57be7c3ea0a15bcaaa6",
		"2f7b38387cf9a69a2f9fa03f20b690f0098f5411097a4f96aa259db21076d2b9",
		"20d34a4e5b489b1bad34f7d86005d757442f4922ef73b8369a703aedc1920b15",
		1,
		2,
		"7c2ef65221a2ad4a84b923786500b2a974e560b6068e5a83393e783ae1524f65"
	)
	var generation_port := FakeContentGenerationMigrationPort.new(
		ContentGenerationMigrationResult.success(target_receipt, migration_receipt, null)
	)
	var legacy := _legacy_text(SaveRootFixture.create_valid_root(), 1)
	var storage := FakeSaveStorage.new()
	storage.seed_file(StorageFaultKey.MAIN, legacy.to_utf8_buffer())
	var repository := SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(target_receipt),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new(),
		generation_port
	)
	add_child_autofree(repository)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_eq(loaded.run.content_snapshot.content_version_value(), "fixture.2")
	assert_eq(loaded.run.content_snapshot.combat_config_id_value(), &"config.combat_default")
	assert_eq(generation_port.requests.size(), 1)
	assert_eq(storage.file_bytes(StorageFaultKey.MAIN).value, legacy.to_utf8_buffer())

func test_invalid_rng_dto_is_rejected_before_clone_or_storage_mutation() -> void:
	var storage := FakeSaveStorage.new()
	var root := SaveRootFixture.create_valid_root()
	root.run.rng_stream_states[0].snapshot.state = null
	var repository := _repository(storage)
	var saved := repository.save(root)
	assert_false(saved.ok)
	assert_eq(saved.error.code, SaveError.DTO_INVALID)
	assert_eq(storage.journal_snapshot().size(), 0)

func test_every_initial_save_storage_invocation_can_be_faulted() -> void:
	var baseline_storage := FakeSaveStorage.new()
	var baseline_repository := _repository(baseline_storage)
	assert_true(baseline_repository.save(SaveRootFixture.create_valid_root()).ok)
	var journal := baseline_storage.journal_snapshot()
	assert_gt(journal.size(), 0)
	for fault: StorageFaultKey in journal:
		var storage := FakeSaveStorage.new()
		storage.inject_fault(fault)
		var repository := _repository(storage)
		var result := repository.save(SaveRootFixture.create_valid_root())
		var label := "%s/%s/%d" % [fault.operation_kind, fault.logical_path, fault.occurrence]
		if result.ok:
			assert_eq(fault.operation_kind, StorageFaultKey.EXISTS, label)
			assert_eq(fault.logical_path, StorageFaultKey.OLD, label)
			assert_gt(result.warnings.size(), 0, label)
			assert_true(_file_valid(storage, StorageFaultKey.MAIN), label)
		else:
			assert_null(
				storage.file_bytes(StorageFaultKey.MAIN),
				"first pre-commit fault must not expose partial main: %s" % label
			)

func test_existing_committed_copy_survives_each_second_save_fault() -> void:
	var discovery := FakeSaveStorage.new()
	var discovery_repository := _repository(discovery)
	var first := SaveRootFixture.create_valid_root()
	assert_true(discovery_repository.save(first).ok)
	discovery.reset_journal()
	var second := first.deep_clone()
	second.profile.meta_currency = 10
	assert_true(discovery_repository.save(second).ok)
	var journal := discovery.journal_snapshot()
	for fault: StorageFaultKey in journal:
		var storage := FakeSaveStorage.new()
		var repository := _repository(storage)
		assert_true(repository.save(first).ok)
		storage.reset_journal()
		storage.inject_fault(fault)
		repository.save(second)
		var main_valid := _file_valid(storage, StorageFaultKey.MAIN)
		var backup_valid := _file_valid(storage, StorageFaultKey.BACKUP)
		assert_true(main_valid or backup_valid, "%s/%s/%d" % [fault.operation_kind, fault.logical_path, fault.occurrence])

func test_same_thread_reentrant_save_and_load_are_busy_before_second_storage_call() -> void:
	var storage := FakeSaveStorage.new()
	var repository := _repository(storage)
	var observer := ReentrantSaveObserver.new()
	observer.repository = repository
	observer.root = SaveRootFixture.create_valid_root()
	storage.set_observer(observer)
	var outer := repository.save(observer.root)
	assert_true(outer.ok)
	assert_not_null(observer.nested_save)
	assert_false(observer.nested_save.ok)
	assert_eq(observer.nested_save.error.code, SaveError.BUSY)
	storage.set_observer(null)
	var load_observer := ReentrantSaveObserver.new()
	load_observer.repository = repository
	load_observer.root = observer.root
	load_observer.call_load = true
	storage.set_observer(load_observer)
	var second_outer := repository.save(observer.root)
	assert_true(second_outer.ok)
	assert_not_null(load_observer.nested_load)
	assert_false(load_observer.nested_load.ok)
	assert_eq(load_observer.nested_load.error.code, LoadError.BUSY)

func test_registry_adapter_loads_matching_run_and_session_holds_generation_lease() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.1",
		[&"pack.core"]
	)
	assert_true(installed.ok)
	var root_ids: Array[StringName] = [
		&"commander.c0", &"unit.player_00", &"unit.player_01", &"unit.player_02",
	]
	var reward_ids: Array[StringName] = [&"reward_table.default"]
	var map_ids: Array[StringName] = [&"map_node.normal"]
	var challenge_ids: Array[StringName] = [
		&"unlock.challenge_0", &"unlock.challenge_1", &"unlock.challenge_2",
		&"unlock.challenge_3", &"unlock.challenge_4", &"unlock.challenge_5",
	]
	var selection := CatalogSelection.new(
		"fixture.1",
		root_ids,
		&"economy.default",
		&"config.combat_default",
		reward_ids,
		map_ids,
		challenge_ids,
		&"meta_reward.default"
	)
	var pinned := registry.compile_pinned_generation(selection)
	assert_true(pinned.ok)
	assert_not_null(pinned.receipt)
	assert_ne(pinned.handle.manifest_digest, installed.handle.manifest_digest)
	var root := SaveRootFixture.create_valid_root()
	root.profile.unlocked_content_ids = [&"commander.c0"]
	root.run.commander_id = &"commander.c0"
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(pinned.receipt)
	assert_true(snapshot_result.ok)
	root.run.content_snapshot = snapshot_result.snapshot
	var storage := FakeSaveStorage.new()
	var repository := SaveRepository.new(
		storage,
		ContentRegistryReceiptAdapter.new(registry),
		ContentRegistryMigrationAdapter.new(registry),
		RunStateValidator.new()
	)
	add_child_autofree(repository)
	assert_true(repository.save(root).ok)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_not_null(loaded.run)
	var session_result := RunSessionFactory.new(registry).create(loaded.profile, loaded.run)
	assert_true(session_result.ok)
	assert_true(session_result.session.has_catalog_pin())
	assert_false(registry._remove_unleased_generation(pinned.handle.manifest_digest))
	session_result = null
	assert_true(registry._remove_unleased_generation(pinned.handle.manifest_digest))

func test_content_port_composition_is_one_shot() -> void:
	var repository := SaveRepository.new(FakeSaveStorage.new())
	add_child_autofree(repository)
	var first := repository._configure_content_ports(
		FakePinnedCatalogReceiptPort.new(SaveRootFixture.create_receipt()),
		FakeContentIdMigrationPort.new()
	)
	assert_true(first.ok)
	var second := repository._configure_content_ports(
		FakePinnedCatalogReceiptPort.new(SaveRootFixture.create_receipt()),
		FakeContentIdMigrationPort.new()
	)
	assert_false(second.ok)
	assert_eq(second.error.code, SaveConfigurationError.ALREADY_CONFIGURED)

func test_run_session_factory_rejects_every_snapshot_receipt_mismatch_without_lease() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.1",
		[&"pack.core"]
	)
	assert_true(installed.ok)
	var root_ids: Array[StringName] = [
		&"commander.c0", &"unit.player_00", &"unit.player_01", &"unit.player_02",
	]
	var reward_ids: Array[StringName] = [&"reward_table.default"]
	var map_ids: Array[StringName] = [&"map_node.normal"]
	var challenge_ids: Array[StringName] = [
		&"unlock.challenge_0", &"unlock.challenge_1", &"unlock.challenge_2",
		&"unlock.challenge_3", &"unlock.challenge_4", &"unlock.challenge_5",
	]
	var selection := CatalogSelection.new(
		"fixture.1",
		root_ids,
		&"economy.default",
		&"config.combat_default",
		reward_ids,
		map_ids,
		challenge_ids,
		&"meta_reward.default"
	)
	var pinned := registry.compile_pinned_generation(selection)
	assert_true(pinned.ok)
	assert_not_null(pinned.receipt)
	var changed_active_ids: Array[StringName] = pinned.receipt.active_entry_ids.duplicate()
	changed_active_ids.remove_at(changed_active_ids.size() - 1)
	var changed_reward_ids: Array[StringName] = [&"reward_table.changed"]
	var changed_map_ids: Array[StringName] = [&"map_node.changed"]
	var changed_challenge_ids: Array[StringName] = [&"unlock.challenge_changed"]
	var mismatches: Array[ContentSnapshotState] = [
		_validated_snapshot_for_equality_test(
			"fixture.changed",
			pinned.receipt.active_entry_ids,
			pinned.receipt.economy_config_id,
			pinned.receipt.reward_table_ids,
			pinned.receipt.map_node_def_ids,
			pinned.receipt.challenge_unlock_def_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			changed_active_ids,
			pinned.receipt.economy_config_id,
			pinned.receipt.reward_table_ids,
			pinned.receipt.map_node_def_ids,
			pinned.receipt.challenge_unlock_def_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			pinned.receipt.active_entry_ids,
			&"economy.changed",
			pinned.receipt.reward_table_ids,
			pinned.receipt.map_node_def_ids,
			pinned.receipt.challenge_unlock_def_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			pinned.receipt.active_entry_ids,
			pinned.receipt.economy_config_id,
			changed_reward_ids,
			pinned.receipt.map_node_def_ids,
			pinned.receipt.challenge_unlock_def_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			pinned.receipt.active_entry_ids,
			pinned.receipt.economy_config_id,
			pinned.receipt.reward_table_ids,
			changed_map_ids,
			pinned.receipt.challenge_unlock_def_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			pinned.receipt.active_entry_ids,
			pinned.receipt.economy_config_id,
			pinned.receipt.reward_table_ids,
			pinned.receipt.map_node_def_ids,
			changed_challenge_ids,
			pinned.receipt.meta_reward_table_id,
			pinned.receipt.manifest_digest
		),
		_validated_snapshot_for_equality_test(
			pinned.receipt.content_version,
			pinned.receipt.active_entry_ids,
			pinned.receipt.economy_config_id,
			pinned.receipt.reward_table_ids,
			pinned.receipt.map_node_def_ids,
			pinned.receipt.challenge_unlock_def_ids,
			&"meta_reward.changed",
			pinned.receipt.manifest_digest
		),
	]
	var root := SaveRootFixture.create_valid_root()
	var unsealed_snapshot := ContentSnapshotState.new(
		pinned.receipt.content_version,
		pinned.receipt.active_entry_ids,
		pinned.receipt.economy_config_id,
		pinned.receipt.combat_config_id,
		pinned.receipt.reward_table_ids,
		pinned.receipt.map_node_def_ids,
		pinned.receipt.challenge_unlock_def_ids,
		pinned.receipt.meta_reward_table_id,
		pinned.receipt.manifest_digest
	)
	root.run.content_snapshot = unsealed_snapshot
	var unsealed_session := RunSessionFactory.new(registry).create(
		root.profile,
		root.run
	)
	assert_false(unsealed_session.ok)
	assert_eq(unsealed_session.error.code, RunSessionBuildError.INPUT_INVALID)
	var unsealed_storage := FakeSaveStorage.new()
	var unsealed_repository := _repository(unsealed_storage)
	var unsealed_save := unsealed_repository.save(root)
	assert_false(unsealed_save.ok)
	assert_eq(unsealed_save.error.code, SaveError.DTO_INVALID)
	assert_eq(unsealed_storage.journal_snapshot().size(), 0)
	assert_false(registry._lease_is_active(pinned.handle.manifest_digest))
	for snapshot: ContentSnapshotState in mismatches:
		root.run.content_snapshot = snapshot
		var result := RunSessionFactory.new(registry).create(root.profile, root.run)
		assert_false(result.ok)
		assert_eq(result.error.code, RunSessionBuildError.SNAPSHOT_MISMATCH)
		assert_false(registry._lease_is_active(pinned.handle.manifest_digest))
	assert_true(registry._remove_unleased_generation(pinned.handle.manifest_digest))


func _validated_snapshot_for_equality_test(
	content_version: String,
	enabled_content_ids: Array[StringName],
	economy_config_id: StringName,
	reward_table_ids: Array[StringName],
	map_node_def_ids: Array[StringName],
	challenge_unlock_def_ids: Array[StringName],
	meta_reward_table_id: StringName,
	manifest_digest: String,
	combat_config_id: StringName = &"config.combat_default"
) -> ContentSnapshotState:
	return ContentSnapshotState.new(
		content_version,
		enabled_content_ids,
		economy_config_id,
		combat_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id,
		manifest_digest,
		ContentSnapshotState._construction_seal
	)


func _repository(storage: SaveStoragePort) -> SaveRepository:
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	return repository


func _legacy_text(root: SaveRoot, schema: int) -> String:
	var encoded := SaveRootFixture.create_codec().encode(root)
	assert_true(encoded.ok)
	var text := encoded.json_text.value.replace(
		"\"schema_version\":%d" % SaveSchemaContract.CURRENT,
		"\"schema_version\":%d" % schema
	)
	text = text.replace(",\"combat_config_id\":\"config.combat_default\"", "")
	text = text.replace("\"config.combat_default\",", "")
	if schema <= 1:
		# 真正的 v1 舊檔 snapshot 沒有這兩個欄位(codec 2 起才寫入);留著會被
		# _exact_keys 判成自相矛盾 payload 而走 incompatible 而非 v1 遷移路徑
		text = text.replace("\"catalog_schema_version\":1,", "")
		text = text.replace("\"content_codec_version\":2,", "")
	if schema == 0:
		text = text.replace("\"hash_version\":1,", "")
	return text


func _migration_target_receipt() -> PinnedCatalogBuildReceipt:
	var source := SaveRootFixture.create_receipt()
	return PinnedCatalogBuildReceipt.new(
		1,
		2,
		"fixture.2",
		"4444444444444444444444444444444444444444444444444444444444444444",
		source.active_entry_ids,
		source.economy_config_id,
		&"config.combat_default",
		source.reward_table_ids,
		source.map_node_def_ids,
		source.challenge_unlock_def_ids,
		source.meta_reward_table_id,
		"3333333333333333333333333333333333333333333333333333333333333333"
	)

func _file_valid(storage: FakeSaveStorage, path: StringName) -> bool:
	var bytes := storage.file_bytes(path)
	if bytes == null:
		return false
	return SaveRootFixture.create_codec().decode_bytes(bytes.value).ok

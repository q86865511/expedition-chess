class_name SaveRepository
extends Node

var _storage: SaveStoragePort
var _codec: SaveJsonCodec
var _validator: RunStateValidator
var _migration_registry: SaveMigrationRegistry
var _generation_migration_port: ContentGenerationMigrationPort
var _operation_mutex := Mutex.new()
var _operation_in_progress: bool = false
var _content_ports_configured: bool = false
var _commit_repository_nonce: RefCounted = RefCounted.new()
var _consumed_commit_uses: Dictionary = {}

func _init(
	storage: SaveStoragePort = null,
	receipt_port: PinnedCatalogReceiptPort = null,
	migration_port: ContentIdMigrationPort = null,
	validator: RunStateValidator = null,
	generation_migration_port: ContentGenerationMigrationPort = null
) -> void:
	_storage = storage if storage != null else FileSaveStorage.new()
	var has_complete_port_pair := receipt_port != null and migration_port != null
	var has_no_ports := receipt_port == null and migration_port == null
	assert(has_complete_port_pair or has_no_ports, "SAVE_CONTENT_PORT_PAIR_REQUIRED")
	_codec = SaveJsonCodec.new(
		receipt_port if has_complete_port_pair else PinnedCatalogReceiptPort.new(),
		migration_port if has_complete_port_pair else ContentIdMigrationPort.new()
	)
	_content_ports_configured = has_complete_port_pair
	_validator = validator if validator != null else RunStateValidator.new()
	_generation_migration_port = generation_migration_port \
		if generation_migration_port != null else ContentGenerationMigrationPort.new()
	_migration_registry = SaveMigrationRegistry.new(_codec, _generation_migration_port)

func _configure_content_ports(
	receipt_port: PinnedCatalogReceiptPort,
	migration_port: ContentIdMigrationPort,
	generation_migration_port: ContentGenerationMigrationPort = null
) -> SaveConfigurationResult:
	if receipt_port == null or migration_port == null:
		return SaveConfigurationResult.failure(
			SaveConfigurationError.new(
				SaveConfigurationError.PORT_REQUIRED,
				&"content_ports"
			)
		)
	if not _begin_operation():
		return SaveConfigurationResult.failure(
			SaveConfigurationError.new(SaveConfigurationError.BUSY, &"repository")
		)
	if _content_ports_configured:
		_end_operation()
		return SaveConfigurationResult.failure(
			SaveConfigurationError.new(
				SaveConfigurationError.ALREADY_CONFIGURED,
				&"content_ports"
			)
		)
	_codec = SaveJsonCodec.new(receipt_port, migration_port)
	if generation_migration_port != null:
		_generation_migration_port = generation_migration_port
	_migration_registry = SaveMigrationRegistry.new(_codec, _generation_migration_port)
	_content_ports_configured = true
	_end_operation()
	return SaveConfigurationResult.success()

func save(state: SaveRoot) -> SaveResult:
	if not _begin_operation():
		return SaveResult.failure(SaveError.new(SaveError.BUSY, &"repository"))
	var result := _save_while_owned(state)
	_end_operation()
	return result

func load() -> LoadResult:
	if not _begin_operation():
		return LoadResult.failure(
			LoadError.new(LoadError.BUSY, &"repository"), LoadResult.ProfileStatus.INVALID
		)
	var result := _load_while_owned()
	_end_operation()
	return result

func migrate(raw_json_text: String) -> MigrationResult:
	if not _begin_operation():
		return MigrationResult.failure(
			UnknownSourceSchemaVersion.new(),
			MigrationError.new(MigrationError.BUSY, &"repository")
		)
	var result := _migration_registry.migrate(raw_json_text)
	_end_operation()
	return result

func _save_while_owned(state: SaveRoot) -> SaveResult:
	if state == null:
		return _save_failure(SaveError.DTO_INVALID, &"root")
	var source_validation := _validator.validate_root(state)
	if not source_validation.ok:
		return _save_failure(SaveError.DTO_INVALID, source_validation.error.field_path)
	var draft := state.deep_clone()
	var validation := _validator.validate_root(draft)
	if not validation.ok:
		return _save_failure(SaveError.DTO_INVALID, validation.error.field_path)
	var encoded := _codec.encode(draft)
	if not encoded.ok:
		return _save_failure(SaveError.CODEC_INVALID, encoded.error.field_path)
	var directory_result := _storage.ensure_directory()
	if not directory_result.ok:
		return _save_storage_failure(directory_result.error)
	var write_result := _write_file(StorageFaultKey.TMP, encoded.bytes.value)
	if not write_result.ok:
		return _save_storage_failure(write_result.error)
	var tmp := _read_candidate(StorageFaultKey.TMP)
	if tmp.storage_error != null:
		return _save_storage_failure(tmp.storage_error)
	if _candidate_has_utf8_error(tmp):
		return _save_failure(SaveError.UTF8_INVALID, &"tmp.bytes")
	if not tmp.valid or tmp.decoded.root == null or tmp.bytes != encoded.bytes.value:
		return _save_failure(SaveError.TMP_READBACK_INVALID, &"tmp")
	var main := _read_candidate(StorageFaultKey.MAIN)
	if main.storage_error != null:
		return _save_storage_failure(main.storage_error)
	var backup := _read_candidate(StorageFaultKey.BACKUP)
	if backup.storage_error != null:
		return _save_storage_failure(backup.storage_error)
	if (main.exists or backup.exists) and not main.valid and not backup.valid:
		if _candidate_has_utf8_error(main) or _candidate_has_utf8_error(backup):
			return _save_failure(SaveError.UTF8_INVALID, &"committed.bytes")
		return _save_failure(SaveError.NO_VALID_COMMITTED, &"committed")
	if main.valid:
		var prepare_old := _remove_if_exists(StorageFaultKey.OLD)
		if not prepare_old.ok:
			return _save_storage_failure(prepare_old.error)
		if backup.exists:
			if not backup.valid:
				var quarantine_backup := _quarantine_path(StorageFaultKey.BACKUP)
				if not quarantine_backup.ok:
					return _save_storage_failure(quarantine_backup.error)
			else:
				var old_result := _storage.rename(StorageFaultKey.BACKUP, StorageFaultKey.OLD)
				if not old_result.ok:
					return _save_storage_failure(old_result.error)
				if not _has_valid_committed():
					return _save_failure(SaveError.NO_VALID_COMMITTED, &"rotation.backup_to_old")
		var backup_result := _storage.rename(StorageFaultKey.MAIN, StorageFaultKey.BACKUP)
		if not backup_result.ok:
			return _save_storage_failure(backup_result.error)
		if not _has_valid_committed():
			return _save_failure(SaveError.NO_VALID_COMMITTED, &"rotation.main_to_backup")
	elif backup.valid and main.exists:
		var quarantine_main := _quarantine_path(StorageFaultKey.MAIN)
		if not quarantine_main.ok:
			return _save_storage_failure(quarantine_main.error)
	var promote := _storage.rename(StorageFaultKey.TMP, StorageFaultKey.MAIN)
	if not promote.ok:
		return _save_storage_failure(promote.error)
	var final_main := _read_candidate(StorageFaultKey.MAIN)
	if final_main.storage_error != null:
		return _recover_after_final_failure(final_main.storage_error, null)
	if not final_main.valid or final_main.decoded.root == null or final_main.bytes != encoded.bytes.value:
		return _recover_after_final_failure(null, final_main.codec_error)
	var warnings: Array[SaveWarning] = []
	var remove_old := _remove_if_exists(StorageFaultKey.OLD)
	if not remove_old.ok:
		warnings.append(SaveWarning.new(remove_old.error.code, &"old"))
	return SaveResult._repository_success(
		encoded.digest.value,
		warnings,
		_issue_commit_capability(
			PersistenceCommitCapability.SAVE,
			encoded.digest.value
		)
	)

func _load_while_owned() -> LoadResult:
	var directory_result := _storage.ensure_directory()
	if not directory_result.ok:
		return _load_storage_failure(directory_result.error)
	var main := _read_candidate(StorageFaultKey.MAIN)
	if main.storage_error != null:
		return _load_storage_failure(main.storage_error)
	if main.valid:
		return _to_load_result(main, false)
	var backup := _read_candidate(StorageFaultKey.BACKUP)
	if backup.storage_error != null:
		return _load_storage_failure(backup.storage_error)
	if backup.valid:
		var result := _to_load_result(backup, true)
		if backup.decoded.root != null:
			_repair_from_backup_while_owned(backup)
		return result
	if not main.exists and not backup.exists:
		return LoadResult.failure(
			LoadError.new(LoadError.NOT_FOUND, &"committed"),
			LoadResult.ProfileStatus.NOT_FOUND
		)
	if _candidate_has_utf8_error(main) or _candidate_has_utf8_error(backup):
		return LoadResult.failure(LoadError.new(LoadError.UTF8_INVALID, &"committed.bytes"))
	return LoadResult.failure(LoadError.new(LoadError.NO_VALID_COMMITTED, &"committed"))

func _to_load_result(candidate: StoredSaveCandidate, recovered_backup: bool) -> LoadResult:
	var diagnostics: Array[LoadDiagnostic] = []
	if recovered_backup:
		diagnostics.append(LoadDiagnostic.new(LoadDiagnostic.RECOVERED_BACKUP, &"backup"))
	for diagnostic: LoadDiagnostic in candidate.decoded.diagnostics:
		diagnostics.append(diagnostic.deep_clone())
	if candidate.decoded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
		return LoadResult._repository_success(
			candidate.decoded.profile, null, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED,
			OptionalStringValue.new(String(candidate.logical_path)), diagnostics,
			"", null
		)
	var root: SaveRoot = candidate.decoded.root
	var committed_digest := _commit_digest(candidate.bytes)
	var capability: PersistenceCommitCapability = null
	if root.run != null:
		capability = _issue_commit_capability(
			PersistenceCommitCapability.ACTIVE_RUN_LOAD,
			committed_digest
		)
	return LoadResult._repository_success(
		root.profile, root.run,
		LoadResult.RunStatus.LOADED if root.run != null else LoadResult.RunStatus.NONE,
		null,
		diagnostics,
		committed_digest if capability != null else "",
		capability
	)

func _consume_save_commit(result: SaveResult) -> bool:
	if result == null \
		or not result.ok \
		or result.committed_digest == null \
		or result._commit_capability == null:
		return false
	if not result._commit_capability._matches(
		_commit_repository_nonce,
		PersistenceCommitCapability.SAVE,
		result.committed_digest.value
	):
		return false
	return _consume_capability_once(result._commit_capability)

func _consume_active_run_load(result: LoadResult) -> bool:
	if result == null \
		or not result.ok \
		or result.run_status != LoadResult.RunStatus.LOADED \
		or result.run == null \
		or result._commit_capability == null:
		return false
	if not result._commit_capability._matches(
		_commit_repository_nonce,
		PersistenceCommitCapability.ACTIVE_RUN_LOAD,
		result._committed_digest
	):
		return false
	return _consume_capability_once(result._commit_capability)

func _issue_commit_capability(
	kind: StringName,
	committed_digest: String
) -> PersistenceCommitCapability:
	return PersistenceCommitCapability.new(
		_commit_repository_nonce,
		RefCounted.new(),
		kind,
		committed_digest
	)

func _consume_capability_once(capability: PersistenceCommitCapability) -> bool:
	var use_identity := capability._use_identity()
	if use_identity == null:
		return false
	_operation_mutex.lock()
	if _consumed_commit_uses.has(use_identity):
		_operation_mutex.unlock()
		return false
	_consumed_commit_uses[use_identity] = true
	_operation_mutex.unlock()
	return true

func _commit_digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func _repair_from_backup_while_owned(backup: StoredSaveCandidate) -> void:
	var write_result := _write_file(StorageFaultKey.TMP, backup.bytes)
	if not write_result.ok:
		return
	var tmp := _read_candidate(StorageFaultKey.TMP)
	if not tmp.valid or tmp.bytes != backup.bytes:
		return
	var main_exists := _storage.exists(StorageFaultKey.MAIN)
	if not main_exists.ok:
		return
	if main_exists.exists.value:
		var quarantine_result := _quarantine_path(StorageFaultKey.MAIN)
		if not quarantine_result.ok:
			return
	var promote := _storage.rename(StorageFaultKey.TMP, StorageFaultKey.MAIN)
	if not promote.ok:
		return
	var final_main := _read_candidate(StorageFaultKey.MAIN)
	if not final_main.valid or final_main.bytes != backup.bytes:
		var quarantine_result := _quarantine_path(StorageFaultKey.MAIN)
		if not quarantine_result.ok:
			return

func _recover_after_final_failure(
	storage_error: StorageError,
	codec_error: SaveCodecError
) -> SaveResult:
	var main_exists := _storage.exists(StorageFaultKey.MAIN)
	if main_exists.ok and main_exists.exists.value:
		var quarantine_result := _quarantine_path(StorageFaultKey.MAIN)
		if not quarantine_result.ok:
			return _save_failure(SaveError.RESTORE_FAILED, &"main", quarantine_result.error)
	var backup := _read_candidate(StorageFaultKey.BACKUP)
	if backup.storage_error != null:
		return _save_failure(SaveError.RESTORE_FAILED, &"backup", backup.storage_error)
	if backup.valid:
		var restore := _storage.restore(StorageFaultKey.BACKUP, StorageFaultKey.MAIN)
		if not restore.ok:
			return _save_failure(SaveError.RESTORE_FAILED, &"backup", restore.error)
		var restored := _read_candidate(StorageFaultKey.MAIN)
		if not restored.valid:
			return _save_failure(SaveError.RESTORE_FAILED, &"main")
	if codec_error != null and codec_error.code == SaveCodecError.UTF8_INVALID:
		return _save_failure(SaveError.UTF8_INVALID, &"main.bytes", storage_error)
	return _save_failure(SaveError.FINAL_READBACK_INVALID, &"main", storage_error)

func _write_file(path: StringName, bytes: PackedByteArray) -> StorageVoidResult:
	var opened := _storage.open_write(path)
	if not opened.ok:
		return StorageVoidResult.failure(opened.error)
	var written := _storage.write_buffer(opened.handle, bytes)
	if not written.ok:
		_storage.close_write(opened.handle)
		return written
	var flushed := _storage.flush_write(opened.handle)
	if not flushed.ok:
		_storage.close_write(opened.handle)
		return flushed
	return _storage.close_write(opened.handle)

func _read_candidate(path: StringName) -> StoredSaveCandidate:
	var exists_result := _storage.exists(path)
	if not exists_result.ok:
		return StoredSaveCandidate.io_failure(path, exists_result.error)
	if not exists_result.exists.value:
		return StoredSaveCandidate.missing(path)
	var opened := _storage.open_read(path)
	if not opened.ok:
		return StoredSaveCandidate.io_failure(path, opened.error)
	var read := _storage.read_all(opened.handle)
	if not read.ok:
		_storage.close_read(opened.handle)
		return StoredSaveCandidate.io_failure(path, read.error)
	var closed := _storage.close_read(opened.handle)
	if not closed.ok:
		return StoredSaveCandidate.io_failure(path, closed.error)
	var bytes := read.bytes.value
	var decoded := _codec.decode_bytes(bytes)
	if not decoded.ok:
		if decoded.error.code == SaveCodecError.UTF8_INVALID:
			return StoredSaveCandidate.invalid(path, bytes, decoded.error)
		var migrated := _migration_registry.migrate(bytes.get_string_from_utf8())
		if not migrated.ok:
			return StoredSaveCandidate.invalid(
				path,
				bytes,
				SaveCodecError.new(migrated.error.field_path)
			)
		if migrated.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
			decoded = SaveDecodeResult.incompatible(
				migrated.profile,
				migrated.incompatible_content_ids,
				migrated.diagnostics
			)
		elif migrated.root != null:
			decoded = SaveDecodeResult.success(
				migrated.root,
				LoadResult.RunStatus.LOADED if migrated.root.run != null \
					else LoadResult.RunStatus.NONE,
				migrated.incompatible_content_ids,
				migrated.diagnostics
			)
		else:
			return StoredSaveCandidate.invalid(path, bytes, SaveCodecError.new(&"root"))
	return StoredSaveCandidate.decoded_value(path, bytes, decoded)

func _candidate_has_utf8_error(candidate: StoredSaveCandidate) -> bool:
	return candidate != null and candidate.codec_error != null \
		and candidate.codec_error.code == SaveCodecError.UTF8_INVALID

func _has_valid_committed() -> bool:
	var main := _read_candidate(StorageFaultKey.MAIN)
	if main.storage_error == null and main.valid:
		return true
	var backup := _read_candidate(StorageFaultKey.BACKUP)
	return backup.storage_error == null and backup.valid

func _quarantine_path(path: StringName) -> StorageVoidResult:
	var remove_existing := _remove_if_exists(StorageFaultKey.QUARANTINE_PATH)
	if not remove_existing.ok:
		return remove_existing
	return _storage.quarantine(path)

func _remove_if_exists(path: StringName) -> StorageVoidResult:
	var exists_result := _storage.exists(path)
	if not exists_result.ok:
		return StorageVoidResult.failure(exists_result.error)
	if not exists_result.exists.value:
		return StorageVoidResult.success()
	return _storage.remove(path)

func _begin_operation() -> bool:
	if not _operation_mutex.try_lock():
		return false
	if _operation_in_progress:
		_operation_mutex.unlock()
		return false
	_operation_in_progress = true
	_operation_mutex.unlock()
	return true

func _end_operation() -> void:
	_operation_mutex.lock()
	_operation_in_progress = false
	_operation_mutex.unlock()

func _save_storage_failure(error: StorageError) -> SaveResult:
	return _save_failure(error.code, &"storage", error)

func _save_failure(
	code: StringName,
	path: StringName,
	storage_error: StorageError = null
) -> SaveResult:
	var diagnostics: Array[DiagnosticValue] = []
	return SaveResult.failure(SaveError.new(code, path, null, diagnostics, storage_error))

func _load_storage_failure(error: StorageError) -> LoadResult:
	var diagnostics: Array[DiagnosticValue] = []
	return LoadResult.failure(LoadError.new(error.code, &"storage", null, diagnostics, error))

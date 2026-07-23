class_name BuildLabMemoryStorage
extends SaveStoragePort

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒的 in-memory
## SaveStoragePort:讓 RunController 走真正的 SaveRepository.save()/load()
## copy-validate-save-swap 交易(HANDOFF §2 契約要求 command 一律經此交易),
## 但不落地寫入玩家真實存檔目錄(FileSaveStorage 預設路徑與正式遊戲共用,
## 開發灰盒不應該去動它)。行為鏡射 tests/fixtures/save/fake_save_storage.gd
## 的 rename/quarantine/restore 語意,但不含該檔案的錯誤注入測試掛鉤。

var _files: Dictionary = {} # StringName logical_path -> PackedByteArray

func ensure_directory() -> StorageVoidResult:
	return StorageVoidResult.success()

func exists(logical_path: StringName) -> StorageExistsResult:
	return StorageExistsResult.success(_files.has(logical_path))

func open_write(logical_path: StringName) -> StorageWriteHandleResult:
	return StorageWriteHandleResult.success(StorageWriteHandle.new(logical_path))

func write_buffer(handle: StorageWriteHandle, bytes: PackedByteArray) -> StorageVoidResult:
	if handle == null:
		return StorageVoidResult.failure(_error(StorageError.WRITE_FAILED, StorageFaultKey.WRITE, &"invalid_handle"))
	_pending[handle.logical_path] = bytes.duplicate()
	return StorageVoidResult.success()

func flush_write(_handle: StorageWriteHandle) -> StorageVoidResult:
	return StorageVoidResult.success()

func close_write(handle: StorageWriteHandle) -> StorageVoidResult:
	if handle == null or not _pending.has(handle.logical_path):
		return StorageVoidResult.failure(_error(StorageError.CLOSE_FAILED, StorageFaultKey.CLOSE, &"invalid_handle"))
	_files[handle.logical_path] = _pending[handle.logical_path]
	_pending.erase(handle.logical_path)
	return StorageVoidResult.success()

func open_read(logical_path: StringName) -> StorageReadHandleResult:
	if not _files.has(logical_path):
		return StorageReadHandleResult.failure(_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_READ, logical_path))
	return StorageReadHandleResult.success(StorageReadHandle.new(logical_path))

func read_all(handle: StorageReadHandle) -> StorageReadResult:
	if handle == null or not _files.has(handle.logical_path):
		return StorageReadResult.failure(_error(StorageError.READ_FAILED, StorageFaultKey.READ, &"invalid_handle"))
	return StorageReadResult.success((_files[handle.logical_path] as PackedByteArray).duplicate())

func close_read(_handle: StorageReadHandle) -> StorageVoidResult:
	return StorageVoidResult.success()

func rename(source: StringName, destination: StringName) -> StorageVoidResult:
	if not _files.has(source) or _files.has(destination):
		return StorageVoidResult.failure(_error(StorageError.RENAME_FAILED, StorageFaultKey.RENAME, source))
	_files[destination] = _files[source]
	_files.erase(source)
	return StorageVoidResult.success()

func quarantine(source: StringName) -> StorageVoidResult:
	return rename(source, StorageFaultKey.QUARANTINE_PATH)

func restore(source: StringName, destination: StringName) -> StorageVoidResult:
	if not _files.has(source):
		return StorageVoidResult.failure(_error(StorageError.RESTORE_FAILED, StorageFaultKey.RESTORE, source))
	_files[destination] = _files[source]
	return StorageVoidResult.success()

func remove(logical_path: StringName) -> StorageVoidResult:
	_files.erase(logical_path)
	return StorageVoidResult.success()

var _pending: Dictionary = {} # logical_path -> PackedByteArray awaiting close_write

func _error(code: StringName, operation: StringName, path: StringName) -> StorageError:
	return StorageError.new(code, operation, path, 0)

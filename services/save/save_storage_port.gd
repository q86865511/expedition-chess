class_name SaveStoragePort
extends RefCounted

func ensure_directory() -> StorageVoidResult:
	return _unsupported(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, StorageError.DIRECTORY_FAILED)

func exists(logical_path: StringName) -> StorageExistsResult:
	return StorageExistsResult.failure(_error(StorageError.EXISTS_FAILED, StorageFaultKey.EXISTS, logical_path))

func open_write(logical_path: StringName) -> StorageWriteHandleResult:
	return StorageWriteHandleResult.failure(_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_WRITE, logical_path))

func write_buffer(handle: StorageWriteHandle, _bytes: PackedByteArray) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.WRITE, _write_handle_path(handle), StorageError.WRITE_FAILED)

func flush_write(handle: StorageWriteHandle) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.FLUSH, _write_handle_path(handle), StorageError.FLUSH_FAILED)

func close_write(handle: StorageWriteHandle) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.CLOSE, _write_handle_path(handle), StorageError.CLOSE_FAILED)

func open_read(logical_path: StringName) -> StorageReadHandleResult:
	return StorageReadHandleResult.failure(_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_READ, logical_path))

func read_all(handle: StorageReadHandle) -> StorageReadResult:
	return StorageReadResult.failure(_error(StorageError.READ_FAILED, StorageFaultKey.READ, _read_handle_path(handle)))

func close_read(handle: StorageReadHandle) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.CLOSE, _read_handle_path(handle), StorageError.CLOSE_FAILED)

func rename(source: StringName, _destination: StringName) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.RENAME, source, StorageError.RENAME_FAILED)

func quarantine(source: StringName) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.QUARANTINE, source, StorageError.QUARANTINE_FAILED)

func restore(source: StringName, _destination: StringName) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.RESTORE, source, StorageError.RESTORE_FAILED)

func remove(logical_path: StringName) -> StorageVoidResult:
	return _unsupported(StorageFaultKey.REMOVE, logical_path, StorageError.REMOVE_FAILED)

func _unsupported(operation: StringName, path: StringName, code: StringName) -> StorageVoidResult:
	return StorageVoidResult.failure(_error(code, operation, path))

func _error(code: StringName, operation: StringName, path: StringName) -> StorageError:
	return StorageError.new(code, operation, path, 0)

func _write_handle_path(handle: StorageWriteHandle) -> StringName:
	return handle.logical_path if handle != null else &"invalid_handle"

func _read_handle_path(handle: StorageReadHandle) -> StringName:
	return handle.logical_path if handle != null else &"invalid_handle"

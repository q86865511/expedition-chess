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

## Enumerates adapter-owned logical files so the repository can discard
## transaction residue before selecting an authoritative save. File-backed
## adapters override this directly. In-memory adapters used by deterministic
## tests expose their stored-file collection as an inherited object property;
## this conservative fallback only reads entries carrying a logical_path.
func logical_paths() -> Array[StringName]:
	var output: Array[StringName] = []
	if not _has_property(self, &"_files"):
		return output
	var stored_files: Variant = get("_files")
	if stored_files is Array:
		for stored: Variant in stored_files:
			if stored is Object and _has_property(stored, &"logical_path"):
				output.append(StringName(stored.get("logical_path")))
	return output

func _unsupported(operation: StringName, path: StringName, code: StringName) -> StorageVoidResult:
	return StorageVoidResult.failure(_error(code, operation, path))

func _error(code: StringName, operation: StringName, path: StringName) -> StorageError:
	return StorageError.new(code, operation, path, 0)

func _write_handle_path(handle: StorageWriteHandle) -> StringName:
	return handle.logical_path if handle != null else &"invalid_handle"

func _read_handle_path(handle: StorageReadHandle) -> StringName:
	return handle.logical_path if handle != null else &"invalid_handle"

func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false

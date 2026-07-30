class_name FileSaveStorage
extends SaveStoragePort

const _BASE_DIR: String = "user://saves"
const _RECOVERY_DIR: String = "user://saves/recovery"
const _RECOVERY_PREFIX: String = "recovery/"

func ensure_directory() -> StorageVoidResult:
	var absolute := ProjectSettings.globalize_path(_BASE_DIR)
	var result := DirAccess.make_dir_recursive_absolute(absolute)
	if result != OK:
		return StorageVoidResult.failure(_storage_error(StorageError.DIRECTORY_FAILED, StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN))
	var recovery_result := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_RECOVERY_DIR)
	)
	if recovery_result != OK:
		return StorageVoidResult.failure(_storage_error(
			StorageError.DIRECTORY_FAILED,
			StorageFaultKey.DIRECTORY,
			&"recovery"
		))
	return StorageVoidResult.success()

func exists(logical_path: StringName) -> StorageExistsResult:
	var path_result := _path_for(logical_path)
	if path_result.is_empty():
		return StorageExistsResult.failure(_storage_error(StorageError.EXISTS_FAILED, StorageFaultKey.EXISTS, logical_path))
	return StorageExistsResult.success(FileAccess.file_exists(path_result))

func open_write(logical_path: StringName) -> StorageWriteHandleResult:
	var path := _path_for(logical_path)
	if path.is_empty():
		return StorageWriteHandleResult.failure(_storage_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_WRITE, logical_path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return StorageWriteHandleResult.failure(_storage_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_WRITE, logical_path))
	return StorageWriteHandleResult.success(FileStorageWriteHandle.new(logical_path, file))

func write_buffer(handle: StorageWriteHandle, bytes: PackedByteArray) -> StorageVoidResult:
	if not handle is FileStorageWriteHandle:
		return _invalid_write_handle(StorageFaultKey.WRITE, handle)
	var file_handle: FileStorageWriteHandle = handle
	if file_handle.file == null or not file_handle.file.is_open():
		return _invalid_write_handle(StorageFaultKey.WRITE, handle)
	file_handle.file.store_buffer(bytes)
	if file_handle.file.get_error() != OK:
		return StorageVoidResult.failure(_storage_error(StorageError.WRITE_FAILED, StorageFaultKey.WRITE, handle.logical_path))
	return StorageVoidResult.success()

func flush_write(handle: StorageWriteHandle) -> StorageVoidResult:
	if not handle is FileStorageWriteHandle:
		return _invalid_write_handle(StorageFaultKey.FLUSH, handle)
	var file_handle: FileStorageWriteHandle = handle
	if file_handle.file == null or not file_handle.file.is_open():
		return _invalid_write_handle(StorageFaultKey.FLUSH, handle)
	file_handle.file.flush()
	if file_handle.file.get_error() != OK:
		return StorageVoidResult.failure(_storage_error(StorageError.FLUSH_FAILED, StorageFaultKey.FLUSH, handle.logical_path))
	return StorageVoidResult.success()

func close_write(handle: StorageWriteHandle) -> StorageVoidResult:
	if not handle is FileStorageWriteHandle:
		return _invalid_write_handle(StorageFaultKey.CLOSE, handle)
	var file_handle: FileStorageWriteHandle = handle
	if file_handle.file == null or not file_handle.file.is_open():
		return _invalid_write_handle(StorageFaultKey.CLOSE, handle)
	var previous_error := file_handle.file.get_error()
	file_handle.file.close()
	file_handle.file = null
	if previous_error != OK:
		return StorageVoidResult.failure(_storage_error(StorageError.CLOSE_FAILED, StorageFaultKey.CLOSE, handle.logical_path))
	return StorageVoidResult.success()

func open_read(logical_path: StringName) -> StorageReadHandleResult:
	var path := _path_for(logical_path)
	if path.is_empty():
		return StorageReadHandleResult.failure(_storage_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_READ, logical_path))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return StorageReadHandleResult.failure(_storage_error(StorageError.OPEN_FAILED, StorageFaultKey.OPEN_READ, logical_path))
	return StorageReadHandleResult.success(FileStorageReadHandle.new(logical_path, file))

func read_all(handle: StorageReadHandle) -> StorageReadResult:
	if not handle is FileStorageReadHandle:
		return _invalid_read_handle(StorageFaultKey.READ, handle)
	var file_handle: FileStorageReadHandle = handle
	if file_handle.file == null or not file_handle.file.is_open():
		return _invalid_read_handle(StorageFaultKey.READ, handle)
	var bytes := file_handle.file.get_buffer(file_handle.file.get_length())
	if file_handle.file.get_error() != OK:
		return StorageReadResult.failure(_storage_error(StorageError.READ_FAILED, StorageFaultKey.READ, handle.logical_path))
	return StorageReadResult.success(bytes)

func close_read(handle: StorageReadHandle) -> StorageVoidResult:
	if not handle is FileStorageReadHandle:
		return _invalid_read_close(handle)
	var file_handle: FileStorageReadHandle = handle
	if file_handle.file == null or not file_handle.file.is_open():
		return _invalid_read_close(handle)
	var previous_error := file_handle.file.get_error()
	file_handle.file.close()
	file_handle.file = null
	if previous_error != OK and previous_error != ERR_FILE_EOF:
		return StorageVoidResult.failure(_storage_error(StorageError.CLOSE_FAILED, StorageFaultKey.CLOSE, handle.logical_path))
	return StorageVoidResult.success()

func rename(source: StringName, destination: StringName) -> StorageVoidResult:
	return _rename_with_code(source, destination, StorageFaultKey.RENAME, StorageError.RENAME_FAILED)

func quarantine(source: StringName) -> StorageVoidResult:
	return _rename_with_code(source, StorageFaultKey.QUARANTINE_PATH, StorageFaultKey.QUARANTINE, StorageError.QUARANTINE_FAILED)

func restore(source: StringName, destination: StringName) -> StorageVoidResult:
	return _rename_with_code(source, destination, StorageFaultKey.RESTORE, StorageError.RESTORE_FAILED)

func remove(logical_path: StringName) -> StorageVoidResult:
	var path := _path_for(logical_path)
	if path.is_empty():
		return StorageVoidResult.failure(_storage_error(StorageError.REMOVE_FAILED, StorageFaultKey.REMOVE, logical_path))
	if not FileAccess.file_exists(path):
		return StorageVoidResult.success()
	var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if result != OK:
		return StorageVoidResult.failure(_storage_error(StorageError.REMOVE_FAILED, StorageFaultKey.REMOVE, logical_path))
	return StorageVoidResult.success()

func logical_paths() -> Array[StringName]:
	var output: Array[StringName] = []
	for path: StringName in [
		StorageFaultKey.MAIN,
		StorageFaultKey.BACKUP,
		StorageFaultKey.TMP,
		StorageFaultKey.OLD,
		StorageFaultKey.QUARANTINE_PATH,
	]:
		var resolved := _path_for(path)
		if not resolved.is_empty() and FileAccess.file_exists(resolved):
			output.append(path)
	var recovery := DirAccess.open(_RECOVERY_DIR)
	if recovery == null:
		return output
	recovery.list_dir_begin()
	var file_name := recovery.get_next()
	while not file_name.is_empty():
		if not recovery.current_is_dir():
			output.append(StringName(_RECOVERY_PREFIX + file_name))
		file_name = recovery.get_next()
	recovery.list_dir_end()
	return output

func _rename_with_code(
	source: StringName,
	destination: StringName,
	operation: StringName,
	code: StringName
) -> StorageVoidResult:
	var source_path := _path_for(source)
	var destination_path := _path_for(destination)
	if source_path.is_empty() or destination_path.is_empty():
		return StorageVoidResult.failure(_storage_error(code, operation, source))
	var result := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source_path),
		ProjectSettings.globalize_path(destination_path)
	)
	if result != OK:
		return StorageVoidResult.failure(_storage_error(code, operation, source))
	return StorageVoidResult.success()

func _path_for(logical_path: StringName) -> String:
	match logical_path:
		StorageFaultKey.MAIN:
			return _BASE_DIR + "/save.json"
		StorageFaultKey.BACKUP:
			return _BASE_DIR + "/save.backup.json"
		StorageFaultKey.TMP:
			return _BASE_DIR + "/save.tmp.json"
		StorageFaultKey.OLD:
			return _BASE_DIR + "/save.old.json"
		StorageFaultKey.QUARANTINE_PATH:
			return _BASE_DIR + "/save.corrupt.json"
		_:
			var dynamic_path := String(logical_path)
			if _is_safe_recovery_path(dynamic_path):
				return _BASE_DIR + "/" + dynamic_path
			return ""

func _is_safe_recovery_path(logical_path: String) -> bool:
	if not logical_path.begins_with(_RECOVERY_PREFIX):
		return false
	var file_name := logical_path.trim_prefix(_RECOVERY_PREFIX)
	return (
		not file_name.is_empty()
		and not file_name.contains("/")
		and not file_name.contains("\\")
		and not file_name.contains("..")
	)

func _storage_error(code: StringName, operation: StringName, path: StringName) -> StorageError:
	return StorageError.new(code, operation, path, 0)

func _invalid_write_handle(
	operation: StringName,
	handle: StorageWriteHandle
) -> StorageVoidResult:
	return StorageVoidResult.failure(_storage_error(
		StorageError.INVALID_HANDLE, operation, _write_handle_path(handle)
	))

func _invalid_read_handle(
	operation: StringName,
	handle: StorageReadHandle
) -> StorageReadResult:
	return StorageReadResult.failure(_storage_error(
		StorageError.INVALID_HANDLE, operation, _read_handle_path(handle)
	))

func _invalid_read_close(handle: StorageReadHandle) -> StorageVoidResult:
	return StorageVoidResult.failure(_storage_error(
		StorageError.INVALID_HANDLE, StorageFaultKey.CLOSE, _read_handle_path(handle)
	))

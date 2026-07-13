extends GutTest

func test_write_handle_failures_are_null_type_and_closed_safe() -> void:
	var storage := FileSaveStorage.new()
	var null_handle: StorageWriteHandle = null
	_assert_write_error(storage.write_buffer(null_handle, PackedByteArray()), StorageFaultKey.WRITE)
	_assert_write_error(storage.flush_write(null_handle), StorageFaultKey.FLUSH)
	_assert_write_error(storage.close_write(null_handle), StorageFaultKey.CLOSE)

	var wrong_type := StorageWriteHandle.new(StorageFaultKey.MAIN)
	_assert_write_error(storage.write_buffer(wrong_type, PackedByteArray()), StorageFaultKey.WRITE)
	_assert_write_error(storage.flush_write(wrong_type), StorageFaultKey.FLUSH)
	_assert_write_error(storage.close_write(wrong_type), StorageFaultKey.CLOSE)

	var closed := FileStorageWriteHandle.new(StorageFaultKey.MAIN, null)
	_assert_write_error(storage.write_buffer(closed, PackedByteArray()), StorageFaultKey.WRITE)
	_assert_write_error(storage.flush_write(closed), StorageFaultKey.FLUSH)
	_assert_write_error(storage.close_write(closed), StorageFaultKey.CLOSE)

func test_read_handle_failures_are_null_type_and_closed_safe() -> void:
	var storage := FileSaveStorage.new()
	var null_handle: StorageReadHandle = null
	_assert_read_error(storage.read_all(null_handle), StorageFaultKey.READ)
	_assert_close_error(storage.close_read(null_handle))

	var wrong_type := StorageReadHandle.new(StorageFaultKey.MAIN)
	_assert_read_error(storage.read_all(wrong_type), StorageFaultKey.READ)
	_assert_close_error(storage.close_read(wrong_type))

	var closed := FileStorageReadHandle.new(StorageFaultKey.MAIN, null)
	_assert_read_error(storage.read_all(closed), StorageFaultKey.READ)
	_assert_close_error(storage.close_read(closed))

func test_invalid_logical_paths_return_stable_named_errors() -> void:
	var storage := FileSaveStorage.new()
	var exists_result := storage.exists(&"invalid")
	assert_false(exists_result.ok)
	assert_eq(exists_result.error.code, StorageError.EXISTS_FAILED)
	var open_write_result := storage.open_write(&"invalid")
	assert_false(open_write_result.ok)
	assert_eq(open_write_result.error.code, StorageError.OPEN_FAILED)
	var open_read_result := storage.open_read(&"invalid")
	assert_false(open_read_result.ok)
	assert_eq(open_read_result.error.code, StorageError.OPEN_FAILED)
	var rename_result := storage.rename(&"invalid", StorageFaultKey.MAIN)
	assert_false(rename_result.ok)
	assert_eq(rename_result.error.code, StorageError.RENAME_FAILED)
	var quarantine_result := storage.quarantine(&"invalid")
	assert_false(quarantine_result.ok)
	assert_eq(quarantine_result.error.code, StorageError.QUARANTINE_FAILED)
	var restore_result := storage.restore(&"invalid", StorageFaultKey.MAIN)
	assert_false(restore_result.ok)
	assert_eq(restore_result.error.code, StorageError.RESTORE_FAILED)
	var remove_result := storage.remove(&"invalid")
	assert_false(remove_result.ok)
	assert_eq(remove_result.error.code, StorageError.REMOVE_FAILED)

func _assert_write_error(result: StorageVoidResult, operation: StringName) -> void:
	assert_false(result.ok)
	assert_not_null(result.error)
	assert_eq(result.error.code, StorageError.INVALID_HANDLE)
	assert_eq(result.error.operation_kind, operation)

func _assert_read_error(result: StorageReadResult, operation: StringName) -> void:
	assert_false(result.ok)
	assert_not_null(result.error)
	assert_eq(result.error.code, StorageError.INVALID_HANDLE)
	assert_eq(result.error.operation_kind, operation)

func _assert_close_error(result: StorageVoidResult) -> void:
	_assert_write_error(result, StorageFaultKey.CLOSE)

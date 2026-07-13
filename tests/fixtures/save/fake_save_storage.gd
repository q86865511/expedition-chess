class_name FakeSaveStorage
extends SaveStoragePort

var _files: Array[FakeStoredFile] = []
var _faults: Array[StorageFaultKey] = []
var _journal: Array[StorageFaultKey] = []
var _counters: Array[FakeOccurrenceCounter] = []
var _observer: FakeStorageObserver

func set_observer(observer: FakeStorageObserver) -> void:
	_observer = observer

func inject_fault(key: StorageFaultKey) -> void:
	_faults.append(key.deep_clone())

func clear_faults() -> void:
	_faults.clear()

func reset_journal() -> void:
	_journal.clear()
	_counters.clear()

func journal_snapshot() -> Array[StorageFaultKey]:
	var output: Array[StorageFaultKey] = []
	for key: StorageFaultKey in _journal:
		output.append(key.deep_clone())
	return output

func seed_file(logical_path: StringName, bytes: PackedByteArray) -> void:
	_set_file(logical_path, bytes)

func file_bytes(logical_path: StringName) -> OptionalBytesValue:
	var file := _find_file(logical_path)
	return OptionalBytesValue.new(file.bytes) if file != null else null

func ensure_directory() -> StorageVoidResult:
	var key := _record(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN)
	if _should_fail(key):
		return _void_failure(&"SAVE_IO_DIRECTORY", key)
	return StorageVoidResult.success()

func exists(logical_path: StringName) -> StorageExistsResult:
	var key := _record(StorageFaultKey.EXISTS, logical_path)
	if _should_fail(key):
		return StorageExistsResult.failure(_make_error(&"SAVE_IO_EXISTS", key))
	return StorageExistsResult.success(_find_file(logical_path) != null)

func open_write(logical_path: StringName) -> StorageWriteHandleResult:
	var key := _record(StorageFaultKey.OPEN_WRITE, logical_path)
	if _should_fail(key):
		return StorageWriteHandleResult.failure(_make_error(&"SAVE_IO_OPEN", key))
	return StorageWriteHandleResult.success(FakeStorageWriteHandle.new(logical_path))

func write_buffer(handle: StorageWriteHandle, bytes: PackedByteArray) -> StorageVoidResult:
	var key := _record(StorageFaultKey.WRITE, handle.logical_path)
	if _should_fail(key) or not handle is FakeStorageWriteHandle:
		return _void_failure(&"SAVE_IO_WRITE", key)
	var fake: FakeStorageWriteHandle = handle
	fake.pending_bytes = bytes.duplicate()
	return StorageVoidResult.success()

func flush_write(handle: StorageWriteHandle) -> StorageVoidResult:
	var key := _record(StorageFaultKey.FLUSH, handle.logical_path)
	if _should_fail(key) or not handle is FakeStorageWriteHandle:
		return _void_failure(&"SAVE_IO_FLUSH", key)
	var fake: FakeStorageWriteHandle = handle
	fake.flushed = true
	return StorageVoidResult.success()

func close_write(handle: StorageWriteHandle) -> StorageVoidResult:
	var key := _record(StorageFaultKey.CLOSE, handle.logical_path)
	if _should_fail(key) or not handle is FakeStorageWriteHandle:
		return _void_failure(&"SAVE_IO_CLOSE", key)
	var fake: FakeStorageWriteHandle = handle
	if fake.closed or not fake.flushed:
		return _void_failure(&"SAVE_IO_CLOSE", key)
	fake.closed = true
	_set_file(fake.logical_path, fake.pending_bytes)
	return StorageVoidResult.success()

func open_read(logical_path: StringName) -> StorageReadHandleResult:
	var key := _record(StorageFaultKey.OPEN_READ, logical_path)
	if _should_fail(key):
		return StorageReadHandleResult.failure(_make_error(&"SAVE_IO_OPEN", key))
	var stored := _find_file(logical_path)
	if stored == null:
		return StorageReadHandleResult.failure(_make_error(&"SAVE_IO_OPEN", key))
	return StorageReadHandleResult.success(FakeStorageReadHandle.new(logical_path, stored.bytes))

func read_all(handle: StorageReadHandle) -> StorageReadResult:
	var key := _record(StorageFaultKey.READ, handle.logical_path)
	if _should_fail(key) or not handle is FakeStorageReadHandle:
		return StorageReadResult.failure(_make_error(&"SAVE_IO_READ", key))
	var fake: FakeStorageReadHandle = handle
	if fake.closed:
		return StorageReadResult.failure(_make_error(&"SAVE_IO_READ", key))
	return StorageReadResult.success(fake.snapshot_bytes)

func close_read(handle: StorageReadHandle) -> StorageVoidResult:
	var key := _record(StorageFaultKey.CLOSE, handle.logical_path)
	if _should_fail(key) or not handle is FakeStorageReadHandle:
		return _void_failure(&"SAVE_IO_CLOSE", key)
	var fake: FakeStorageReadHandle = handle
	if fake.closed:
		return _void_failure(&"SAVE_IO_CLOSE", key)
	fake.closed = true
	return StorageVoidResult.success()

func rename(source: StringName, destination: StringName) -> StorageVoidResult:
	return _move(source, destination, StorageFaultKey.RENAME, &"SAVE_IO_RENAME")

func quarantine(source: StringName) -> StorageVoidResult:
	return _move(source, StorageFaultKey.QUARANTINE_PATH, StorageFaultKey.QUARANTINE, &"SAVE_IO_QUARANTINE")

func restore(source: StringName, destination: StringName) -> StorageVoidResult:
	return _move(source, destination, StorageFaultKey.RESTORE, &"SAVE_IO_RESTORE")

func remove(logical_path: StringName) -> StorageVoidResult:
	var key := _record(StorageFaultKey.REMOVE, logical_path)
	if _should_fail(key):
		return _void_failure(&"SAVE_IO_REMOVE", key)
	var index := _find_file_index(logical_path)
	if index >= 0:
		_files.remove_at(index)
	return StorageVoidResult.success()

func _move(
	source: StringName,
	destination: StringName,
	operation: StringName,
	error_code: StringName
) -> StorageVoidResult:
	var key := _record(operation, source)
	if _should_fail(key):
		return _void_failure(error_code, key)
	var source_index := _find_file_index(source)
	if source_index < 0 or _find_file(destination) != null:
		return _void_failure(error_code, key)
	var bytes := _files[source_index].bytes.duplicate()
	_files.remove_at(source_index)
	_files.append(FakeStoredFile.new(destination, bytes))
	return StorageVoidResult.success()

func _record(operation: StringName, path: StringName) -> StorageFaultKey:
	var counter := _counter(operation, path)
	var key := StorageFaultKey.new(operation, path, counter.count)
	counter.count += 1
	_journal.append(key.deep_clone())
	if _observer != null:
		_observer.before_operation(key.deep_clone())
	return key

func _counter(operation: StringName, path: StringName) -> FakeOccurrenceCounter:
	for counter: FakeOccurrenceCounter in _counters:
		if counter.operation_kind == operation and counter.logical_path == path:
			return counter
	var created := FakeOccurrenceCounter.new(operation, path)
	_counters.append(created)
	return created

func _should_fail(key: StorageFaultKey) -> bool:
	for fault: StorageFaultKey in _faults:
		if fault.equals(key):
			return true
	return false

func _find_file(path: StringName) -> FakeStoredFile:
	var index := _find_file_index(path)
	return _files[index] if index >= 0 else null

func _find_file_index(path: StringName) -> int:
	for index: int in range(_files.size()):
		if _files[index].logical_path == path:
			return index
	return -1

func _set_file(path: StringName, bytes: PackedByteArray) -> void:
	var index := _find_file_index(path)
	if index >= 0:
		_files[index] = FakeStoredFile.new(path, bytes)
	else:
		_files.append(FakeStoredFile.new(path, bytes))

func _void_failure(code: StringName, key: StorageFaultKey) -> StorageVoidResult:
	return StorageVoidResult.failure(_make_error(code, key))

func _make_error(code: StringName, key: StorageFaultKey) -> StorageError:
	return StorageError.new(code, key.operation_kind, key.logical_path, key.occurrence)

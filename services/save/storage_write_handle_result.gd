class_name StorageWriteHandleResult
extends RefCounted

var ok: bool
var handle: StorageWriteHandle
var error: StorageError

static func success(p_handle: StorageWriteHandle) -> StorageWriteHandleResult:
	return StorageWriteHandleResult.new(true, p_handle, null)

static func failure(p_error: StorageError) -> StorageWriteHandleResult:
	return StorageWriteHandleResult.new(false, null, p_error)

func _init(p_ok: bool, p_handle: StorageWriteHandle, p_error: StorageError) -> void:
	ResultInvariant.require(p_ok, p_error, p_handle != null, p_handle == null)
	ok = p_ok
	handle = p_handle
	error = p_error.deep_clone() if p_error != null else null

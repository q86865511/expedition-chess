class_name StorageVoidResult
extends RefCounted

var ok: bool
var error: StorageError

static func success() -> StorageVoidResult:
	return StorageVoidResult.new(true, null)

static func failure(p_error: StorageError) -> StorageVoidResult:
	return StorageVoidResult.new(false, p_error)

func _init(p_ok: bool, p_error: StorageError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null

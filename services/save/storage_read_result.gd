class_name StorageReadResult
extends RefCounted

var ok: bool
var bytes: OptionalBytesValue
var error: StorageError

static func success(p_bytes: PackedByteArray) -> StorageReadResult:
	return StorageReadResult.new(true, OptionalBytesValue.new(p_bytes), null)

static func failure(p_error: StorageError) -> StorageReadResult:
	return StorageReadResult.new(false, null, p_error)

func _init(p_ok: bool, p_bytes: OptionalBytesValue, p_error: StorageError) -> void:
	ResultInvariant.require(p_ok, p_error, p_bytes != null, p_bytes == null)
	ok = p_ok
	bytes = p_bytes.deep_clone() if p_bytes != null else null
	error = p_error.deep_clone() if p_error != null else null

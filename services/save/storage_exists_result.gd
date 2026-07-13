class_name StorageExistsResult
extends RefCounted

var ok: bool
var exists: OptionalBoolValue
var error: StorageError

static func success(p_exists: bool) -> StorageExistsResult:
	return StorageExistsResult.new(true, OptionalBoolValue.new(p_exists), null)

static func failure(p_error: StorageError) -> StorageExistsResult:
	return StorageExistsResult.new(false, null, p_error)

func _init(p_ok: bool, p_exists: OptionalBoolValue, p_error: StorageError) -> void:
	ResultInvariant.require(p_ok, p_error, p_exists != null, p_exists == null)
	ok = p_ok
	exists = p_exists.deep_clone() if p_exists != null else null
	error = p_error.deep_clone() if p_error != null else null

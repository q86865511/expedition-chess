class_name CatalogHandleResult
extends RefCounted

var ok: bool
var value: CatalogHandle
var error: CatalogHandleError

static func success(handle: CatalogHandle) -> CatalogHandleResult:
	return CatalogHandleResult.new(true, handle, null)

static func failure(code: StringName, path: StringName = &"") -> CatalogHandleResult:
	return CatalogHandleResult.new(false, null, CatalogHandleError.new(code, path))

func _init(p_ok: bool, p_value: CatalogHandle, p_error: CatalogHandleError) -> void:
	ResultInvariant.require(p_ok, p_error, p_value != null, p_value == null)
	ok = p_ok
	value = p_value.deep_clone() if p_ok and p_value != null else null
	error = p_error if not p_ok else null

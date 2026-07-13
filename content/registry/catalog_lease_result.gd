class_name CatalogLeaseResult
extends RefCounted

var ok: bool
var lease: CatalogLease
var error: CatalogLeaseError

static func success(value: CatalogLease) -> CatalogLeaseResult:
	return CatalogLeaseResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"catalog_handle") -> CatalogLeaseResult:
	return CatalogLeaseResult.new(false, null, CatalogLeaseError.new(code, path))

func _init(p_ok: bool, p_lease: CatalogLease, p_error: CatalogLeaseError) -> void:
	ResultInvariant.require(p_ok, p_error, p_lease != null, p_lease == null)
	ok = p_ok
	lease = p_lease if p_ok else null
	error = p_error if not p_ok else null

class_name CatalogCompileResult
extends RefCounted

var ok: bool
var handle: CatalogHandle
var receipt: PinnedCatalogBuildReceipt
var error: CatalogCompileError

static func success(p_handle: CatalogHandle, p_receipt: PinnedCatalogBuildReceipt = null) -> CatalogCompileResult:
	return CatalogCompileResult.new(true, p_handle, p_receipt, null)

static func failure(code: StringName, path: StringName = &"", source: StringName = &"") -> CatalogCompileResult:
	return CatalogCompileResult.new(false, null, null, CatalogCompileError.new(code, path, source))

func _init(
	p_ok: bool,
	p_handle: CatalogHandle,
	p_receipt: PinnedCatalogBuildReceipt,
	p_error: CatalogCompileError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_handle != null,
		p_handle == null and p_receipt == null
	)
	ok = p_ok
	handle = p_handle.deep_clone() if p_ok and p_handle != null else null
	receipt = p_receipt.deep_clone() if p_ok and p_receipt != null else null
	error = p_error if not p_ok else null

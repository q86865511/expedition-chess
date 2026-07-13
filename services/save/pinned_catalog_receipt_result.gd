class_name PinnedCatalogReceiptResult
extends RefCounted

var ok: bool
var receipt: PinnedCatalogBuildReceipt
var error: PinnedCatalogReceiptError

static func success(p_receipt: PinnedCatalogBuildReceipt) -> PinnedCatalogReceiptResult:
	return PinnedCatalogReceiptResult.new(true, p_receipt, null)

static func failure(p_error: PinnedCatalogReceiptError) -> PinnedCatalogReceiptResult:
	return PinnedCatalogReceiptResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_receipt: PinnedCatalogBuildReceipt,
	p_error: PinnedCatalogReceiptError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_receipt != null, p_receipt == null)
	ok = p_ok
	receipt = p_receipt.deep_clone() if p_receipt != null else null
	error = p_error.deep_clone() if p_error != null else null

func deep_clone() -> PinnedCatalogReceiptResult:
	return PinnedCatalogReceiptResult.new(ok, receipt, error)

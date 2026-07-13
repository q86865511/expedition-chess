class_name FakePinnedCatalogReceiptPort
extends PinnedCatalogReceiptPort

var receipt: PinnedCatalogBuildReceipt
var injected_error: PinnedCatalogReceiptError

func _init(p_receipt: PinnedCatalogBuildReceipt = null) -> void:
	receipt = p_receipt.deep_clone() if p_receipt != null else null

func inject_error(error: PinnedCatalogReceiptError) -> void:
	injected_error = error.deep_clone()

func compile_or_lookup(_probe: ContentSnapshotProbe) -> PinnedCatalogReceiptResult:
	if injected_error != null:
		return PinnedCatalogReceiptResult.failure(injected_error)
	if receipt == null:
		return PinnedCatalogReceiptResult.failure(
			PinnedCatalogReceiptError.new(PinnedCatalogReceiptError.COMPILE_FAILED, &"run.content_snapshot")
		)
	return PinnedCatalogReceiptResult.success(receipt)

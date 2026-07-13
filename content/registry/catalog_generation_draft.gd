class_name CatalogGenerationDraft
extends RefCounted

var snapshot: ContentCatalogSnapshot
var handle: CatalogHandle
var receipt: PinnedCatalogBuildReceipt

func _init(
	p_snapshot: ContentCatalogSnapshot,
	p_handle: CatalogHandle,
	p_receipt: PinnedCatalogBuildReceipt = null
) -> void:
	snapshot = p_snapshot.deep_clone()
	handle = p_handle.deep_clone()
	receipt = p_receipt.deep_clone() if p_receipt != null else null

func deep_clone() -> CatalogGenerationDraft:
	return CatalogGenerationDraft.new(snapshot, handle, receipt)

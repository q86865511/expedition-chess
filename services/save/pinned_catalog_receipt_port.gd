class_name PinnedCatalogReceiptPort
extends RefCounted

func compile_or_lookup(_probe: ContentSnapshotProbe) -> PinnedCatalogReceiptResult:
	return PinnedCatalogReceiptResult.failure(
		PinnedCatalogReceiptError.new(
			PinnedCatalogReceiptError.COMPILE_FAILED,
			&"run.content_snapshot"
		)
	)

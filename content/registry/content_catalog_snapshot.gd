class_name ContentCatalogSnapshot
extends RefCounted

var manifest: ContentManifestValue
var manifest_bytes: PackedByteArray
var manifest_digest: String
var entries: Array[ContentEntryValue] = []
var entry_bytes: Array[PackedByteArray] = []
var diagnostic_catalog_bytes: PackedByteArray

func deep_clone() -> ContentCatalogSnapshot:
	var result := ContentCatalogSnapshot.new()
	result.manifest = manifest.deep_clone() if manifest != null else null
	result.manifest_bytes = manifest_bytes.duplicate()
	result.manifest_digest = manifest_digest
	for entry in entries:
		result.entries.append(entry.deep_clone())
	for bytes in entry_bytes:
		result.entry_bytes.append(bytes.duplicate())
	result.diagnostic_catalog_bytes = diagnostic_catalog_bytes.duplicate()
	return result

func _find_entry(content_id: StringName) -> ContentEntryValue:
	for entry in entries:
		if entry.content_id == content_id:
			return entry.deep_clone()
	return null

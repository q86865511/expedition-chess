class_name ContentGenerationMigrationReceiptV2
extends RefCounted

var source_content_version: String
var target_content_version: String
var source_manifest_digest: String
var target_manifest_digest: String
var mapping_digest: String
var localization_catalog_digest: String
var pack_digest: String
var source_catalog_schema_version: int = 1
var target_catalog_schema_version: int = 2
var from_codec: int = 2
var to_codec: int = 3
var receipt_digest: String

func deep_clone() -> ContentGenerationMigrationReceiptV2:
	var clone := ContentGenerationMigrationReceiptV2.new()
	clone.source_content_version = source_content_version
	clone.target_content_version = target_content_version
	clone.source_manifest_digest = source_manifest_digest
	clone.target_manifest_digest = target_manifest_digest
	clone.mapping_digest = mapping_digest
	clone.localization_catalog_digest = localization_catalog_digest
	clone.pack_digest = pack_digest
	clone.source_catalog_schema_version = source_catalog_schema_version
	clone.target_catalog_schema_version = target_catalog_schema_version
	clone.from_codec = from_codec
	clone.to_codec = to_codec
	clone.receipt_digest = receipt_digest
	return clone

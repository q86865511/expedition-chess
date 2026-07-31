class_name ContentGenerationMigrationPackV2
extends RefCounted

var source_content_version: String
var target_content_version: String
var source_manifest_digest: String
var expected_target_manifest_digest: String
var source_catalog_schema_version: int = 1
var target_catalog_schema_version: int = 2
var from_codec: int = 2
var to_codec: int = 3
var mappings: Array[ContentGenerationMigrationEntryV2] = []
var mapping_digest: String
var localization_catalog_digest: String
var pack_digest: String

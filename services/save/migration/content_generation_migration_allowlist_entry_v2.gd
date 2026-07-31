class_name ContentGenerationMigrationAllowlistEntryV2
extends RefCounted

var source_content_version: String
var source_manifest_digest: String
var pack_digest: String

func _init(
	p_source_content_version: String,
	p_source_manifest_digest: String,
	p_pack_digest: String
) -> void:
	source_content_version = p_source_content_version
	source_manifest_digest = p_source_manifest_digest
	pack_digest = p_pack_digest

func matches(pack: ContentGenerationMigrationPackV2) -> bool:
	return pack != null \
		and source_content_version == pack.source_content_version \
		and source_manifest_digest == pack.source_manifest_digest \
		and pack_digest == pack.pack_digest

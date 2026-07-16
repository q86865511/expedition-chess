class_name ContentGenerationMigrationPackV1
extends RefCounted

var source_content_version: String
var source_manifest_digest: String
var target_content_version: String
var expected_target_manifest_digest: String
var combat_config_entry_bytes: PackedByteArray
var combat_config_entry_digest: String
var boss_mapping_entries: Array[BossSourceMigrationEntryV1] = []
var boss_mapping_digest: String
var from_codec: int
var to_codec: int
var pack_digest: String

func _init(
	p_source_content_version: String,
	p_source_manifest_digest: String,
	p_target_content_version: String,
	p_expected_target_manifest_digest: String,
	p_combat_config_entry_bytes: PackedByteArray,
	p_combat_config_entry_digest: String,
	p_boss_mapping_entries: Array[BossSourceMigrationEntryV1],
	p_boss_mapping_digest: String,
	p_from_codec: int,
	p_to_codec: int,
	p_pack_digest: String
) -> void:
	source_content_version = p_source_content_version
	source_manifest_digest = p_source_manifest_digest
	target_content_version = p_target_content_version
	expected_target_manifest_digest = p_expected_target_manifest_digest
	combat_config_entry_bytes = p_combat_config_entry_bytes.duplicate()
	combat_config_entry_digest = p_combat_config_entry_digest
	for entry: BossSourceMigrationEntryV1 in p_boss_mapping_entries:
		boss_mapping_entries.append(entry.deep_clone())
	boss_mapping_digest = p_boss_mapping_digest
	from_codec = p_from_codec
	to_codec = p_to_codec
	pack_digest = p_pack_digest

func deep_clone() -> ContentGenerationMigrationPackV1:
	return ContentGenerationMigrationPackV1.new(
		source_content_version,
		source_manifest_digest,
		target_content_version,
		expected_target_manifest_digest,
		combat_config_entry_bytes,
		combat_config_entry_digest,
		boss_mapping_entries,
		boss_mapping_digest,
		from_codec,
		to_codec,
		pack_digest
	)

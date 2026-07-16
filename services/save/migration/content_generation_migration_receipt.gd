class_name ContentGenerationMigrationReceipt
extends RefCounted

var source_manifest_digest: String
var target_manifest_digest: String
var combat_config_entry_digest: String
var boss_mapping_digest: String
var pack_digest: String
var from_codec: int
var to_codec: int
var receipt_digest: String

func _init(
	p_source_manifest_digest: String,
	p_target_manifest_digest: String,
	p_combat_config_entry_digest: String,
	p_boss_mapping_digest: String,
	p_pack_digest: String,
	p_from_codec: int,
	p_to_codec: int,
	p_receipt_digest: String
) -> void:
	source_manifest_digest = p_source_manifest_digest
	target_manifest_digest = p_target_manifest_digest
	combat_config_entry_digest = p_combat_config_entry_digest
	boss_mapping_digest = p_boss_mapping_digest
	pack_digest = p_pack_digest
	from_codec = p_from_codec
	to_codec = p_to_codec
	receipt_digest = p_receipt_digest

func deep_clone() -> ContentGenerationMigrationReceipt:
	return ContentGenerationMigrationReceipt.new(
		source_manifest_digest,
		target_manifest_digest,
		combat_config_entry_digest,
		boss_mapping_digest,
		pack_digest,
		from_codec,
		to_codec,
		receipt_digest
	)

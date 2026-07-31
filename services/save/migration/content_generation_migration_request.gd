class_name ContentGenerationMigrationRequest
extends RefCounted

var source_content_version: String
var source_manifest_digest: String
var enabled_content_ids: Array[StringName] = []
var economy_config_id: StringName
var reward_table_ids: Array[StringName] = []
var map_node_def_ids: Array[StringName] = []
var challenge_unlock_def_ids: Array[StringName] = []
var meta_reward_table_id: StringName
var source_catalog_schema_version: int
var source_content_codec_version: int

func _init(
	p_source_content_version: String,
	p_source_manifest_digest: String,
	p_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_source_catalog_schema_version: int = 0,
	p_source_content_codec_version: int = 0
) -> void:
	source_content_version = p_source_content_version
	source_manifest_digest = p_source_manifest_digest
	enabled_content_ids = p_enabled_content_ids.duplicate()
	economy_config_id = p_economy_config_id
	reward_table_ids = p_reward_table_ids.duplicate()
	map_node_def_ids = p_map_node_def_ids.duplicate()
	challenge_unlock_def_ids = p_challenge_unlock_def_ids.duplicate()
	meta_reward_table_id = p_meta_reward_table_id
	source_catalog_schema_version = p_source_catalog_schema_version
	source_content_codec_version = p_source_content_codec_version

func deep_clone() -> ContentGenerationMigrationRequest:
	return ContentGenerationMigrationRequest.new(
		source_content_version,
		source_manifest_digest,
		enabled_content_ids,
		economy_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id,
		source_catalog_schema_version,
		source_content_codec_version
	)

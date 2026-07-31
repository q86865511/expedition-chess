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
## 由 SaveMigrationRegistry traverse raw run state 產生的完整引用面。
## codec 2→3 的 port 以此逐筆要求 exact mapping;空清單視為呼叫端未 traverse。
var referenced_entries: Array[ContentGenerationMigrationReference] = []

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
	p_source_content_codec_version: int = 0,
	p_referenced_entries: Array[ContentGenerationMigrationReference] = []
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
	for reference: ContentGenerationMigrationReference in p_referenced_entries:
		referenced_entries.append(reference.deep_clone())

func referenced_entries_copy() -> Array[ContentGenerationMigrationReference]:
	var result: Array[ContentGenerationMigrationReference] = []
	for reference: ContentGenerationMigrationReference in referenced_entries:
		result.append(reference.deep_clone())
	return result

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
		source_content_codec_version,
		referenced_entries_copy()
	)

class_name ContentSnapshotProbe
extends RefCounted

var content_version: String
var enabled_content_ids: Array[StringName] = []
var economy_config_id: StringName
var combat_config_id: StringName
var reward_table_ids: Array[StringName] = []
var map_node_def_ids: Array[StringName] = []
var challenge_unlock_def_ids: Array[StringName] = []
var meta_reward_table_id: StringName
var manifest_digest: String
var catalog_schema_version: int = 1
var content_codec_version: int = 2

func _init(
	p_content_version: String,
	p_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_combat_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_manifest_digest: String,
	p_catalog_schema_version: int = 1,
	p_content_codec_version: int = 2
) -> void:
	content_version = p_content_version
	enabled_content_ids.assign(p_enabled_content_ids)
	economy_config_id = p_economy_config_id
	combat_config_id = p_combat_config_id
	reward_table_ids.assign(p_reward_table_ids)
	map_node_def_ids.assign(p_map_node_def_ids)
	challenge_unlock_def_ids.assign(p_challenge_unlock_def_ids)
	meta_reward_table_id = p_meta_reward_table_id
	manifest_digest = p_manifest_digest
	catalog_schema_version = p_catalog_schema_version
	content_codec_version = p_content_codec_version

func to_selection() -> CatalogSelection:
	return CatalogSelection.new(
		content_version,
		enabled_content_ids,
		economy_config_id,
		combat_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id
	)

func deep_clone() -> ContentSnapshotProbe:
	return ContentSnapshotProbe.new(
		content_version,
		enabled_content_ids,
		economy_config_id,
		combat_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id,
		manifest_digest,
		catalog_schema_version,
		content_codec_version
	)

class_name PinnedCatalogBuildReceipt
extends RefCounted

var catalog_schema_version: int
var content_codec_version: int
var content_version: String
var selection_digest: String
var active_entry_ids: Array[StringName] = []
var economy_config_id: StringName
var reward_table_ids: Array[StringName] = []
var map_node_def_ids: Array[StringName] = []
var challenge_unlock_def_ids: Array[StringName] = []
var meta_reward_table_id: StringName
var manifest_digest: String

func _init(
	p_catalog_schema_version: int,
	p_content_codec_version: int,
	p_content_version: String,
	p_selection_digest: String,
	p_active_entry_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_manifest_digest: String
) -> void:
	catalog_schema_version = p_catalog_schema_version
	content_codec_version = p_content_codec_version
	content_version = p_content_version
	selection_digest = p_selection_digest
	active_entry_ids.assign(p_active_entry_ids)
	economy_config_id = p_economy_config_id
	reward_table_ids.assign(p_reward_table_ids)
	map_node_def_ids.assign(p_map_node_def_ids)
	challenge_unlock_def_ids.assign(p_challenge_unlock_def_ids)
	meta_reward_table_id = p_meta_reward_table_id
	manifest_digest = p_manifest_digest

func deep_clone() -> PinnedCatalogBuildReceipt:
	return PinnedCatalogBuildReceipt.new(
		catalog_schema_version,
		content_codec_version,
		content_version,
		selection_digest,
		active_entry_ids,
		economy_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id,
		manifest_digest
	)

class_name CatalogSelection
extends RefCounted

var content_version: String
var root_enabled_content_ids: Array[StringName] = []
var economy_config_id: StringName
var reward_table_ids: Array[StringName] = []
var map_node_def_ids: Array[StringName] = []
var challenge_unlock_def_ids: Array[StringName] = []
var meta_reward_table_id: StringName

func _init(
	p_content_version: String,
	p_root_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName
) -> void:
	content_version = p_content_version
	root_enabled_content_ids.assign(p_root_enabled_content_ids)
	economy_config_id = p_economy_config_id
	reward_table_ids.assign(p_reward_table_ids)
	map_node_def_ids.assign(p_map_node_def_ids)
	challenge_unlock_def_ids.assign(p_challenge_unlock_def_ids)
	meta_reward_table_id = p_meta_reward_table_id

func deep_clone() -> CatalogSelection:
	return CatalogSelection.new(
		content_version,
		root_enabled_content_ids,
		economy_config_id,
		reward_table_ids,
		map_node_def_ids,
		challenge_unlock_def_ids,
		meta_reward_table_id
	)

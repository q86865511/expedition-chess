class_name BuildLabContentBootstrap
extends RefCounted

## Build Lab is a compatibility adapter over the production content bootstrap.
## Content loading, dependency validation, installation and pinned receipt
## creation all have one implementation in app/content.


func run(registry: ContentRegistryService) -> BuildLabBootstrapResult:
	var dependency := ProjectContentDependencyPort.new(LocalizationCatalog.new())
	var production := ProjectContentBootstrap.new(dependency).run(registry)
	if not production.ok:
		return BuildLabBootstrapResult.failure(
			"%s: %s" % [production.error_code, production.error_message]
		)
	var result := BuildLabBootstrapResult.success()
	result.registry = production.registry
	result.manifest_digest = production.manifest_digest
	result.content_version = production.content_version
	result.content_snapshot = production.content_snapshot
	result.receipt = production.receipt
	result.battle_catalog = production.battle_catalog
	result.forge_table = production.forge_table
	result.relic_table = production.relic_table
	result.consumable_rules = production.consumable_rules
	result.economy_catalog = production.economy_catalog
	result.economy_config_id = production.economy_config_id
	result.unit_ids = production.unit_ids.duplicate()
	result.player_unit_ids = production.player_unit_ids.duplicate()
	result.equipment_ids = production.equipment_ids.duplicate()
	result.item_component_ids = production.item_component_ids.duplicate()
	result.battle_relic_ids = production.battle_relic_ids.duplicate()
	result.run_relic_ids = production.run_relic_ids.duplicate()
	result.map_node_ids = production.map_node_ids.duplicate()
	result.reward_table_ids = production.reward_table_ids.duplicate()
	result.dismantle_consumable_id = production.dismantle_consumable_id
	result.encounter_ids = production.encounter_ids.duplicate()
	result.commander_ids = production.commander_ids.duplicate()
	result.base_profile_unlocked_content_ids = \
		production.base_profile_unlocked_content_ids.duplicate()
	result.meta_reward_table_id = production.meta_reward_table_id
	result.meta_reward_table = production.meta_reward_table
	production.release_registry_ownership()
	return result

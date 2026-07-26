class_name BuildLabContentBootstrap
extends RefCounted

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒的內容安裝入口:
## 讀取磁碟上兩個正式 .tres pack(content/packs/build_systems、
## content/packs/vertical_slice,比照
## tests/unit/content_validation/test_vertical_slice_content_pack.gd 的安裝
## 流程),經 ContentValidator 驗證後 ContentRegistryService.install_validated()
## 產生真正的 pinned manifest digest,再依 design §3 用四個既有 production
## builder(BattleRuleCatalogBuilder／ForgeRecipeTableBuilder／
## RunRelicTableBuilder／EconomyExpeditionCatalogBuilder)組出 BuildLabSession
## 要接線進 RunController 的 catalog/table 集合。不虛構內容、不繞過驗證器。
##
## T11 wave4 修復(見 HANDOFF.md、content/packs/vertical_slice/README.md「T11
## wave4 內容缺口修復」):economy_config 補齊 layer_income/xp_thresholds、
## 雙 pack 新增 meta_reward_table 內容後,改用 registry.compile_pinned_generation()
## 以「全部內容為 root」的 CatalogSelection 換回真正的 PinnedCatalogBuildReceipt
## (而非手刻 receipt),讓 ContentRegistryReceiptAdapter 的 save/load 路徑可用
## (見 build_lab_session.gd 對 receipt port 的選用說明)。root_enabled_content_ids
## 傳入全部 ids 時,closure 後的 active_ids 與 install_validated 的全集合相同,
## 產生的 manifest digest 與 install_result 的 digest 一致。

const BUILD_SYSTEMS_ROOT: String = "res://content/packs/build_systems"
const VERTICAL_SLICE_ROOT: String = "res://content/packs/vertical_slice"
const CONTENT_VERSION: String = "0.1.0-build-lab"
const PACK_IDS: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice"]

func run(registry: ContentRegistryService) -> BuildLabBootstrapResult:
	var combined: Array[ContentDefinition] = []
	var load_error := _load_pack(BUILD_SYSTEMS_ROOT, combined)
	if not load_error.is_empty():
		return BuildLabBootstrapResult.failure(load_error)
	load_error = _load_pack(VERTICAL_SLICE_ROOT, combined)
	if not load_error.is_empty():
		return BuildLabBootstrapResult.failure(load_error)

	var input := ContentValidationInput.new(
		combined, [], [], BuildLabDependencyPort.new(), 9
	)
	var report := ContentValidator.new().validate(input)
	if not report.valid:
		return BuildLabBootstrapResult.failure(
			"content validation failed: " + _issue_text(report)
		)

	var install_result := registry.install_validated(input, CONTENT_VERSION, PACK_IDS)
	if not install_result.ok:
		return BuildLabBootstrapResult.failure(
			"install_validated failed: %s field=%s" % [
				install_result.error.code, install_result.error.field_path
			]
		)
	var digest := install_result.handle.manifest_digest

	var ids := _collect_ids(combined)
	if ids.economy_config_id == &"" or ids.dismantle_consumable_id == &"" \
		or ids.reward_table_ids.is_empty() or ids.meta_reward_table_id == &"":
		return BuildLabBootstrapResult.failure(
			"content pack missing required economy_config/dismantle consumable/reward_table/meta_reward_table"
		)

	var selection := CatalogSelection.new(
		CONTENT_VERSION, ids.all_ids, ids.economy_config_id, &"config.combat_default",
		ids.reward_table_ids, ids.map_node_ids, ids.challenge_unlock_ids,
		ids.meta_reward_table_id
	)
	var pinned_result := registry.compile_pinned_generation(selection)
	if not pinned_result.ok:
		return BuildLabBootstrapResult.failure(
			"compile_pinned_generation failed: %s field=%s" % [
				pinned_result.error.code, pinned_result.error.field_path
			]
		)
	if pinned_result.handle.manifest_digest != digest:
		return BuildLabBootstrapResult.failure(
			"pinned generation digest diverged from full install digest"
		)
	var receipt := pinned_result.receipt
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	if not snapshot_result.ok:
		return BuildLabBootstrapResult.failure(
			"content_snapshot build failed: %s" % snapshot_result.error.field_path
		)
	var meta_reward_table := MetaRewardTableReader.new().try_read(
		registry, digest, ids.meta_reward_table_id
	)
	if meta_reward_table == null:
		return BuildLabBootstrapResult.failure(
			"MetaRewardTableReader failed: %s" % String(ids.meta_reward_table_id)
		)

	var battle_roots: Array[StringName] = []
	battle_roots.append_array(ids.unit_ids)
	battle_roots.append_array(ids.equipment_ids)
	battle_roots.append_array(ids.battle_relic_ids)
	var battle_result := BattleRuleCatalogBuilder.new().build(registry, digest, battle_roots)
	if not battle_result.ok:
		return BuildLabBootstrapResult.failure(
			"BattleRuleCatalogBuilder failed: %s field=%s" % [
				battle_result.error.code, battle_result.error.field_path
			]
		)

	var forge_result := ForgeRecipeTableBuilder.new().build(registry, digest, ids.equipment_ids)
	if not forge_result.ok:
		return BuildLabBootstrapResult.failure(
			"ForgeRecipeTableBuilder failed: %s field=%s" % [
				forge_result.error.code, forge_result.error.field_path
			]
		)

	var relic_result := RunRelicTableBuilder.new().build(registry, digest, ids.run_relic_ids)
	if not relic_result.ok:
		return BuildLabBootstrapResult.failure(
			"RunRelicTableBuilder failed: %s field=%s" % [
				relic_result.error.code, relic_result.error.field_path
			]
		)

	# T11 wave4:economy_config 已補齊必填 TUNE 欄位(見 README「T11 wave4 內容缺口
	# 修復」),EconomyExpeditionCatalogBuilder 現在對正式內容 build 應成功,不再需要
	# 具名缺口的軟性繞過 -- 與其餘三個 production builder 一致,失敗即整體失敗。
	var economy_result := EconomyExpeditionCatalogBuilder.new().build(
		registry, digest, ids.economy_config_id, ids.unit_ids, ids.map_node_ids,
		ids.reward_table_ids
	)
	if not economy_result.ok:
		return BuildLabBootstrapResult.failure(
			"EconomyExpeditionCatalogBuilder failed: %s field=%s" % [
				economy_result.error.code, economy_result.error.field_path
			]
		)

	var consumable_rule := ConsumableRule.new()
	consumable_rule.consumable_id = ids.dismantle_consumable_id
	consumable_rule.use_timing = &"dismantle"
	consumable_rule.has_run_operations = false

	var result := BuildLabBootstrapResult.success()
	result.registry = registry
	result.manifest_digest = digest
	result.content_version = CONTENT_VERSION
	result.content_snapshot = snapshot_result.snapshot
	result.receipt = receipt
	result.battle_catalog = battle_result.catalog
	result.forge_table = forge_result.table
	result.relic_table = relic_result.table
	result.consumable_rules = ConsumableRuleTable.new(digest, [consumable_rule])
	result.economy_catalog = economy_result.catalog
	result.economy_config_id = ids.economy_config_id
	result.unit_ids = ids.unit_ids
	result.encounter_ids = ids.encounter_ids
	result.commander_ids = ids.commander_ids
	result.base_profile_unlocked_content_ids = ids.base_profile_unlocked_content_ids
	result.meta_reward_table_id = ids.meta_reward_table_id
	result.meta_reward_table = meta_reward_table
	result.player_unit_ids = ids.player_unit_ids
	result.equipment_ids = ids.equipment_ids
	result.item_component_ids = ids.item_component_ids
	result.battle_relic_ids = ids.battle_relic_ids
	result.run_relic_ids = ids.run_relic_ids
	result.map_node_ids = ids.map_node_ids
	result.reward_table_ids = ids.reward_table_ids
	result.dismantle_consumable_id = ids.dismantle_consumable_id
	return result

class _CollectedIds:
	var all_ids: Array[StringName] = []
	var unit_ids: Array[StringName] = []
	## S5 T11：正式 run composition 需要的兩類（build lab 自己用不到）。
	var encounter_ids: Array[StringName] = []
	var commander_ids: Array[StringName] = []
	## wave5 A2：新 profile 的起始解鎖集合（unlock_kind == base_profile）。
	var base_profile_unlocked_content_ids: Array[StringName] = []
	var player_unit_ids: Array[StringName] = []
	var equipment_ids: Array[StringName] = []
	var item_component_ids: Array[StringName] = []
	var battle_relic_ids: Array[StringName] = []
	var run_relic_ids: Array[StringName] = []
	var reward_table_ids: Array[StringName] = []
	var map_node_ids: Array[StringName] = []
	var challenge_unlock_ids: Array[StringName] = []
	var economy_config_id: StringName = &""
	var dismantle_consumable_id: StringName = &""
	var meta_reward_table_id: StringName = &""

func _collect_ids(definitions: Array[ContentDefinition]) -> _CollectedIds:
	var ids := _CollectedIds.new()
	for definition: ContentDefinition in definitions:
		ids.all_ids.append(definition.id)
		match definition.category_name():
			&"unit":
				ids.unit_ids.append(definition.id)
				var unit := definition as UnitDef
				if unit.availability in [&"player", &"shared"]:
					ids.player_unit_ids.append(definition.id)
			&"equipment":
				ids.equipment_ids.append(definition.id)
			&"item_component":
				ids.item_component_ids.append(definition.id)
			&"relic":
				var relic := definition as RelicDef
				if relic.category == &"battle":
					ids.battle_relic_ids.append(definition.id)
				else:
					ids.run_relic_ids.append(definition.id)
			&"reward_table":
				ids.reward_table_ids.append(definition.id)
			&"map_node":
				ids.map_node_ids.append(definition.id)
			&"unlock":
				var unlock := definition as UnlockDef
				if unlock.unlock_kind == &"challenge":
					ids.challenge_unlock_ids.append(definition.id)
				elif unlock.unlock_kind == &"base_profile":
					for content_id: StringName in unlock.unlocked_content_refs:
						if not ids.base_profile_unlocked_content_ids.has(content_id):
							ids.base_profile_unlocked_content_ids.append(content_id)
			&"economy_config":
				ids.economy_config_id = definition.id
			&"consumable":
				var consumable := definition as ConsumableDef
				if consumable.use_timing == &"dismantle":
					ids.dismantle_consumable_id = definition.id
			&"encounter":
				ids.encounter_ids.append(definition.id)
			&"commander":
				ids.commander_ids.append(definition.id)
			&"meta_reward_table":
				ids.meta_reward_table_id = definition.id
	ids.all_ids.sort_custom(_name_less)
	ids.unit_ids.sort_custom(_name_less)
	ids.encounter_ids.sort_custom(_name_less)
	ids.commander_ids.sort_custom(_name_less)
	ids.base_profile_unlocked_content_ids.sort_custom(_name_less)
	ids.player_unit_ids.sort_custom(_name_less)
	ids.equipment_ids.sort_custom(_name_less)
	ids.item_component_ids.sort_custom(_name_less)
	ids.battle_relic_ids.sort_custom(_name_less)
	ids.run_relic_ids.sort_custom(_name_less)
	ids.reward_table_ids.sort_custom(_name_less)
	ids.map_node_ids.sort_custom(_name_less)
	ids.challenge_unlock_ids.sort_custom(_name_less)
	return ids

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _load_pack(root: String, output: Array[ContentDefinition]) -> String:
	return _load_dir(root, output)

func _load_dir(path: String, output: Array[ContentDefinition]) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return "unable to open content pack directory: " + path
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				var nested_error := _load_dir(full_path, output)
				if not nested_error.is_empty():
					return nested_error
			elif entry.ends_with(".tres"):
				var resource := load(full_path)
				if not (resource is ContentDefinition):
					return "unexpected resource type at " + full_path
				output.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)

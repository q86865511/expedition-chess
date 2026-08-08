class_name ProjectContentBootstrap
extends RefCounted

const BUILD_SYSTEMS_ROOT: String = "res://content/packs/build_systems"
const VERTICAL_SLICE_ROOT: String = "res://content/packs/vertical_slice"
const CONTENT_VERSION: String = "0.2.0-content-production"
const PACK_IDS: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice"]
# csv_translation importer 不會把原始 CSV bytes 放入 export PCK；runtime checksum
# 讀取 byte-identical `.raw` 副本，顯示用 Translation resources 仍由原 CSV 產生。
const LOCALIZATION_CATALOG_PATH: String = "res://localization/catalog.v2.csv.raw"
const LOCALIZATION_CATALOG_SHA256: String = \
	"16507b3ebc2ad6af5545864d909a33612c689e0446fe268a00c17599fdfb3e23"
const REQUIRED_ASSET_PATHS: Array[String] = [
	"res://content/packs/build_systems/traits/faction_arcane.tres",
	"res://content/packs/vertical_slice/units/slice_player_00.tres",
]

const LOCALIZATION_CATALOG_INVALID: StringName = &"CONTENT_LOCALIZATION_CATALOG_INVALID"

var _dependency_port: ContentDependencyPort
var _registry_for_result: ContentRegistryService
var _owns_registry_for_result: bool
var _localization_catalog_error: StringName = &""
var _localization_catalog_error_detail: String = ""
## 只在正式 load 路徑上有值(注入 dependency port 的測試路徑為 null);
## codec 2→3 migration pack 的 L10N2 digest 必須綁在這份實際安裝的 catalog 上。
var _localization_catalog: LocalizationCatalog


## H3 fail-closed 修正:production catalog 一律先經 typed load result 驗證
## (design.md:143-152、R5:66-68)。載入失敗不得回傳 fallback catalog 讓 boot 照常成功;
## 失敗原因記在 `_localization_catalog_error`,由 run() 在任何內容安裝前立即回報失敗,
## 讓呼叫端(app_root.gd)走既有 boot failure 呈現路徑。`localization_catalog_load_override`
## 僅供測試注入竄改 SHA 的 LoadResult,避免測試須竄改磁碟上的正式 catalog。
func _init(
	dependency_port: ContentDependencyPort = null,
	localization_catalog_load_override: LocalizationCatalogLoadResult = null
) -> void:
	_dependency_port = dependency_port
	if _dependency_port == null:
		var loaded := (
			localization_catalog_load_override
			if localization_catalog_load_override != null
			else _load_production_localization_catalog()
		)
		if loaded.ok:
			_localization_catalog = loaded.catalog
			_dependency_port = ProjectContentDependencyPort.new(loaded.catalog)
		else:
			_localization_catalog_error = LOCALIZATION_CATALOG_INVALID
			_localization_catalog_error_detail = (
				"%s/row=%d/key=%s" % [
					String(loaded.error.code), loaded.error.row,
					String(loaded.error.key),
				]
				if loaded.error != null else "UNKNOWN"
			)


func _load_production_localization_catalog() -> LocalizationCatalogLoadResult:
	if not FileAccess.file_exists(LOCALIZATION_CATALOG_PATH):
		return LocalizationCatalogLoadResult.failure(
			LocalizationCatalogLoadError.new(LocalizationCatalogLoadError.IO)
		)
	var file := FileAccess.open(LOCALIZATION_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return LocalizationCatalogLoadResult.failure(
			LocalizationCatalogLoadError.new(LocalizationCatalogLoadError.IO)
		)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var request := LocalizationCatalogLoadRequest.new(
		StringName(LOCALIZATION_CATALOG_PATH),
		bytes,
		LOCALIZATION_CATALOG_SHA256
	)
	return LocalizationCatalogLoader.new().load_catalog(request)


func run(registry: ContentRegistryService) -> ProjectContentBootstrapResult:
	if registry == null:
		return ProjectContentBootstrapResult.failure(
			&"CONTENT_REGISTRY_MISSING", "registry is required", null, false
		)
	_registry_for_result = registry
	_owns_registry_for_result = registry.get_parent() == null
	if not _localization_catalog_error.is_empty():
		return _failure(
			_localization_catalog_error,
			"production localization catalog load failed: %s" % String(
				_localization_catalog_error_detail
			)
		)
	for path: String in REQUIRED_ASSET_PATHS:
		if not _dependency_port.asset_exists(path):
			return _failure(&"CONTENT_ASSET_MISSING", path)

	var combined: Array[ContentDefinition] = []
	var load_error := _load_pack(BUILD_SYSTEMS_ROOT, combined)
	if not load_error.is_empty():
		return _failure(&"CONTENT_ASSET_MISSING", load_error)
	load_error = _load_pack(VERTICAL_SLICE_ROOT, combined)
	if not load_error.is_empty():
		return _failure(&"CONTENT_ASSET_MISSING", load_error)

	for definition: ContentDefinition in combined:
		if not _dependency_port.localization_key_exists(definition.display_name_key):
			return _failure(
				&"CONTENT_LOCALIZATION_KEY_MISSING",
				String(definition.display_name_key)
			)
		if definition is TraitDef:
			var trait_definition := definition as TraitDef
			if not _dependency_port.localization_key_exists(
				trait_definition.description_key
			):
				return _failure(
					&"CONTENT_LOCALIZATION_KEY_MISSING",
					String(trait_definition.description_key)
				)
		elif definition is AbilityDef:
			var ability := definition as AbilityDef
			if not _dependency_port.localization_key_exists(ability.description_key):
				return _failure(
					&"CONTENT_LOCALIZATION_KEY_MISSING",
					String(ability.description_key)
				)

	# codec 2→3 的歷史 id 除了 generation migration pack 之外,也必須在 save decode
	# 的 content id migration port 上解得開(否則 generation 升級成功、decode 仍判
	# incompatible)。alias／tombstone 與 pack mapping 同出一張宣告表。
	var input := ContentValidationInput.new(
		combined,
		ProductionContentGenerationMigrations.content_aliases(),
		ProductionContentGenerationMigrations.content_tombstones(),
		_dependency_port,
		9
	)
	var report := ContentValidator.new().validate(input)
	if not report.valid:
		var first := report.issues[0]
		return _failure(first.code, _issue_text(report))

	var install_result := registry.install_validated(input, CONTENT_VERSION, PACK_IDS)
	if not install_result.ok:
		return _failure(
			install_result.error.code,
			"field=%s" % install_result.error.field_path
		)
	var digest := install_result.handle.manifest_digest
	var ids := _collect_ids(combined)
	if ids.economy_config_id == &"" or ids.dismantle_consumable_id == &"" \
		or ids.reward_table_ids.is_empty() or ids.meta_reward_table_id == &"":
		return _failure(
			&"CONTENT_REQUIRED_ENTRY_MISSING",
			"economy/consumable/reward/meta entry missing"
		)

	var selection := CatalogSelection.new(
		CONTENT_VERSION, ids.all_ids, ids.economy_config_id, &"config.combat_default",
		ids.reward_table_ids, ids.map_node_ids, ids.challenge_unlock_ids,
		ids.meta_reward_table_id
	)
	var pinned_result := registry.compile_pinned_generation(selection)
	if not pinned_result.ok:
		return _failure(
			pinned_result.error.code,
			"field=%s" % pinned_result.error.field_path
		)
	if pinned_result.handle.manifest_digest != digest:
		return _failure(
			&"CONTENT_PINNED_DIGEST_MISMATCH",
			"pinned generation digest diverged from installed generation"
		)
	var receipt := pinned_result.receipt
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	if not snapshot_result.ok:
		return _failure(
			&"CONTENT_SNAPSHOT_BUILD_FAILED",
			String(snapshot_result.error.field_path)
		)
	var definition_views: Array[ContentDefinitionView] = []
	for content_id: StringName in receipt.active_entry_ids:
		var definition_view := registry.try_resolve(
			ContentRef.new(digest, content_id)
		)
		if definition_view == null:
			return _failure(
				&"CONTENT_PINNED_DEFINITION_VIEW_MISSING",
				String(content_id)
			)
		definition_views.append(definition_view)
	var meta_reward_table := MetaRewardTableReader.new().try_read(
		registry, digest, ids.meta_reward_table_id
	)
	if meta_reward_table == null:
		return _failure(
			&"CONTENT_META_REWARD_TABLE_BUILD_FAILED",
			String(ids.meta_reward_table_id)
		)

	var battle_roots: Array[StringName] = []
	battle_roots.append_array(ids.unit_ids)
	battle_roots.append_array(ids.equipment_ids)
	battle_roots.append_array(ids.battle_relic_ids)
	# Encounter compilation is a production battle concern too.  Keeping these
	# out of the pinned battle catalog made MapNodeRule.generator_id resolve in
	# economy while the formal NodeEntry/StartCombat path failed closed.
	battle_roots.append_array(ids.encounter_ids)
	var battle_result := BattleRuleCatalogBuilder.new().build(
		registry, digest, battle_roots
	)
	if not battle_result.ok:
		return _failure(
			battle_result.error.code,
			"field=%s" % battle_result.error.field_path
		)
	var forge_result := ForgeRecipeTableBuilder.new().build(
		registry, digest, ids.equipment_ids
	)
	if not forge_result.ok:
		return _failure(
			forge_result.error.code,
			"field=%s" % forge_result.error.field_path
		)
	var relic_result := RunRelicTableBuilder.new().build(
		registry, digest, ids.run_relic_ids
	)
	if not relic_result.ok:
		return _failure(
			relic_result.error.code,
			"field=%s" % relic_result.error.field_path
		)
	var economy_result := EconomyExpeditionCatalogBuilder.new().build(
		registry, digest, ids.economy_config_id, ids.unit_ids, ids.map_node_ids,
		ids.reward_table_ids
	)
	if not economy_result.ok:
		return _failure(
			economy_result.error.code,
			"field=%s" % economy_result.error.field_path
		)

	var consumable_rule := ConsumableRule.new()
	consumable_rule.consumable_id = ids.dismantle_consumable_id
	consumable_rule.use_timing = &"dismantle"
	consumable_rule.has_run_operations = false

	var result := ProjectContentBootstrapResult.success(
		receipt, digest, registry, _owns_registry_for_result
	)
	result.content_version = CONTENT_VERSION
	result.content_snapshot = snapshot_result.snapshot
	result.localization_catalog = _localization_catalog
	result.install_presentation_projection(
		definition_views,
		battle_result.catalog,
		report.version_maximum_population
	)
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
	var encounter_ids: Array[StringName] = []
	var commander_ids: Array[StringName] = []
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
	for values: Array[StringName] in [
		ids.all_ids, ids.unit_ids, ids.encounter_ids, ids.commander_ids,
		ids.base_profile_unlocked_content_ids, ids.player_unit_ids,
		ids.equipment_ids, ids.item_component_ids, ids.battle_relic_ids,
		ids.run_relic_ids, ids.reward_table_ids, ids.map_node_ids,
		ids.challenge_unlock_ids,
	]:
		values.sort_custom(_name_less)
	return ids


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
					dir.list_dir_end()
					return nested_error
			elif entry.ends_with(".tres") or entry.ends_with(".tres.remap"):
				# Exported PCK directory enumeration exposes compiled resources with
				# a `.remap` suffix; ResourceLoader still resolves the canonical
				# `.tres` path through that remap.
				var load_path := (
					full_path.trim_suffix(".remap")
					if entry.ends_with(".remap") else full_path
				)
				var resource := load(load_path)
				if not (resource is ContentDefinition):
					dir.list_dir_end()
					return "unexpected resource type at " + load_path
				output.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [
			issue.code, issue.source_id, issue.field_path,
		])
	return ", ".join(values)


func _failure(code: StringName, message: String) -> ProjectContentBootstrapResult:
	return ProjectContentBootstrapResult.failure(
		code,
		message,
		_registry_for_result,
		_owns_registry_for_result
	)


func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

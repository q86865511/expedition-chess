class_name ProjectContentBootstrapResult
extends RefCounted

var ok: bool
var error_code: StringName
var error_message: String
var error: ProjectContentBootstrapError

var registry: ContentRegistryService
var manifest_digest: String = ""
var content_version: String = ""
var content_snapshot: ContentSnapshotState
var receipt: PinnedCatalogBuildReceipt
var battle_catalog: BattleRuleCatalog
var forge_table: ForgeRecipeTable
var relic_table: RunRelicTable
var consumable_rules: ConsumableRuleTable
var economy_catalog: EconomyExpeditionCatalog
## 本次 boot 實際安裝(且經 SHA 驗證)的 localization catalog;
## codec 2→3 migration pack 的 L10N2 digest 必須由它重算。
var localization_catalog: LocalizationCatalog

var economy_config_id: StringName = &""
var unit_ids: Array[StringName] = []
var player_unit_ids: Array[StringName] = []
var equipment_ids: Array[StringName] = []
var item_component_ids: Array[StringName] = []
var battle_relic_ids: Array[StringName] = []
var run_relic_ids: Array[StringName] = []
var map_node_ids: Array[StringName] = []
var reward_table_ids: Array[StringName] = []
var dismantle_consumable_id: StringName = &""
var encounter_ids: Array[StringName] = []
var commander_ids: Array[StringName] = []
var base_profile_unlocked_content_ids: Array[StringName] = []
var meta_reward_table_id: StringName = &""
var meta_reward_table: MetaRewardTableDef
var _owns_registry: bool
var _definition_views_by_id: Dictionary = {}
var _pinned_battle_catalog: BattleRuleCatalog
var _maximum_population_value: int


static func failure(
	code: StringName,
	message: String,
	p_registry: ContentRegistryService,
	p_owns_registry: bool
) -> ProjectContentBootstrapResult:
	return ProjectContentBootstrapResult.new(
		false,
		ProjectContentBootstrapError.new(code, message),
		null,
		"",
		p_registry,
		p_owns_registry
	)


static func success(
	p_receipt: PinnedCatalogBuildReceipt,
	p_manifest_digest: String,
	p_registry: ContentRegistryService,
	p_owns_registry: bool
) -> ProjectContentBootstrapResult:
	return ProjectContentBootstrapResult.new(
		true,
		null,
		p_receipt,
		p_manifest_digest,
		p_registry,
		p_owns_registry
	)


func _init(
	p_ok: bool,
	p_error: ProjectContentBootstrapError,
	p_receipt: PinnedCatalogBuildReceipt,
	p_manifest_digest: String,
	p_registry: ContentRegistryService,
	p_owns_registry: bool
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_receipt != null and p_manifest_digest.length() == 64,
		p_receipt == null and p_manifest_digest.is_empty()
	)
	ok = p_ok
	error = p_error
	error_code = p_error.code if p_error != null else &""
	error_message = p_error.message if p_error != null else ""
	receipt = p_receipt.deep_clone() if p_receipt != null else null
	manifest_digest = p_manifest_digest
	registry = p_registry
	_owns_registry = p_owns_registry


func release_registry_ownership() -> void:
	_owns_registry = false


func install_presentation_projection(
	definition_views: Array[ContentDefinitionView],
	p_battle_catalog: BattleRuleCatalog,
	p_maximum_population: int
) -> void:
	_definition_views_by_id.clear()
	for view: ContentDefinitionView in definition_views:
		if view != null and view.manifest_digest == manifest_digest:
			_definition_views_by_id[view.content_id] = view.deep_clone()
	_pinned_battle_catalog = (
		p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	)
	battle_catalog = (
		p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	)
	_maximum_population_value = maxi(0, p_maximum_population)


func try_definition_view(content_id: StringName) -> ContentDefinitionView:
	var stored: Variant = _definition_views_by_id.get(content_id)
	if not stored is ContentDefinitionView:
		return null
	return (stored as ContentDefinitionView).deep_clone()


func definition_view(content_id: StringName) -> ContentDefinitionView:
	var view := try_definition_view(content_id)
	assert(view != null, "CONTENT_DEFINITION_VIEW_MISSING")
	return view


func battle_catalog_snapshot() -> BattleRuleCatalog:
	return (
		_pinned_battle_catalog.deep_clone()
		if _pinned_battle_catalog != null
		else null
	)


func maximum_population() -> int:
	return _maximum_population_value


func collection_snapshot(profile: ProfileState) -> CollectionBrowserSnapshot:
	var snapshot := CollectionBrowserSnapshot.new()
	if profile == null:
		return snapshot
	for content_id: StringName in profile.discovered_content_ids:
		if not snapshot.content_ids.has(content_id):
			snapshot.content_ids.append(content_id)
	for content_id: StringName in profile.unlocked_content_ids:
		if not snapshot.content_ids.has(content_id):
			snapshot.content_ids.append(content_id)
	for equipment_id: StringName in equipment_ids:
		if not snapshot.recipe_ids.has(equipment_id):
			snapshot.recipe_ids.append(equipment_id)
	for value: Variant in _definition_views_by_id.values():
		if not value is ContentDefinitionView:
			continue
		var view := value as ContentDefinitionView
		if view.category in [&"ability", &"effect", &"trait"] \
			and not snapshot.glossary_ids.has(view.content_id):
			snapshot.glossary_ids.append(view.content_id)
	snapshot.content_ids.sort_custom(_name_less)
	snapshot.recipe_ids.sort_custom(_name_less)
	snapshot.glossary_ids.sort_custom(_name_less)
	return snapshot.deep_clone()


func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _owns_registry \
		and is_instance_valid(registry) and registry.get_parent() == null:
		registry.free()

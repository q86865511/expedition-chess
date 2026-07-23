extends GutTest

func test_catalog_decodes_from_pinned_generation_and_is_clone_isolated() -> void:
	var fixture := SyntheticContentFixture.build_valid()
	var economy: EconomyConfigDef = null
	var unit_ids: Array[StringName] = []
	var map_ids: Array[StringName] = []
	var reward_ids: Array[StringName] = []
	for definition: ContentDefinition in fixture.definitions:
		if definition is EconomyConfigDef:
			economy = definition
		elif definition is UnitDef:
			unit_ids.append(definition.id)
		elif definition is MapNodeDef:
			map_ids.append(definition.id)
		elif definition is RewardTableDef:
			reward_ids.append(definition.id)
	assert_not_null(economy)
	if economy == null: return
	# layer_income／xp_thresholds 已由 SyntheticContentFixture._economy() 預設補齊
	# (T11 wave4,見 content_validator.gd 對 EconomyConfigDef 必填欄位的驗證器對齊)——
	# 這裡只再補上驗證器不要求、但本測試不需要斷言的 streak_rewards／loss_subsidy。
	economy.streak_rewards = [_pair(3, 1), _pair(5, 2)]
	economy.loss_subsidy = [_pair(2, 3)]
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "economy.fixture", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok: return
	var built := EconomyExpeditionCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, economy.id, unit_ids, map_ids,
		reward_ids
	)
	assert_true(built.ok)
	if not built.ok: return
	assert_eq(built.catalog.manifest_digest_value(), installed.handle.manifest_digest)
	assert_gt(built.catalog.shop_units().size(), 0)
	assert_eq(built.catalog.map_nodes_for(MapNodeState.NodeKind.BOSS).size(), 1)
	assert_eq(built.catalog.reward_tables().size(), 2)
	var standard := built.catalog.try_reward_table(PendingRewardState.StageId.STANDARD)
	assert_not_null(standard)
	if standard != null:
		assert_eq(standard.candidates[0].conditions.size(), 1)
		assert_eq(standard.candidates[0].conditions[0].kind, &"expedition_hp_below")
	var config := built.catalog.config()
	config.gold_cap = 1
	assert_eq(built.catalog.config().gold_cap, 99)
	var wrong_generation := EconomyExpeditionCatalogBuilder.new().build(
		registry,
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		economy.id, unit_ids, map_ids, reward_ids
	)
	assert_false(wrong_generation.ok)
	assert_eq(wrong_generation.error.code, EconomyCatalogError.RESOLVE_FAILED)
	var wrong_category_ids: Array[StringName] = [economy.id]
	var wrong_category := EconomyExpeditionCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, economy.id,
		unit_ids, map_ids, wrong_category_ids
	)
	assert_false(wrong_category.ok)
	assert_eq(wrong_category.error.code, EconomyCatalogError.PAYLOAD_INVALID)

func _pair(key: int, value: int) -> U32PairDef:
	var pair := U32PairDef.new()
	pair.key_u32 = key
	pair.value_u32 = value
	return pair

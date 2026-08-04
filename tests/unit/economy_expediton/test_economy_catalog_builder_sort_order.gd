extends GutTest

## BP-SI-007 回歸測試：EconomyExpeditionCatalogBuilder 內部對 unit_ids／map_node_ids／
## reward_table_ids 的排序曾用裸 Array[StringName].sort()（依 interned 指標序，非決定性）；
## 現改用 StableNameSort.id_less。本測試驗證建出的 shop_units／map_nodes 順序具字典序，
## 且刻意打亂輸入順序（含 event_1/event_2/event_10 這種數值序與字典序分歧的 id）以避免
## 「輸入剛好已排序」造成偽陽性。

func test_shop_units_and_event_map_nodes_are_built_in_dictionary_id_order() -> void:
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
	economy.streak_rewards = [_pair(3, 1), _pair(5, 2)]
	economy.loss_subsidy = [_pair(2, 3)]

	# 刻意打亂輸入順序（反轉），確保測試真的在驗證 builder 的排序行為，而不是恰好輸入
	# 已排序才通過。
	unit_ids.reverse()
	map_ids.reverse()

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "economy.sort_order.fixture", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok: return

	var built := EconomyExpeditionCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, economy.id, unit_ids, map_ids, reward_ids
	)
	assert_true(built.ok)
	if not built.ok: return

	var shop_ids: Array[String] = []
	for rule: ShopUnitRule in built.catalog.shop_units():
		shop_ids.append(String(rule.unit_id))
	var expected_shop_ids := shop_ids.duplicate()
	expected_shop_ids.sort()
	assert_eq(shop_ids.size() > 0, true)
	assert_eq(shop_ids, expected_shop_ids, "shop_units 順序須為 unit_id 字典序")

	# map_node.event_0..event_11：數值序與字典序分歧（event_10 < event_2），足以揪出
	# 指標序殘留的 bug。
	var event_ids: Array[String] = []
	for rule: MapNodeRule in built.catalog.map_nodes_for(MapNodeState.NodeKind.EVENT):
		event_ids.append(String(rule.definition_id))
	var expected_event_ids := event_ids.duplicate()
	expected_event_ids.sort()
	assert_eq(event_ids.size(), 12)
	assert_eq(event_ids, expected_event_ids, "event map_nodes 順序須為 definition_id 字典序")
	assert_ne(event_ids, _numeric_event_order(), "驗證用序列不能剛好等於字典序（否則測試無鑑別力）")

func _numeric_event_order() -> Array[String]:
	var result: Array[String] = []
	for index in 12:
		result.append("map_node.event_%d" % index)
	return result

func _pair(key: int, value: int) -> U32PairDef:
	var pair := U32PairDef.new()
	pair.key_u32 = key
	pair.value_u32 = value
	return pair

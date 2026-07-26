extends GutTest

## T06(specs/meta-progression) — ShopService 在既有 slot-gated 遺物折扣後,再加
## 指揮官/挑戰 always-active 折扣貢獻。
## Covers：S5-AC-003；tasks.md T06 驗收：「四個 run 層作用點消費端在 slot-gated 後加
## always-active 貢獻」(shop 為其一)。
## 依據 design.md §6.1:117 與既有 tests/unit/economy_expediton/test_shop_service_relics.gd
## 的 economy×shop_discount 慣例(W2-F3：shop 折扣只吃 shop_discount kind,不吃 add_gold)。
##
## 範圍聲明：本檔只鎖 ShopService.generate_offers()/quote_refresh() 的價格折扣子點;
## RunRelicTable 手動建構,不經 RunModifierTableBuilder(見 test_run_modifier_table_builder.gd)。

func test_commander_always_active_shop_discount_applies_with_no_relic_slots_active() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 2),
	])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, []
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 3, "5 base cost - 2 commander always-active discount")

func test_always_active_discount_stacks_on_top_of_slot_gated_relic_discount() -> void:
	var catalog := _catalog_with_unit_cost(10)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_slot_gated_rule(&"relic.eco_a", 2),
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 1),
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_discount", 1),
	])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.eco_a"]
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 6, "10 base - 2 slot-gated - 1 commander - 1 challenge")

func test_always_active_discount_still_floors_at_one_gold() -> void:
	var catalog := _catalog_with_unit_cost(1)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 10),
	])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, []
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 1, "discount must floor at 1 gold, never 0 or negative")

func test_refresh_shop_applies_the_same_always_active_discount() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 2),
	])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, []
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	var refreshed := ShopService.new().quote_refresh(RefreshShopRequest.new(
		&"run_fixture", &"node_fixture", generated.transaction.economy_state,
		generated.transaction.unit_pool_state, generated.transaction.roster_state,
		generated.transaction.reservation_owners, generated.transaction.next_shop_rng_snapshot,
		generated.transaction.next_transaction_serial, generated.transaction.next_unit_serial,
		catalog, table, []
	))
	assert_true(refreshed.ok)
	if not refreshed.ok:
		return
	for offer: ShopOffer in refreshed.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 3, "refresh 必須重新套用相同的 always-active 折扣")

func test_route_category_always_active_rule_does_not_affect_shop_price() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule_with_category(&"challenge.fixture", &"challenge", &"route", &"add_gold", 50),
	])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, []
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 5, "route 類 always-active 規則不得影響商店價格")

func _catalog_with_unit_cost(cost: int) -> EconomyExpeditionCatalog:
	var base := EconomyTestFixture.catalog()
	var units: Array[ShopUnitRule] = [
		ShopUnitRule.new(&"unit.test_a", 1, cost),
		ShopUnitRule.new(&"unit.test_b", 1, cost),
	]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(base.map_nodes_for(kind))
	return EconomyExpeditionCatalog.new(base.manifest_digest_value(), base.config(), units, nodes)

func _slot_gated_rule(relic_id: StringName, amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"shop_discount"
	operation.amount = amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _always_active_rule(source_id: StringName, source: StringName, kind: StringName, amount: int) -> RunRelicRule:
	return _always_active_rule_with_category(source_id, source, &"economy", kind, amount)

func _always_active_rule_with_category(
	source_id: StringName, source: StringName, category: StringName, kind: StringName, amount: int
) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

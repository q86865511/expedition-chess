extends GutTest

## T07 (specs/meta-progression) — ShopService 在既有 slot-gated／always-active 折扣加總後，
## 再減去 ShopSurcharge 的 always-active 貢獻（design §6.3 軌 B：淨值 = discount − surcharge，
## 商店成本 = cost + surcharge − discount，下限 clamp 沿用既有規則）。
## Covers：S5-AC-010（軌 B：ShopSurcharge 實際提高 reroll/購買成本）；tasks.md T07 驗收
## 「shop/settlement 作用點消費端實際生效（surcharge 提高成本...clamp 沿用）」。
## 依據 design.md §6.3:131-134 與既有 tests/unit/meta_progression/
## test_shop_service_commander_challenge_modifiers.gd 的 economy×shop_discount always-active
## 慣例（本檔逐項鏡射該檔，符號反向：discount 降價、surcharge 加價）。
##
## 假設聲明（design.md 未釘死處，本檔測試作者決定，逐條列出；實作代理請照此實作）：
## 1. RunRelicOperationRule.kind 的執行期字串為 &"shop_surcharge"（category=&"economy"，與
##    &"shop_discount" 同一 category，消費端同一 ShopService 折扣/加價路徑）——本檔只用既有
##    RunRelicTable／RunRelicRule／RunRelicOperationRule 型別以純字串 kind 建構，
##    不參照任何尚不存在的 class_name（ShopSurchargeOperationDef 屬內容編譯層，見
##    tests/unit/content_validation/test_challenge_affix_operation_validation.gd），故本檔
##    不需 GUT 動態載入 trick，直接靜態撰寫即可，紅燈以「斷言失敗」形式呈現（ShopService 尚未
##    讀取 shop_surcharge kind，加價不會發生，cost 仍等於既有折扣後金額）。
## 2. 消費點與既有 shop_discount 同一處（shop_service.gd 的 _economy_discount 或其等價擴充）：
##    surcharge 同時支援 slot-gated（sum_operation_amount）與 always-active
##    （sum_always_active）兩種加總，比照 shop_discount 現行支援兩者的慣例；但本檔只驗
##    always-active 路徑（commander/challenge 來源）——slot-gated surcharge 目前無内容著作
##    (design §6.3 僅描述 challenge 來源)，不在本任務驗收範圍，未列入本檔斷言。
## 3. 淨值公式：net_discount = (slot-gated discount 加總 + always-active discount 加總)
##    − (slot-gated surcharge 加總 + always-active surcharge 加總)；offer.cost =
##    maxi(1, base_cost − net_discount)，即 base_cost + surcharge − discount，下限仍是既有的
##    1 gold（shop_service.gd 現行 `maxi(1, ...)` 慣例不變，見 test C）。
## 4. quote_refresh() 呼叫 _generate_offers() 產生的新一輪 offers 同樣套用 surcharge。
##    W4-F4 修正（2026-07-25，使用者裁決）：reroll 動作本身的固定費用（config.reroll_cost）
##    現在也套用 surcharge（design §6.3／§12 案例 010 原文明確點名「reroll/購買成本」兩者，
##    修正前只套用於購買成本，reroll_cost 完全不受影響是本檔原假設聲明記錄的既有缺口）；但
##    **不**套用 discount——discount 維持 S4 既有行為不動，此不對稱為刻意設計（design.md
##    §6.3 已同步補註）。reroll 實付 ＝ maxi(1, config.reroll_cost + surcharge)，見
##    test_refresh_shop_reroll_cost_increases_with_challenge_surcharge／
##    test_refresh_shop_reroll_cost_unaffected_at_challenge_zero。

func test_challenge_surcharge_increases_offer_cost_with_no_relic_slots_active() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_surcharge", 2),
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
		assert_eq(offer.cost, 7, "5 base cost + 2 challenge always-active surcharge")

func test_surcharge_nets_against_slot_gated_and_always_active_discount() -> void:
	var catalog := _catalog_with_unit_cost(10)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_slot_gated_discount_rule(&"relic.eco_a", 2),
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 1),
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_surcharge", 4),
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
		assert_eq(offer.cost, 11, "10 base - 2 slot-gated discount - 1 commander discount + 4 challenge surcharge")

func test_surcharge_cannot_push_cost_below_the_existing_one_gold_floor() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"commander.fixture", &"commander", &"shop_discount", 20),
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_surcharge", 3),
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
		assert_eq(offer.cost, 1, "17 net discount (20 - 3) still floors at the existing 1 gold minimum")

func test_refresh_shop_applies_the_same_challenge_surcharge() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_surcharge", 2),
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
		assert_eq(offer.cost, 7, "refresh 必須重新套用相同的 always-active surcharge")

## W4-F4 修正（2026-07-25）：reroll 這個動作本身的固定費用也套用 surcharge（不套 discount，
## 見檔頭假設聲明第 4 點與 shop_service.gd _economy_surcharge 的不對稱說明）。
func test_refresh_shop_reroll_cost_increases_with_challenge_surcharge() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule(&"challenge.fixture", &"challenge", &"shop_surcharge", 3),
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
	var gold_before := generated.transaction.economy_state.gold
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
	assert_eq(
		gold_before - refreshed.transaction.economy_state.gold, 5,
		"2 base reroll_cost + 3 challenge surcharge（W4-F4：reroll 成本須套 surcharge）"
	)

## Challenge 0（無 surcharge）時 reroll 成本必須維持既有數值不變——證明本修正不影響既有行為。
func test_refresh_shop_reroll_cost_unaffected_at_challenge_zero() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, []
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	var gold_before := generated.transaction.economy_state.gold
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
	assert_eq(
		gold_before - refreshed.transaction.economy_state.gold, 2,
		"Challenge 0（無 surcharge）reroll 成本維持既有 2 gold 不變"
	)

func test_route_category_surcharge_does_not_affect_shop_price() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule_with_category(&"challenge.fixture", &"challenge", &"route", &"shop_surcharge", 50),
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
		assert_eq(offer.cost, 5, "route 類 always-active 規則不得影響商店價格（surcharge 亦同）")

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

func _slot_gated_discount_rule(relic_id: StringName, amount: int) -> RunRelicRule:
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

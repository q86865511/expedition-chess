extends GutTest

func test_generate_refresh_and_buy_conserve_pool_and_reservations() -> void:
	var catalog := EconomyTestFixture.catalog()
	var service := ShopService.new()
	var generated := service.generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(20, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(generated.ok)
	if not generated.ok: return
	assert_eq(generated.transaction.economy_state.shop_offers.size(), 5)
	assert_eq(_active_owners(generated.transaction.reservation_owners), 5)
	_assert_pool_conserved(generated.transaction.unit_pool_state)
	var before_counter := generated.transaction.next_shop_rng_snapshot.counter.to_hex()

	var refreshed := service.quote_refresh(RefreshShopRequest.new(
		&"run_fixture", &"node_fixture", generated.transaction.economy_state,
		generated.transaction.unit_pool_state, generated.transaction.roster_state,
		generated.transaction.reservation_owners, generated.transaction.next_shop_rng_snapshot,
		generated.transaction.next_transaction_serial, generated.transaction.next_unit_serial,
		catalog
	))
	assert_true(refreshed.ok)
	if not refreshed.ok: return
	assert_eq(refreshed.transaction.economy_state.gold, 18)
	assert_eq(refreshed.transaction.economy_state.shop_refresh_index, 1)
	assert_eq(_active_owners(refreshed.transaction.reservation_owners), 5)
	assert_eq(_released_owners(refreshed.transaction.reservation_owners), 5)
	assert_ne(refreshed.transaction.next_shop_rng_snapshot.counter.to_hex(), before_counter)
	_assert_pool_conserved(refreshed.transaction.unit_pool_state)

	var offer := refreshed.transaction.economy_state.shop_offers[0]
	var bought := service.quote_buy(BuyOfferRequest.new(
		&"run_fixture", &"node_fixture", offer.offer_id,
		refreshed.transaction.economy_state, refreshed.transaction.unit_pool_state,
		refreshed.transaction.roster_state, refreshed.transaction.reservation_owners,
		refreshed.transaction.next_shop_rng_snapshot,
		refreshed.transaction.next_transaction_serial, refreshed.transaction.next_unit_serial,
		catalog, EconomyTestFixture.battle_catalog()
	))
	assert_true(bought.ok)
	if not bought.ok: return
	assert_eq(bought.transaction.economy_state.gold, 17)
	assert_eq(bought.transaction.roster_state.unit_instances.size(), 1)
	assert_eq(bought.transaction.roster_state.bench_unit_instance_ids.size(), 1)
	assert_eq(bought.transaction.economy_state.shop_offers.size(), 4)
	_assert_pool_conserved(bought.transaction.unit_pool_state)
	var stale := service.quote_buy(BuyOfferRequest.new(
		&"run_fixture", &"node_fixture", offer.offer_id,
		bought.transaction.economy_state, bought.transaction.unit_pool_state,
		bought.transaction.roster_state, bought.transaction.reservation_owners,
		bought.transaction.next_shop_rng_snapshot,
		bought.transaction.next_transaction_serial, bought.transaction.next_unit_serial,
		catalog, EconomyTestFixture.battle_catalog()
	))
	assert_false(stale.ok)
	assert_eq(stale.error.code, ShopError.OFFER_STALE)

func test_sell_and_xp_follow_versioned_rules() -> void:
	var catalog := EconomyTestFixture.catalog()
	var pool := catalog.create_initial_pool()
	var entry := pool.entries[0]
	entry.remaining_copies -= 3
	entry.held_copies = 3
	var roster := EconomyTestFixture.empty_roster()
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new("u_0000000000000001", entry.unit_def_id, 2, no_equipment, U64Bits.one())
	roster.unit_instances.append(unit)
	roster.bench_unit_instance_ids.append(unit.instance_id)
	var service := ShopService.new()
	var sold := service.quote_sell(SellUnitRequest.new(
		&"run_fixture", &"node_fixture", unit.instance_id,
		EconomyState.new(10, 3, 0, 0, 0, 0, []), pool, roster,
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(sold.ok)
	if not sold.ok: return
	assert_eq(sold.transaction.economy_state.gold, 12)
	assert_eq(sold.transaction.roster_state.unit_instances.size(), 0)
	assert_eq(sold.transaction.unit_pool_state.entries[0].held_copies, 0)
	_assert_pool_conserved(sold.transaction.unit_pool_state)

	var xp := service.quote_buy_xp(BuyXpRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(20, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(xp.ok)
	assert_eq(xp.transaction.economy_state.level, 4)
	assert_eq(xp.transaction.economy_state.xp, 0)
	assert_eq(xp.transaction.economy_state.gold, 16)
	var maxed := service.quote_buy_xp(BuyXpRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(20, 9, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_false(maxed.ok)
	assert_eq(maxed.error.code, ShopError.LEVEL_MAX)

func test_buy_rejects_insufficient_gold_and_full_bench_without_mutation() -> void:
	var catalog := EconomyTestFixture.catalog()
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(20, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(generated.ok)
	if not generated.ok: return
	var offer := generated.transaction.economy_state.shop_offers[0]
	var poor_economy := generated.transaction.economy_state.deep_clone()
	poor_economy.gold = 0
	var poor := ShopService.new().quote_buy(BuyOfferRequest.new(
		&"run_fixture", &"node_fixture", offer.offer_id, poor_economy,
		generated.transaction.unit_pool_state, generated.transaction.roster_state,
		generated.transaction.reservation_owners,
		generated.transaction.next_shop_rng_snapshot,
		generated.transaction.next_transaction_serial,
		generated.transaction.next_unit_serial, catalog,
		EconomyTestFixture.battle_catalog()
	))
	assert_false(poor.ok)
	assert_eq(poor.error.code, ShopError.GOLD_INSUFFICIENT)
	assert_eq(generated.transaction.economy_state.gold, 20)

	var full_roster := generated.transaction.roster_state.deep_clone()
	var no_equipment: Array[String] = []
	for index: int in range(9):
		var id := "u_%016x" % (index + 10)
		full_roster.unit_instances.append(UnitInstance.new(
			id, &"unit.test_b", 3, no_equipment,
			U64Bits.from_u32(0, index + 10).value
		))
		full_roster.bench_unit_instance_ids.append(id)
	var full := ShopService.new().quote_buy(BuyOfferRequest.new(
		&"run_fixture", &"node_fixture", offer.offer_id,
		generated.transaction.economy_state, generated.transaction.unit_pool_state,
		full_roster, generated.transaction.reservation_owners,
		generated.transaction.next_shop_rng_snapshot,
		generated.transaction.next_transaction_serial,
		generated.transaction.next_unit_serial, catalog,
		EconomyTestFixture.battle_catalog()
	))
	assert_false(full.ok)
	assert_eq(full.error.code, ShopError.ROSTER_FULL)
	assert_eq(full_roster.bench_unit_instance_ids.size(), 9)

func test_sell_prices_all_stars_and_moves_equipment_to_overflow() -> void:
	var catalog := EconomyTestFixture.catalog()
	var expected_prices := [1, 2, 6]
	var copy_counts := [1, 3, 9]
	for star: int in range(1, 4):
		var pool := catalog.create_initial_pool()
		var entry := pool.entries[0]
		entry.remaining_copies -= copy_counts[star - 1]
		entry.held_copies = copy_counts[star - 1]
		var roster := EconomyTestFixture.empty_roster()
		var equipment_ids: Array[String] = []
		if star == 3:
			for index: int in range(16):
				var inventory_id := "i_%016x" % (index + 1)
				roster.item_instances.append(ItemInstanceState.new(
					inventory_id, &"item.inventory", null,
					U64Bits.from_u32(0, index + 1).value
				))
				roster.inventory_item_instance_ids.append(inventory_id)
			var equipped_id := "i_0000000000000011"
			roster.item_instances.append(ItemInstanceState.new(
				equipped_id, &"item.equipped",
				OptionalStringValue.new("u_0000000000000001"),
				U64Bits.from_u32(0, 17).value
			))
			equipment_ids.append(equipped_id)
		var unit := UnitInstance.new(
			"u_0000000000000001", entry.unit_def_id, star,
			equipment_ids, U64Bits.one()
		)
		roster.unit_instances.append(unit)
		roster.bench_unit_instance_ids.append(unit.instance_id)
		var sold := ShopService.new().quote_sell(SellUnitRequest.new(
			&"run_fixture", &"node_fixture", unit.instance_id,
			EconomyState.new(10, 3, 0, 0, 0, 0, []), pool, roster,
			EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
			U64Bits.zero(), U64Bits.one(), catalog
		))
		assert_true(sold.ok, "star %d" % star)
		if not sold.ok: continue
		assert_eq(sold.transaction.economy_state.gold, 10 + expected_prices[star - 1])
		assert_eq(sold.transaction.unit_pool_state.entries[0].held_copies, 0)
		if star == 3:
			assert_eq(sold.transaction.roster_state.pending_item_overflow, ["i_0000000000000011"])
		_assert_pool_conserved(sold.transaction.unit_pool_state)

func test_xp_curve_consumes_164_xp_and_preserves_cross_level_overflow() -> void:
	var catalog := EconomyTestFixture.catalog()
	var service := ShopService.new()
	var overflow := service.quote_buy_xp(BuyXpRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(20, 3, 3, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(overflow.ok)
	if not overflow.ok: return
	assert_eq(overflow.transaction.economy_state.level, 4)
	assert_eq(overflow.transaction.economy_state.xp, 3)

	var economy := EconomyState.new(200, 3, 0, 0, 0, 0, [])
	var pool := catalog.create_initial_pool()
	var roster := EconomyTestFixture.empty_roster()
	var owners := EconomyTestFixture.empty_owners()
	var rng := EconomyTestFixture.shop_rng()
	var transaction_serial := U64Bits.zero()
	var unit_serial := U64Bits.one()
	for _purchase: int in range(41):
		var bought := service.quote_buy_xp(BuyXpRequest.new(
			&"run_fixture", &"node_fixture", economy, pool, roster, owners, rng,
			transaction_serial, unit_serial, catalog
		))
		assert_true(bought.ok)
		if not bought.ok: return
		economy = bought.transaction.economy_state
		pool = bought.transaction.unit_pool_state
		roster = bought.transaction.roster_state
		owners = bought.transaction.reservation_owners
		rng = bought.transaction.next_shop_rng_snapshot
		transaction_serial = bought.transaction.next_transaction_serial
		unit_serial = bought.transaction.next_unit_serial
	assert_eq(economy.level, 9)
	assert_eq(economy.xp, 0)
	assert_eq(economy.gold, 36)

func _active_owners(owners: Array[ReservationOwnerState]) -> int:
	var count := 0
	for owner: ReservationOwnerState in owners:
		if owner.status == ReservationOwnerState.Status.ACTIVE: count += 1
	return count

func _released_owners(owners: Array[ReservationOwnerState]) -> int:
	var count := 0
	for owner: ReservationOwnerState in owners:
		if owner.status == ReservationOwnerState.Status.RELEASED: count += 1
	return count

func _assert_pool_conserved(pool: UnitPoolState) -> void:
	for entry: UnitPoolEntryState in pool.entries:
		assert_eq(entry.remaining_copies + entry.reserved_copies + entry.held_copies, entry.total_copies)

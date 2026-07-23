class_name ShopService
extends RefCounted

const OFFER_COUNT: int = 5
const MAX_TIER_RETRIES: int = 20
const INVENTORY_CAPACITY: int = 16

func generate_offers(request: GenerateOffersRequest) -> ShopTransactionResult:
	var error := _validate_request(request)
	if error != null:
		return ShopTransactionResult.failure(error.code, error.field_path)
	if not request.economy_state.shop_offers.is_empty():
		return ShopTransactionResult.failure(ShopError.OFFER_STALE, &"economy_state.shop_offers")
	var economy := request.economy_state.deep_clone()
	var pool := request.unit_pool_state.deep_clone()
	var owners := _clone_owners(request.reservation_owners)
	var stream_result := Pcg32Stream.from_snapshot(request.shop_rng_snapshot)
	if not stream_result.ok:
		return ShopTransactionResult.failure(ShopError.RNG_FAILED, &"shop_rng_snapshot")
	var generation_error := _generate_offers(
		request.run_id, request.node_id, economy, pool, owners,
		stream_result.stream, request.catalog, _economy_discount(request)
	)
	if generation_error != null:
		return ShopTransactionResult.failure(generation_error.code, generation_error.field_path)
	return _finish(request, &"shop_generate", economy, pool, request.roster_state,
		owners, stream_result.stream.snapshot(), request.next_unit_serial)

func quote_refresh(request: RefreshShopRequest) -> ShopTransactionResult:
	var error := _validate_request(request)
	if error != null:
		return ShopTransactionResult.failure(error.code, error.field_path)
	var config := request.catalog.config()
	if request.economy_state.gold < config.reroll_cost:
		return ShopTransactionResult.failure(ShopError.GOLD_INSUFFICIENT, &"economy_state.gold")
	var economy := request.economy_state.deep_clone()
	var pool := request.unit_pool_state.deep_clone()
	var owners := _clone_owners(request.reservation_owners)
	var release_error := _release_offers(economy, pool, owners)
	if release_error != null:
		return ShopTransactionResult.failure(release_error.code, release_error.field_path)
	economy.gold -= config.reroll_cost
	economy.shop_refresh_index += 1
	var stream_result := Pcg32Stream.from_snapshot(request.shop_rng_snapshot)
	if not stream_result.ok:
		return ShopTransactionResult.failure(ShopError.RNG_FAILED, &"shop_rng_snapshot")
	var generation_error := _generate_offers(
		request.run_id, request.node_id, economy, pool, owners,
		stream_result.stream, request.catalog, _economy_discount(request)
	)
	if generation_error != null:
		return ShopTransactionResult.failure(generation_error.code, generation_error.field_path)
	return _finish(request, &"shop_refresh", economy, pool, request.roster_state,
		owners, stream_result.stream.snapshot(), request.next_unit_serial)

func quote_buy(request: BuyOfferRequest) -> ShopTransactionResult:
	var error := _validate_request(request)
	if error != null or request.battle_catalog == null or request.offer_id.is_empty():
		return ShopTransactionResult.failure(
			error.code if error != null else ShopError.INPUT_INVALID,
			error.field_path if error != null else &"offer_id"
		)
	var economy := request.economy_state.deep_clone()
	var pool := request.unit_pool_state.deep_clone()
	var roster := request.roster_state.deep_clone()
	var owners := _clone_owners(request.reservation_owners)
	var offer_index := _offer_index(economy.shop_offers, request.offer_id)
	if offer_index < 0:
		return ShopTransactionResult.failure(ShopError.OFFER_STALE, &"offer_id")
	var offer := economy.shop_offers[offer_index]
	if economy.gold < offer.cost:
		return ShopTransactionResult.failure(ShopError.GOLD_INSUFFICIENT, &"economy_state.gold")
	var owner := _find_owner(owners, offer.reservation_owner_key)
	var pool_entry := _find_pool(pool, offer.unit_def_id)
	if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
		or owner.unit_def_id != offer.unit_def_id or owner.reserved_copies != 1:
		return ShopTransactionResult.failure(ShopError.RESERVATION_INVALID, &"reservation_owner")
	if pool_entry == null or pool_entry.reserved_copies < 1:
		return ShopTransactionResult.failure(ShopError.UNIT_POOL_INVALID, &"unit_pool_state")
	var created := InstanceIdFactory.new().create(&"u", request.next_unit_serial)
	if not created.ok:
		return ShopTransactionResult.failure(ShopError.SERIAL_EXHAUSTED, &"next_unit_serial")
	var no_equipment: Array[String] = []
	roster.unit_instances.append(UnitInstance.new(
		String(created.instance_id), offer.unit_def_id, 1, no_equipment,
		request.next_unit_serial
	))
	roster.bench_unit_instance_ids.append(String(created.instance_id))
	pool_entry.reserved_copies -= 1
	pool_entry.held_copies += 1
	owner.status = ReservationOwnerState.Status.CONSUMED
	economy.gold -= offer.cost
	economy.shop_offers.remove_at(offer_index)
	var merged := UnitMergeService.new().merge_all(roster, request.battle_catalog)
	if not merged.ok:
		return ShopTransactionResult.failure(ShopError.MERGE_FAILED, merged.error.field_path)
	if merged.roster.bench_unit_instance_ids.size() > 9:
		return ShopTransactionResult.failure(ShopError.ROSTER_FULL, &"roster_state.bench_unit_instance_ids")
	return _finish(request, &"shop_buy", economy, pool, merged.roster,
		owners, request.shop_rng_snapshot, created.next_serial)

func quote_sell(request: SellUnitRequest) -> ShopTransactionResult:
	var error := _validate_request(request)
	if error != null or request.unit_instance_id.is_empty():
		return ShopTransactionResult.failure(
			error.code if error != null else ShopError.INPUT_INVALID,
			error.field_path if error != null else &"unit_instance_id"
		)
	var economy := request.economy_state.deep_clone()
	var pool := request.unit_pool_state.deep_clone()
	var roster := request.roster_state.deep_clone()
	var unit := _find_unit(roster, request.unit_instance_id)
	if unit == null:
		return ShopTransactionResult.failure(ShopError.UNIT_MISSING, &"unit_instance_id")
	var unit_rule := request.catalog.try_shop_unit(unit.def_id)
	var pool_entry := _find_pool(pool, unit.def_id)
	if unit_rule == null or pool_entry == null:
		return ShopTransactionResult.failure(ShopError.UNIT_RULE_MISSING, &"unit.def_id")
	var copies: int = [0, 1, 3, 9][unit.star]
	if pool_entry.held_copies < copies:
		return ShopTransactionResult.failure(ShopError.UNIT_POOL_INVALID, &"unit_pool_state.held_copies")
	var sale_price := unit_rule.cost
	if unit.star == 2: sale_price = 3 * unit_rule.cost - 1
	if unit.star == 3: sale_price = 9 * unit_rule.cost - 3
	sale_price = maxi(1, sale_price)
	var equipment_ids := unit.equipment_instance_ids.duplicate()
	for item_id: String in equipment_ids:
		var item := _find_item(roster, item_id)
		if item == null or item.bound_unit_instance_id == null \
			or item.bound_unit_instance_id.value != unit.instance_id:
			return ShopTransactionResult.failure(ShopError.INPUT_INVALID, &"roster_state.item_instances")
		item.bound_unit_instance_id = null
		if roster.inventory_item_instance_ids.size() < INVENTORY_CAPACITY:
			roster.inventory_item_instance_ids.append(item_id)
		else:
			roster.pending_item_overflow.append(item_id)
	roster.inventory_item_instance_ids.sort()
	roster.pending_item_overflow.sort()
	_remove_unit_from_roster(roster, unit.instance_id)
	pool_entry.held_copies -= copies
	pool_entry.remaining_copies += copies
	economy.gold = mini(request.catalog.config().gold_cap, economy.gold + sale_price)
	return _finish(request, &"shop_sell", economy, pool, roster,
		request.reservation_owners, request.shop_rng_snapshot, request.next_unit_serial)

func quote_buy_xp(request: BuyXpRequest) -> ShopTransactionResult:
	var error := _validate_request(request)
	if error != null:
		return ShopTransactionResult.failure(error.code, error.field_path)
	var config := request.catalog.config()
	if request.economy_state.level >= 9:
		return ShopTransactionResult.failure(ShopError.LEVEL_MAX, &"economy_state.level")
	if request.economy_state.gold < config.xp_buy_cost:
		return ShopTransactionResult.failure(ShopError.GOLD_INSUFFICIENT, &"economy_state.gold")
	var economy := request.economy_state.deep_clone()
	economy.gold -= config.xp_buy_cost
	economy.xp += config.xp_buy_amount
	while economy.level < 9:
		var threshold := config.value_for(config.xp_thresholds, economy.level, -1)
		if threshold < 1:
			return ShopTransactionResult.failure(ShopError.CONFIG_INVALID, &"xp_thresholds")
		if economy.xp < threshold:
			break
		economy.xp -= threshold
		economy.level += 1
	if economy.level == 9:
		economy.xp = 0
	return _finish(request, &"shop_buy_xp", economy, request.unit_pool_state,
		request.roster_state, request.reservation_owners,
		request.shop_rng_snapshot, request.next_unit_serial)

func _validate_request(request: ShopStateRequest) -> ShopError:
	if request == null or request.run_id.is_empty() or request.node_id.is_empty() \
		or request.economy_state == null or request.unit_pool_state == null \
		or request.roster_state == null or request.shop_rng_snapshot == null \
		or request.next_transaction_serial == null or request.next_unit_serial == null \
		or request.catalog == null:
		return ShopError.new(ShopError.INPUT_INVALID, &"request")
	if request.next_transaction_serial.equals(U64Bits.max_value()):
		return ShopError.new(ShopError.SERIAL_EXHAUSTED, &"next_transaction_serial")
	return null

func _economy_discount(request: ShopStateRequest) -> int:
	if request.relic_table == null:
		return 0
	return request.relic_table.sum_operation_amount(
		request.active_relic_ids, &"economy", &"shop_discount"
	)

func _generate_offers(
	run_id: StringName, node_id: StringName, economy: EconomyState,
	pool: UnitPoolState, owners: Array[ReservationOwnerState],
	stream: Pcg32Stream, catalog: EconomyExpeditionCatalog, price_discount: int
) -> ShopError:
	var odds := catalog.config().try_odds_for_level(economy.level)
	if odds == null:
		return ShopError.new(ShopError.CONFIG_INVALID, &"shop_odds_by_level")
	var stage := StringName("refresh_%010d" % economy.shop_refresh_index)
	for slot_index: int in range(OFFER_COUNT):
		var selected_rule: ShopUnitRule = null
		for _retry: int in range(MAX_TIER_RETRIES):
			var tier_draw := stream.next_basis_points()
			if not tier_draw.ok:
				return ShopError.new(ShopError.RNG_FAILED, &"shop_rng")
			var tier := _tier_from_roll(odds.tier_basis_points, tier_draw.value_u32.low_u32())
			var candidates: Array[ShopUnitRule] = []
			var total := 0
			for rule: ShopUnitRule in catalog.shop_units():
				var entry := _find_pool(pool, rule.unit_id)
				if rule.cost_tier == tier and entry != null and entry.remaining_copies > 0:
					candidates.append(rule)
					total += entry.remaining_copies
			if total == 0:
				continue
			var unit_draw := stream.next_bounded(total)
			if not unit_draw.ok:
				return ShopError.new(ShopError.RNG_FAILED, &"shop_rng")
			var cursor := unit_draw.value_u32.low_u32()
			for rule: ShopUnitRule in candidates:
				var copies := _find_pool(pool, rule.unit_id).remaining_copies
				if cursor < copies:
					selected_rule = rule
					break
				cursor -= copies
			if selected_rule != null:
				break
		if selected_rule == null:
			continue
		var key_result := RuntimeKeySchemaRegistry.new().build_reservation_owner(
			run_id, node_id, &"shop", stage, slot_index
		)
		if not key_result.ok:
			return ShopError.new(ShopError.KEY_FAILED, key_result.error.field_path)
		var owner_key := key_result.key_state as ReservationOwnerKeyState
		if _find_owner(owners, owner_key) != null:
			return ShopError.new(ShopError.RESERVATION_INVALID, &"reservation_owners")
		var entry := _find_pool(pool, selected_rule.unit_id)
		entry.remaining_copies -= 1
		entry.reserved_copies += 1
		var owner_payload := EconomyPayloadDigest.sha256([
			"RSV1", String(owner_key.digest), String(selected_rule.unit_id), "1"
		])
		if owner_payload.is_empty():
			return ShopError.new(ShopError.DIGEST_FAILED, &"reservation_owner.payload_digest")
		owners.append(ReservationOwnerState.new(
			owner_key, selected_rule.unit_id, 1,
			ReservationOwnerState.Status.ACTIVE, owner_payload
		))
		economy.shop_offers.append(ShopOffer.new(
			slot_index, String(owner_key.digest), selected_rule.unit_id,
			maxi(1, selected_rule.cost - price_discount), 1, owner_key
		))
	_sort_owners(owners)
	return null

func _release_offers(
	economy: EconomyState, pool: UnitPoolState,
	owners: Array[ReservationOwnerState]
) -> ShopError:
	for offer: ShopOffer in economy.shop_offers:
		var owner := _find_owner(owners, offer.reservation_owner_key)
		var entry := _find_pool(pool, offer.unit_def_id)
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or entry == null or entry.reserved_copies < offer.reserved_copies:
			return ShopError.new(ShopError.RESERVATION_INVALID, &"shop_offers")
		entry.reserved_copies -= offer.reserved_copies
		entry.remaining_copies += offer.reserved_copies
		owner.status = ReservationOwnerState.Status.RELEASED
	economy.shop_offers.clear()
	return null

func _finish(
	request: ShopStateRequest, command_kind: StringName,
	economy: EconomyState, pool: UnitPoolState, roster: RosterState,
	owners: Array[ReservationOwnerState], rng: RngSnapshot,
	next_unit_serial: U64Bits
) -> ShopTransactionResult:
	var key_result := RuntimeKeySchemaRegistry.new().build_transaction(
		request.run_id, request.node_id, command_kind, request.next_transaction_serial
	)
	if not key_result.ok:
		return ShopTransactionResult.failure(ShopError.KEY_FAILED, key_result.error.field_path)
	var payload := _transaction_digest(command_kind, key_result.key_state.digest, economy, pool, roster, owners, rng)
	if payload.is_empty():
		return ShopTransactionResult.failure(ShopError.DIGEST_FAILED, &"payload_digest")
	var receipt := TransactionReceiptState.new(key_result.key_state as TransactionKeyState, payload)
	return ShopTransactionResult.success(ShopTransaction.new(
		economy, pool, roster, owners, rng,
		request.next_transaction_serial.add(U64Bits.one()), next_unit_serial, receipt
	))

func _transaction_digest(
	kind: StringName, key_digest: StringName, economy: EconomyState,
	pool: UnitPoolState, roster: RosterState,
	owners: Array[ReservationOwnerState], rng: RngSnapshot
) -> String:
	var parts: Array[String] = ["SHP1", String(kind), String(key_digest), str(economy.gold), str(economy.level), str(economy.xp), str(economy.shop_refresh_index), rng.counter.to_hex()]
	for offer: ShopOffer in economy.shop_offers:
		parts.append("%d:%s:%s:%d" % [offer.slot_index, offer.offer_id, String(offer.unit_def_id), offer.cost])
	for entry: UnitPoolEntryState in pool.entries:
		parts.append("%s:%d:%d:%d:%d" % [String(entry.unit_def_id), entry.total_copies, entry.remaining_copies, entry.reserved_copies, entry.held_copies])
	for unit: UnitInstance in roster.unit_instances:
		parts.append("%s:%s:%d" % [unit.instance_id, String(unit.def_id), unit.star])
	for owner: ReservationOwnerState in owners:
		parts.append("%s:%d" % [String(owner.key.digest), owner.status])
	return EconomyPayloadDigest.sha256(parts)

func _tier_from_roll(odds: Array[int], roll: int) -> int:
	var cumulative := 0
	for index: int in range(odds.size()):
		cumulative += odds[index]
		if roll < cumulative:
			return index + 1
	return odds.size()

func _offer_index(offers: Array[ShopOffer], offer_id: String) -> int:
	for index: int in range(offers.size()):
		if offers[index].offer_id == offer_id:
			return index
	return -1

func _find_owner(owners: Array[ReservationOwnerState], key: ReservationOwnerKeyState) -> ReservationOwnerState:
	if key == null:
		return null
	for owner: ReservationOwnerState in owners:
		if owner.key != null and owner.key.digest == key.digest:
			return owner
	return null

func _find_pool(pool: UnitPoolState, unit_id: StringName) -> UnitPoolEntryState:
	for entry: UnitPoolEntryState in pool.entries:
		if entry.unit_def_id == unit_id:
			return entry
	return null

func _find_unit(roster: RosterState, instance_id: String) -> UnitInstance:
	for unit: UnitInstance in roster.unit_instances:
		if unit.instance_id == instance_id:
			return unit
	return null

func _find_item(roster: RosterState, instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id == instance_id:
			return item
	return null

func _remove_unit_from_roster(roster: RosterState, instance_id: String) -> void:
	for index: int in range(roster.board.placements.size() - 1, -1, -1):
		if roster.board.placements[index].unit_instance_id == instance_id:
			roster.board.placements.remove_at(index)
	roster.bench_unit_instance_ids.erase(instance_id)
	for index: int in range(roster.unit_instances.size() - 1, -1, -1):
		if roster.unit_instances[index].instance_id == instance_id:
			roster.unit_instances.remove_at(index)

func _clone_owners(source: Array[ReservationOwnerState]) -> Array[ReservationOwnerState]:
	var result: Array[ReservationOwnerState] = []
	for owner: ReservationOwnerState in source: result.append(owner.deep_clone())
	return result

func _sort_owners(owners: Array[ReservationOwnerState]) -> void:
	owners.sort_custom(func(left: ReservationOwnerState, right: ReservationOwnerState) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)

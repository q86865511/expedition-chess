class_name RunStateValidator
extends RefCounted

const _MAX_U32: int = 0xffffffff
const _MIN_I32: int = -2147483648
const _MAX_I32: int = 2147483647
const _DIGEST_PATTERN: String = "^[0-9a-f]{64}$"
const _PROFILE_PATTERN: String = "^[0-9a-f]{32}$"
const _STABLE_ID_PATTERN: String = StableIdValidator.PATTERN
const _UNIT_ID_PATTERN: String = "^u_[0-9a-f]{16}$"
const _ITEM_ID_PATTERN: String = "^it_[0-9a-f]{16}$"

var _digest_regex: RegEx
var _profile_regex: RegEx
var _stable_id_regex: RegEx
var _unit_id_regex: RegEx
var _item_id_regex: RegEx

func _init() -> void:
	_digest_regex = RegEx.new()
	_profile_regex = RegEx.new()
	_stable_id_regex = RegEx.new()
	_unit_id_regex = RegEx.new()
	_item_id_regex = RegEx.new()
	_digest_regex.compile(_DIGEST_PATTERN)
	_profile_regex.compile(_PROFILE_PATTERN)
	_stable_id_regex.compile(_STABLE_ID_PATTERN)
	_unit_id_regex.compile(_UNIT_ID_PATTERN)
	_item_id_regex.compile(_ITEM_ID_PATTERN)

func validate_root(root: SaveRoot) -> DtoValidationResult:
	if root == null:
		return _failure(&"root")
	if root.schema_version != SaveSchemaContract.CURRENT:
		return _failure(&"schema_version")
	if root.rng_version != 1:
		return _failure(&"rng_version")
	if root.hash_version != 1:
		return _failure(&"hash_version")
	if not _is_utc(root.saved_at_utc):
		return _failure(&"saved_at_utc")
	var profile_result := validate_profile(root.profile)
	if not profile_result.ok:
		return profile_result
	if root.run == null:
		return DtoValidationResult.success()
	if root.run.content_snapshot == null:
		return _failure(&"run.content_snapshot")
	if root.run.run_key == null or root.run.run_key.next_run_serial == null:
		return _failure(&"run.run_key")
	if root.content_version != root.run.content_snapshot.content_version_value():
		return _failure(&"content_version")
	if root.run.run_key.profile_id != root.profile.profile_id:
		return _failure(&"run.run_key.profile_id")
	if root.run.run_key.next_run_serial.equals(U64Bits.max_value()):
		return _failure(&"run.run_key.next_run_serial")
	if root.run.run_key.next_run_serial.add(U64Bits.one()).to_hex() != root.profile.next_run_serial.to_hex():
		return _failure(&"profile.next_run_serial")
	return validate_run(root.run, root.rng_version, root.hash_version)

func validate_profile(profile: ProfileState) -> DtoValidationResult:
	if profile == null or not _matches(_profile_regex, profile.profile_id):
		return _failure(&"profile.profile_id")
	if profile.next_run_serial == null or not _is_u32(profile.meta_currency):
		return _failure(&"profile.next_run_serial")
	if not _is_u32(profile.highest_challenge_level):
		return _failure(&"profile.highest_challenge_level")
	if not _stable_id(profile.settings_ref):
		return _failure(&"profile.settings_ref")
	if not _sorted_unique_names(profile.unlocked_content_ids):
		return _failure(&"profile.unlocked_content_ids")
	if not _sorted_unique_names(profile.discovered_content_ids):
		return _failure(&"profile.discovered_content_ids")
	var last_digest := ""
	for receipt: SettlementReceiptState in profile.settlement_receipts:
		if receipt == null or receipt.key == null \
			or not _runtime_key(receipt.key) or not _digest(receipt.payload_digest):
			return _failure(&"profile.settlement_receipts")
		if String(receipt.key.digest) <= last_digest or not _is_i32(receipt.currency_delta):
			return _failure(&"profile.settlement_receipts")
		last_digest = String(receipt.key.digest)
	if profile.last_selection != null:
		if not _stable_id(profile.last_selection.commander_id) \
			or not _is_u32(profile.last_selection.challenge_level):
			return _failure(&"profile.last_selection")
	var previous_commander_id := ""
	for record: CommanderChallengeRecordState in profile.commander_challenge_records:
		if record == null or not _stable_id(record.commander_id) \
			or not _is_u32(record.highest_cleared_level):
			return _failure(&"profile.commander_challenge_records")
		var commander_text := String(record.commander_id)
		if commander_text <= previous_commander_id:
			return _failure(&"profile.commander_challenge_records")
		previous_commander_id = commander_text
	return DtoValidationResult.success()

func validate_run(
	run: RunState,
	expected_rng_version: int = 1,
	expected_hash_version: int = 1,
	battle_catalog: BattleRuleCatalog = null
) -> DtoValidationResult:
	if run == null or run.run_key == null or run.run_id != String(run.run_key.digest):
		return _failure(&"run.run_id")
	if not _runtime_key(run.run_key):
		return _failure(&"run.run_key.digest")
	if run.run_seed == null:
		return _failure(&"run.run_seed")
	if run.next_transaction_serial == null or run.next_unit_serial == null or run.next_item_serial == null:
		return _failure(&"run.next_serial")
	if not _stable_id(run.commander_id) or not _is_u32(run.challenge_level) or not _is_u32(run.act_index):
		return _failure(&"run.commander_id")
	if run.expedition_hp < 0 or run.expedition_hp > 100:
		return _failure(&"run.expedition_hp")
	var phase_result := _validate_phase_resolution_pair(run)
	if not phase_result.ok:
		return phase_result
	var snapshot_result := _validate_content_snapshot(run.content_snapshot)
	if not snapshot_result.ok:
		return snapshot_result
	var map_result := _validate_map(run)
	if not map_result.ok:
		return map_result
	var economy_result := _validate_economy(run.economy_state)
	if not economy_result.ok:
		return economy_result
	var pool_result := _validate_pool(run.unit_pool_state)
	if not pool_result.ok:
		return pool_result
	var roster_result := _validate_roster(run.roster_state)
	if not roster_result.ok:
		return roster_result
	# Hard gate (design §5.4), the 繞不過 final defence behind the early-exit
	# checks in StartCombatEvent/NonCombatNodeService: the one-shot item-overflow
	# tray may be non-empty only while the player can still dispose of it -- during
	# PREPARE (the disposition window) or REWARD (the item-resolution flow that
	# populates it, validated in _validate_resolution). Once the run has left
	# PREPARE into COMBAT, a committed MAP transition, or terminal RESULTS, the
	# tray MUST be empty -- so any future PREPARE exit is caught here at
	# commit-validate time and can never softlock. Placed after _validate_roster
	# so structural roster errors (e.g. duplicate item location) still surface
	# first, mirroring how the reward-phase tray gate lives in _validate_resolution.
	if run.run_phase in [
		RunState.RunPhase.COMBAT, RunState.RunPhase.MAP, RunState.RunPhase.RESULTS,
	] and not run.roster_state.pending_item_overflow.is_empty():
		return _failure(&"run.roster_state.pending_item_overflow")
	if battle_catalog != null:
		var equipment_kind_result := _validate_equipment_kind(run.roster_state, battle_catalog)
		if not equipment_kind_result.ok:
			return equipment_kind_result
	var pool_roster_result := _validate_pool_roster_conservation(
		run.unit_pool_state,
		run.roster_state
	)
	if not pool_roster_result.ok:
		return pool_roster_result
	if run.rng_stream_states.size() != 4:
		return _failure(&"run.rng_stream_states")
	for index: int in range(4):
		var named_rng: NamedRngState = run.rng_stream_states[index]
		if named_rng == null or named_rng.stream_name != index or named_rng.snapshot == null:
			return _failure(&"run.rng_stream_states")
		var rng_result := _validate_rng_snapshot(
			named_rng.snapshot,
			expected_rng_version,
			StringName("run.rng_stream_states.%d.snapshot" % index)
		)
		if not rng_result.ok:
			return rng_result
	if not _sorted_unique_strings(run.income_claimed_node_ids):
		return _failure(&"run.income_claimed_node_ids")
	if not _sorted_unique_ints(run.loss_stipend_claimed_act_ids):
		return _failure(&"run.loss_stipend_claimed_act_ids")
	if not _sorted_unique_names(run.discovered_content_ids):
		return _failure(&"run.discovered_content_ids")
	if not _receipts_sorted(run):
		return _failure(&"run.ledgers")
	var node_choice_ledger_result := _validate_node_choice_ledger(run)
	if not node_choice_ledger_result.ok:
		return node_choice_ledger_result
	var reservation_result := _validate_reservation_ledger(run)
	if not reservation_result.ok:
		return reservation_result
	return _validate_resolution(
		run, run.resolution_state, expected_rng_version, expected_hash_version
	)

func _validate_content_snapshot(snapshot: ContentSnapshotState) -> DtoValidationResult:
	if snapshot == null \
		or not snapshot.is_validated() \
		or snapshot.content_version_value().is_empty() \
		or not _digest(snapshot.manifest_digest_value()):
		return _failure(&"run.content_snapshot")
	var enabled_content_ids := snapshot.enabled_content_ids_copy()
	var reward_table_ids := snapshot.reward_table_ids_copy()
	var map_node_def_ids := snapshot.map_node_def_ids_copy()
	var challenge_unlock_def_ids := snapshot.challenge_unlock_def_ids_copy()
	if not _sorted_unique_names(enabled_content_ids):
		return _failure(&"run.content_snapshot.enabled_content_ids")
	if not _stable_id(snapshot.economy_config_id_value()) \
		or not _stable_id(snapshot.meta_reward_table_id_value()):
		return _failure(&"run.content_snapshot.config")
	if not _sorted_unique_names(reward_table_ids):
		return _failure(&"run.content_snapshot.reward_table_ids")
	if not _sorted_unique_names(map_node_def_ids):
		return _failure(&"run.content_snapshot.map_node_def_ids")
	if not _sorted_unique_names(challenge_unlock_def_ids):
		return _failure(&"run.content_snapshot.challenge_unlock_def_ids")
	if not _contains_name(enabled_content_ids, snapshot.economy_config_id_value()):
		return _failure(&"run.content_snapshot.economy_config_id")
	if not _contains_name(enabled_content_ids, snapshot.meta_reward_table_id_value()):
		return _failure(&"run.content_snapshot.meta_reward_table_id")
	for value: StringName in reward_table_ids:
		if not _contains_name(enabled_content_ids, value):
			return _failure(&"run.content_snapshot.reward_table_ids")
	for value: StringName in map_node_def_ids:
		if not _contains_name(enabled_content_ids, value):
			return _failure(&"run.content_snapshot.map_node_def_ids")
	for value: StringName in challenge_unlock_def_ids:
		if not _contains_name(enabled_content_ids, value):
			return _failure(&"run.content_snapshot.challenge_unlock_def_ids")
	return DtoValidationResult.success()

func _validate_map(run: RunState) -> DtoValidationResult:
	var map: MapState = run.map_state
	if map == null:
		return _failure(&"run.map_state")
	if (run.current_node_id == null) != (map.current_node_id == null):
		return _failure(&"run.current_node_id")
	if run.current_node_id != null and run.current_node_id.value != map.current_node_id.value:
		return _failure(&"run.current_node_id")
	var previous_sort_key := ""
	var node_ids: Array[String] = []
	for node: MapNodeState in map.nodes:
		if node == null or node.node_key == null or node.node_id != String(node.node_key.digest):
			return _failure(&"run.map_state.nodes")
		if not _runtime_key(node.node_key):
			return _failure(&"run.map_state.nodes.node_key")
		if node.node_key.run_id != run.run_id or node.node_key.act_index != node.act_index:
			return _failure(&"run.map_state.nodes.node_key")
		if node.node_key.layer_index != node.layer_index or node.node_key.slot_index != node.slot_index:
			return _failure(&"run.map_state.nodes.node_key")
		if node.node_key.node_kind != MapNodeState.node_kind_to_token(node.node_kind):
			return _failure(&"run.map_state.nodes.node_key.node_kind")
		if not _stable_id(node.def_id) or not _digest(node.generated_payload_digest):
			return _failure(&"run.map_state.nodes")
		var sort_key := "%010d/%010d/%010d/%s" % [node.act_index, node.layer_index, node.slot_index, node.node_id]
		if sort_key <= previous_sort_key:
			return _failure(&"run.map_state.nodes")
		previous_sort_key = sort_key
		node_ids.append(node.node_id)
	if not _sorted_unique_strings(map.completed_node_ids):
		return _failure(&"run.map_state.completed_node_ids")
	for node_id: String in map.completed_node_ids:
		if not node_ids.has(node_id):
			return _failure(&"run.map_state.completed_node_ids")
	for node: MapNodeState in map.nodes:
		if node.completed != map.completed_node_ids.has(node.node_id):
			return _failure(&"run.map_state.nodes.completed")
	var previous_edge := ""
	for edge: MapEdgeState in map.edges:
		if edge == null:
			return _failure(&"run.map_state.edges")
		var edge_key := edge.from_node_id + "/" + edge.to_node_id
		if edge_key <= previous_edge or not node_ids.has(edge.from_node_id) or not node_ids.has(edge.to_node_id):
			return _failure(&"run.map_state.edges")
		previous_edge = edge_key
	if _map_has_cycle(node_ids, map.edges):
		return _failure(&"run.map_state.edges.cycle")
	return DtoValidationResult.success()

func _validate_economy(economy: EconomyState) -> DtoValidationResult:
	if economy == null:
		return _failure(&"run.economy_state")
	if not _is_u32(economy.gold) or not _is_u32(economy.level) or not _is_u32(economy.xp):
		return _failure(&"run.economy_state")
	if not _is_u32(economy.win_streak) or not _is_u32(economy.loss_streak) or not _is_u32(economy.shop_refresh_index):
		return _failure(&"run.economy_state")
	if economy.shop_offers.size() > 5:
		return _failure(&"run.economy_state.shop_offers")
	var previous_slot := -1
	for index: int in range(economy.shop_offers.size()):
		var offer: ShopOffer = economy.shop_offers[index]
		if offer == null or offer.slot_index <= previous_slot or offer.slot_index < 0 \
			or offer.slot_index >= 5 or not _stable_id(offer.unit_def_id) \
			or offer.reservation_owner_key == null:
			return _failure(&"run.economy_state.shop_offers")
		if not _is_u32(offer.cost) or not _is_u32(offer.reserved_copies):
			return _failure(&"run.economy_state.shop_offers")
		previous_slot = offer.slot_index
	return DtoValidationResult.success()

func _validate_pool(pool: UnitPoolState) -> DtoValidationResult:
	if pool == null:
		return _failure(&"run.unit_pool_state")
	var previous := ""
	for entry: UnitPoolEntryState in pool.entries:
		if entry == null:
			return _failure(&"run.unit_pool_state.entries")
		var unit_id := String(entry.unit_def_id)
		if unit_id <= previous or not _stable_id(entry.unit_def_id):
			return _failure(&"run.unit_pool_state.entries")
		if not _is_u32(entry.total_copies) or not _is_u32(entry.remaining_copies):
			return _failure(&"run.unit_pool_state.entries")
		if not _is_u32(entry.reserved_copies) or not _is_u32(entry.held_copies):
			return _failure(&"run.unit_pool_state.entries")
		if entry.remaining_copies + entry.reserved_copies + entry.held_copies != entry.total_copies:
			return _failure(&"run.unit_pool_state.entries")
		previous = unit_id
	return DtoValidationResult.success()

func _validate_roster(roster: RosterState) -> DtoValidationResult:
	if roster == null or roster.board == null or roster.active_relic_slots.size() != 5:
		return _failure(&"run.roster_state")
	var unit_ids: Array[String] = []
	for unit: UnitInstance in roster.unit_instances:
		if unit == null or not _matches(_unit_id_regex, unit.instance_id) \
			or unit_ids.has(unit.instance_id):
			return _failure(&"run.roster_state.unit_instances")
		if not _stable_id(unit.def_id) or unit.star < 1 or unit.star > 3 or unit.acquired_serial == null:
			return _failure(&"run.roster_state.unit_instances")
		if unit.equipment_instance_ids.size() > 3 \
			or not _unique_nonempty_strings(unit.equipment_instance_ids):
			return _failure(&"run.roster_state.unit_instances.equipment_instance_ids")
		unit_ids.append(unit.instance_id)
	var placed: Array[String] = []
	var coordinates: Array[String] = []
	var previous_placement := ""
	for placement: BoardPlacementState in roster.board.placements:
		if placement == null or placement.logical_x < 0 or placement.logical_x > 7 \
			or placement.logical_y < 0 or placement.logical_y > 7:
			return _failure(&"run.roster_state.board.placements")
		var coordinate := "%d,%d" % [placement.logical_y, placement.logical_x]
		var sort_key := coordinate + "/" + placement.unit_instance_id
		if coordinates.has(coordinate) or placed.has(placement.unit_instance_id) or not unit_ids.has(placement.unit_instance_id):
			return _failure(&"run.roster_state.board.placements")
		if sort_key <= previous_placement:
			return _failure(&"run.roster_state.board.placements")
		coordinates.append(coordinate)
		placed.append(placement.unit_instance_id)
		previous_placement = sort_key
	if roster.bench_unit_instance_ids.size() > 9 \
		or not _unique_nonempty_strings(roster.bench_unit_instance_ids):
		return _failure(&"run.roster_state.bench_unit_instance_ids")
	for unit_id: String in roster.bench_unit_instance_ids:
		if placed.has(unit_id) or not unit_ids.has(unit_id):
			return _failure(&"run.roster_state.bench_unit_instance_ids")
	for unit_id: String in unit_ids:
		if not placed.has(unit_id) and not roster.bench_unit_instance_ids.has(unit_id):
			return _failure(&"run.roster_state.unit_instances.location")
	var item_ids: Array[String] = []
	for item: ItemInstanceState in roster.item_instances:
		if item == null or not _matches(_item_id_regex, item.instance_id) \
			or item_ids.has(item.instance_id):
			return _failure(&"run.roster_state.item_instances")
		if not _stable_id(item.def_id) or item.acquired_serial == null:
			return _failure(&"run.roster_state.item_instances")
		if item.bound_unit_instance_id != null and not unit_ids.has(item.bound_unit_instance_id.value):
			return _failure(&"run.roster_state.item_instances")
		item_ids.append(item.instance_id)
	if roster.inventory_item_instance_ids.size() > 16 \
		or not _sorted_unique_strings(roster.inventory_item_instance_ids) \
		or not _sorted_unique_strings(roster.pending_item_overflow):
		return _failure(&"run.roster_state.inventory")
	var equipped_item_ids: Array[String] = []
	for unit: UnitInstance in roster.unit_instances:
		for item_id: String in unit.equipment_instance_ids:
			if equipped_item_ids.has(item_id):
				return _failure(&"run.roster_state.unit_instances.equipment_instance_ids")
			var item := _find_item(roster.item_instances, item_id)
			if item == null or item.bound_unit_instance_id == null \
				or item.bound_unit_instance_id.value != unit.instance_id:
				return _failure(&"run.roster_state.item_instances.bound_unit_instance_id")
			equipped_item_ids.append(item_id)
	for item_id: String in roster.inventory_item_instance_ids:
		var item := _find_item(roster.item_instances, item_id)
		if item == null or item.bound_unit_instance_id != null \
			or roster.pending_item_overflow.has(item_id) or equipped_item_ids.has(item_id):
			return _failure(&"run.roster_state.inventory")
	for item_id: String in roster.pending_item_overflow:
		var item := _find_item(roster.item_instances, item_id)
		if item == null or item.bound_unit_instance_id != null or equipped_item_ids.has(item_id):
			return _failure(&"run.roster_state.pending_item_overflow")
	for item: ItemInstanceState in roster.item_instances:
		if item.bound_unit_instance_id != null:
			if not equipped_item_ids.has(item.instance_id):
				return _failure(&"run.roster_state.item_instances.bound_unit_instance_id")
		elif not roster.inventory_item_instance_ids.has(item.instance_id) \
			and not roster.pending_item_overflow.has(item.instance_id):
			return _failure(&"run.roster_state.item_instances.location")
	for index: int in range(5):
		var slot: RelicSlotState = roster.active_relic_slots[index]
		if slot == null or slot.slot_index != index \
			or (slot.relic_id != null and not _stable_id(slot.relic_id.value)):
			return _failure(&"run.roster_state.active_relic_slots")
	return DtoValidationResult.success()

func _validate_equipment_kind(
	roster: RosterState,
	battle_catalog: BattleRuleCatalog
) -> DtoValidationResult:
	for item: ItemInstanceState in roster.item_instances:
		if item.bound_unit_instance_id != null \
			and battle_catalog.try_equipment_rule(item.def_id) == null:
			return _failure(&"run.roster_state.item_instances.def_id")
	return DtoValidationResult.success()

func _validate_pool_roster_conservation(
	pool: UnitPoolState,
	roster: RosterState
) -> DtoValidationResult:
	for entry: UnitPoolEntryState in pool.entries:
		var weighted_copies := 0
		for unit: UnitInstance in roster.unit_instances:
			if unit.def_id == entry.unit_def_id:
				weighted_copies += _star_copy_weight(unit.star)
		if weighted_copies != entry.held_copies:
			return _failure(&"run.unit_pool_state.entries.held_copies")
	for unit: UnitInstance in roster.unit_instances:
		var found := false
		for entry: UnitPoolEntryState in pool.entries:
			if entry.unit_def_id == unit.def_id:
				found = true
				break
		if not found:
			return _failure(&"run.unit_pool_state.entries.unit_def_id")
	return DtoValidationResult.success()

func _star_copy_weight(star: int) -> int:
	match star:
		1: return 1
		2: return 3
		3: return 9
	return 0

func _find_item(items: Array[ItemInstanceState], instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in items:
		if item != null and item.instance_id == instance_id:
			return item
	return null

func _validate_resolution(
	run: RunState,
	resolution: ResolutionState,
	expected_rng_version: int,
	expected_hash_version: int
) -> DtoValidationResult:
	if resolution == null:
		return _failure(&"run.resolution_state")
	match resolution.kind:
		ResolutionState.Kind.IDLE:
			if not resolution is IdleResolutionState:
				return _failure(&"run.resolution_state")
		ResolutionState.Kind.COMBAT_PENDING:
			if not resolution is CombatPendingResolutionState:
				return _failure(&"run.resolution_state")
			var combat: CombatPendingResolutionState = resolution
			if combat.battle_setup == null or combat.battle_setup.rng_version != expected_rng_version:
				return _failure(&"run.resolution_state.battle_setup")
			if combat.battle_setup.hash_version != expected_hash_version:
				return _failure(&"run.resolution_state.battle_setup.hash_version")
			var combat_rng_result := _validate_rng_snapshot(
				combat.battle_setup.combat_rng_snapshot,
				expected_rng_version,
				&"run.resolution_state.battle_setup.combat_rng_snapshot"
			)
			if not combat_rng_result.ok:
				return combat_rng_result
		ResolutionState.Kind.BATTLE_RESULT_PENDING:
			if not resolution is BattleResultPendingResolutionState:
				return _failure(&"run.resolution_state")
			var battle: BattleResultPendingResolutionState = resolution
			if not _digest(battle.battle_setup_hash) or battle.battle_result == null:
				return _failure(&"run.resolution_state.battle_result")
			if String(battle.battle_result.battle_setup_hash) \
				!= battle.battle_setup_hash:
				return _failure(
					&"run.resolution_state.battle_result.battle_setup_hash"
				)
			var battle_result_error := battle.battle_result.validate()
			if battle_result_error != null:
				return _failure(StringName(
					"run.resolution_state.battle_result.%s" % \
					String(battle_result_error.field_path)
				))
			var result_validation := _validate_run_mutation_proposals(
				battle.battle_result.run_mutation_proposals
			)
			if not result_validation.ok:
				return result_validation
		ResolutionState.Kind.REWARD_PENDING:
			if not resolution is RewardPendingResolutionState:
				return _failure(&"run.resolution_state")
			var reward: RewardPendingResolutionState = resolution
			if reward.pending_reward == null or reward.pending_reward.transaction_id == null:
				return _failure(&"run.resolution_state.pending_reward")
			var pending_result := _validate_pending_reward(run, reward.pending_reward)
			if not pending_result.ok:
				return pending_result
			if reward.pending_reward.phase == PendingRewardState.Phase.CHOOSING:
				if reward.pending_reward.selected_choice_id != null or reward.pending_reward.selected_unit_reservation != null:
					return _failure(&"run.resolution_state.pending_reward.phase")
		ResolutionState.Kind.NODE_CHOICE_PENDING:
			if not resolution is NodeChoicePendingState:
				return _failure(&"run.resolution_state")
			var choice_pending := resolution as NodeChoicePendingState
			if (
				not choice_pending.is_valid()
				or run.current_node_id == null
				or StringName(run.current_node_id.value) != choice_pending.node_id
				or choice_pending.content_version
					!= run.content_snapshot.content_version_value()
				or choice_pending.catalog_schema_version
					!= run.content_snapshot.catalog_schema_version_value()
				or choice_pending.content_codec_version
					!= run.content_snapshot.content_codec_version_value()
				or choice_pending.manifest_digest
					!= run.content_snapshot.manifest_digest_value()
			):
				return _failure(&"run.resolution_state.node_choice_pending")
		ResolutionState.Kind.NODE_SERVICE_PENDING:
			if not resolution is NodeServicePendingResolutionState:
				return _failure(&"run.resolution_state")
			var service_pending := resolution as NodeServicePendingResolutionState
			if (
				service_pending.service_kind not in [&"dismantle", &"reward"]
				or not _node_key_digest(String(service_pending.node_id))
				or not _digest(service_pending.choice_receipt_digest)
				or not _has_node_choice_receipt(
					run,
					service_pending.choice_receipt_digest
				)
			):
				return _failure(&"run.resolution_state.node_service_pending")
		_:
			return _failure(&"run.resolution_state.kind")
	return DtoValidationResult.success()

func _validate_pending_reward(
	run: RunState,
	pending: PendingRewardState
) -> DtoValidationResult:
	if pending.node_id.is_empty() or run.current_node_id == null \
		or pending.node_id != run.current_node_id.value \
		or not _runtime_key(pending.transaction_id):
		return _failure(&"run.resolution_state.pending_reward.identity")
	var expected_offer_count := 1 \
		if pending.stage_id == PendingRewardState.StageId.EVENT_GRANT else 3
	if pending.offers.size() != expected_offer_count:
		return _failure(&"run.resolution_state.pending_reward.offers")
	var choice_ids: Array[String] = []
	var unit_owner_digests: Array[StringName] = []
	for offer: RewardOfferState in pending.offers:
		if offer == null or offer.choice_id.is_empty() \
			or choice_ids.has(offer.choice_id) or not _digest(offer.payload_digest) \
			or not _is_u32(offer.amount):
			return _failure(&"run.resolution_state.pending_reward.offers")
		if offer.reward_kind in [
			RewardOfferState.RewardKind.UNIT,
			RewardOfferState.RewardKind.ITEM,
			RewardOfferState.RewardKind.RELIC,
		] and (offer.content_id == null or not _stable_id(offer.content_id.value)):
			return _failure(&"run.resolution_state.pending_reward.offers.content_id")
		if offer.reward_kind == RewardOfferState.RewardKind.UNIT \
			and offer.reservation_owner_key == null:
			return _failure(&"run.resolution_state.pending_reward.offers.reservation")
		if offer.reward_kind == RewardOfferState.RewardKind.UNIT:
			if unit_owner_digests.has(offer.reservation_owner_key.digest):
				return _failure(&"run.resolution_state.pending_reward.offers.reservation")
			unit_owner_digests.append(offer.reservation_owner_key.digest)
		choice_ids.append(offer.choice_id)
	var reserved_owner_digests: Array[StringName] = []
	for reserved: ReservedCopyState in pending.reserved_copies:
		if reserved == null or not _stable_id(reserved.unit_def_id) \
			or reserved.copies < 1 or reserved.reservation_owner_key == null \
			or not _runtime_key(reserved.reservation_owner_key):
			return _failure(&"run.resolution_state.pending_reward.reserved_copies")
		var owner := _find_reservation_owner(
			run.reservation_owners, reserved.reservation_owner_key
		)
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or owner.unit_def_id != reserved.unit_def_id \
			or owner.reserved_copies != reserved.copies:
			return _failure(&"run.resolution_state.pending_reward.reserved_copies")
		if reserved_owner_digests.has(reserved.reservation_owner_key.digest):
			return _failure(&"run.resolution_state.pending_reward.reserved_copies")
		reserved_owner_digests.append(reserved.reservation_owner_key.digest)
	match pending.phase:
		PendingRewardState.Phase.CHOOSING:
			if pending.selected_choice_id != null \
				or pending.selected_unit_reservation != null:
				return _failure(&"run.resolution_state.pending_reward.phase")
			if unit_owner_digests.size() != reserved_owner_digests.size():
				return _failure(&"run.resolution_state.pending_reward.reserved_copies")
			for digest: StringName in unit_owner_digests:
				if not reserved_owner_digests.has(digest):
					return _failure(&"run.resolution_state.pending_reward.reserved_copies")
		PendingRewardState.Phase.UNIT_RESOLUTION:
			if pending.selected_choice_id == null \
				or pending.selected_unit_reservation == null:
				return _failure(&"run.resolution_state.pending_reward.phase")
			var selected_unit_offer := _find_reward_offer(
				pending.offers, pending.selected_choice_id.value
			)
			if selected_unit_offer == null \
				or selected_unit_offer.reward_kind != RewardOfferState.RewardKind.UNIT \
				or selected_unit_offer.reservation_owner_key == null \
				or selected_unit_offer.reservation_owner_key.digest \
					!= pending.selected_unit_reservation.digest \
				or reserved_owner_digests != [pending.selected_unit_reservation.digest]:
				return _failure(&"run.resolution_state.pending_reward.selected_unit_reservation")
		PendingRewardState.Phase.ITEM_RESOLUTION:
			var selected_item_phase_offer := _find_reward_offer(
				pending.offers,
				pending.selected_choice_id.value if pending.selected_choice_id != null else ""
			)
			var item_reward_flow := selected_item_phase_offer != null \
				and selected_item_phase_offer.reward_kind == RewardOfferState.RewardKind.ITEM \
				and pending.selected_unit_reservation == null \
				and reserved_owner_digests.is_empty()
			var unit_overflow_flow := selected_item_phase_offer != null \
				and selected_item_phase_offer.reward_kind == RewardOfferState.RewardKind.UNIT \
				and pending.selected_unit_reservation != null \
				and selected_item_phase_offer.reservation_owner_key != null \
				and selected_item_phase_offer.reservation_owner_key.digest \
					== pending.selected_unit_reservation.digest \
				and reserved_owner_digests.size() == 1 \
				and reserved_owner_digests[0] == pending.selected_unit_reservation.digest
			if run.roster_state.pending_item_overflow.is_empty() \
				or (not item_reward_flow and not unit_overflow_flow):
				return _failure(&"run.resolution_state.pending_reward.phase")
		PendingRewardState.Phase.RELIC_RESOLUTION:
			var selected_relic_offer := _find_reward_offer(
				pending.offers,
				pending.selected_choice_id.value if pending.selected_choice_id != null else ""
			)
			if selected_relic_offer == null \
				or selected_relic_offer.reward_kind != RewardOfferState.RewardKind.RELIC \
				or pending.selected_unit_reservation != null \
				or not reserved_owner_digests.is_empty():
				return _failure(&"run.resolution_state.pending_reward.phase")
		PendingRewardState.Phase.READY_TO_ADVANCE:
			if _find_reward_offer(
				pending.offers,
				pending.selected_choice_id.value if pending.selected_choice_id != null else ""
			) == null \
				or pending.selected_unit_reservation != null \
				or not run.roster_state.pending_item_overflow.is_empty() \
				or not reserved_owner_digests.is_empty():
				return _failure(&"run.resolution_state.pending_reward.phase")
	if pending.selected_choice_id != null \
		and not choice_ids.has(pending.selected_choice_id.value):
		return _failure(&"run.resolution_state.pending_reward.selected_choice_id")
	return DtoValidationResult.success()

func _validate_phase_resolution_pair(run: RunState) -> DtoValidationResult:
	if run.resolution_state == null:
		return _failure(&"run.resolution_state")
	match run.run_phase:
		RunState.RunPhase.MAP:
			if run.expedition_hp == 0 \
				or run.resolution_state.kind != ResolutionState.Kind.IDLE:
				return _failure(&"run.run_phase")
		RunState.RunPhase.PREPARE:
			if run.expedition_hp == 0 \
				or run.resolution_state.kind not in [
					ResolutionState.Kind.IDLE,
					ResolutionState.Kind.NODE_CHOICE_PENDING,
					ResolutionState.Kind.NODE_SERVICE_PENDING,
				]:
				return _failure(&"run.run_phase")
		RunState.RunPhase.COMBAT:
			if run.resolution_state.kind not in [
				ResolutionState.Kind.COMBAT_PENDING,
				ResolutionState.Kind.BATTLE_RESULT_PENDING,
			]:
				return _failure(&"run.run_phase")
		RunState.RunPhase.REWARD:
			if run.resolution_state.kind != ResolutionState.Kind.REWARD_PENDING:
				return _failure(&"run.run_phase")
		RunState.RunPhase.RESULTS:
			if run.resolution_state.kind != ResolutionState.Kind.IDLE \
				or (run.expedition_hp > 0 and not _final_boss_completed(run)):
				return _failure(&"run.run_phase")
		_:
			return _failure(&"run.run_phase")
	return DtoValidationResult.success()

func _final_boss_completed(run: RunState) -> bool:
	if run == null or run.map_state == null:
		return false
	for node: MapNodeState in run.map_state.nodes:
		if node.act_index == 3 \
			and node.node_kind == MapNodeState.NodeKind.BOSS and node.completed:
			return true
	return false

func _validate_reservation_ledger(run: RunState) -> DtoValidationResult:
	var live_reference_counts: Dictionary = {}
	var active_copy_totals: Dictionary = {}
	for owner: ReservationOwnerState in run.reservation_owners:
		if owner.reserved_copies < 1 or not _stable_id(owner.unit_def_id):
			return _failure(&"run.reservation_owners")
		if owner.status == ReservationOwnerState.Status.ACTIVE:
			live_reference_counts[owner.key.digest] = 0
			active_copy_totals[owner.unit_def_id] = int(
				active_copy_totals.get(owner.unit_def_id, 0)
			) + owner.reserved_copies
	for offer: ShopOffer in run.economy_state.shop_offers:
		var owner := _find_reservation_owner(
			run.reservation_owners, offer.reservation_owner_key
		)
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or owner.unit_def_id != offer.unit_def_id \
			or owner.reserved_copies != offer.reserved_copies:
			return _failure(&"run.economy_state.shop_offers.reservation")
		live_reference_counts[owner.key.digest] = int(
			live_reference_counts.get(owner.key.digest, 0)
		) + 1
	if run.resolution_state is RewardPendingResolutionState:
		var pending := (run.resolution_state as RewardPendingResolutionState).pending_reward
		if pending != null:
			for reserved: ReservedCopyState in pending.reserved_copies:
				var owner := _find_reservation_owner(
					run.reservation_owners, reserved.reservation_owner_key
				)
				if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
					or owner.unit_def_id != reserved.unit_def_id \
					or owner.reserved_copies != reserved.copies:
					return _failure(&"run.resolution_state.pending_reward.reserved_copies")
				live_reference_counts[owner.key.digest] = int(
					live_reference_counts.get(owner.key.digest, 0)
				) + 1
	for owner: ReservationOwnerState in run.reservation_owners:
		var references := int(live_reference_counts.get(owner.key.digest, 0))
		if (owner.status == ReservationOwnerState.Status.ACTIVE and references != 1) \
			or (owner.status != ReservationOwnerState.Status.ACTIVE and references != 0):
			return _failure(&"run.reservation_owners.lifecycle")
	for entry: UnitPoolEntryState in run.unit_pool_state.entries:
		if entry.reserved_copies != int(
			active_copy_totals.get(entry.unit_def_id, 0)
		):
			return _failure(&"run.unit_pool_state.entries.reserved_copies")
	return DtoValidationResult.success()

func _find_reward_offer(
	offers: Array[RewardOfferState],
	choice_id: String
) -> RewardOfferState:
	for offer: RewardOfferState in offers:
		if offer.choice_id == choice_id:
			return offer
	return null

func _find_reservation_owner(
	owners: Array[ReservationOwnerState],
	key: ReservationOwnerKeyState
) -> ReservationOwnerState:
	for owner: ReservationOwnerState in owners:
		if owner.key != null and owner.key.digest == key.digest:
			return owner
	return null

func _validate_run_mutation_proposals(
	proposals: Array[RunMutationProposal]
) -> DtoValidationResult:
	var previous_identity := ""
	for proposal: RunMutationProposal in proposals:
		if proposal == null:
			return _failure(&"run.resolution_state.battle_result.run_mutation_proposals")
		var restored := RunMutationProposal.restore(
			proposal.claim_scope,
			proposal.source_instance_or_slot,
			proposal.effect_id,
			proposal.operation_index,
			proposal.operation_kind,
			proposal.amount,
			proposal.payload_digest
		)
		if not restored.ok:
			return _failure(StringName(
				"run.resolution_state.battle_result.run_mutation_proposals.%s"
				% String(restored.error.field_path)
			))
		var identity := proposal.identity_key()
		if identity <= previous_identity:
			return _failure(
				&"run.resolution_state.battle_result.run_mutation_proposals.order"
			)
		previous_identity = identity
	return DtoValidationResult.success()

func _receipts_sorted(run: RunState) -> bool:
	var previous := ""
	for owner: ReservationOwnerState in run.reservation_owners:
		if owner.key == null or not _runtime_key(owner.key) or String(owner.key.digest) <= previous or not _digest(owner.payload_digest):
			return false
		previous = String(owner.key.digest)
	previous = ""
	for receipt: TransactionReceiptState in run.transaction_receipts:
		if receipt.key == null or not _runtime_key(receipt.key) or String(receipt.key.digest) <= previous or not _digest(receipt.payload_digest):
			return false
		previous = String(receipt.key.digest)
	previous = ""
	for receipt: ClaimReceiptState in run.claim_receipts:
		if receipt.key == null or not _runtime_key(receipt.key) or String(receipt.key.digest) <= previous or not _digest(receipt.payload_digest):
			return false
		previous = String(receipt.key.digest)
	return true


func _validate_node_choice_ledger(run: RunState) -> DtoValidationResult:
	var previous_serial := ""
	var seen_serials: Dictionary = {}
	var seen_pending: Dictionary = {}
	for entry: NodeChoiceReceiptLedgerEntry in run.node_choice_receipts:
		if entry == null or entry.receipt == null or not entry.receipt.is_valid():
			return _failure(&"run.node_choice_receipts")
		var receipt := entry.receipt
		if String(receipt.run_id) != run.run_id:
			return _failure(&"run.node_choice_receipts.run_id")
		if (
			not previous_serial.is_empty()
			and receipt.transaction_serial <= previous_serial
		):
			return _failure(&"run.node_choice_receipts.order")
		if (
			seen_serials.has(receipt.transaction_serial)
			or seen_pending.has(
				"%s\u0000%s" % [String(receipt.node_id), receipt.pending_digest]
			)
		):
			return _failure(&"run.node_choice_receipts.unique")
		var matching_transaction := false
		for transaction: TransactionReceiptState in run.transaction_receipts:
			if (
				transaction != null
				and transaction.key != null
				and String(transaction.key.digest) == receipt.transaction_digest
			):
				matching_transaction = true
				break
		if not matching_transaction:
			return _failure(&"run.node_choice_receipts.transaction_digest")
		previous_serial = receipt.transaction_serial
		seen_serials[receipt.transaction_serial] = true
		seen_pending[
			"%s\u0000%s" % [String(receipt.node_id), receipt.pending_digest]
		] = true
	return DtoValidationResult.success()


func _has_node_choice_receipt(run: RunState, receipt_digest: String) -> bool:
	for entry: NodeChoiceReceiptLedgerEntry in run.node_choice_receipts:
		if (
			entry != null
			and entry.receipt != null
			and entry.receipt.receipt_digest == receipt_digest
		):
			return true
	return false

func _map_has_cycle(node_ids: Array[String], edges: Array[MapEdgeState]) -> bool:
	var visit_states: Array[int] = []
	visit_states.resize(node_ids.size())
	visit_states.fill(0)
	for node_index: int in range(node_ids.size()):
		if visit_states[node_index] == 0 \
			and _map_cycle_from(node_index, node_ids, edges, visit_states):
			return true
	return false

func _map_cycle_from(
	node_index: int,
	node_ids: Array[String],
	edges: Array[MapEdgeState],
	visit_states: Array[int]
) -> bool:
	visit_states[node_index] = 1
	var node_id := node_ids[node_index]
	for edge: MapEdgeState in edges:
		if edge.from_node_id != node_id:
			continue
		var target_index := node_ids.find(edge.to_node_id)
		if target_index < 0:
			return true
		if visit_states[target_index] == 1:
			return true
		if visit_states[target_index] == 0 \
			and _map_cycle_from(target_index, node_ids, edges, visit_states):
			return true
	visit_states[node_index] = 2
	return false

func _validate_rng_snapshot(
	snapshot: RngSnapshot,
	expected_version: int,
	path: StringName
) -> DtoValidationResult:
	if snapshot == null or snapshot.rng_version != expected_version:
		return _failure(path)
	var reconstructed := RngSnapshot.create(
		snapshot.rng_version, snapshot.state, snapshot.inc, snapshot.counter
	)
	if not reconstructed.ok:
		return _failure(path)
	return DtoValidationResult.success()

func _is_u32(value: int) -> bool:
	return value >= 0 and value <= _MAX_U32

func _is_i32(value: int) -> bool:
	return value >= _MIN_I32 and value <= _MAX_I32

func _is_utc(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") != OK:
		return false
	return expression.search(value) != null

func _digest(value: String) -> bool:
	return _matches(_digest_regex, value)

# runtime node_id 是 RuntimeKeyCodecV1 的 "node_" + 64 lower-hex key digest
func _node_key_digest(value: String) -> bool:
	return value.begins_with("node_") and _digest(value.trim_prefix("node_"))

func _runtime_key(value: RuntimeKeyState) -> bool:
	if value == null:
		return false
	var result := RuntimeKeySchemaRegistry.new().reencode_state(value)
	return result.ok

func _stable_id(value: StringName) -> bool:
	return _matches(_stable_id_regex, String(value))

func _matches(expression: RegEx, value: String) -> bool:
	return expression.search(value) != null

func _sorted_unique_names(values: Array[StringName]) -> bool:
	var previous := ""
	for value: StringName in values:
		var text := String(value)
		if not _stable_id(value) or text <= previous:
			return false
		previous = text
	return true

func _sorted_unique_strings(values: Array[String]) -> bool:
	var previous := ""
	for value: String in values:
		if value.is_empty() or value <= previous:
			return false
		previous = value
	return true

func _unique_nonempty_strings(values: Array[String]) -> bool:
	var seen: Array[String] = []
	for value: String in values:
		if value.is_empty() or seen.has(value):
			return false
		seen.append(value)
	return true

func _sorted_unique_ints(values: Array[int]) -> bool:
	var previous: int = -1
	for value: int in values:
		if not _is_u32(value) or value <= previous:
			return false
		previous = value
	return true

func _contains_name(values: Array[StringName], target: StringName) -> bool:
	for value: StringName in values:
		if value == target:
			return true
	return false

func _failure(field_path: StringName) -> DtoValidationResult:
	return DtoValidationResult.failure(DtoValidationError.new(field_path))

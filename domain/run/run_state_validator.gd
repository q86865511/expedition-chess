class_name RunStateValidator
extends RefCounted

const _MAX_U32: int = 0xffffffff
const _MIN_I32: int = -2147483648
const _MAX_I32: int = 2147483647
const _DIGEST_PATTERN: String = "^[0-9a-f]{64}$"
const _PROFILE_PATTERN: String = "^[0-9a-f]{32}$"
const _STABLE_ID_PATTERN: String = "^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$"
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
	return DtoValidationResult.success()

func validate_run(run: RunState, expected_rng_version: int = 1, expected_hash_version: int = 1) -> DtoValidationResult:
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
	if not _is_i32(run.expedition_hp):
		return _failure(&"run.expedition_hp")
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
	if not _receipts_sorted(run):
		return _failure(&"run.ledgers")
	return _validate_resolution(run.resolution_state, expected_rng_version, expected_hash_version)

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
	if economy.shop_offers.size() != 0 and economy.shop_offers.size() != 5:
		return _failure(&"run.economy_state.shop_offers")
	for index: int in range(economy.shop_offers.size()):
		var offer: ShopOffer = economy.shop_offers[index]
		if offer.slot_index != index or not _stable_id(offer.unit_def_id) or offer.reservation_owner_key == null:
			return _failure(&"run.economy_state.shop_offers")
		if not _is_u32(offer.cost) or not _is_u32(offer.reserved_copies):
			return _failure(&"run.economy_state.shop_offers")
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
			if reward.pending_reward.phase == PendingRewardState.Phase.CHOOSING:
				if reward.pending_reward.selected_choice_id != null or reward.pending_reward.selected_unit_reservation != null:
					return _failure(&"run.resolution_state.pending_reward.phase")
		_:
			return _failure(&"run.resolution_state.kind")
	return DtoValidationResult.success()

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

class_name RunState
extends RefCounted

enum RunPhase { MAP, PREPARE, COMBAT, REWARD, RESULTS }

var run_id: String
var run_key: RunKeyState
var run_seed: U64Bits
var content_snapshot: ContentSnapshotState
var next_transaction_serial: U64Bits
var next_unit_serial: U64Bits
var next_item_serial: U64Bits
var commander_id: StringName
var challenge_level: int
var act_index: int
var map_state: MapState
var current_node_id: OptionalStringValue
var run_phase: RunPhase
var expedition_hp: int
var economy_state: EconomyState
var unit_pool_state: UnitPoolState
var roster_state: RosterState
var cleared_normal_count: int
var cleared_elite_count: int
var defeated_boss_count: int
var rng_stream_states: Array[NamedRngState] = []
var income_claimed_node_ids: Array[String] = []
var loss_stipend_claimed_act_ids: Array[int] = []
var reservation_owners: Array[ReservationOwnerState] = []
var transaction_receipts: Array[TransactionReceiptState] = []
var claim_receipts: Array[ClaimReceiptState] = []
var node_choice_receipts: Array[NodeChoiceReceiptLedgerEntry] = []
var resolution_state: ResolutionState
var discovered_content_ids: Array[StringName] = []

func _init(
	p_run_id: String,
	p_run_key: RunKeyState,
	p_run_seed: U64Bits,
	p_content_snapshot: ContentSnapshotState,
	p_next_transaction_serial: U64Bits,
	p_next_unit_serial: U64Bits,
	p_next_item_serial: U64Bits,
	p_commander_id: StringName,
	p_challenge_level: int,
	p_act_index: int,
	p_map_state: MapState,
	p_current_node_id: OptionalStringValue,
	p_run_phase: RunPhase,
	p_expedition_hp: int,
	p_economy_state: EconomyState,
	p_unit_pool_state: UnitPoolState,
	p_roster_state: RosterState,
	p_cleared_normal_count: int,
	p_cleared_elite_count: int,
	p_defeated_boss_count: int,
	p_rng_stream_states: Array[NamedRngState],
	p_income_claimed_node_ids: Array[String],
	p_loss_stipend_claimed_act_ids: Array[int],
	p_reservation_owners: Array[ReservationOwnerState],
	p_transaction_receipts: Array[TransactionReceiptState],
	p_claim_receipts: Array[ClaimReceiptState],
	p_resolution_state: ResolutionState,
	p_discovered_content_ids: Array[StringName],
	p_node_choice_receipts: Array[NodeChoiceReceiptLedgerEntry] = []
) -> void:
	run_id = p_run_id
	run_key = p_run_key.deep_clone()
	run_seed = p_run_seed.deep_clone()
	content_snapshot = p_content_snapshot.deep_clone()
	next_transaction_serial = p_next_transaction_serial.deep_clone()
	next_unit_serial = p_next_unit_serial.deep_clone()
	next_item_serial = p_next_item_serial.deep_clone()
	commander_id = p_commander_id
	challenge_level = p_challenge_level
	act_index = p_act_index
	map_state = p_map_state.deep_clone()
	current_node_id = p_current_node_id.deep_clone() if p_current_node_id != null else null
	run_phase = p_run_phase
	expedition_hp = p_expedition_hp
	economy_state = p_economy_state.deep_clone()
	unit_pool_state = p_unit_pool_state.deep_clone()
	roster_state = p_roster_state.deep_clone()
	cleared_normal_count = p_cleared_normal_count
	cleared_elite_count = p_cleared_elite_count
	defeated_boss_count = p_defeated_boss_count
	for named_rng: NamedRngState in p_rng_stream_states:
		rng_stream_states.append(named_rng.deep_clone())
	income_claimed_node_ids.assign(p_income_claimed_node_ids)
	loss_stipend_claimed_act_ids.assign(p_loss_stipend_claimed_act_ids)
	for owner: ReservationOwnerState in p_reservation_owners:
		reservation_owners.append(owner.deep_clone())
	for receipt: TransactionReceiptState in p_transaction_receipts:
		transaction_receipts.append(receipt.deep_clone())
	for receipt: ClaimReceiptState in p_claim_receipts:
		claim_receipts.append(receipt.deep_clone())
	for entry: NodeChoiceReceiptLedgerEntry in p_node_choice_receipts:
		node_choice_receipts.append(entry.deep_clone())
	resolution_state = p_resolution_state.deep_clone()
	discovered_content_ids.assign(p_discovered_content_ids)

func deep_clone() -> RunState:
	return RunState.new(
		run_id, run_key, run_seed, content_snapshot,
		next_transaction_serial, next_unit_serial, next_item_serial,
		commander_id, challenge_level, act_index, map_state, current_node_id,
		run_phase, expedition_hp, economy_state, unit_pool_state, roster_state,
		cleared_normal_count, cleared_elite_count, defeated_boss_count,
		rng_stream_states, income_claimed_node_ids, loss_stipend_claimed_act_ids,
		reservation_owners, transaction_receipts, claim_receipts, resolution_state,
		discovered_content_ids, node_choice_receipts
	)

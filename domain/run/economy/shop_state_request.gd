class_name ShopStateRequest
extends RefCounted

var run_id: StringName
var node_id: StringName
var economy_state: EconomyState
var unit_pool_state: UnitPoolState
var roster_state: RosterState
var reservation_owners: Array[ReservationOwnerState] = []
var shop_rng_snapshot: RngSnapshot
var next_transaction_serial: U64Bits
var next_unit_serial: U64Bits
var catalog: EconomyExpeditionCatalog
var relic_table: RunRelicTable
var active_relic_ids: Array[StringName] = []

func _init(
	p_run_id: StringName, p_node_id: StringName, p_economy: EconomyState,
	p_pool: UnitPoolState, p_roster: RosterState,
	p_owners: Array[ReservationOwnerState], p_rng: RngSnapshot,
	p_next_transaction_serial: U64Bits, p_next_unit_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog,
	p_relic_table: RunRelicTable = null,
	p_active_relic_ids: Array[StringName] = []
) -> void:
	run_id = p_run_id
	node_id = p_node_id
	economy_state = p_economy.deep_clone() if p_economy != null else null
	unit_pool_state = p_pool.deep_clone() if p_pool != null else null
	roster_state = p_roster.deep_clone() if p_roster != null else null
	for owner: ReservationOwnerState in p_owners: reservation_owners.append(owner.deep_clone())
	shop_rng_snapshot = p_rng.deep_clone() if p_rng != null else null
	next_transaction_serial = p_next_transaction_serial.deep_clone() if p_next_transaction_serial != null else null
	next_unit_serial = p_next_unit_serial.deep_clone() if p_next_unit_serial != null else null
	catalog = p_catalog.deep_clone() if p_catalog != null else null
	relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	active_relic_ids = p_active_relic_ids.duplicate()

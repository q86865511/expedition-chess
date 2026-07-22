class_name SellUnitRequest
extends ShopStateRequest

var unit_instance_id: String

func _init(
	p_run_id: StringName, p_node_id: StringName, p_unit_instance_id: String,
	p_economy: EconomyState, p_pool: UnitPoolState, p_roster: RosterState,
	p_owners: Array[ReservationOwnerState], p_rng: RngSnapshot,
	p_next_transaction_serial: U64Bits, p_next_unit_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog
) -> void:
	super(p_run_id, p_node_id, p_economy, p_pool, p_roster, p_owners, p_rng, p_next_transaction_serial, p_next_unit_serial, p_catalog)
	unit_instance_id = p_unit_instance_id

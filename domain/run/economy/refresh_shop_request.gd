class_name RefreshShopRequest
extends ShopStateRequest

func _init(
	p_run_id: StringName, p_node_id: StringName, p_economy: EconomyState,
	p_pool: UnitPoolState, p_roster: RosterState,
	p_owners: Array[ReservationOwnerState], p_rng: RngSnapshot,
	p_next_transaction_serial: U64Bits, p_next_unit_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog
) -> void:
	super(p_run_id, p_node_id, p_economy, p_pool, p_roster, p_owners, p_rng, p_next_transaction_serial, p_next_unit_serial, p_catalog)

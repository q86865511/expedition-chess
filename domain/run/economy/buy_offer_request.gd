class_name BuyOfferRequest
extends ShopStateRequest

var offer_id: String
var battle_catalog: BattleRuleCatalog

func _init(
	p_run_id: StringName, p_node_id: StringName, p_offer_id: String,
	p_economy: EconomyState, p_pool: UnitPoolState, p_roster: RosterState,
	p_owners: Array[ReservationOwnerState], p_rng: RngSnapshot,
	p_next_transaction_serial: U64Bits, p_next_unit_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog, p_battle_catalog: BattleRuleCatalog
) -> void:
	super(p_run_id, p_node_id, p_economy, p_pool, p_roster, p_owners, p_rng, p_next_transaction_serial, p_next_unit_serial, p_catalog)
	offer_id = p_offer_id
	battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null

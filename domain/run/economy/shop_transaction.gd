class_name ShopTransaction
extends RefCounted

var economy_state: EconomyState
var unit_pool_state: UnitPoolState
var roster_state: RosterState
var reservation_owners: Array[ReservationOwnerState] = []
var next_shop_rng_snapshot: RngSnapshot
var next_transaction_serial: U64Bits
var next_unit_serial: U64Bits
var receipt: TransactionReceiptState

func _init(
	p_economy: EconomyState, p_pool: UnitPoolState, p_roster: RosterState,
	p_owners: Array[ReservationOwnerState], p_rng: RngSnapshot,
	p_next_transaction_serial: U64Bits, p_next_unit_serial: U64Bits,
	p_receipt: TransactionReceiptState
) -> void:
	economy_state = p_economy.deep_clone()
	unit_pool_state = p_pool.deep_clone()
	roster_state = p_roster.deep_clone()
	for owner: ReservationOwnerState in p_owners: reservation_owners.append(owner.deep_clone())
	next_shop_rng_snapshot = p_rng.deep_clone()
	next_transaction_serial = p_next_transaction_serial.deep_clone()
	next_unit_serial = p_next_unit_serial.deep_clone()
	receipt = p_receipt.deep_clone()

func deep_clone() -> ShopTransaction:
	return ShopTransaction.new(economy_state, unit_pool_state, roster_state, reservation_owners, next_shop_rng_snapshot, next_transaction_serial, next_unit_serial, receipt)

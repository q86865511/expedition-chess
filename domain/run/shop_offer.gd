class_name ShopOffer
extends RefCounted

var slot_index: int
var offer_id: String
var unit_def_id: StringName
var cost: int
var reserved_copies: int
var reservation_owner_key: ReservationOwnerKeyState

func _init(
	p_slot_index: int,
	p_offer_id: String,
	p_unit_def_id: StringName,
	p_cost: int,
	p_reserved_copies: int,
	p_reservation_owner_key: ReservationOwnerKeyState
) -> void:
	slot_index = p_slot_index
	offer_id = p_offer_id
	unit_def_id = p_unit_def_id
	cost = p_cost
	reserved_copies = p_reserved_copies
	reservation_owner_key = p_reservation_owner_key.deep_clone()

func deep_clone() -> ShopOffer:
	return ShopOffer.new(slot_index, offer_id, unit_def_id, cost, reserved_copies, reservation_owner_key)

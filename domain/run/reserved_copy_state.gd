class_name ReservedCopyState
extends RefCounted

var unit_def_id: StringName
var copies: int
var reservation_owner_key: ReservationOwnerKeyState

func _init(
	p_unit_def_id: StringName,
	p_copies: int,
	p_reservation_owner_key: ReservationOwnerKeyState
) -> void:
	unit_def_id = p_unit_def_id
	copies = p_copies
	reservation_owner_key = p_reservation_owner_key.deep_clone()

func deep_clone() -> ReservedCopyState:
	return ReservedCopyState.new(unit_def_id, copies, reservation_owner_key)

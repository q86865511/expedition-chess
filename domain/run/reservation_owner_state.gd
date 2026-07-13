class_name ReservationOwnerState
extends RefCounted

enum Status { ACTIVE, CONSUMED, RELEASED }

var key: ReservationOwnerKeyState
var unit_def_id: StringName
var reserved_copies: int
var status: Status
var payload_digest: String

func _init(
	p_key: ReservationOwnerKeyState,
	p_unit_def_id: StringName,
	p_reserved_copies: int,
	p_status: Status,
	p_payload_digest: String
) -> void:
	key = p_key.deep_clone()
	unit_def_id = p_unit_def_id
	reserved_copies = p_reserved_copies
	status = p_status
	payload_digest = p_payload_digest

func deep_clone() -> ReservationOwnerState:
	return ReservationOwnerState.new(key, unit_def_id, reserved_copies, status, payload_digest)

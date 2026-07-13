class_name UnitPoolEntryState
extends RefCounted

var unit_def_id: StringName
var total_copies: int
var remaining_copies: int
var reserved_copies: int
var held_copies: int

func _init(
	p_unit_def_id: StringName,
	p_total_copies: int,
	p_remaining_copies: int,
	p_reserved_copies: int,
	p_held_copies: int
) -> void:
	unit_def_id = p_unit_def_id
	total_copies = p_total_copies
	remaining_copies = p_remaining_copies
	reserved_copies = p_reserved_copies
	held_copies = p_held_copies

func deep_clone() -> UnitPoolEntryState:
	return UnitPoolEntryState.new(unit_def_id, total_copies, remaining_copies, reserved_copies, held_copies)

class_name UnitCopyLedgerEntry
extends RefCounted

var unit_def_id: StringName
var weighted_copies: int

func _init(p_unit_def_id: StringName, p_weighted_copies: int) -> void:
	unit_def_id = p_unit_def_id
	weighted_copies = p_weighted_copies

func deep_clone() -> UnitCopyLedgerEntry:
	return UnitCopyLedgerEntry.new(unit_def_id, weighted_copies)

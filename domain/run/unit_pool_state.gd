class_name UnitPoolState
extends RefCounted

var entries: Array[UnitPoolEntryState] = []

func _init(p_entries: Array[UnitPoolEntryState]) -> void:
	for entry: UnitPoolEntryState in p_entries:
		entries.append(entry.deep_clone())

func deep_clone() -> UnitPoolState:
	return UnitPoolState.new(entries)

class_name CombatUnitInspectionSnapshot
extends RefCounted

var unit_serial: int
var source_id: StringName
var side_id: StringName
var target_serial: int
var stats: Dictionary = {}
var equipment_ids: Array[StringName] = []
var trait_ids: Array[StringName] = []
var status_ids: Array[StringName] = []


func deep_clone() -> CombatUnitInspectionSnapshot:
	var clone := CombatUnitInspectionSnapshot.new()
	clone.unit_serial = unit_serial
	clone.source_id = source_id
	clone.side_id = side_id
	clone.target_serial = target_serial
	clone.stats = stats.duplicate(true)
	clone.equipment_ids.assign(equipment_ids)
	clone.trait_ids.assign(trait_ids)
	clone.status_ids.assign(status_ids)
	return clone

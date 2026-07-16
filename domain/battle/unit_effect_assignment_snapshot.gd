class_name UnitEffectAssignmentSnapshot
extends RefCounted

var priority: int
var source_stable_id: StringName
var effect_index: int
var effect_id: StringName

func deep_clone() -> UnitEffectAssignmentSnapshot:
	var copied := UnitEffectAssignmentSnapshot.new()
	copied.priority = priority
	copied.source_stable_id = source_stable_id
	copied.effect_index = effect_index
	copied.effect_id = effect_id
	return copied

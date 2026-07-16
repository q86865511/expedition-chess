class_name BossPhaseSnapshot
extends RefCounted

var phase_index: int = 0
var hp_threshold_bps: int = 0
var source_instance_id: StringName = &""
var effect_ids: Array[StringName] = []

func deep_clone() -> BossPhaseSnapshot:
	var copied := BossPhaseSnapshot.new()
	copied.phase_index = phase_index
	copied.hp_threshold_bps = hp_threshold_bps
	copied.source_instance_id = source_instance_id
	copied.effect_ids = effect_ids.duplicate()
	return copied

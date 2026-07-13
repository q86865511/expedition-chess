class_name BossPhaseSnapshot
extends RefCounted

var phase_index: int = 0
var hp_threshold_bps: int = 0
var effect_ids: Array[StringName] = []

func deep_clone() -> BossPhaseSnapshot:
	var copied := BossPhaseSnapshot.new()
	copied.phase_index = phase_index
	copied.hp_threshold_bps = hp_threshold_bps
	copied.effect_ids = effect_ids.duplicate()
	return copied

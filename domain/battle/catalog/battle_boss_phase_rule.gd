class_name BattleBossPhaseRule
extends RefCounted

var phase_index: int
var hp_threshold_bps: int
var source_spawn_key: String
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleBossPhaseRule:
	var copied := BattleBossPhaseRule.new()
	copied.phase_index = phase_index
	copied.hp_threshold_bps = hp_threshold_bps
	copied.source_spawn_key = source_spawn_key
	copied.effect_ids = effect_ids.duplicate()
	return copied

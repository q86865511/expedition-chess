class_name BossPhaseEventPayload
extends BattleEventPayload

var phase_index: int = 0
var hp_threshold_bps: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := BossPhaseEventPayload.new()
	copied.phase_index = phase_index
	copied.hp_threshold_bps = hp_threshold_bps
	return copied

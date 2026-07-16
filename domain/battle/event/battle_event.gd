class_name BattleEvent
extends RefCounted

const CODEC_VERSION: int = 1
const TYPES: Array[StringName] = [
	&"spawn", &"move", &"attack", &"cast", &"damage", &"heal", &"shield",
	&"mana", &"modifier", &"status", &"death", &"boss_phase", &"summon_failure",
	&"battle_finished",
]

var event_codec_version: int = CODEC_VERSION
var tick: int = 0
var sequence: int = 0
var type: StringName = &""
var source_instance_id: OptionalStringNameValue = null
var target_instance_ids: Array[StringName] = []
var payload: BattleEventPayload = null

func deep_clone() -> BattleEvent:
	var copied := BattleEvent.new()
	copied.event_codec_version = event_codec_version
	copied.tick = tick
	copied.sequence = sequence
	copied.type = type
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.target_instance_ids = target_instance_ids.duplicate()
	copied.payload = payload.deep_clone() if payload != null else null
	return copied

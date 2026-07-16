class_name BossSourceMigrationEntryV1
extends RefCounted

var encounter_id: StringName
var phase_index: int
var source_spawn_key: String

func _init(p_encounter_id: StringName, p_phase_index: int, p_source_spawn_key: String) -> void:
	encounter_id = p_encounter_id
	phase_index = p_phase_index
	source_spawn_key = p_source_spawn_key

func deep_clone() -> BossSourceMigrationEntryV1:
	return BossSourceMigrationEntryV1.new(encounter_id, phase_index, source_spawn_key)

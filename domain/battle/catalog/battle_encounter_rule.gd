class_name BattleEncounterRule
extends RefCounted

var encounter_id: StringName
var encounter_kind: StringName
var preview_schema_version: int
var enemy_spawns: Array[BattleEnemySpawnRule] = []
var affix_ids: Array[StringName] = []
var boss_phases: Array[BattleBossPhaseRule] = []

func deep_clone() -> BattleEncounterRule:
	var copied := BattleEncounterRule.new()
	copied.encounter_id = encounter_id
	copied.encounter_kind = encounter_kind
	copied.preview_schema_version = preview_schema_version
	for spawn: BattleEnemySpawnRule in enemy_spawns:
		copied.enemy_spawns.append(spawn.deep_clone())
	copied.affix_ids = affix_ids.duplicate()
	for phase: BattleBossPhaseRule in boss_phases:
		copied.boss_phases.append(phase.deep_clone())
	return copied

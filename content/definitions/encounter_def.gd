class_name EncounterDef
extends ContentDefinition

@export var encounter_kind: StringName
@export var preview_schema_version: int = 1
@export var enemy_spawns: Array[EnemySpawnDef] = []
@export var affix_refs: Array[StringName] = []
@export var boss_phases: Array[BossPhaseDef] = []

func category_name() -> StringName:
	return &"encounter"

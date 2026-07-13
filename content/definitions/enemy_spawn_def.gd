class_name EnemySpawnDef
extends Resource

@export var side: StringName = &"enemy"
@export var logical_y: int
@export var logical_x: int
@export var spawn_key: String
@export var unit_ref: StringName
@export_range(1, 3) var star: int = 1
@export var effect_refs: Array[StringName] = []

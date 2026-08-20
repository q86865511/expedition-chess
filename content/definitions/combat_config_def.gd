class_name CombatConfigDef
extends ContentDefinition

@export var simulation_version: int = 1
@export var tick_rate: int = 20
@export var board_width: int = 8
@export var board_height: int = 8
@export var soft_limit_ticks: int = 1200
@export var hard_limit_ticks: int = 1800
@export var progress_scale: int = 1000
@export var resistance_base: int = 100
@export var basis_points: int = 10000
@export var overtime_interval_ticks: int = 20
@export var main_actions_per_tick: int = 1
@export var attack_mana_gain: int = 10
@export var damage_mana_factor: int = 10
@export var damage_mana_min: int = 1
@export var damage_mana_max: int = 10
@export var overtime_step_bps: int = 200
@export var overtime_cap_bps: int = 2000
@export var act1_base_damage: int = 6
@export var act2_base_damage: int = 10
@export var act3_base_damage: int = 14
@export var survivor_damage: int = 2
@export var boss_damage: int = 10
@export var effect_resolution_budget: int = 4096
@export var operation_budget: int = 8192
@export var event_budget: int = 16384
@export var entity_budget: int = 64
## spec §5.13／REQ-ENEMY-003:每一幕的敵方成長乘數(基點),只作用於
## health/attack/armor/magic_resist。act1 恆等 10000 是固定規則,act2／act3 為 TUNE。
@export var act1_enemy_stat_bps: int = 10000
@export var act2_enemy_stat_bps: int = 14000
@export var act3_enemy_stat_bps: int = 16000

func category_name() -> StringName:
	return &"combat_config"

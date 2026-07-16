class_name BattleCombatConfigRule
extends RefCounted

var config_id: StringName
var simulation_version: int
var tick_rate: int
var board_width: int
var board_height: int
var soft_limit_ticks: int
var hard_limit_ticks: int
var progress_scale: int
var resistance_base: int
var basis_points: int
var overtime_interval_ticks: int
var main_actions_per_tick: int
var attack_mana_gain: int
var damage_mana_factor: int
var damage_mana_min: int
var damage_mana_max: int
var overtime_step_bps: int
var overtime_cap_bps: int
var act1_base_damage: int
var act2_base_damage: int
var act3_base_damage: int
var survivor_damage: int
var boss_damage: int
var effect_resolution_budget: int
var operation_budget: int
var event_budget: int
var entity_budget: int

func deep_clone() -> BattleCombatConfigRule:
	var copied := BattleCombatConfigRule.new()
	for property: StringName in _integer_properties():
		copied.set(property, get(property))
	copied.config_id = config_id
	return copied

static func _integer_properties() -> Array[StringName]:
	return [
		&"simulation_version", &"tick_rate", &"board_width", &"board_height",
		&"soft_limit_ticks", &"hard_limit_ticks", &"progress_scale", &"resistance_base",
		&"basis_points", &"overtime_interval_ticks", &"main_actions_per_tick",
		&"attack_mana_gain", &"damage_mana_factor", &"damage_mana_min", &"damage_mana_max",
		&"overtime_step_bps", &"overtime_cap_bps", &"act1_base_damage", &"act2_base_damage",
		&"act3_base_damage", &"survivor_damage", &"boss_damage", &"effect_resolution_budget",
		&"operation_budget", &"event_budget", &"entity_budget",
	]

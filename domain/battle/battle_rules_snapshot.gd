class_name BattleRulesSnapshot
extends RefCounted

var simulation_version: int = 1
var event_codec_version: int = 1
var result_codec_version: int = 1
var combat_config_id: StringName = &"config.combat_default"
var tick_rate: int = 20
var board_width: int = 8
var board_height: int = 8
var soft_limit_ticks: int = 1200
var hard_limit_ticks: int = 1800
var progress_scale: int = 1000
var resistance_base: int = 100
var basis_points: int = 10000
var overtime_interval_ticks: int = 20
var main_actions_per_tick: int = 1
var attack_mana_gain: int = 10
var damage_mana_factor: int = 10
var damage_mana_min: int = 1
var damage_mana_max: int = 10
var overtime_step_bps: int = 200
var overtime_cap_bps: int = 2000
var act1_base_damage: int = 6
var act2_base_damage: int = 10
var act3_base_damage: int = 14
var survivor_damage: int = 2
var boss_damage: int = 10
var effect_resolution_budget: int = 4096
var operation_budget: int = 8192
var event_budget: int = 16384
var entity_budget: int = 64
var act1_enemy_stat_bps: int = 10000
var act2_enemy_stat_bps: int = 13000
var act3_enemy_stat_bps: int = 16000
var act_index: int = 1
var encounter_kind: StringName = &"normal"
var ability_rules: Array[BattleAbilityRuleSnapshot] = []
var effect_rules: Array[BattleEffectRuleSnapshot] = []
var summoned_unit_templates: Array[SummonedUnitRuleSnapshot] = []

func deep_clone() -> BattleRulesSnapshot:
	var copied := BattleRulesSnapshot.new()
	copied.simulation_version = simulation_version
	copied.event_codec_version = event_codec_version
	copied.result_codec_version = result_codec_version
	copied.combat_config_id = combat_config_id
	copied.tick_rate = tick_rate
	copied.board_width = board_width
	copied.board_height = board_height
	copied.soft_limit_ticks = soft_limit_ticks
	copied.hard_limit_ticks = hard_limit_ticks
	copied.progress_scale = progress_scale
	copied.resistance_base = resistance_base
	copied.basis_points = basis_points
	copied.overtime_interval_ticks = overtime_interval_ticks
	copied.main_actions_per_tick = main_actions_per_tick
	copied.attack_mana_gain = attack_mana_gain
	copied.damage_mana_factor = damage_mana_factor
	copied.damage_mana_min = damage_mana_min
	copied.damage_mana_max = damage_mana_max
	copied.overtime_step_bps = overtime_step_bps
	copied.overtime_cap_bps = overtime_cap_bps
	copied.act1_base_damage = act1_base_damage
	copied.act2_base_damage = act2_base_damage
	copied.act3_base_damage = act3_base_damage
	copied.survivor_damage = survivor_damage
	copied.boss_damage = boss_damage
	copied.effect_resolution_budget = effect_resolution_budget
	copied.operation_budget = operation_budget
	copied.event_budget = event_budget
	copied.entity_budget = entity_budget
	copied.act1_enemy_stat_bps = act1_enemy_stat_bps
	copied.act2_enemy_stat_bps = act2_enemy_stat_bps
	copied.act3_enemy_stat_bps = act3_enemy_stat_bps
	copied.act_index = act_index
	copied.encounter_kind = encounter_kind
	for rule: BattleAbilityRuleSnapshot in ability_rules:
		copied.ability_rules.append(rule.deep_clone())
	for rule: BattleEffectRuleSnapshot in effect_rules:
		copied.effect_rules.append(rule.deep_clone())
	for template: SummonedUnitRuleSnapshot in summoned_unit_templates:
		copied.summoned_unit_templates.append(template.deep_clone())
	return copied

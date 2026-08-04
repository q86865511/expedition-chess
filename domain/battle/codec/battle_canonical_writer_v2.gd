class_name BattleCanonicalWriterV2
extends BattleCanonicalWriter

func _write_unit(value: UnitBattleSnapshot) -> String:
	var ability := "null" if value.ability_id == null else _quote(String(value.ability_id.value))
	var fields: Array[String] = [
		_field("instance_id", _quote(String(value.instance_id))),
		_field("unit_id", _quote(String(value.unit_id))),
		_field("side", _quote(String(value.side))),
		_field("logical_y", str(value.logical_y)),
		_field("logical_x", str(value.logical_x)),
		_field("star", str(value.star)),
		_field("health", str(value.health)),
		_field("attack", str(value.attack)),
		_field("armor", str(value.armor)),
		_field("magic_resist", str(value.magic_resist)),
		_field("attack_speed_milli", str(value.attack_speed_milli)),
		_field("attack_range_cells", str(value.attack_range_cells)),
		_field("start_mana", str(value.start_mana)),
		_field("max_mana", str(value.max_mana)),
		_field("move_speed_milli", str(value.move_speed_milli)),
		_field("basic_attack_profile", _quote(String(value.basic_attack_profile))),
		_field("ability_id", ability),
		_field("effect_ids", _write_ids(value.effect_ids)),
		_field("effect_assignments", _write_effects(value.effect_assignments)),
	]
	return "{" + ",".join(fields) + "}"

func _write_traits(values: Array[TraitBattleSnapshot]) -> String:
	var items: Array[String] = []
	for value: TraitBattleSnapshot in values:
		items.append("{" + ",".join([
			_field("trait_id", _quote(String(value.trait_id))),
			_field("tier", str(value.tier)),
			_field("member_instance_ids", _write_ids(value.member_instance_ids)),
			_field("effect_assignments", _write_effects(value.effect_assignments)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_effect(value: BattleEffectSnapshot) -> String:
	var source_instance := "null" if value.source_instance_id == null else _quote(String(value.source_instance_id.value))
	var fields: Array[String] = [
		_field("priority", str(value.priority)),
		_field("source_category", _quote(String(value.source_category))),
		_field("source_side", _quote(String(value.source_side))),
		_field("source_stable_id", _quote(String(value.source_stable_id))),
		_field("source_instance_id", source_instance),
		_field("source_slot", str(value.source_slot)),
		_field("effect_index", str(value.effect_index)),
		_field("effect_id", _quote(String(value.effect_id))),
		_field("target_ids", _write_ids(value.target_ids)),
		_field("integer_params", _write_int_params(value.integer_params)),
		_field("id_params", _write_id_params(value.id_params)),
	]
	return "{" + ",".join(fields) + "}"

func _write_phases(values: Array[BossPhaseSnapshot]) -> String:
	var items: Array[String] = []
	for value: BossPhaseSnapshot in values:
		items.append("{" + ",".join([
			_field("phase_index", str(value.phase_index)),
			_field("hp_threshold_bps", str(value.hp_threshold_bps)),
			_field("source_instance_id", _quote(String(value.source_instance_id))),
			_field("effect_ids", _write_ids(value.effect_ids)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_rules(value: BattleRulesSnapshot) -> String:
	var fields: Array[String] = [
		_field("simulation_version", str(value.simulation_version)),
		_field("event_codec_version", str(value.event_codec_version)),
		_field("result_codec_version", str(value.result_codec_version)),
		_field("combat_config_id", _quote(String(value.combat_config_id))),
		_field("tick_rate", str(value.tick_rate)),
		_field("board_width", str(value.board_width)),
		_field("board_height", str(value.board_height)),
		_field("soft_limit_ticks", str(value.soft_limit_ticks)),
		_field("hard_limit_ticks", str(value.hard_limit_ticks)),
		_field("progress_scale", str(value.progress_scale)),
		_field("resistance_base", str(value.resistance_base)),
		_field("basis_points", str(value.basis_points)),
		_field("overtime_interval_ticks", str(value.overtime_interval_ticks)),
		_field("main_actions_per_tick", str(value.main_actions_per_tick)),
		_field("attack_mana_gain", str(value.attack_mana_gain)),
		_field("damage_mana_factor", str(value.damage_mana_factor)),
		_field("damage_mana_min", str(value.damage_mana_min)),
		_field("damage_mana_max", str(value.damage_mana_max)),
		_field("overtime_step_bps", str(value.overtime_step_bps)),
		_field("overtime_cap_bps", str(value.overtime_cap_bps)),
		_field("act1_base_damage", str(value.act1_base_damage)),
		_field("act2_base_damage", str(value.act2_base_damage)),
		_field("act3_base_damage", str(value.act3_base_damage)),
		_field("survivor_damage", str(value.survivor_damage)),
		_field("boss_damage", str(value.boss_damage)),
		_field("effect_resolution_budget", str(value.effect_resolution_budget)),
		_field("operation_budget", str(value.operation_budget)),
		_field("event_budget", str(value.event_budget)),
		_field("entity_budget", str(value.entity_budget)),
		_field("act1_enemy_stat_bps", str(value.act1_enemy_stat_bps)),
		_field("act2_enemy_stat_bps", str(value.act2_enemy_stat_bps)),
		_field("act3_enemy_stat_bps", str(value.act3_enemy_stat_bps)),
		_field("act_index", str(value.act_index)),
		_field("encounter_kind", _quote(String(value.encounter_kind))),
		_field("ability_rules", _write_ability_rules(value.ability_rules)),
		_field("effect_rules", _write_effect_rules(value.effect_rules)),
		_field("summoned_unit_templates", _write_summoned_templates(value.summoned_unit_templates)),
	]
	return "{" + ",".join(fields) + "}"

func _write_ability_rules(values: Array[BattleAbilityRuleSnapshot]) -> String:
	var items: Array[String] = []
	for value: BattleAbilityRuleSnapshot in values:
		items.append("{" + ",".join([
			_field("ability_id", _quote(String(value.ability_id))),
			_field("target_rule", _quote(String(value.target_rule))),
			_field("cast_ticks", str(value.cast_ticks)),
			_field("effect_ids", _write_ids(value.effect_ids)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_effect_rules(values: Array[BattleEffectRuleSnapshot]) -> String:
	var items: Array[String] = []
	for value: BattleEffectRuleSnapshot in values:
		items.append("{" + ",".join([
			_field("effect_id", _quote(String(value.effect_id))),
			_field("trigger", _quote(String(value.trigger))),
			_field("periodic_interval_ticks", str(value.periodic_interval_ticks)),
			_field("conditions", _write_conditions(value.conditions)),
			_field("battle_operations", _write_battle_operations(value.battle_operations)),
			_field("run_operations", _write_run_operations(value.run_operations)),
			_field("stacking", _quote(String(value.stacking))),
			_field("max_stacks", str(value.max_stacks)),
			_field("duration_ticks", str(value.duration_ticks)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_conditions(values: Array[BattleConditionRule]) -> String:
	var items: Array[String] = []
	for value: BattleConditionRule in values:
		items.append("{" + ",".join([
			_field("kind", _quote(String(value.kind))),
			_field("subject", _quote(String(value.subject))),
			_field("comparator", _quote(String(value.comparator))),
			_field("int_value", str(value.int_value.value) if value.int_value != null else "null"),
			_field("stable_id_value", _quote(String(value.stable_id_value.value)) if value.stable_id_value != null else "null"),
			_field("max_uses_per_battle", str(value.max_uses_per_battle.value) if value.max_uses_per_battle != null else "null"),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_battle_operations(values: Array[BattleOperationRule]) -> String:
	var items: Array[String] = []
	for value: BattleOperationRule in values:
		var fields: Array[String] = [
			_field("operation_index", str(value.operation_index)),
			_field("kind", _quote(String(value.kind))),
		]
		match value.kind:
			&"damage": fields.append_array([
				_field("base", str(value.base_amount)), _field("scaling", _quote(String(value.scaling))),
				_field("damage_type", _quote(String(value.damage_type))), _field("target", _quote(String(value.target)))])
			&"heal": fields.append_array([
				_field("base", str(value.base_amount)), _field("scaling", _quote(String(value.scaling))),
				_field("target", _quote(String(value.target)))])
			&"shield": fields.append_array([
				_field("amount", str(value.amount)), _field("duration_ticks", str(value.duration_ticks)),
				_field("target", _quote(String(value.target)))])
			&"modify_stat": fields.append_array([
				_field("stat", _quote(String(value.stat))), _field("mode", _quote(String(value.mode))),
				_field("amount", str(value.amount)), _field("duration_ticks", str(value.duration_ticks)),
				_field("target", _quote(String(value.target)))])
			&"apply_status": fields.append_array([
				_field("status_id", _quote(String(value.status_id.value))), _field("stacks", str(value.stacks)),
				_field("duration_ticks", str(value.duration_ticks)), _field("target", _quote(String(value.target)))])
			&"remove_status": fields.append_array([
				_field("status_id", _quote(String(value.status_id.value))), _field("target", _quote(String(value.target)))])
			&"move": fields.append_array([
				_field("direction", _quote(String(value.direction))), _field("cells", str(value.cells))])
			&"summon": fields.append_array([
				_field("unit_id", _quote(String(value.unit_id.value))), _field("count", str(value.count)),
				_field("max_active_per_source", str(value.max_active_per_source)),
				_field("placement_rule", _quote(String(value.placement_rule)))])
			&"grant_mana": fields.append_array([
				_field("amount", str(value.amount)), _field("target", _quote(String(value.target)))])
		items.append("{" + ",".join(fields) + "}")
	return "[" + ",".join(items) + "]"

func _write_run_operations(values: Array[BattleRunOperationRule]) -> String:
	var items: Array[String] = []
	for value: BattleRunOperationRule in values:
		items.append("{" + ",".join([
			_field("operation_index", str(value.operation_index)),
			_field("kind", _quote(String(value.kind))),
			_field("amount", str(value.amount)),
			_field("claim_scope", _quote(String(value.claim_scope))),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_summoned_templates(values: Array[SummonedUnitRuleSnapshot]) -> String:
	var items: Array[String] = []
	for value: SummonedUnitRuleSnapshot in values:
		var ability := "null" if value.ability_id == null else _quote(String(value.ability_id.value))
		items.append("{" + ",".join([
			_field("unit_id", _quote(String(value.unit_id))), _field("star", str(value.star)),
			_field("trait_ids", _write_ids(value.trait_ids)), _field("health", str(value.health)),
			_field("attack", str(value.attack)), _field("armor", str(value.armor)),
			_field("magic_resist", str(value.magic_resist)), _field("attack_speed_milli", str(value.attack_speed_milli)),
			_field("attack_range_cells", str(value.attack_range_cells)), _field("start_mana", str(value.start_mana)),
			_field("max_mana", str(value.max_mana)), _field("move_speed_milli", str(value.move_speed_milli)),
			_field("ability_id", ability), _field("ai_profile", _quote(String(value.ai_profile))),
			_field("basic_attack_profile", _quote(String(value.basic_attack_profile))),
			_field("unit_effect_assignments", _write_assignments(value.unit_effect_assignments)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _write_assignments(values: Array[UnitEffectAssignmentSnapshot]) -> String:
	var items: Array[String] = []
	for value: UnitEffectAssignmentSnapshot in values:
		items.append("{" + ",".join([
			_field("priority", str(value.priority)),
			_field("source_stable_id", _quote(String(value.source_stable_id))),
			_field("effect_index", str(value.effect_index)),
			_field("effect_id", _quote(String(value.effect_id))),
		]) + "}")
	return "[" + ",".join(items) + "]"

class_name BattleCanonicalWriter
extends RefCounted

func write(inputs: BattleSetupInputs) -> PackedByteArray:
	return _write_inputs(inputs).to_utf8_buffer()

func _write_inputs(value: BattleSetupInputs) -> String:
	var fields: Array[String] = [
		_field("setup_schema_version", str(value.setup_schema_version)),
		_field("content_version", _quote(value.content_version)),
		_field("manifest_digest", _quote(String(value.manifest_digest))),
		_field("encounter_snapshot", _write_encounter(value.encounter_snapshot)),
		_field("player_units", _write_units(value.player_units)),
		_field("player_active_traits", _write_traits(value.player_active_traits)),
		_field("player_equipment_effects", _write_effects(value.player_equipment_effects)),
		_field("player_relic_effects", _write_effects(value.player_relic_effects)),
		_field("commander_effects", _write_effects(value.commander_effects)),
		_field("challenge_modifiers", _write_effects(value.challenge_modifiers)),
		_field("battle_rules", _write_rules(value.battle_rules)),
	]
	return "{" + ",".join(fields) + "}"

func _write_encounter(value: EncounterPreviewSnapshot) -> String:
	var fields: Array[String] = [
		_field("preview_schema_version", str(value.preview_schema_version)),
		_field("encounter_id", _quote(String(value.encounter_id))),
		_field("manifest_digest", _quote(String(value.manifest_digest))),
		_field("enemy_units", _write_units(value.enemy_units)),
		_field("active_traits", _write_traits(value.active_traits)),
		_field("affix_effects", _write_effects(value.affix_effects)),
		_field("boss_phases", _write_phases(value.boss_phases)),
	]
	return "{" + ",".join(fields) + "}"

func _write_units(values: Array[UnitBattleSnapshot]) -> String:
	var items: Array[String] = []
	for value: UnitBattleSnapshot in values:
		items.append(_write_unit(value))
	return "[" + ",".join(items) + "]"

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
		_field("ability_id", ability),
		_field("effect_ids", _write_ids(value.effect_ids)),
	]
	return "{" + ",".join(fields) + "}"

func _write_traits(values: Array[TraitBattleSnapshot]) -> String:
	var items: Array[String] = []
	for value: TraitBattleSnapshot in values:
		var fields: Array[String] = [
			_field("trait_id", _quote(String(value.trait_id))),
			_field("tier", str(value.tier)),
			_field("member_instance_ids", _write_ids(value.member_instance_ids)),
		]
		items.append("{" + ",".join(fields) + "}")
	return "[" + ",".join(items) + "]"

func _write_effects(values: Array[BattleEffectSnapshot]) -> String:
	var items: Array[String] = []
	for value: BattleEffectSnapshot in values:
		items.append(_write_effect(value))
	return "[" + ",".join(items) + "]"

func _write_effect(value: BattleEffectSnapshot) -> String:
	var source_instance := "null" if value.source_instance_id == null else _quote(String(value.source_instance_id.value))
	var fields: Array[String] = [
		_field("priority", str(value.priority)),
		_field("source_stable_id", _quote(String(value.source_stable_id))),
		_field("source_instance_id", source_instance),
		_field("effect_index", str(value.effect_index)),
		_field("effect_id", _quote(String(value.effect_id))),
		_field("target_ids", _write_ids(value.target_ids)),
		_field("integer_params", _write_int_params(value.integer_params)),
		_field("id_params", _write_id_params(value.id_params)),
	]
	return "{" + ",".join(fields) + "}"

func _write_int_params(values: Array[BattleIntParam]) -> String:
	var items: Array[String] = []
	for value: BattleIntParam in values:
		items.append("{" + _field("key", _quote(String(value.key))) + "," + _field("value", str(value.value)) + "}")
	return "[" + ",".join(items) + "]"

func _write_id_params(values: Array[BattleIdParam]) -> String:
	var items: Array[String] = []
	for value: BattleIdParam in values:
		items.append("{" + _field("key", _quote(String(value.key))) + "," + _field("value", _quote(String(value.value))) + "}")
	return "[" + ",".join(items) + "]"

func _write_phases(values: Array[BossPhaseSnapshot]) -> String:
	var items: Array[String] = []
	for value: BossPhaseSnapshot in values:
		var fields: Array[String] = [
			_field("phase_index", str(value.phase_index)),
			_field("hp_threshold_bps", str(value.hp_threshold_bps)),
			_field("effect_ids", _write_ids(value.effect_ids)),
		]
		items.append("{" + ",".join(fields) + "}")
	return "[" + ",".join(items) + "]"

func _write_rules(value: BattleRulesSnapshot) -> String:
	var fields: Array[String] = [
		_field("tick_rate", str(value.tick_rate)),
		_field("board_width", str(value.board_width)),
		_field("board_height", str(value.board_height)),
		_field("soft_limit_ticks", str(value.soft_limit_ticks)),
		_field("hard_limit_ticks", str(value.hard_limit_ticks)),
	]
	return "{" + ",".join(fields) + "}"

func _write_ids(values: Array[StringName]) -> String:
	var items: Array[String] = []
	for value: StringName in values:
		items.append(_quote(String(value)))
	return "[" + ",".join(items) + "]"

func _field(key: String, encoded_value: String) -> String:
	return _quote(key) + ":" + encoded_value

func _quote(value: String) -> String:
	var output := "\""
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		match code:
			34: output += "\\\""
			92: output += "\\\\"
			8: output += "\\b"
			12: output += "\\f"
			10: output += "\\n"
			13: output += "\\r"
			9: output += "\\t"
			_:
				if code < 32:
					output += "\\u%04x" % code
				else:
					output += String.chr(code)
	return output + "\""

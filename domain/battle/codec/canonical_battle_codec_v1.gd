class_name CanonicalBattleCodecV1
extends RefCounted

const CODEC_INVALID: StringName = &"BATTLE_CODEC_INVALID"

func encode(inputs: BattleSetupInputs) -> BattleCodecResult:
	var validation := BattleSetupInputsValidator.new().validate(inputs)
	if not validation.ok:
		return BattleCodecResult.failure(validation.error.code, validation.error.field_path)
	return BattleCodecResult.encoded(BattleCanonicalWriter.new().write(inputs))

func decode(bytes: PackedByteArray) -> BattleCodecResult:
	if bytes.is_empty():
		return BattleCodecResult.failure(CODEC_INVALID, &"bytes")
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return BattleCodecResult.failure(CODEC_INVALID, &"bytes")
	var reader := BattleCanonicalReader.new(text)
	var inputs := _read_inputs(reader)
	if reader.failed() or not reader.at_end():
		return BattleCodecResult.failure(CODEC_INVALID, reader.error_path() if reader.failed() else &"trailing_bytes")
	var validation := BattleSetupInputsValidator.new().validate(inputs)
	if not validation.ok:
		return BattleCodecResult.failure(CODEC_INVALID, validation.error.field_path)
	var canonical := BattleCanonicalWriter.new().write(inputs)
	if canonical != bytes:
		return BattleCodecResult.failure(CODEC_INVALID, &"canonical_bytes")
	return BattleCodecResult.decoded(inputs)

func _read_inputs(reader: BattleCanonicalReader) -> BattleSetupInputs:
	var value := BattleSetupInputs.new()
	reader.begin_object(&"inputs")
	reader.read_key("setup_schema_version", true, &"setup_schema_version")
	value.setup_schema_version = reader.read_int(&"setup_schema_version")
	reader.read_key("content_version", false, &"content_version")
	value.content_version = reader.read_string(&"content_version")
	reader.read_key("manifest_digest", false, &"manifest_digest")
	value.manifest_digest = StringName(reader.read_string(&"manifest_digest"))
	reader.read_key("encounter_snapshot", false, &"encounter_snapshot")
	value.encounter_snapshot = _read_encounter(reader)
	reader.read_key("player_units", false, &"player_units")
	value.player_units = _read_units(reader, &"player_units")
	reader.read_key("player_active_traits", false, &"player_active_traits")
	value.player_active_traits = _read_traits(reader, &"player_active_traits")
	reader.read_key("player_equipment_effects", false, &"player_equipment_effects")
	value.player_equipment_effects = _read_effects(reader, &"player_equipment_effects")
	reader.read_key("player_relic_effects", false, &"player_relic_effects")
	value.player_relic_effects = _read_effects(reader, &"player_relic_effects")
	reader.read_key("commander_effects", false, &"commander_effects")
	value.commander_effects = _read_effects(reader, &"commander_effects")
	reader.read_key("challenge_modifiers", false, &"challenge_modifiers")
	value.challenge_modifiers = _read_effects(reader, &"challenge_modifiers")
	reader.read_key("battle_rules", false, &"battle_rules")
	value.battle_rules = _read_rules(reader)
	reader.end_object(&"inputs")
	return value

func _read_encounter(reader: BattleCanonicalReader) -> EncounterPreviewSnapshot:
	var value := EncounterPreviewSnapshot.new()
	reader.begin_object(&"encounter_snapshot")
	reader.read_key("preview_schema_version", true, &"encounter_snapshot.preview_schema_version")
	value.preview_schema_version = reader.read_int(&"encounter_snapshot.preview_schema_version")
	reader.read_key("encounter_id", false, &"encounter_snapshot.encounter_id")
	value.encounter_id = StringName(reader.read_string(&"encounter_snapshot.encounter_id"))
	reader.read_key("manifest_digest", false, &"encounter_snapshot.manifest_digest")
	value.manifest_digest = StringName(reader.read_string(&"encounter_snapshot.manifest_digest"))
	reader.read_key("enemy_units", false, &"encounter_snapshot.enemy_units")
	value.enemy_units = _read_units(reader, &"encounter_snapshot.enemy_units")
	reader.read_key("active_traits", false, &"encounter_snapshot.active_traits")
	value.active_traits = _read_traits(reader, &"encounter_snapshot.active_traits")
	reader.read_key("affix_effects", false, &"encounter_snapshot.affix_effects")
	value.affix_effects = _read_effects(reader, &"encounter_snapshot.affix_effects")
	reader.read_key("boss_phases", false, &"encounter_snapshot.boss_phases")
	value.boss_phases = _read_phases(reader, &"encounter_snapshot.boss_phases")
	reader.end_object(&"encounter_snapshot")
	return value

func _read_units(reader: BattleCanonicalReader, path: StringName) -> Array[UnitBattleSnapshot]:
	var values: Array[UnitBattleSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		values.append(_read_unit(reader, StringName("%s.%d" % [path, values.size()])))
	return values

func _read_unit(reader: BattleCanonicalReader, path: StringName) -> UnitBattleSnapshot:
	var value := UnitBattleSnapshot.new()
	reader.begin_object(path)
	reader.read_key("instance_id", true, path)
	value.instance_id = StringName(reader.read_string(StringName("%s.instance_id" % path)))
	reader.read_key("unit_id", false, path)
	value.unit_id = StringName(reader.read_string(StringName("%s.unit_id" % path)))
	reader.read_key("side", false, path)
	value.side = StringName(reader.read_string(StringName("%s.side" % path)))
	reader.read_key("logical_y", false, path)
	value.logical_y = reader.read_int(StringName("%s.logical_y" % path))
	reader.read_key("logical_x", false, path)
	value.logical_x = reader.read_int(StringName("%s.logical_x" % path))
	reader.read_key("star", false, path)
	value.star = reader.read_int(StringName("%s.star" % path))
	reader.read_key("health", false, path)
	value.health = reader.read_int(StringName("%s.health" % path))
	reader.read_key("attack", false, path)
	value.attack = reader.read_int(StringName("%s.attack" % path))
	reader.read_key("armor", false, path)
	value.armor = reader.read_int(StringName("%s.armor" % path))
	reader.read_key("magic_resist", false, path)
	value.magic_resist = reader.read_int(StringName("%s.magic_resist" % path))
	reader.read_key("attack_speed_milli", false, path)
	value.attack_speed_milli = reader.read_int(StringName("%s.attack_speed_milli" % path))
	reader.read_key("attack_range_cells", false, path)
	value.attack_range_cells = reader.read_int(StringName("%s.attack_range_cells" % path))
	reader.read_key("start_mana", false, path)
	value.start_mana = reader.read_int(StringName("%s.start_mana" % path))
	reader.read_key("max_mana", false, path)
	value.max_mana = reader.read_int(StringName("%s.max_mana" % path))
	reader.read_key("move_speed_milli", false, path)
	value.move_speed_milli = reader.read_int(StringName("%s.move_speed_milli" % path))
	reader.read_key("ability_id", false, path)
	if reader.next_is_null():
		reader.read_null(StringName("%s.ability_id" % path))
	else:
		value.ability_id = OptionalStringNameValue.of(StringName(reader.read_string(StringName("%s.ability_id" % path))))
	reader.read_key("effect_ids", false, path)
	value.effect_ids = _read_ids(reader, StringName("%s.effect_ids" % path))
	reader.end_object(path)
	return value

func _read_traits(reader: BattleCanonicalReader, path: StringName) -> Array[TraitBattleSnapshot]:
	var values: Array[TraitBattleSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := TraitBattleSnapshot.new()
		var item_path := StringName("%s.%d" % [path, values.size()])
		reader.begin_object(item_path)
		reader.read_key("trait_id", true, item_path)
		value.trait_id = StringName(reader.read_string(StringName("%s.trait_id" % item_path)))
		reader.read_key("tier", false, item_path)
		value.tier = reader.read_int(StringName("%s.tier" % item_path))
		reader.read_key("member_instance_ids", false, item_path)
		value.member_instance_ids = _read_ids(reader, StringName("%s.member_instance_ids" % item_path))
		reader.end_object(item_path)
		values.append(value)
	return values

func _read_effects(reader: BattleCanonicalReader, path: StringName) -> Array[BattleEffectSnapshot]:
	var values: Array[BattleEffectSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		values.append(_read_effect(reader, StringName("%s.%d" % [path, values.size()])))
	return values

func _read_effect(reader: BattleCanonicalReader, path: StringName) -> BattleEffectSnapshot:
	var value := BattleEffectSnapshot.new()
	reader.begin_object(path)
	reader.read_key("priority", true, path)
	value.priority = reader.read_int(StringName("%s.priority" % path))
	reader.read_key("source_stable_id", false, path)
	value.source_stable_id = StringName(reader.read_string(StringName("%s.source_stable_id" % path)))
	reader.read_key("source_instance_id", false, path)
	if reader.next_is_null():
		reader.read_null(StringName("%s.source_instance_id" % path))
	else:
		value.source_instance_id = OptionalStringNameValue.of(StringName(reader.read_string(StringName("%s.source_instance_id" % path))))
	reader.read_key("effect_index", false, path)
	value.effect_index = reader.read_int(StringName("%s.effect_index" % path))
	reader.read_key("effect_id", false, path)
	value.effect_id = StringName(reader.read_string(StringName("%s.effect_id" % path)))
	reader.read_key("target_ids", false, path)
	value.target_ids = _read_ids(reader, StringName("%s.target_ids" % path))
	reader.read_key("integer_params", false, path)
	value.integer_params = _read_int_params(reader, StringName("%s.integer_params" % path))
	reader.read_key("id_params", false, path)
	value.id_params = _read_id_params(reader, StringName("%s.id_params" % path))
	reader.end_object(path)
	return value

func _read_int_params(reader: BattleCanonicalReader, path: StringName) -> Array[BattleIntParam]:
	var values: Array[BattleIntParam] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BattleIntParam.new()
		reader.begin_object(path)
		reader.read_key("key", true, path)
		value.key = StringName(reader.read_string(path))
		reader.read_key("value", false, path)
		value.value = reader.read_int(path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_id_params(reader: BattleCanonicalReader, path: StringName) -> Array[BattleIdParam]:
	var values: Array[BattleIdParam] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BattleIdParam.new()
		reader.begin_object(path)
		reader.read_key("key", true, path)
		value.key = StringName(reader.read_string(path))
		reader.read_key("value", false, path)
		value.value = StringName(reader.read_string(path))
		reader.end_object(path)
		values.append(value)
	return values

func _read_phases(reader: BattleCanonicalReader, path: StringName) -> Array[BossPhaseSnapshot]:
	var values: Array[BossPhaseSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BossPhaseSnapshot.new()
		reader.begin_object(path)
		reader.read_key("phase_index", true, path)
		value.phase_index = reader.read_int(path)
		reader.read_key("hp_threshold_bps", false, path)
		value.hp_threshold_bps = reader.read_int(path)
		reader.read_key("effect_ids", false, path)
		value.effect_ids = _read_ids(reader, path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_rules(reader: BattleCanonicalReader) -> BattleRulesSnapshot:
	var value := BattleRulesSnapshot.new()
	reader.begin_object(&"battle_rules")
	reader.read_key("tick_rate", true, &"battle_rules.tick_rate")
	value.tick_rate = reader.read_int(&"battle_rules.tick_rate")
	reader.read_key("board_width", false, &"battle_rules.board_width")
	value.board_width = reader.read_int(&"battle_rules.board_width")
	reader.read_key("board_height", false, &"battle_rules.board_height")
	value.board_height = reader.read_int(&"battle_rules.board_height")
	reader.read_key("soft_limit_ticks", false, &"battle_rules.soft_limit_ticks")
	value.soft_limit_ticks = reader.read_int(&"battle_rules.soft_limit_ticks")
	reader.read_key("hard_limit_ticks", false, &"battle_rules.hard_limit_ticks")
	value.hard_limit_ticks = reader.read_int(&"battle_rules.hard_limit_ticks")
	reader.end_object(&"battle_rules")
	return value

func _read_ids(reader: BattleCanonicalReader, path: StringName) -> Array[StringName]:
	var values: Array[StringName] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		values.append(StringName(reader.read_string(path)))
	return values

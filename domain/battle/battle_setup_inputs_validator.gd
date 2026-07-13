class_name BattleSetupInputsValidator
extends RefCounted

const INPUT_INVALID: StringName = &"BATTLE_INPUT_INVALID"
const PREVIEW_MISMATCH: StringName = &"BATTLE_PREVIEW_MISMATCH"

var _stable_ids := StableIdValidator.new()
static var _trusted_authority: BattleSetupValidationAuthority = \
	BattleSetupValidationAuthority.new()

func validate_for_build(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	var validation := validate(inputs)
	if not validation.ok:
		return validation
	var encoded := CanonicalBattleCodecV1.new().encode(inputs)
	if not encoded.ok:
		return BattleInputValidationResult.failure(
			encoded.error.code,
			encoded.error.field_path
		)
	var digest := _sha256_hex(encoded.canonical_bytes)
	if digest.is_empty():
		return BattleInputValidationResult.failure(INPUT_INVALID, &"sha256")
	var receipt := _trusted_authority._issue_validated(StringName(digest))
	if receipt == null:
		return BattleInputValidationResult.failure(
			INPUT_INVALID,
			&"validation_receipt"
		)
	return BattleInputValidationResult.success(receipt)

static func _verifies_receipt(
	receipt: BattleSetupValidationReceipt,
	expected_digest: StringName
) -> bool:
	return _trusted_authority._verifies(receipt, expected_digest)

static func _sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func validate(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	if inputs == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"inputs")
	if inputs.setup_schema_version != 1:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"setup_schema_version")
	if inputs.content_version.is_empty() or not _ascii_nonempty(inputs.content_version):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"content_version")
	if not _digest(inputs.manifest_digest):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"manifest_digest")
	if inputs.encounter_snapshot == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot")
	var encounter_result := _validate_encounter(inputs.encounter_snapshot, inputs.manifest_digest)
	if not encounter_result.ok:
		return encounter_result
	var units_result := _validate_units(inputs.player_units, &"player_units", &"player")
	if not units_result.ok:
		return units_result
	var trait_result := _validate_traits(inputs.player_active_traits, &"player_active_traits")
	if not trait_result.ok:
		return trait_result
	var effect_result := _validate_effects(inputs.player_equipment_effects, &"player_equipment_effects")
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(inputs.player_relic_effects, &"player_relic_effects")
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(inputs.commander_effects, &"commander_effects")
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(inputs.challenge_modifiers, &"challenge_modifiers")
	if not effect_result.ok:
		return effect_result
	if inputs.battle_rules == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules")
	if inputs.battle_rules.tick_rate != 20 or inputs.battle_rules.board_width != 8 or inputs.battle_rules.board_height != 8:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules")
	if not _positive_i32(inputs.battle_rules.soft_limit_ticks) or not _positive_i32(inputs.battle_rules.hard_limit_ticks) or inputs.battle_rules.hard_limit_ticks <= inputs.battle_rules.soft_limit_ticks:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.hard_limit_ticks")
	var all_instances: Array[StringName] = []
	for unit: UnitBattleSnapshot in inputs.player_units:
		all_instances.append(unit.instance_id)
	for unit: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		if all_instances.has(unit.instance_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.enemy_units.instance_id")
		all_instances.append(unit.instance_id)
	return BattleInputValidationResult.success()

func _validate_encounter(preview: EncounterPreviewSnapshot, expected_digest: StringName) -> BattleInputValidationResult:
	if preview.preview_schema_version != 1:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.preview_schema_version")
	if not _stable_ids.is_valid(preview.encounter_id):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.encounter_id")
	if preview.manifest_digest != expected_digest:
		return BattleInputValidationResult.failure(PREVIEW_MISMATCH, &"encounter_snapshot.manifest_digest")
	var units_result := _validate_units(preview.enemy_units, &"encounter_snapshot.enemy_units", &"enemy")
	if not units_result.ok:
		return units_result
	var traits_result := _validate_traits(preview.active_traits, &"encounter_snapshot.active_traits")
	if not traits_result.ok:
		return traits_result
	var effects_result := _validate_effects(preview.affix_effects, &"encounter_snapshot.affix_effects")
	if not effects_result.ok:
		return effects_result
	var previous_phase := -1
	for index: int in range(preview.boss_phases.size()):
		var phase := preview.boss_phases[index]
		if phase == null or not _nonnegative_i32(phase.phase_index) or phase.phase_index <= previous_phase or phase.hp_threshold_bps < 0 or phase.hp_threshold_bps > 10000:
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("encounter_snapshot.boss_phases.%d" % index))
		if not _sorted_unique_ids(phase.effect_ids, true):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("encounter_snapshot.boss_phases.%d.effect_ids" % index))
		previous_phase = phase.phase_index
	return BattleInputValidationResult.success()

func _validate_units(units: Array[UnitBattleSnapshot], path: StringName, required_side: StringName) -> BattleInputValidationResult:
	var previous: UnitBattleSnapshot = null
	var seen: Array[StringName] = []
	for index: int in range(units.size()):
		var unit := units[index]
		var item_path := StringName("%s.%d" % [path, index])
		if unit == null or unit.side != required_side:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _ascii_nonempty(String(unit.instance_id)) or seen.has(unit.instance_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.instance_id" % item_path))
		if not _stable_ids.is_valid(unit.unit_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.unit_id" % item_path))
		if unit.logical_x < 0 or unit.logical_x > 7 or unit.logical_y < 0 or unit.logical_y > 7 or unit.star < 1 or unit.star > 3:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _positive_i32(unit.health) or not _nonnegative_i32(unit.attack) or not _i32(unit.armor) or not _i32(unit.magic_resist):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _positive_i32(unit.attack_speed_milli) or unit.attack_range_cells < 0 or unit.attack_range_cells > 7:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _nonnegative_i32(unit.start_mana) or not _nonnegative_i32(unit.max_mana) or unit.max_mana < unit.start_mana or not _positive_i32(unit.move_speed_milli):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if unit.ability_id != null and not _stable_ids.is_valid(unit.ability_id.value):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.ability_id" % item_path))
		if not _sorted_unique_ids(unit.effect_ids, true):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.effect_ids" % item_path))
		if previous != null and not _unit_before(previous, unit):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		seen.append(unit.instance_id)
		previous = unit
	return BattleInputValidationResult.success()

func _validate_traits(traits: Array[TraitBattleSnapshot], path: StringName) -> BattleInputValidationResult:
	var previous_id := ""
	for index: int in range(traits.size()):
		var trait_snapshot := traits[index]
		if trait_snapshot == null or not _stable_ids.is_valid(trait_snapshot.trait_id) or not _positive_i32(trait_snapshot.tier):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.%d" % [path, index]))
		if index > 0 and previous_id >= String(trait_snapshot.trait_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		if not _sorted_unique_ids(trait_snapshot.member_instance_ids, false):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.%d.member_instance_ids" % [path, index]))
		previous_id = String(trait_snapshot.trait_id)
	return BattleInputValidationResult.success()

func _validate_effects(effects: Array[BattleEffectSnapshot], path: StringName) -> BattleInputValidationResult:
	var previous: BattleEffectSnapshot = null
	for index: int in range(effects.size()):
		var effect := effects[index]
		var item_path := StringName("%s.%d" % [path, index])
		if effect == null or not _i32(effect.priority) or not _nonnegative_i32(effect.effect_index) or not _stable_ids.is_valid(effect.source_stable_id) or not _stable_ids.is_valid(effect.effect_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if effect.source_instance_id != null and not _ascii_nonempty(String(effect.source_instance_id.value)):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source_instance_id" % item_path))
		if not _sorted_unique_ids(effect.target_ids, false):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.target_ids" % item_path))
		var previous_key := ""
		for parameter_index: int in range(effect.integer_params.size()):
			var parameter := effect.integer_params[parameter_index]
			if parameter == null or not _enum_token(String(parameter.key)) or not _i32(parameter.value) or (parameter_index > 0 and previous_key >= String(parameter.key)):
				return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.integer_params" % item_path))
			previous_key = String(parameter.key)
		previous_key = ""
		for parameter_index: int in range(effect.id_params.size()):
			var parameter := effect.id_params[parameter_index]
			if parameter == null or not _enum_token(String(parameter.key)) or not _stable_ids.is_valid(parameter.value) or (parameter_index > 0 and previous_key >= String(parameter.key)):
				return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.id_params" % item_path))
			previous_key = String(parameter.key)
		if previous != null and not _effect_before(previous, effect):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		previous = effect
	return BattleInputValidationResult.success()

func _unit_before(left: UnitBattleSnapshot, right: UnitBattleSnapshot) -> bool:
	var left_side := 0 if left.side == &"player" else 1
	var right_side := 0 if right.side == &"player" else 1
	if left_side != right_side: return left_side < right_side
	if left.logical_y != right.logical_y: return left.logical_y < right.logical_y
	if left.logical_x != right.logical_x: return left.logical_x < right.logical_x
	return String(left.instance_id) < String(right.instance_id)

func _effect_before(left: BattleEffectSnapshot, right: BattleEffectSnapshot) -> bool:
	if left.priority != right.priority: return left.priority < right.priority
	if left.source_stable_id != right.source_stable_id: return String(left.source_stable_id) < String(right.source_stable_id)
	return left.effect_index < right.effect_index

func _sorted_unique_ids(values: Array[StringName], require_stable: bool) -> bool:
	var previous := ""
	for index: int in range(values.size()):
		var current := String(values[index])
		if (require_stable and not _stable_ids.is_valid(values[index])) or (not require_stable and not _ascii_nonempty(current)):
			return false
		if index > 0 and previous >= current:
			return false
		previous = current
	return true

func _digest(value: StringName) -> bool:
	var text := String(value)
	if text.length() != 64: return false
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102): return false
	return true

func _ascii_nonempty(value: String) -> bool:
	if value.is_empty(): return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126: return false
	return true

func _enum_token(value: String) -> bool:
	if value.is_empty(): return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if index == 0:
			if code < 97 or code > 122: return false
		elif not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true

func _i32(value: int) -> bool:
	return value >= -2147483648 and value <= 2147483647

func _nonnegative_i32(value: int) -> bool:
	return value >= 0 and value <= 2147483647

func _positive_i32(value: int) -> bool:
	return value > 0 and value <= 2147483647

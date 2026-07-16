extends GutTest

const BattleFixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")

func test_v2_round_trip_hash_envelope_and_v1_golden_compatibility() -> void:
	var inputs: BattleSetupInputs = BattleFixture.create_inputs()
	inputs.setup_schema_version = 2
	inputs.player_equipment_effects[0].source_category = &"equipment"
	inputs.player_equipment_effects[0].source_side = &"player"
	inputs.player_equipment_effects[0].source_instance_id = OptionalStringNameValue.of(
		&"u_0000000000000001"
	)
	inputs.player_equipment_effects[0].source_slot = 0
	inputs.challenge_modifiers.append(_assignment(
		&"challenge", &"player", &"challenge.test", &"", 0, 0
	))
	inputs.commander_effects.append(_assignment(
		&"commander", &"player", &"commander.test", &"", 0, 0
	))
	inputs.player_relic_effects.append(_assignment(
		&"relic", &"player", &"relic.test", &"", 0, 0
	))
	inputs.player_active_traits[0].effect_assignments.append(_assignment(
		&"trait", &"player", &"trait.test", &"", 0, 0
	))
	inputs.encounter_snapshot.affix_effects.append(_assignment(
		&"encounter_affix", &"enemy", &"affix.test", &"", 0, 0
	))
	inputs.player_units[0].effect_ids = [&"effect.test"]
	inputs.player_units[0].basic_attack_profile = &"magic_projectile"
	inputs.player_units[0].effect_assignments.append(_assignment(
		&"unit",
		&"player",
		&"unit.hero",
		&"u_0000000000000001",
		0,
		0
	))
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.test"
	ability.target_rule = &"self"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.test"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.test"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	inputs.battle_rules.effect_rules.append(effect)

	var codec := CanonicalBattleCodecV2.new()
	var encoded := codec.encode(inputs)
	assert_true(encoded.ok, "v2 setup should encode")
	if not encoded.ok:
		return
	var decoded := codec.decode(encoded.canonical_bytes)
	assert_true(decoded.ok, "v2 canonical bytes should decode")
	if decoded.ok:
		assert_eq(codec.encode(decoded.inputs).canonical_bytes, encoded.canonical_bytes)
		assert_eq(decoded.inputs.player_equipment_effects[0].source_category, &"equipment")
		assert_eq(decoded.inputs.player_units[0].effect_assignments[0].source_instance_id.value, &"u_0000000000000001")
		assert_eq(decoded.inputs.player_active_traits[0].effect_assignments[0].source_category, &"trait")
		assert_eq(decoded.inputs.player_units[0].basic_attack_profile, &"magic_projectile")

	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	assert_true(validation.ok, "v2 setup should issue a trusted receipt")
	if not validation.ok:
		return
	var seed := U64Bits.from_hex("000000000000002a").value
	var built := BattleSetupHashBuilder.new(seed).build_from_validated(inputs, validation.receipt)
	assert_true(built.ok, "v2 setup should build")
	if not built.ok:
		return
	assert_eq(String(built.battle_setup.battle_setup_hash), BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes))
	assert_eq(String(built.battle_setup.battle_setup_envelope_digest).length(), 64)
	assert_true(BattleSetupEnvelopeVerifier.new().verify(built.battle_setup, seed).ok)
	var changed_profile := inputs.deep_clone()
	changed_profile.player_units[0].basic_attack_profile = &"melee"
	var changed_profile_bytes := codec.encode(changed_profile)
	assert_true(changed_profile_bytes.ok)
	assert_ne(
		BattleSetupHashBuilder.sha256_hex(changed_profile_bytes.canonical_bytes),
		String(built.battle_setup.battle_setup_hash)
	)
	var tampered := built.battle_setup.deep_clone()
	tampered.battle_setup_envelope_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	var rejected := BattleSetupEnvelopeVerifier.new().verify(tampered, seed)
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, BattleSetupEnvelopeError.DIGEST_MISMATCH)

	var v1_inputs: BattleSetupInputs = BattleFixture.create_inputs()
	var v1_encoded := CanonicalBattleCodecV1.new().encode(v1_inputs)
	assert_true(v1_encoded.ok)
	assert_eq(v1_encoded.canonical_bytes.size(), BattleFixture.GOLDEN_SIZE)
	assert_eq(BattleSetupHashBuilder.sha256_hex(v1_encoded.canonical_bytes), BattleFixture.GOLDEN_SHA256)

func test_v2_unknown_effect_operation_is_rejected_without_partial_acceptance() -> void:
	var inputs := _minimal_v2_inputs()
	var effect: BattleEffectRuleSnapshot = inputs.battle_rules.effect_rules[0]
	var unknown := BattleOperationRule.new()
	unknown.operation_index = 0
	unknown.kind = &"unknown"
	effect.battle_operations.append(unknown)
	var encoded := CanonicalBattleCodecV2.new().encode(inputs)
	assert_false(encoded.ok)
	assert_eq(encoded.error.field_path, &"battle_rules.effect_rules.payload")

func test_v2_effect_source_location_and_owner_are_hashed_and_strict() -> void:
	var inputs := _minimal_v2_inputs()
	var codec := CanonicalBattleCodecV2.new()
	var baseline := codec.encode(inputs)
	assert_true(baseline.ok)
	if not baseline.ok:
		return
	var changed := inputs.deep_clone()
	changed.player_equipment_effects[0].source_slot = 1
	var changed_encoded := codec.encode(changed)
	assert_true(changed_encoded.ok)
	if changed_encoded.ok:
		assert_ne(
			BattleSetupHashBuilder.sha256_hex(changed_encoded.canonical_bytes),
			BattleSetupHashBuilder.sha256_hex(baseline.canonical_bytes)
		)
	var wrong_owner := inputs.deep_clone()
	wrong_owner.player_equipment_effects[0].source_instance_id = OptionalStringNameValue.of(
		&"u_missing"
	)
	var rejected := codec.encode(wrong_owner)
	assert_false(rejected.ok)
	assert_eq(rejected.error.field_path, &"player_equipment_effects.0.source_instance_id")
	var wrong_location := inputs.deep_clone()
	wrong_location.player_equipment_effects[0].source_category = &"relic"
	rejected = codec.encode(wrong_location)
	assert_false(rejected.ok)
	assert_eq(rejected.error.field_path, &"player_equipment_effects.0.source")

func _minimal_v2_inputs() -> BattleSetupInputs:
	var inputs: BattleSetupInputs = BattleFixture.create_inputs()
	inputs.setup_schema_version = 2
	inputs.player_equipment_effects[0].source_category = &"equipment"
	inputs.player_equipment_effects[0].source_side = &"player"
	inputs.player_equipment_effects[0].source_instance_id = OptionalStringNameValue.of(
		&"u_0000000000000001"
	)
	inputs.player_equipment_effects[0].source_slot = 0
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.test"
	ability.target_rule = &"self"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.test"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.test"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	inputs.battle_rules.effect_rules.append(effect)
	return inputs

func _assignment(
	category: StringName,
	side: StringName,
	stable_id: StringName,
	owner_id: StringName,
	slot: int,
	effect_index: int
) -> BattleEffectSourceAssignmentSnapshot:
	var value := BattleEffectSourceAssignmentSnapshot.new()
	value.priority = 0
	value.source_category = category
	value.source_side = side
	value.source_stable_id = stable_id
	if not owner_id.is_empty():
		value.source_instance_id = OptionalStringNameValue.of(owner_id)
	value.source_slot = slot
	value.effect_index = effect_index
	value.effect_id = &"effect.test"
	return value

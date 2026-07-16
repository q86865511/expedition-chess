class_name BattleSimulationFixture
extends RefCounted

static func create_inputs() -> BattleSetupInputs:
	var base = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")
	var inputs: BattleSetupInputs = base.create_inputs()
	inputs.setup_schema_version = 2
	var equipment := inputs.player_equipment_effects[0]
	equipment.source_category = &"equipment"
	equipment.source_side = &"player"
	equipment.source_instance_id = OptionalStringNameValue.of(
		inputs.player_units[0].instance_id
	)
	equipment.source_slot = 0
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.test"
	ability.target_rule = &"current_target"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.test"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.test"
	effect.trigger = &"cast"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	inputs.battle_rules.effect_rules.append(effect)
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	enemy.effect_ids.append(&"effect.test")
	var assignment := BattleEffectSnapshot.new()
	assignment.source_category = &"unit"
	assignment.source_side = &"enemy"
	assignment.source_stable_id = enemy.unit_id
	assignment.source_instance_id = OptionalStringNameValue.of(enemy.instance_id)
	assignment.effect_id = &"effect.test"
	enemy.effect_assignments.append(assignment)
	return inputs

static func build_setup(
	inputs: BattleSetupInputs = null,
	run_seed: U64Bits = null
) -> BattleSetup:
	var actual_inputs := inputs.deep_clone() if inputs != null else create_inputs()
	var seed := run_seed.deep_clone() if run_seed != null else U64Bits.zero()
	var validation := BattleSetupInputsValidator.new().validate_for_build(actual_inputs)
	assert(
		validation.ok,
		"%s at %s" % [
			String(validation.error.code) if validation.error != null else "unknown",
			String(validation.error.field_path) if validation.error != null else "unknown",
		]
	)
	if not validation.ok:
		return null
	var built := BattleSetupHashBuilder.new(seed).build_from_validated(
		actual_inputs, validation.receipt
	)
	assert(built.ok)
	return built.battle_setup if built.ok else null

static func run_to_result(
	setup: BattleSetup,
	max_steps: int = 1801
) -> BattleResult:
	var simulation := BattleSimulation.new()
	var initialized := simulation.initialize(setup)
	assert(initialized.ok)
	if not initialized.ok:
		return null
	for _index: int in range(max_steps):
		var stepped := simulation.step()
		assert(stepped.ok)
		if not stepped.ok:
			return null
		if stepped.finished:
			var queried := simulation.result()
			assert(queried.ok)
			return queried.result if queried.ok else null
	assert(false, "simulation did not finish within max_steps")
	return null

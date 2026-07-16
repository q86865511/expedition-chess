extends GutTest

func test_initialize_rejects_hash_tamper_without_entering_lifecycle() -> void:
	var setup := BattleSimulationFixture.build_setup()
	setup.inputs.player_units[0].attack += 1
	var simulation := BattleSimulation.new()
	var result := simulation.initialize(setup)
	assert_false(result.ok)
	assert_eq(result.error.code, BattleSimulationError.SETUP_HASH_MISMATCH)
	assert_false(simulation.is_finished())
	assert_false(simulation.result().ok)

func test_first_tick_emits_spawn_and_deterministic_movement_events() -> void:
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup()).ok)
	var first := simulation.step()
	assert_true(first.ok)
	assert_eq(first.tick, 1)
	assert_eq(_count_type(first.events, &"spawn"), 2)
	assert_eq(_count_type(first.events, &"move"), 2)
	_assert_event_stream_valid(first.events)

func test_same_setup_produces_identical_result_and_summary_hash() -> void:
	var setup := BattleSimulationFixture.build_setup()
	var first := BattleSimulationFixture.run_to_result(setup)
	var second := BattleSimulationFixture.run_to_result(setup)
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.result_hash, second.result_hash)
	assert_eq(first.summary_hash, second.summary_hash)
	assert_eq(first.outcome, second.outcome)
	assert_lte(first.final_tick, 1800)
	assert_null(first.validate())

func test_simultaneous_lethal_attacks_resolve_both_deaths_as_player_loss() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	player.logical_y = 3
	player.logical_x = 3
	enemy.logical_y = 4
	enemy.logical_x = 3
	player.health = 10
	enemy.health = 10
	player.attack = 20
	enemy.attack = 20
	player.max_mana = 0
	enemy.max_mana = 0
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var tick := simulation.step()
	assert_true(tick.ok)
	assert_true(tick.finished)
	assert_eq(_count_type(tick.events, &"attack"), 2)
	assert_eq(_count_type(tick.events, &"damage"), 2)
	assert_eq(_count_type(tick.events, &"death"), 2)
	var result := simulation.result()
	assert_true(result.ok)
	assert_eq(result.result.outcome, &"player_loss")
	assert_eq(result.result.final_tick, 1)
	assert_eq(result.result.survivor_instance_ids, [])
	assert_eq(result.result.expedition_damage, 6)
	assert_not_null(simulation.validation_receipt())
	_assert_event_stream_valid(tick.events)

func test_damage_wave_uses_shared_final_health_and_deterministic_killer() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	var first := inputs.player_units[0]
	first.logical_y = 3
	first.logical_x = 2
	first.attack = 20
	first.attack_range_cells = 7
	first.max_mana = 0
	var second := first.deep_clone()
	second.instance_id = &"u_0000000000000002"
	second.logical_x = 4
	second.effect_ids.clear()
	second.effect_assignments.clear()
	inputs.player_units.append(second)
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	enemy.logical_y = 4
	enemy.logical_x = 3
	enemy.health = 30
	enemy.attack = 0
	enemy.max_mana = 0
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	assert_true(stepped.finished)
	var damages: Array[DamageEventPayload] = []
	var killer := &""
	for event: BattleEvent in stepped.events:
		if event.type == &"damage" and event.target_instance_ids[0] == enemy.instance_id:
			damages.append(event.payload as DamageEventPayload)
		elif event.type == &"death" and event.source_instance_id.value == enemy.instance_id:
			killer = event.target_instance_ids[0]
	assert_eq(damages.size(), 2)
	assert_eq(damages[0].health_after, 0)
	assert_eq(damages[1].health_after, 0)
	assert_eq(damages[0].health_damage, 20)
	assert_eq(damages[1].health_damage, 10)
	assert_eq(killer, first.instance_id)

func test_result_is_unavailable_before_finish_and_step_is_rejected_after_finish() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.player_units[0].logical_y = 3
	inputs.player_units[0].logical_x = 3
	inputs.encounter_snapshot.enemy_units[0].logical_y = 4
	inputs.encounter_snapshot.enemy_units[0].logical_x = 3
	inputs.player_units[0].attack = 1000
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	assert_false(simulation.result().ok)
	assert_true(simulation.step().finished)
	var rejected := simulation.step()
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, BattleSimulationError.LIFECYCLE_INVALID)

func test_full_mana_cast_has_priority_and_applies_resolved_damage_next_tick() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	player.logical_y = 3
	player.logical_x = 3
	enemy.logical_y = 4
	enemy.logical_x = 3
	player.start_mana = player.max_mana
	enemy.health = 30
	var operation := BattleOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"damage"
	operation.base_amount = 50
	operation.scaling = &"flat"
	operation.damage_type = &"magical"
	operation.target = &"target"
	inputs.battle_rules.effect_rules[0].battle_operations.append(operation)
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var started := simulation.step()
	assert_true(started.ok)
	assert_false(started.finished)
	assert_eq(_count_type(started.events, &"cast"), 1)
	assert_eq(_count_type(started.events, &"attack"), 1)
	var resolved := simulation.step()
	assert_true(resolved.ok)
	assert_true(resolved.finished)
	assert_eq(_count_type(resolved.events, &"cast"), 1)
	assert_eq(_count_type(resolved.events, &"damage"), 1)
	assert_eq(_count_type(resolved.events, &"death"), 1)
	assert_eq(simulation.result().result.outcome, &"player_win")
	_assert_event_stream_valid(started.events)
	_assert_event_stream_valid(resolved.events)

func test_boss_phase_uses_explicit_source_instance_and_fixed_phase_order() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.battle_rules.encounter_kind = &"boss"
	var phase_one := BossPhaseSnapshot.new()
	phase_one.phase_index = 0
	phase_one.hp_threshold_bps = 10000
	phase_one.source_instance_id = inputs.encounter_snapshot.enemy_units[0].instance_id
	var phase_two := BossPhaseSnapshot.new()
	phase_two.phase_index = 1
	phase_two.hp_threshold_bps = 10000
	phase_two.source_instance_id = inputs.encounter_snapshot.enemy_units[0].instance_id
	var phase_values: Array[BossPhaseSnapshot] = [phase_one, phase_two]
	inputs.encounter_snapshot.boss_phases = phase_values
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	var phases: Array[BattleEvent] = []
	for event: BattleEvent in stepped.events:
		if event.type == &"boss_phase":
			phases.append(event)
	assert_eq(phases.size(), 2)
	assert_eq(phases[0].source_instance_id.value, &"e_0000000000000001")
	assert_eq((phases[0].payload as BossPhaseEventPayload).phase_index, 0)
	assert_eq((phases[1].payload as BossPhaseEventPayload).phase_index, 1)
	_assert_event_stream_valid(phases)

func test_overtime_starts_at_1200_and_forces_result_before_hard_limit() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.player_units[0].attack = 0
	inputs.encounter_snapshot.enemy_units[0].attack = 0
	inputs.player_units[0].max_mana = 0
	inputs.encounter_snapshot.enemy_units[0].max_mana = 0
	inputs.player_units[0].logical_y = 3
	inputs.player_units[0].logical_x = 3
	inputs.encounter_snapshot.enemy_units[0].logical_y = 4
	inputs.encounter_snapshot.enemy_units[0].logical_x = 3
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var first_overtime_tick := -1
	for _index: int in range(1801):
		var stepped := simulation.step()
		assert_true(stepped.ok)
		for event: BattleEvent in stepped.events:
			if event.type == &"damage" \
				and (event.payload as DamageEventPayload).damage_type == &"true" \
				and first_overtime_tick < 0:
				first_overtime_tick = event.tick
		if stepped.finished:
			break
	assert_eq(first_overtime_tick, 1200)
	assert_true(simulation.is_finished())
	assert_lte(simulation.result().result.final_tick, 1800)
	assert_eq(simulation.result().result.outcome, &"player_loss")

func test_boss_loss_uses_act_snapshot_and_encounter_survivor_formula_without_mutation() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.battle_rules.act_index = 2
	inputs.battle_rules.encounter_kind = &"boss"
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	player.logical_y = 3
	player.logical_x = 3
	player.health = 1
	player.attack = 0
	player.max_mana = 0
	enemy.logical_y = 4
	enemy.logical_x = 3
	enemy.attack = 1000
	enemy.max_mana = 0
	var second := enemy.deep_clone()
	second.instance_id = &"e_0000000000000002"
	second.logical_x = 4
	second.effect_ids.clear()
	second.effect_assignments.clear()
	inputs.encounter_snapshot.enemy_units.append(second)
	var result := BattleSimulationFixture.run_to_result(
		BattleSimulationFixture.build_setup(inputs)
	)
	assert_not_null(result)
	assert_eq(result.outcome, &"player_loss")
	assert_eq(result.expedition_damage, 24)

func test_path_tie_uses_fixed_direction_order_and_blocks_corner_cutting() -> void:
	var mover := BattleEntityState.new()
	mover.instance_id = &"u_0000000000000001"
	mover.side = &"player"
	mover.logical_y = 3
	mover.logical_x = 3
	var target := BattleEntityState.new()
	target.instance_id = &"e_0000000000000001"
	target.side = &"enemy"
	target.logical_y = 5
	target.logical_x = 3
	var blocker := BattleEntityState.new()
	blocker.instance_id = &"u_0000000000000002"
	blocker.side = &"player"
	blocker.logical_y = 4
	blocker.logical_x = 3
	var entities: Array[BattleEntityState] = [mover, target, blocker]
	var step := BattlePathfinder.new().next_step_toward_attack_position(
		mover, target, entities, 8, 8, 1
	)
	assert_eq(step, Vector2i(4, 3))
	assert_false(BattlePathfinder.new().can_step(
		Vector2i(3, 3), Vector2i(4, 4), mover.instance_id, entities, 8, 8
	))

func test_target_cell_rank_is_side_relative_before_instance_id_tie_break() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	var front := inputs.player_units[0]
	front.logical_y = 3
	front.logical_x = 2
	front.max_mana = 0
	var back := front.deep_clone()
	back.instance_id = &"u_0000000000000002"
	back.logical_y = 0
	back.logical_x = 3
	back.effect_ids.clear()
	back.effect_assignments.clear()
	var ordered_players: Array[UnitBattleSnapshot] = [back, front]
	inputs.player_units = ordered_players
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	enemy.logical_y = 4
	enemy.logical_x = 3
	enemy.attack_range_cells = 7
	enemy.max_mana = 0
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	var enemy_target := &""
	for event: BattleEvent in stepped.events:
		if event.type == &"attack" and event.source_instance_id != null \
			and event.source_instance_id.value == enemy.instance_id:
			enemy_target = event.target_instance_ids[0]
			break
	assert_eq(enemy_target, front.instance_id)

func test_initial_unit_attack_event_uses_hashed_presentation_profile() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.player_units[0].basic_attack_profile = &"magic_projectile"
	inputs.player_units[0].logical_y = 3
	inputs.player_units[0].logical_x = 3
	inputs.player_units[0].max_mana = 0
	inputs.encounter_snapshot.enemy_units[0].logical_y = 4
	inputs.encounter_snapshot.enemy_units[0].logical_x = 3
	inputs.encounter_snapshot.enemy_units[0].max_mana = 0
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	for event: BattleEvent in stepped.events:
		if event.type == &"attack" and event.source_instance_id != null \
			and event.source_instance_id.value == inputs.player_units[0].instance_id:
			assert_eq(
				(event.payload as AttackEventPayload).presentation_profile,
				&"basic.magic_projectile"
			)
			return
	fail_test("player attack event missing")

func test_random_target_is_seeded_reproducible_and_stream_driven() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.battle_rules.ability_rules[0].target_rule = &"random_enemy"
	inputs.player_units[0].start_mana = inputs.player_units[0].max_mana
	inputs.player_units[0].logical_y = 3
	inputs.player_units[0].logical_x = 3
	inputs.encounter_snapshot.enemy_units[0].logical_y = 4
	inputs.encounter_snapshot.enemy_units[0].logical_x = 2
	var second := inputs.encounter_snapshot.enemy_units[0].deep_clone()
	second.instance_id = &"e_0000000000000002"
	second.logical_x = 4
	second.effect_ids.clear()
	second.effect_assignments.clear()
	inputs.encounter_snapshot.enemy_units.append(second)
	var observed: Dictionary = {}
	for seed_value: int in range(16):
		var seed := U64Bits.from_u32(0, seed_value).value
		var setup := BattleSimulationFixture.build_setup(inputs, seed)
		var first_target := _first_cast_target(setup)
		var repeated_target := _first_cast_target(setup)
		assert_eq(first_target, repeated_target)
		observed[String(first_target)] = true
	assert_eq(observed.size(), 2)

func test_runtime_dispatches_all_non_cast_triggers_and_persists_battle_end_intent() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	player.logical_y = 3
	player.logical_x = 3
	enemy.logical_y = 4
	enemy.logical_x = 3
	player.attack = 1000
	player.max_mana = 1000
	enemy.max_mana = 1000
	_attach_mana_effect(inputs, player, &"effect.runtime_battle_start", &"battle_start")
	_attach_mana_effect(inputs, player, &"effect.runtime_periodic", &"periodic", 1)
	_attach_mana_effect(inputs, player, &"effect.runtime_attack", &"attack")
	_attach_mana_effect(inputs, player, &"effect.runtime_hit", &"hit")
	_attach_mana_effect(inputs, player, &"effect.runtime_kill", &"kill")
	_attach_mana_effect(inputs, enemy, &"effect.runtime_damaged", &"damaged")
	_attach_mana_effect(inputs, enemy, &"effect.runtime_death", &"death")
	_attach_battle_end_intent(inputs, player)
	_sort_effect_contract(inputs)
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	assert_true(stepped.finished)
	var snapshot := simulation.state_snapshot()
	var player_state := _entity(snapshot, player.instance_id)
	var enemy_state := _entity(snapshot, enemy.instance_id)
	for effect_id: StringName in [
		&"effect.runtime_battle_start", &"effect.runtime_periodic",
		&"effect.runtime_attack", &"effect.runtime_hit", &"effect.runtime_kill",
		&"effect.runtime_battle_end",
	]:
		assert_eq(player_state.effect_use_count(effect_id), 1, String(effect_id))
	assert_eq(enemy_state.effect_use_count(&"effect.runtime_damaged"), 1)
	assert_eq(enemy_state.effect_use_count(&"effect.runtime_death"), 1)
	var result := simulation.result()
	assert_true(result.ok)
	assert_eq(result.result.run_mutation_proposals.size(), 1)
	assert_eq(result.result.run_mutation_proposals[0].operation_kind, &"add_gold")

func test_fatal_effect_budget_rolls_back_tick_rng_events_and_enters_failed_lifecycle() -> void:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.battle_rules.effect_resolution_budget = 64
	inputs.battle_rules.operation_budget = 64
	for index: int in range(65):
		_attach_mana_effect(
			inputs,
			inputs.player_units[0],
			StringName("effect.budget_%03d" % index),
			&"battle_start"
		)
	_sort_effect_contract(inputs)
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(BattleSimulationFixture.build_setup(inputs)).ok)
	var before := simulation.state_snapshot()
	var failed := simulation.step()
	assert_false(failed.ok)
	assert_eq(failed.error.code, BattleSimulationError.EFFECT_FAILED)
	var after := simulation.state_snapshot()
	assert_eq(after.tick, before.tick)
	assert_eq(after.next_event_sequence, before.next_event_sequence)
	assert_eq(after.events.size(), before.events.size())
	assert_eq(
		after.rng_snapshot.state.to_hex(), before.rng_snapshot.state.to_hex()
	)
	var rejected := simulation.step()
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, BattleSimulationError.LIFECYCLE_INVALID)

func _attach_mana_effect(
	inputs: BattleSetupInputs,
	unit: UnitBattleSnapshot,
	effect_id: StringName,
	trigger: StringName,
	periodic_interval: int = 0
) -> void:
	var rule := BattleEffectRuleSnapshot.new()
	rule.effect_id = effect_id
	rule.trigger = trigger
	rule.periodic_interval_ticks = periodic_interval
	rule.stacking = &"replace"
	rule.max_stacks = 1
	rule.duration_ticks = 1
	var operation := BattleOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"grant_mana"
	operation.amount = 1
	operation.target = &"self"
	rule.battle_operations.append(operation)
	inputs.battle_rules.effect_rules.append(rule)
	_attach_unit_source(unit, effect_id)

func _attach_battle_end_intent(
	inputs: BattleSetupInputs,
	unit: UnitBattleSnapshot
) -> void:
	var rule := BattleEffectRuleSnapshot.new()
	rule.effect_id = &"effect.runtime_battle_end"
	rule.trigger = &"battle_end"
	rule.stacking = &"replace"
	rule.max_stacks = 1
	rule.duration_ticks = 1
	var operation := BattleRunOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 1
	operation.claim_scope = &"once_per_node"
	rule.run_operations.append(operation)
	inputs.battle_rules.effect_rules.append(rule)
	_attach_unit_source(unit, rule.effect_id)

func _attach_unit_source(unit: UnitBattleSnapshot, effect_id: StringName) -> void:
	unit.effect_ids.append(effect_id)
	var assignment := BattleEffectSnapshot.new()
	assignment.source_category = &"unit"
	assignment.source_side = unit.side
	assignment.source_stable_id = unit.unit_id
	assignment.source_instance_id = OptionalStringNameValue.of(unit.instance_id)
	assignment.effect_id = effect_id
	unit.effect_assignments.append(assignment)

func _sort_effect_contract(inputs: BattleSetupInputs) -> void:
	inputs.battle_rules.effect_rules.sort_custom(func(
		left: BattleEffectRuleSnapshot,
		right: BattleEffectRuleSnapshot
	) -> bool: return String(left.effect_id) < String(right.effect_id))
	for unit: UnitBattleSnapshot in [
		inputs.player_units[0], inputs.encounter_snapshot.enemy_units[0]
	]:
		unit.effect_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
			return String(left) < String(right))
		unit.effect_assignments.sort_custom(func(
			left: BattleEffectSnapshot,
			right: BattleEffectSnapshot
		) -> bool: return String(left.effect_id) < String(right.effect_id))
		for index: int in range(unit.effect_assignments.size()):
			unit.effect_assignments[index].effect_index = index

func _entity(state: BattleState, instance_id: StringName) -> BattleEntityState:
	for entity: BattleEntityState in state.entities:
		if entity.instance_id == instance_id:
			return entity
	return null

func _first_cast_target(setup: BattleSetup) -> StringName:
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(setup).ok)
	var stepped := simulation.step()
	assert_true(stepped.ok)
	for event: BattleEvent in stepped.events:
		if event.type == &"cast" \
			and event.source_instance_id != null \
			and event.source_instance_id.value == &"u_0000000000000001":
			return event.target_instance_ids[0]
	return &""

func _count_type(events: Array[BattleEvent], type: StringName) -> int:
	var count := 0
	for event: BattleEvent in events:
		if event.type == type:
			count += 1
	return count

func _assert_event_stream_valid(events: Array[BattleEvent]) -> void:
	var previous := -1
	var codec := BattleEventCodecV1.new()
	for event: BattleEvent in events:
		assert_gt(event.sequence, previous)
		previous = event.sequence
		var encoded := codec.encode(event)
		assert_true(
			encoded.ok,
			String(encoded.error.field_path) if encoded.error != null else "event invalid"
		)

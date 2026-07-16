class_name BattleSimulation
extends RefCounted

const PLAYER: StringName = &"player"
const ENEMY: StringName = &"enemy"

var _setup: BattleSetup
var _state: BattleState
var _finished: bool = false
var _result: BattleResult
var _validation_receipt: BattleResultValidationReceipt
var _initialized: bool = false
var _failed: bool = false
var _delivered_event_count: int = 0
var _pathfinder := BattlePathfinder.new()

func initialize(setup: BattleSetup) -> BattleInitializationResult:
	if _initialized:
		return _init_failure(BattleSimulationError.LIFECYCLE_INVALID, &"initialize")
	var setup_error := _validate_setup(setup)
	if setup_error != null:
		return BattleInitializationResult.failure(setup_error)
	var candidate := BattleState.new()
	candidate.tick = 1
	candidate.rng_snapshot = setup.combat_rng_snapshot.deep_clone()
	var all_units: Array[UnitBattleSnapshot] = []
	all_units.append_array(setup.inputs.player_units)
	all_units.append_array(setup.inputs.encounter_snapshot.enemy_units)
	for unit: UnitBattleSnapshot in all_units:
		if unit == null:
			return _init_failure(BattleSimulationError.SETUP_INVALID, &"units")
		var entity := _entity_from_snapshot(unit, setup.inputs.battle_rules)
		candidate.entities.append(entity)
		for assignment: BattleEffectSnapshot in entity.effect_assignments:
			_append_effect_source(candidate, assignment)
	_append_effect_sources(candidate, setup.inputs.player_equipment_effects)
	_append_effect_sources(candidate, setup.inputs.player_relic_effects)
	_append_effect_sources(candidate, setup.inputs.commander_effects)
	_append_effect_sources(candidate, setup.inputs.challenge_modifiers)
	_append_effect_sources(candidate, setup.inputs.encounter_snapshot.affix_effects)
	for trait_snapshot: TraitBattleSnapshot in setup.inputs.player_active_traits:
		_append_effect_sources(candidate, trait_snapshot.effect_assignments)
	for trait_snapshot: TraitBattleSnapshot in setup.inputs.encounter_snapshot.active_traits:
		_append_effect_sources(candidate, trait_snapshot.effect_assignments)
	if candidate.entities.size() > setup.inputs.battle_rules.entity_budget:
		return _init_failure(BattleSimulationError.ENTITY_BUDGET_EXCEEDED, &"entities")
	candidate.entities.sort_custom(_entity_precedes)
	candidate.effect_sources.sort_custom(_source_precedes)
	var spawn_entities: Array[BattleEntityState] = []
	for entity: BattleEntityState in candidate.entities:
		spawn_entities.append(entity)
	spawn_entities.sort_custom(_spawn_precedes)
	for entity: BattleEntityState in spawn_entities:
		_append_spawn_event(candidate, entity)
	_setup = setup.deep_clone()
	_state = candidate
	_initialized = true
	return BattleInitializationResult.success()

func step() -> BattleStepResult:
	if not _initialized or _state == null or _finished or _failed:
		return _step_failure(BattleSimulationError.LIFECYCLE_INVALID, &"step")
	var draft := _state.deep_clone()
	var event_start := _delivered_event_count
	var tick := draft.tick
	var rules := _setup.inputs.battle_rules
	var budget := BattleTickBudget.new(
		rules.effect_resolution_budget,
		rules.operation_budget,
		rules.event_budget,
		rules.entity_budget
	)
	_expire_timed_states(draft, rules)
	var scheduled_error := _resolve_scheduled_triggers(draft, rules, budget)
	if scheduled_error != null:
		return _enter_failed(scheduled_error)
	if tick >= rules.soft_limit_ticks \
		and (tick - rules.soft_limit_ticks) % rules.overtime_interval_ticks == 0:
		_apply_overtime_batch(draft, rules)
		_check_boss_phases(draft)
		var overtime_death_error := _process_deaths(draft, rules, budget)
		if overtime_death_error != null:
			return _enter_failed(overtime_death_error)
	var action_error := _execute_tick(draft, rules, budget)
	if action_error != null:
		return _enter_failed(action_error)
	_check_boss_phases(draft)
	var death_error := _process_deaths(draft, rules, budget)
	if death_error != null:
		return _enter_failed(death_error)
	var outcome := _outcome(draft, tick >= rules.hard_limit_ticks)
	if not outcome.is_empty():
		var final_error := _finalize(draft, outcome, rules, budget)
		if final_error != null:
			return _enter_failed(final_error)
	else:
		draft.tick += 1
	if draft.events.size() - event_start > rules.event_budget:
		return _enter_failed(BattleSimulationError.new(
			BattleSimulationError.BUDGET_EXCEEDED, &"event_budget"
		))
	var tick_events: Array[BattleEvent] = []
	for index: int in range(event_start, draft.events.size()):
		tick_events.append(draft.events[index].deep_clone())
	_state = draft
	_delivered_event_count = draft.events.size()
	return BattleStepResult.success(tick, tick_events, _finished)

func is_finished() -> bool:
	return _finished

func result() -> BattleResultQuery:
	if not _initialized or not _finished or _result == null:
		return BattleResultQuery.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, &"result"
		))
	return BattleResultQuery.success(_result)

func validation_receipt() -> BattleResultValidationReceipt:
	return _validation_receipt.deep_clone() if _validation_receipt != null else null

func state_snapshot() -> BattleState:
	return _state.deep_clone() if _state != null else null

func _validate_setup(setup: BattleSetup) -> BattleSimulationError:
	if setup == null or setup.inputs == null or setup.inputs.setup_schema_version != 2:
		return BattleSimulationError.new(BattleSimulationError.SETUP_INVALID, &"setup")
	if setup.hash_version != 1 or setup.rng_version != 1 \
		or setup.combat_rng_snapshot == null:
		return BattleSimulationError.new(
			BattleSimulationError.VERSION_TUPLE_UNSUPPORTED, &"setup.version"
		)
	var rules := setup.inputs.battle_rules
	if rules == null or rules.simulation_version != 1 \
		or rules.event_codec_version != 1 or rules.result_codec_version != 1:
		return BattleSimulationError.new(
			BattleSimulationError.VERSION_TUPLE_UNSUPPORTED, &"battle_rules.version"
		)
	var validated := BattleSetupInputsValidator.new().validate_for_build(setup.inputs)
	if not validated.ok:
		return BattleSimulationError.new(
			BattleSimulationError.SETUP_INVALID,
			validated.error.field_path,
			validated.error.code
		)
	var encoded := CanonicalBattleCodecV2.new().encode(setup.inputs)
	if not encoded.ok:
		return BattleSimulationError.new(
			BattleSimulationError.SETUP_INVALID, encoded.error.field_path
		)
	if BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes) \
		!= String(setup.battle_setup_hash):
		return BattleSimulationError.new(
			BattleSimulationError.SETUP_HASH_MISMATCH, &"battle_setup_hash"
		)
	var rng := Pcg32Stream.from_snapshot(setup.combat_rng_snapshot)
	if not rng.ok:
		return BattleSimulationError.new(
			BattleSimulationError.RNG_INVALID, &"combat_rng_snapshot"
		)
	var hash_regex := RegEx.new()
	hash_regex.compile("^[0-9a-f]{64}$")
	if hash_regex.search(String(setup.battle_setup_envelope_digest)) == null:
		return BattleSimulationError.new(
			BattleSimulationError.SETUP_INVALID, &"battle_setup_envelope_digest"
		)
	return null

func _entity_from_snapshot(
	unit: UnitBattleSnapshot,
	rules: BattleRulesSnapshot
) -> BattleEntityState:
	var entity := BattleEntityState.new()
	entity.instance_id = unit.instance_id
	entity.unit_id = unit.unit_id
	entity.origin = &"player" if unit.side == PLAYER else &"encounter"
	entity.side = unit.side
	entity.logical_y = unit.logical_y
	entity.logical_x = unit.logical_x
	entity.spawn_y = unit.logical_y
	entity.spawn_x = unit.logical_x
	entity.max_health = unit.health
	entity.health = unit.health
	entity.base_attack = unit.attack
	entity.base_armor = unit.armor
	entity.base_magic_resist = unit.magic_resist
	entity.base_attack_speed_milli = unit.attack_speed_milli
	entity.base_move_speed_milli = unit.move_speed_milli
	entity.attack = unit.attack
	entity.armor = unit.armor
	entity.magic_resist = unit.magic_resist
	entity.attack_speed_milli = unit.attack_speed_milli
	entity.move_speed_milli = unit.move_speed_milli
	entity.attack_range_cells = unit.attack_range_cells
	entity.mana = unit.start_mana
	entity.max_mana = unit.max_mana
	entity.ability_id = unit.ability_id.deep_clone() if unit.ability_id != null else null
	entity.basic_attack_profile = StringName(
		"basic.%s" % String(unit.basic_attack_profile)
	)
	entity.attack_progress = BattleCombatMath.initial_progress(
		entity.attack_speed_milli, rules
	)
	entity.move_progress = BattleCombatMath.initial_progress(
		entity.move_speed_milli, rules
	)
	for assignment: BattleEffectSnapshot in unit.effect_assignments:
		entity.effect_assignments.append(assignment.deep_clone())
	return entity

func _execute_tick(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget
) -> BattleSimulationError:
	var cast_error := _resolve_ready_casts(state, rules, budget)
	if cast_error != null:
		return cast_error
	var threshold := BattleCombatMath.threshold(rules)
	var movers: Array[BattleMoveProposal] = []
	var attackers: Array[BattleEntityState] = []
	for entity: BattleEntityState in state.entities:
		if not entity.alive or entity.death_pending:
			continue
		if entity.cast_ability_id != null \
			or entity.last_main_action_tick == state.tick:
			entity.attack_progress = BattleCombatMath.advance_progress(
				entity.attack_progress, entity.attack_speed_milli, rules
			)
			entity.move_progress = BattleCombatMath.advance_progress(
				entity.move_progress, entity.move_speed_milli, rules
			)
			continue
		var target := _select_target(entity, state.entities, rules)
		if target == null:
			continue
		entity.current_target_id = OptionalStringNameValue.of(target.instance_id)
		if entity.max_mana > 0 and entity.mana >= entity.max_mana \
			and entity.ability_id != null:
			var start_error := _start_cast(state, entity, target, rules)
			if start_error != null:
				return start_error
			continue
		if _in_range(entity, target):
			entity.attack_progress = BattleCombatMath.advance_progress(
				entity.attack_progress, entity.attack_speed_milli, rules
			)
			if entity.attack_progress >= threshold:
				attackers.append(entity)
		else:
			entity.move_progress = BattleCombatMath.advance_progress(
				entity.move_progress, entity.move_speed_milli, rules
			)
			if entity.move_progress >= threshold:
				var destination := _pathfinder.next_step_toward_attack_position(
					entity, target, state.entities,
					rules.board_width, rules.board_height, entity.attack_range_cells
				)
				if destination.x >= 0:
					var proposal := BattleMoveProposal.new()
					proposal.instance_id = entity.instance_id
					proposal.effective_speed = entity.move_speed_milli
					proposal.start_y = entity.logical_y
					proposal.start_x = entity.logical_x
					proposal.to_y = destination.y
					proposal.to_x = destination.x
					movers.append(proposal)
	_apply_moves(state, movers, rules)
	attackers.sort_custom(_entity_precedes)
	var hit_requests: Array[BattleTriggerRequest] = []
	var damaged_requests: Array[BattleTriggerRequest] = []
	var damage_requests: Array[BattleDamageRequest] = []
	for attacker: BattleEntityState in attackers:
		if not attacker.alive:
			continue
		var target := _entity_by_optional(state.entities, attacker.current_target_id)
		if target == null or not target.alive or not _in_range(attacker, target):
			continue
		attacker.attack_progress -= threshold
		attacker.last_main_action_tick = state.tick
		_append_attack_event(state, attacker, target)
		var attack_trigger_error := _resolve_entity_trigger(
			state, rules, budget, &"attack", attacker, target
		)
		if attack_trigger_error != null:
			return attack_trigger_error
		_grant_mana(state, attacker, rules.attack_mana_gain, &"attack")
		damage_requests.append(_damage_request(
			state, attacker, target, attacker.attack, &"physical", &"attack"
		))
	var outcomes := _apply_damage_wave(state, damage_requests)
	for outcome: BattleDamageOutcome in outcomes:
		var source := _entity_by_optional(
			state.entities, outcome.request.source_instance_id
		)
		var target := _entity_by_id(
			state.entities, outcome.request.target_instance_id
		)
		if source != null and outcome.request.raw_amount > 0:
			hit_requests.append(_trigger_request(&"hit", source, target))
		if outcome.applied_amount > 0:
			damaged_requests.append(_trigger_request(
				&"damaged", target, source
			))
	for request: BattleTriggerRequest in hit_requests:
		var hit_error := _resolve_trigger_request(state, rules, budget, request)
		if hit_error != null:
			return hit_error
	damaged_requests.sort_custom(func(
		left: BattleTriggerRequest,
		right: BattleTriggerRequest
	) -> bool:
		var left_source := _entity_by_id(state.entities, left.source_instance_id)
		var right_source := _entity_by_id(state.entities, right.source_instance_id)
		return _entity_precedes(left_source, right_source)
	)
	for request: BattleTriggerRequest in damaged_requests:
		var damaged_error := _resolve_trigger_request(
			state, rules, budget, request
		)
		if damaged_error != null:
			return damaged_error
	return null

func _trigger_request(
	trigger: StringName,
	source: BattleEntityState,
	target: BattleEntityState
) -> BattleTriggerRequest:
	var request := BattleTriggerRequest.new()
	request.trigger = trigger
	request.source_instance_id = source.instance_id
	request.target_instance_id = OptionalStringNameValue.of(target.instance_id) \
		if target != null else null
	return request

func _resolve_trigger_request(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget,
	request: BattleTriggerRequest
) -> BattleSimulationError:
	var source := _entity_by_id(state.entities, request.source_instance_id)
	var target := _entity_by_optional(state.entities, request.target_instance_id)
	return _resolve_entity_trigger(
		state, rules, budget, request.trigger, source, target
	)

func _start_cast(
	state: BattleState,
	caster: BattleEntityState,
	current_target: BattleEntityState,
	rules: BattleRulesSnapshot
) -> BattleSimulationError:
	var ability := _ability_rule(rules, caster.ability_id.value)
	if ability == null:
		return BattleSimulationError.new(
			BattleSimulationError.INVARIANT_FAILED, &"ability_rule"
		)
	var target := _ability_target(ability, caster, current_target, state)
	if target == null and ability.target_rule != &"self":
		return null
	var before := caster.mana
	caster.mana = 0
	var mana_payload := ManaEventPayload.new()
	mana_payload.reason = &"cast_reset"
	mana_payload.delta = -before
	mana_payload.mana_after = 0
	_append_event(state, &"mana", &"", [caster.instance_id], mana_payload, false)
	caster.cast_ability_id = caster.ability_id.deep_clone()
	caster.cast_target_id = OptionalStringNameValue.of(
		caster.instance_id if ability.target_rule == &"self" else target.instance_id
	)
	caster.cast_resolve_tick = state.tick + ability.cast_ticks
	caster.last_main_action_tick = state.tick
	var payload := CastEventPayload.new()
	payload.ability_id = ability.ability_id
	payload.action = &"start"
	payload.resolve_tick = caster.cast_resolve_tick
	_append_event(
		state,
		&"cast",
		caster.instance_id,
		[caster.cast_target_id.value],
		payload
	)
	return null

func _resolve_ready_casts(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget
) -> BattleSimulationError:
	var casters: Array[BattleEntityState] = []
	for entity: BattleEntityState in state.entities:
		if entity.alive and entity.cast_ability_id != null \
			and entity.cast_resolve_tick <= state.tick:
			casters.append(entity)
	casters.sort_custom(_entity_precedes)
	for caster: BattleEntityState in casters:
		var ability := _ability_rule(rules, caster.cast_ability_id.value)
		var target := _entity_by_optional(state.entities, caster.cast_target_id)
		if ability == null:
			return BattleSimulationError.new(
				BattleSimulationError.INVARIANT_FAILED, &"cast.ability_rule"
			)
		if target == null or not target.alive:
			_append_cast_fizzle(state, caster, ability, &"target_invalid")
			caster.last_main_action_tick = state.tick
			_clear_cast(caster)
			continue
		var payload := CastEventPayload.new()
		payload.ability_id = ability.ability_id
		payload.action = &"resolve"
		payload.resolve_tick = state.tick
		_append_event(state, &"cast", caster.instance_id, [target.instance_id], payload)
		caster.last_main_action_tick = state.tick
		for effect_id: StringName in ability.effect_ids:
			var resolved := _resolve_effect_for_caster(
				state, rules, budget, caster, target, effect_id
			)
			if resolved != null:
				return resolved
		_clear_cast(caster)
	return null

func _resolve_effect_for_caster(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget,
	caster: BattleEntityState,
	target: BattleEntityState,
	effect_id: StringName
) -> BattleSimulationError:
	var rule := _effect_rule(rules, effect_id)
	if rule == null or rule.trigger != &"cast":
		return BattleSimulationError.new(
			BattleSimulationError.EFFECT_FAILED, &"effect_rule", &"EFFECT_RULE_MISSING"
		)
	var sources: Array[EffectSourceState] = []
	for source: EffectSourceState in state.effect_sources:
		if source.effect_id != effect_id:
			continue
		if source.source_instance_id == null \
			or source.source_instance_id.value == caster.instance_id:
			sources.append(source)
	if sources.is_empty():
		return BattleSimulationError.new(
			BattleSimulationError.EFFECT_FAILED, &"effect_source", &"EFFECT_SOURCE_MISSING"
		)
	sources.sort_custom(_source_precedes)
	for source: EffectSourceState in sources:
		var context := EffectContext.new()
		context.tick = state.tick
		context.effect_rule = rule
		context.source_state = source
		context.source_entity = caster if source.source_instance_id != null else null
		context.target_entity = target
		context.ordered_entities = state.entities
		context.status_marker_ids = _status_marker_ids(rules)
		context.summoned_unit_ids = _summoned_unit_ids(rules)
		context.effect_use_count = caster.effect_use_count(effect_id)
		context.budget = budget
		context.rng_snapshot = state.rng_snapshot
		var result := EffectResolver.new().resolve(EffectTrigger.new(&"cast"), context)
		if not result.ok:
			return BattleSimulationError.new(
				BattleSimulationError.EFFECT_FAILED,
				result.error.field_path,
				result.error.code
			)
		budget.effect_count = result.resolution.budget.effect_count
		budget.operation_count = result.resolution.budget.operation_count
		budget.event_count = result.resolution.budget.event_count
		state.rng_snapshot = result.resolution.rng_snapshot.deep_clone()
		if result.resolution.matched:
			var apply_error := _apply_effect_operations(
				state, rules, budget, result.resolution.battle_operations
			)
			if apply_error != null:
				return apply_error
			for proposal: RunMutationProposal in result.resolution.run_effect_intents:
				state.run_mutation_proposals.append(proposal.deep_clone())
			caster.record_effect_use(
				effect_id,
				caster.effect_use_count(effect_id) + result.resolution.use_count_delta
			)
	return null

func _resolve_scheduled_triggers(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget
) -> BattleSimulationError:
	for source: EffectSourceState in state.effect_sources:
		var rule := _effect_rule(rules, source.effect_id)
		if rule == null:
			return BattleSimulationError.new(
				BattleSimulationError.EFFECT_FAILED, &"effect_rule",
				&"EFFECT_RULE_MISSING"
			)
		var trigger := &""
		if state.tick == 1 and rule.trigger == &"battle_start":
			trigger = &"battle_start"
		elif rule.trigger == &"periodic" \
			and state.tick % rule.periodic_interval_ticks == 0:
			trigger = &"periodic"
		if trigger.is_empty():
			continue
		var owner := _entity_by_optional(state.entities, source.source_instance_id)
		if source.source_instance_id != null and (owner == null or not owner.alive):
			continue
		var target := owner
		var resolved := _resolve_effect_source(
			state, rules, budget, trigger, source, owner, target
		)
		if resolved != null:
			return resolved
	return null

func _resolve_entity_trigger(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget,
	trigger: StringName,
	source_entity: BattleEntityState,
	target_entity: BattleEntityState
) -> BattleSimulationError:
	if source_entity == null:
		return null
	for source: EffectSourceState in state.effect_sources:
		if source.source_instance_id == null \
			or source.source_instance_id.value != source_entity.instance_id:
			continue
		var rule := _effect_rule(rules, source.effect_id)
		if rule == null:
			return BattleSimulationError.new(
				BattleSimulationError.EFFECT_FAILED, &"effect_rule",
				&"EFFECT_RULE_MISSING"
			)
		if rule.trigger != trigger:
			continue
		var resolved := _resolve_effect_source(
			state, rules, budget, trigger, source, source_entity, target_entity
		)
		if resolved != null:
			return resolved
	return null

func _resolve_effect_source(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget,
	trigger: StringName,
	source: EffectSourceState,
	source_entity: BattleEntityState,
	target_entity: BattleEntityState
) -> BattleSimulationError:
	var rule := _effect_rule(rules, source.effect_id)
	if rule == null or rule.trigger != trigger:
		return BattleSimulationError.new(
			BattleSimulationError.EFFECT_FAILED, &"effect_rule",
			&"EFFECT_TRIGGER_MISMATCH"
		)
	var use_count := source_entity.effect_use_count(source.effect_id) \
		if source_entity != null else state.global_effect_use_count(
			_effect_source_identity(source), source.effect_id
		)
	var context := EffectContext.new()
	context.tick = state.tick
	context.effect_rule = rule
	context.source_state = source
	context.source_entity = source_entity
	context.target_entity = target_entity
	context.ordered_entities = state.entities
	context.status_marker_ids = _status_marker_ids(rules)
	context.summoned_unit_ids = _summoned_unit_ids(rules)
	context.effect_use_count = use_count
	context.budget = budget
	context.rng_snapshot = state.rng_snapshot
	var result := EffectResolver.new().resolve(EffectTrigger.new(trigger), context)
	if not result.ok:
		return BattleSimulationError.new(
			BattleSimulationError.EFFECT_FAILED,
			result.error.field_path,
			result.error.code
		)
	budget.effect_count = result.resolution.budget.effect_count
	budget.operation_count = result.resolution.budget.operation_count
	budget.event_count = result.resolution.budget.event_count
	state.rng_snapshot = result.resolution.rng_snapshot.deep_clone()
	if not result.resolution.matched:
		return null
	var apply_error := _apply_effect_operations(
		state, rules, budget, result.resolution.battle_operations
	)
	if apply_error != null:
		return apply_error
	for proposal: RunMutationProposal in result.resolution.run_effect_intents:
		state.run_mutation_proposals.append(proposal.deep_clone())
	var updated_count := use_count + result.resolution.use_count_delta
	if source_entity != null:
		source_entity.record_effect_use(source.effect_id, updated_count)
	else:
		state.record_global_effect_use(
			_effect_source_identity(source), source.effect_id, updated_count
		)
	return null

func _effect_source_identity(source: EffectSourceState) -> String:
	return "%s/%s/%s/%010d/%010d" % [
		String(source.source_category), String(source.source_side),
		String(source.source_stable_id), source.source_slot, source.effect_index,
	]

func _apply_effect_operations(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget,
	operations: Array[BattleOperation]
) -> BattleSimulationError:
	var hit_requests: Array[BattleTriggerRequest] = []
	var damaged_requests: Array[BattleTriggerRequest] = []
	var damage_requests: Array[BattleDamageRequest] = []
	for operation: BattleOperation in operations:
		var source := _entity_by_optional(state.entities, operation.source_instance_id)
		var target := _entity_by_optional(state.entities, operation.target_instance_id)
		if operation.kind != &"damage":
			continue
		if target == null:
			return _operation_target_error(operation)
		damage_requests.append(_damage_request(
			state, source, target, operation.amount,
			operation.damage_type, &"effect"
		))
	var outcomes := _apply_damage_wave(state, damage_requests)
	for outcome: BattleDamageOutcome in outcomes:
		var source := _entity_by_optional(
			state.entities, outcome.request.source_instance_id
		)
		var target := _entity_by_id(
			state.entities, outcome.request.target_instance_id
		)
		if source != null and outcome.request.raw_amount > 0:
			hit_requests.append(_trigger_request(&"hit", source, target))
		if outcome.applied_amount > 0:
			damaged_requests.append(_trigger_request(
				&"damaged", target, source
			))
	for operation: BattleOperation in operations:
		if operation.kind == &"damage":
			continue
		var source := _entity_by_optional(state.entities, operation.source_instance_id)
		var target := _entity_by_optional(state.entities, operation.target_instance_id)
		match operation.kind:
			&"heal":
				if target == null:
					return _operation_target_error(operation)
				_apply_heal(state, source, target, operation.amount)
			&"shield":
				if target == null:
					return _operation_target_error(operation)
				_apply_shield(state, target, operation, rules)
			&"modify_stat":
				if target == null:
					return _operation_target_error(operation)
				_apply_modifier(state, target, operation, rules)
			&"apply_status":
				if target == null or operation.status_id == null:
					return _operation_target_error(operation)
				_apply_status(state, target, operation, rules)
			&"remove_status":
				if target == null or operation.status_id == null:
					return _operation_target_error(operation)
				_remove_status(state, target, operation.status_id.value)
			&"grant_mana":
				if target == null:
					return _operation_target_error(operation)
				_grant_mana(state, target, operation.amount, &"effect")
			&"move":
				if source == null:
					return _operation_target_error(operation)
				_apply_effect_move(state, source, operation, rules)
			&"summon":
				if source == null or operation.unit_id == null:
					return _operation_target_error(operation)
				var summon_error := _apply_summon(
					state, source, operation, rules
				)
				if summon_error != null:
					return summon_error
			_:
				return BattleSimulationError.new(
					BattleSimulationError.EFFECT_FAILED,
					&"battle_operation.kind",
					&"EFFECT_OPERATION_UNKNOWN"
				)
	for request: BattleTriggerRequest in hit_requests:
		var hit_error := _resolve_trigger_request(state, rules, budget, request)
		if hit_error != null:
			return hit_error
	damaged_requests.sort_custom(func(
		left: BattleTriggerRequest,
		right: BattleTriggerRequest
	) -> bool:
		return _entity_precedes(
			_entity_by_id(state.entities, left.source_instance_id),
			_entity_by_id(state.entities, right.source_instance_id)
		)
	)
	for request: BattleTriggerRequest in damaged_requests:
		var damaged_error := _resolve_trigger_request(
			state, rules, budget, request
		)
		if damaged_error != null:
			return damaged_error
	return null

func _apply_heal(
	state: BattleState,
	source: BattleEntityState,
	target: BattleEntityState,
	amount: int
) -> void:
	var before := target.health
	target.health = mini(target.max_health, target.health + amount)
	if target.health > 0:
		target.death_pending = false
	var payload := HealEventPayload.new()
	payload.requested = amount
	payload.applied = target.health - before
	payload.health_after = target.health
	_append_event(
		state, &"heal", source.instance_id if source != null else &"",
		[target.instance_id], payload, source != null
	)

func _apply_shield(
	state: BattleState,
	target: BattleEntityState,
	operation: BattleOperation,
	rules: BattleRulesSnapshot
) -> void:
	var timed := _timed_from_operation(operation, &"shield", operation.effect_id, state)
	timed.amount = operation.amount
	timed.stacks = 1
	timed.expires_tick = mini(rules.hard_limit_ticks, state.tick + operation.duration_ticks)
	var action := _stack_timed(target.shields, timed, operation.max_stacks)
	if action == &"none":
		return
	var payload := ShieldEventPayload.new()
	payload.delta = operation.amount
	payload.remaining = _shield_total(target)
	payload.expires_tick = timed.expires_tick
	_append_event(state, &"shield", &"", [target.instance_id], payload, false)

func _apply_modifier(
	state: BattleState,
	target: BattleEntityState,
	operation: BattleOperation,
	rules: BattleRulesSnapshot
) -> void:
	var timed := _timed_from_operation(operation, &"modifier", operation.effect_id, state)
	timed.amount = operation.amount
	timed.stacks = 1
	timed.stat = operation.stat
	timed.mode = operation.mode
	timed.expires_tick = mini(rules.hard_limit_ticks, state.tick + operation.duration_ticks)
	var action := _stack_timed(target.modifiers, timed, operation.max_stacks)
	if action == &"none":
		return
	BattleCombatMath.recompute_effective_stats(target, rules)
	var payload := ModifierEventPayload.new()
	payload.stat = operation.stat
	payload.mode = operation.mode
	payload.amount = operation.amount
	payload.expires_tick = timed.expires_tick
	payload.action = &"apply"
	_append_event(state, &"modifier", &"", [target.instance_id], payload, false)

func _apply_status(
	state: BattleState,
	target: BattleEntityState,
	operation: BattleOperation,
	rules: BattleRulesSnapshot
) -> void:
	var timed := _timed_from_operation(
		operation, &"status", operation.status_id.value, state
	)
	timed.stacks = operation.stacks
	timed.expires_tick = mini(rules.hard_limit_ticks, state.tick + operation.duration_ticks)
	var action := _stack_timed(target.statuses, timed, operation.max_stacks)
	if action == &"none":
		return
	var payload := StatusEventPayload.new()
	payload.status_id = operation.status_id.value
	payload.action = action
	payload.stacks = _status_stacks(target, operation.status_id.value)
	payload.remaining_ticks = maxi(0, timed.expires_tick - state.tick)
	_append_event(state, &"status", &"", [target.instance_id], payload, false)

func _remove_status(
	state: BattleState,
	target: BattleEntityState,
	status_id: StringName
) -> void:
	for index: int in range(target.statuses.size() - 1, -1, -1):
		if target.statuses[index].state_id == status_id:
			target.statuses.remove_at(index)
	var payload := StatusEventPayload.new()
	payload.status_id = status_id
	payload.action = &"remove"
	payload.stacks = 0
	payload.remaining_ticks = 0
	_append_event(state, &"status", &"", [target.instance_id], payload, false)

func _apply_effect_move(
	state: BattleState,
	source: BattleEntityState,
	operation: BattleOperation,
	rules: BattleRulesSnapshot
) -> void:
	var target := _entity_by_optional(state.entities, source.current_target_id)
	var destination := Vector2i(-1, -1)
	if operation.direction == &"forward":
		destination = _pathfinder.forward_step(
			source, state.entities, rules.board_width, rules.board_height
		)
	elif operation.direction == &"toward_target" and target != null:
		destination = _pathfinder.next_step_toward_attack_position(
			source, target, state.entities, rules.board_width, rules.board_height, 0
		)
	elif operation.direction == &"away_from_target" and target != null:
		destination = _pathfinder.away_step(
			source, target, state.entities, rules.board_width, rules.board_height
		)
	if destination.x < 0:
		return
	var payload := MoveEventPayload.new()
	payload.from_y = source.logical_y
	payload.from_x = source.logical_x
	payload.to_y = destination.y
	payload.to_x = destination.x
	source.logical_y = destination.y
	source.logical_x = destination.x
	_append_event(state, &"move", source.instance_id, [], payload)

func _apply_summon(
	state: BattleState,
	source: BattleEntityState,
	operation: BattleOperation,
	rules: BattleRulesSnapshot
) -> BattleSimulationError:
	var template := _summon_template(rules, operation.unit_id.value)
	if template == null:
		return BattleSimulationError.new(
			BattleSimulationError.EFFECT_FAILED,
			&"summon.template",
			&"SUMMON_TEMPLATE_MISSING"
		)
	var request_serial := source.next_summon_request_serial(
		operation.effect_id, operation.operation_index
	)
	operation.primitive_ordinal = request_serial
	var active_from_source := 0
	for existing: BattleEntityState in state.entities:
		if (existing.alive or existing.death_pending) \
			and existing.origin == &"summon" \
			and existing.summoner_instance_id != null \
			and existing.summoner_instance_id.value == source.instance_id \
			and existing.summon_effect_id != null \
			and existing.summon_effect_id.value == operation.effect_id \
			and existing.summon_operation_index == operation.operation_index \
			and existing.unit_id == operation.unit_id.value:
			active_from_source += 1
	if active_from_source >= operation.max_active_per_source:
		_append_summon_failure(state, source, operation, &"max_active")
		return null
	if _active_entity_count(state.entities) >= rules.entity_budget:
		_append_summon_failure(state, source, operation, &"entity_budget")
		return null
	var destination := _adjacent_free_cell(source, state.entities, rules)
	if destination.x < 0:
		_append_summon_failure(state, source, operation, &"no_cell")
		return null
	var id_result := BattleEntityIdCodecV1.new().encode_summon(
		String(_setup.battle_setup_hash).hex_decode(),
		source.instance_id,
		operation.effect_id,
		operation.operation_index,
		request_serial
	)
	if not id_result.ok or _entity_by_id(state.entities, id_result.entity_id) != null:
		return BattleSimulationError.new(
			BattleSimulationError.INVARIANT_FAILED,
			&"summon.instance_id",
			&"SUMMON_ID_COLLISION"
		)
	var entity := BattleEntityState.new()
	entity.instance_id = id_result.entity_id
	entity.unit_id = template.unit_id
	entity.origin = &"summon"
	entity.summoner_instance_id = OptionalStringNameValue.of(source.instance_id)
	entity.summon_effect_id = OptionalStringNameValue.of(operation.effect_id)
	entity.summon_operation_index = operation.operation_index
	entity.side = source.side
	entity.logical_y = destination.y
	entity.logical_x = destination.x
	entity.spawn_y = destination.y
	entity.spawn_x = destination.x
	entity.trait_ids = template.trait_ids.duplicate()
	entity.max_health = template.health
	entity.health = template.health
	entity.base_attack = template.attack
	entity.base_armor = template.armor
	entity.base_magic_resist = template.magic_resist
	entity.base_attack_speed_milli = template.attack_speed_milli
	entity.base_move_speed_milli = template.move_speed_milli
	entity.attack = template.attack
	entity.armor = template.armor
	entity.magic_resist = template.magic_resist
	entity.attack_speed_milli = template.attack_speed_milli
	entity.move_speed_milli = template.move_speed_milli
	entity.attack_range_cells = template.attack_range_cells
	entity.mana = template.start_mana
	entity.max_mana = template.max_mana
	entity.ability_id = template.ability_id.deep_clone() if template.ability_id != null else null
	entity.basic_attack_profile = StringName("basic.%s" % String(template.basic_attack_profile))
	entity.attack_progress = BattleCombatMath.initial_progress(entity.attack_speed_milli, rules)
	entity.move_progress = BattleCombatMath.initial_progress(entity.move_speed_milli, rules)
	for unit_assignment: UnitEffectAssignmentSnapshot in template.unit_effect_assignments:
		var assignment := BattleEffectSnapshot.new()
		assignment.priority = unit_assignment.priority
		assignment.source_category = &"unit"
		assignment.source_side = entity.side
		assignment.source_stable_id = unit_assignment.source_stable_id
		assignment.source_instance_id = OptionalStringNameValue.of(entity.instance_id)
		assignment.effect_index = unit_assignment.effect_index
		assignment.effect_id = unit_assignment.effect_id
		entity.effect_assignments.append(assignment)
	state.entities.append(entity)
	state.entities.sort_custom(_entity_precedes)
	_append_effect_sources(state, entity.effect_assignments)
	state.effect_sources.sort_custom(_source_precedes)
	_append_spawn_event(state, entity)
	return null

func _active_entity_count(entities: Array[BattleEntityState]) -> int:
	var count := 0
	for entity: BattleEntityState in entities:
		if entity.alive or entity.death_pending:
			count += 1
	return count

func _append_summon_failure(
	state: BattleState,
	source: BattleEntityState,
	operation: BattleOperation,
	reason: StringName
) -> void:
	var payload := SummonFailureEventPayload.new()
	payload.unit_id = operation.unit_id.value
	payload.request_ordinal = operation.primitive_ordinal
	payload.reason = reason
	_append_event(state, &"summon_failure", source.instance_id, [], payload)

func _apply_moves(
	state: BattleState,
	proposals: Array[BattleMoveProposal],
	rules: BattleRulesSnapshot
) -> void:
	proposals.sort_custom(_move_precedes)
	var claimed: Dictionary = {}
	var occupied_at_batch_start: Dictionary = {}
	for occupant: BattleEntityState in state.entities:
		if occupant.alive and not occupant.death_pending:
			occupied_at_batch_start["%d:%d" % [
				occupant.logical_y, occupant.logical_x
			]] = String(occupant.instance_id)
	for proposal: BattleMoveProposal in proposals:
		var destination_key := "%d:%d" % [proposal.to_y, proposal.to_x]
		if claimed.has(destination_key):
			continue
		if occupied_at_batch_start.has(destination_key) \
			and String(occupied_at_batch_start[destination_key]) != String(proposal.instance_id):
			continue
		var entity := _entity_by_id(state.entities, proposal.instance_id)
		if entity == null or not entity.alive:
			continue
		var from := Vector2i(proposal.start_x, proposal.start_y)
		var to := Vector2i(proposal.to_x, proposal.to_y)
		if not _pathfinder.can_step(
			from, to, entity.instance_id, state.entities,
			rules.board_width, rules.board_height
		):
			continue
		claimed[destination_key] = true
		entity.logical_y = proposal.to_y
		entity.logical_x = proposal.to_x
		entity.move_progress -= BattleCombatMath.threshold(rules)
		entity.last_main_action_tick = state.tick
		var payload := MoveEventPayload.new()
		payload.from_y = proposal.start_y
		payload.from_x = proposal.start_x
		payload.to_y = proposal.to_y
		payload.to_x = proposal.to_x
		_append_event(state, &"move", entity.instance_id, [], payload)

func _damage_request(
	state: BattleState,
	source: BattleEntityState,
	target: BattleEntityState,
	raw: int,
	damage_type: StringName,
	reason: StringName
) -> BattleDamageRequest:
	var request := BattleDamageRequest.new()
	request.source_instance_id = OptionalStringNameValue.of(source.instance_id) \
		if source != null else null
	request.target_instance_id = target.instance_id
	request.raw_amount = raw
	request.damage_type = damage_type
	request.reason = reason
	request.work_sequence = state.next_work_sequence
	state.next_work_sequence += 1
	return request

func _apply_damage_wave(
	state: BattleState,
	requests: Array[BattleDamageRequest]
) -> Array[BattleDamageOutcome]:
	var outcomes: Array[BattleDamageOutcome] = []
	for request: BattleDamageRequest in requests:
		var target := _entity_by_id(state.entities, request.target_instance_id)
		if target == null:
			continue
		var resistance := target.armor if request.damage_type == &"physical" \
			else target.magic_resist
		var post := BattleCombatMath.post_resistance(
			request.raw_amount, resistance, request.damage_type,
			_setup.inputs.battle_rules
		)
		var shield_absorbed := _absorb_shields(target, post)
		var health_damage := mini(target.health, post - shield_absorbed)
		target.health -= health_damage
		var outcome := BattleDamageOutcome.new()
		outcome.request = request.deep_clone()
		outcome.post_resistance_amount = post
		outcome.shield_absorbed = shield_absorbed
		outcome.health_damage = health_damage
		outcome.applied_amount = shield_absorbed + health_damage
		outcomes.append(outcome)
	for entity: BattleEntityState in state.entities:
		if entity.alive and entity.health <= 0:
			entity.death_pending = true
	for outcome: BattleDamageOutcome in outcomes:
		var request := outcome.request
		var source := _entity_by_optional(state.entities, request.source_instance_id)
		var target := _entity_by_id(state.entities, request.target_instance_id)
		if target == null:
			continue
		if source != null:
			state.record_damage_contribution(
				target.instance_id, source.instance_id, outcome.health_damage
			)
		var payload := DamageEventPayload.new()
		payload.damage_type = request.damage_type
		payload.raw_amount = request.raw_amount
		payload.post_resistance_amount = outcome.post_resistance_amount
		payload.shield_absorbed = outcome.shield_absorbed
		payload.health_damage = outcome.health_damage
		payload.health_after = target.health
		_append_event(
			state, &"damage", source.instance_id if source != null else &"",
			[target.instance_id], payload, source != null
		)
		if source != null and outcome.health_damage > 0:
			var mana_gain := BattleCombatMath.damage_mana(
				outcome.health_damage, target.max_health,
				_setup.inputs.battle_rules
			)
			_grant_mana(state, target, mana_gain, &"damaged")
	return outcomes

func _apply_overtime_batch(state: BattleState, rules: BattleRulesSnapshot) -> void:
	var overtime_index := (state.tick - rules.soft_limit_ticks) \
		/ rules.overtime_interval_ticks + 1
	var living: Array[BattleEntityState] = []
	for entity: BattleEntityState in state.entities:
		if entity.alive and not entity.death_pending:
			living.append(entity)
	living.sort_custom(_entity_precedes)
	var requests: Array[BattleDamageRequest] = []
	for entity: BattleEntityState in living:
		var raw := BattleCombatMath.overtime_damage(
			entity.max_health, overtime_index, rules
		)
		requests.append(_damage_request(
			state, null, entity, raw, &"true", &"overtime"
		))
	_apply_damage_wave(state, requests)

func _process_deaths(
	state: BattleState,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget
) -> BattleSimulationError:
	while true:
		var dying: Array[BattleEntityState] = []
		for candidate: BattleEntityState in state.entities:
			if candidate.alive and candidate.death_pending:
				dying.append(candidate)
		dying.sort_custom(_entity_precedes)
		if dying.is_empty():
			break
		var trigger_requests: Array[BattleTriggerRequest] = []
		for entity: BattleEntityState in dying:
			if not entity.alive or not entity.death_pending:
				continue
			var killer_id := state.killer_for(entity.instance_id)
			var killer := _entity_by_optional(state.entities, killer_id)
			if entity.cast_ability_id != null:
				var ability := _ability_rule(rules, entity.cast_ability_id.value)
				if ability != null:
					_append_cast_fizzle(state, entity, ability, &"caster_death")
				_clear_cast(entity)
			entity.alive = false
			entity.death_pending = false
			if killer != null:
				trigger_requests.append(_trigger_request(
					&"kill", killer, entity
				))
			trigger_requests.append(_trigger_request(
				&"death", entity, killer
			))
			var payload := DeathEventPayload.new()
			payload.origin = entity.origin
			payload.logical_y = entity.logical_y
			payload.logical_x = entity.logical_x
			var targets: Array[StringName] = []
			if killer_id != null:
				targets.append(killer_id.value)
			_append_event(state, &"death", entity.instance_id, targets, payload)
		for request: BattleTriggerRequest in trigger_requests:
			var trigger_error := _resolve_trigger_request(
				state, rules, budget, request
			)
			if trigger_error != null:
				return trigger_error
	for entity: BattleEntityState in state.entities:
		state.clear_damage_contributions(entity.instance_id)
	return null

func _check_boss_phases(state: BattleState) -> void:
	var phases: Array[BossPhaseSnapshot] = []
	for phase: BossPhaseSnapshot in _setup.inputs.encounter_snapshot.boss_phases:
		phases.append(phase.deep_clone())
	phases.sort_custom(func(left: BossPhaseSnapshot, right: BossPhaseSnapshot) -> bool:
		if left.source_instance_id != right.source_instance_id:
			return String(left.source_instance_id) < String(right.source_instance_id)
		return left.phase_index < right.phase_index
	)
	for phase: BossPhaseSnapshot in phases:
		if state.has_triggered_boss_phase(
			phase.source_instance_id, phase.phase_index
		):
			continue
		var source := _entity_by_id(state.entities, phase.source_instance_id)
		if source == null or source.max_health <= 0 \
			or source.health * 10000 > source.max_health * phase.hp_threshold_bps:
			continue
		state.mark_boss_phase_triggered(
			phase.source_instance_id, phase.phase_index
		)
		var payload := BossPhaseEventPayload.new()
		payload.phase_index = phase.phase_index
		payload.hp_threshold_bps = phase.hp_threshold_bps
		_append_event(
			state, &"boss_phase", source.instance_id, [], payload
		)

func _finalize(
	state: BattleState,
	outcome: StringName,
	rules: BattleRulesSnapshot,
	budget: BattleTickBudget
) -> BattleSimulationError:
	for source: EffectSourceState in state.effect_sources:
		var rule := _effect_rule(rules, source.effect_id)
		if rule == null or rule.trigger != &"battle_end":
			continue
		if not rule.battle_operations.is_empty():
			return BattleSimulationError.new(
				BattleSimulationError.EFFECT_FAILED,
				&"battle_end.battle_operations",
				&"EFFECT_OPERATION_INVALID"
			)
		var owner := _entity_by_optional(state.entities, source.source_instance_id)
		var end_error := _resolve_effect_source(
			state, rules, budget, &"battle_end", source, owner, owner
		)
		if end_error != null:
			return end_error
	var survivors: Array[StringName] = []
	for entity: BattleEntityState in state.entities:
		if entity.alive:
			survivors.append(entity.instance_id)
	survivors.sort_custom(_name_less)
	var expedition_damage := _expedition_damage(state, outcome)
	var terminal := BattleFinishedEventPayload.new()
	terminal.outcome = outcome
	terminal.expedition_damage = expedition_damage
	_append_event(state, &"battle_finished", &"", survivors, terminal, false)
	var draft := BattleResultRecord.new()
	draft.battle_setup_hash = _setup.battle_setup_hash
	draft.outcome = outcome
	draft.final_tick = state.tick
	draft.survivor_instance_ids = survivors
	draft.expedition_damage = expedition_damage
	for proposal: RunMutationProposal in state.run_mutation_proposals:
		draft.run_mutation_proposals.append(proposal.deep_clone())
	var finalized := BattleResultFinalizer.new().finalize(
		draft, state.events, _setup.battle_setup_envelope_digest
	)
	if not finalized.ok:
		return BattleSimulationError.new(
			BattleSimulationError.RESULT_FINALIZATION_FAILED,
			finalized.error.field_path,
			finalized.error.code
		)
	_result = BattleResult.from_record(finalized.record)
	_validation_receipt = finalized.receipt.deep_clone()
	_finished = true
	return null

func _outcome(state: BattleState, force: bool) -> StringName:
	var player_alive := false
	var enemy_alive := false
	for entity: BattleEntityState in state.entities:
		if not entity.alive:
			continue
		player_alive = player_alive or entity.side == PLAYER
		enemy_alive = enemy_alive or entity.side == ENEMY
	if not player_alive:
		return &"player_loss"
	if not enemy_alive:
		return &"player_win"
	return &"player_loss" if force else &""

func _expedition_damage(state: BattleState, outcome: StringName) -> int:
	if outcome != &"player_loss":
		return 0
	var rules := _setup.inputs.battle_rules
	var base := rules.act1_base_damage
	if rules.act_index == 2:
		base = rules.act2_base_damage
	elif rules.act_index >= 3:
		base = rules.act3_base_damage
	var encounter_survivors := 0
	for entity: BattleEntityState in state.entities:
		if entity.alive and entity.side == ENEMY and entity.origin == &"encounter":
			encounter_survivors += 1
	return base + encounter_survivors * rules.survivor_damage \
		+ (rules.boss_damage if rules.encounter_kind == &"boss" else 0)

func _select_target(
	mover: BattleEntityState,
	entities: Array[BattleEntityState],
	rules: BattleRulesSnapshot
) -> BattleEntityState:
	var candidates: Array[BattleEntityState] = []
	for target: BattleEntityState in entities:
		if target.alive and not target.death_pending and target.side != mover.side:
			var cost := _pathfinder.path_cost_to_attack_position(
				mover, target, entities, rules.board_width,
				rules.board_height, mover.attack_range_cells
			)
			if cost >= 0:
				candidates.append(target)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left: BattleEntityState, right: BattleEntityState) -> bool:
		var left_cost := _pathfinder.path_cost_to_attack_position(
			mover, left, entities, rules.board_width, rules.board_height,
			mover.attack_range_cells
		)
		var right_cost := _pathfinder.path_cost_to_attack_position(
			mover, right, entities, rules.board_width, rules.board_height,
			mover.attack_range_cells
		)
		if left_cost != right_cost:
			return left_cost < right_cost
		var left_rank := _target_cell_rank(left, rules)
		var right_rank := _target_cell_rank(right, rules)
		if left_rank != right_rank:
			return left_rank < right_rank
		return String(left.instance_id) < String(right.instance_id)
	)
	return candidates[0]

func _target_cell_rank(
	target: BattleEntityState,
	rules: BattleRulesSnapshot
) -> int:
	var row_rank := target.logical_y
	if target.side == PLAYER:
		row_rank = rules.board_height - 1 - target.logical_y
	return row_rank * rules.board_width + target.logical_x

func _ability_target(
	ability: BattleAbilityRuleSnapshot,
	caster: BattleEntityState,
	current_target: BattleEntityState,
	state: BattleState
) -> BattleEntityState:
	match ability.target_rule:
		&"self":
			return caster
		&"current_target", &"nearest_enemy":
			return current_target
		&"random_enemy":
			var enemies: Array[BattleEntityState] = []
			for entity: BattleEntityState in state.entities:
				if entity.alive and not entity.death_pending and entity.side != caster.side:
					enemies.append(entity)
			enemies.sort_custom(_entity_precedes)
			if enemies.is_empty():
				return null
			var stream_result := Pcg32Stream.from_snapshot(state.rng_snapshot)
			if not stream_result.ok:
				return null
			var draw := stream_result.stream.next_bounded(enemies.size())
			if not draw.ok:
				return null
			state.rng_snapshot = draw.next_snapshot.deep_clone()
			return enemies[draw.value_u32.low_u32()]
		&"lowest_health_ally":
			var allies: Array[BattleEntityState] = []
			for entity: BattleEntityState in state.entities:
				if entity.alive and not entity.death_pending and entity.side == caster.side:
					allies.append(entity)
			allies.sort_custom(func(left: BattleEntityState, right: BattleEntityState) -> bool:
				var left_scaled := left.health * right.max_health
				var right_scaled := right.health * left.max_health
				if left_scaled != right_scaled:
					return left_scaled < right_scaled
				return _entity_precedes(left, right)
			)
			return allies[0] if not allies.is_empty() else null
	return null

func _ability_rule(
	rules: BattleRulesSnapshot,
	ability_id: StringName
) -> BattleAbilityRuleSnapshot:
	for rule: BattleAbilityRuleSnapshot in rules.ability_rules:
		if rule.ability_id == ability_id:
			return rule
	return null

func _effect_rule(
	rules: BattleRulesSnapshot,
	effect_id: StringName
) -> BattleEffectRuleSnapshot:
	for rule: BattleEffectRuleSnapshot in rules.effect_rules:
		if rule.effect_id == effect_id:
			return rule
	return null

func _summon_template(
	rules: BattleRulesSnapshot,
	unit_id: StringName
) -> SummonedUnitRuleSnapshot:
	for template: SummonedUnitRuleSnapshot in rules.summoned_unit_templates:
		if template.unit_id == unit_id:
			return template
	return null

func _status_marker_ids(rules: BattleRulesSnapshot) -> Array[StringName]:
	var values: Array[StringName] = []
	for rule: BattleEffectRuleSnapshot in rules.effect_rules:
		for operation: BattleOperationRule in rule.battle_operations:
			if operation.status_id != null and not values.has(operation.status_id.value):
				values.append(operation.status_id.value)
	values.sort_custom(_name_less)
	return values

func _summoned_unit_ids(rules: BattleRulesSnapshot) -> Array[StringName]:
	var values: Array[StringName] = []
	for template: SummonedUnitRuleSnapshot in rules.summoned_unit_templates:
		values.append(template.unit_id)
	values.sort_custom(_name_less)
	return values

func _append_effect_sources(
	state: BattleState,
	assignments: Array[BattleEffectSnapshot]
) -> void:
	for assignment: BattleEffectSnapshot in assignments:
		_append_effect_source(state, assignment)

func _append_effect_source(
	state: BattleState,
	assignment: BattleEffectSnapshot
) -> void:
	if assignment == null:
		return
	var source := EffectSourceState.from_assignment(assignment)
	var owner := _entity_by_optional(state.entities, source.source_instance_id)
	if owner != null:
		source.instantiated_y = owner.logical_y
		source.instantiated_x = owner.logical_x
	source.proposal_source_token = _proposal_source_token(source)
	state.effect_sources.append(source)

func _proposal_source_token(source: EffectSourceState) -> String:
	var codec := ProposalSourceCodecV1.new()
	var result: ProposalSourceResult = null
	match source.source_category:
		&"unit":
			if source.source_instance_id != null \
				and String(source.source_instance_id.value).begins_with("u_"):
				result = codec.player_unit(String(source.source_instance_id.value))
		&"equipment":
			if source.source_instance_id != null:
				result = codec.equipment(
					String(source.source_instance_id.value), source.source_slot
				)
		&"commander":
			result = codec.commander(source.source_stable_id)
		&"relic":
			result = codec.relic(source.source_slot)
		&"trait":
			result = codec.trait_source(source.source_stable_id)
	return result.token.value if result != null and result.ok else ""

func _append_cast_fizzle(
	state: BattleState,
	caster: BattleEntityState,
	ability: BattleAbilityRuleSnapshot,
	reason: StringName
) -> void:
	var payload := CastEventPayload.new()
	payload.ability_id = ability.ability_id
	payload.action = &"fizzle"
	payload.fizzle_reason = reason
	payload.resolve_tick = state.tick
	_append_event(state, &"cast", caster.instance_id, [], payload)

func _clear_cast(entity: BattleEntityState) -> void:
	entity.cast_ability_id = null
	entity.cast_target_id = null
	entity.cast_resolve_tick = -1

func _timed_from_operation(
	operation: BattleOperation,
	kind: StringName,
	state_id: StringName,
	state: BattleState
) -> BattleTimedState:
	var timed := BattleTimedState.new()
	timed.kind = kind
	timed.state_id = state_id
	timed.source_instance_id = operation.source_instance_id.deep_clone() \
		if operation.source_instance_id != null else null
	timed.operation_index = operation.operation_index
	timed.applied_sequence = state.next_work_sequence
	state.next_work_sequence += 1
	timed.stacking = operation.stacking
	return timed

func _stack_timed(
	values: Array[BattleTimedState],
	candidate: BattleTimedState,
	max_stacks: int
) -> StringName:
	return BattleTimedStackResolver.apply(values, candidate, max_stacks)

func _shield_total(target: BattleEntityState) -> int:
	var total := 0
	for shield: BattleTimedState in target.shields:
		total += shield.amount
	return total

func _status_stacks(target: BattleEntityState, status_id: StringName) -> int:
	var total := 0
	for status: BattleTimedState in target.statuses:
		if status.state_id == status_id:
			total += maxi(1, status.stacks)
	return total

func _adjacent_free_cell(
	source: BattleEntityState,
	entities: Array[BattleEntityState],
	rules: BattleRulesSnapshot
) -> Vector2i:
	var start := Vector2i(source.logical_x, source.logical_y)
	for delta: Vector2i in BattlePathfinder.DIRECTIONS:
		var candidate := start + delta
		if candidate.x >= 0 and candidate.x < rules.board_width \
			and candidate.y >= 0 and candidate.y < rules.board_height \
			and not _cell_occupied(candidate, entities):
			return candidate
	return Vector2i(-1, -1)

func _cell_occupied(
	cell: Vector2i,
	entities: Array[BattleEntityState]
) -> bool:
	for entity: BattleEntityState in entities:
		if (entity.alive or entity.death_pending) \
			and entity.logical_x == cell.x and entity.logical_y == cell.y:
			return true
	return false

func _operation_target_error(operation: BattleOperation) -> BattleSimulationError:
	return BattleSimulationError.new(
		BattleSimulationError.EFFECT_FAILED,
		StringName("battle_operation.%d.target" % operation.operation_index),
		&"EFFECT_TARGET_INVALID"
	)

func _expire_timed_states(state: BattleState, rules: BattleRulesSnapshot) -> void:
	for entity: BattleEntityState in state.entities:
		_expire_timed_collection(state, entity, entity.shields, &"shield")
		_expire_timed_collection(state, entity, entity.modifiers, &"modifier")
		_expire_timed_collection(state, entity, entity.statuses, &"status")
		BattleCombatMath.recompute_effective_stats(entity, rules)

func _expire_timed_collection(
	state: BattleState,
	entity: BattleEntityState,
	values: Array[BattleTimedState],
	kind: StringName
) -> void:
	var expired: Array[BattleTimedState] = []
	for value: BattleTimedState in values:
		if value.expires_tick <= state.tick:
			expired.append(value)
	expired.sort_custom(_timed_precedes)
	for value: BattleTimedState in expired:
		values.erase(value)
		var source_id := &"" if value.source_instance_id == null \
			else value.source_instance_id.value
		match kind:
			&"shield":
				var shield := ShieldEventPayload.new()
				shield.delta = -value.amount
				shield.remaining = _shield_total(entity)
				shield.expires_tick = state.tick
				_append_event(
					state, &"shield", source_id, [entity.instance_id],
					shield, value.source_instance_id != null
				)
			&"modifier":
				var modifier := ModifierEventPayload.new()
				modifier.stat = value.stat
				modifier.mode = value.mode
				modifier.amount = value.amount
				modifier.expires_tick = state.tick
				modifier.action = &"expire"
				_append_event(
					state, &"modifier", source_id, [entity.instance_id],
					modifier, value.source_instance_id != null
				)
			&"status":
				var status := StatusEventPayload.new()
				status.status_id = value.state_id
				status.action = &"expire"
				status.stacks = maxi(1, value.stacks)
				status.remaining_ticks = 0
				_append_event(
					state, &"status", source_id, [entity.instance_id],
					status, value.source_instance_id != null
				)

func _absorb_shields(target: BattleEntityState, amount: int) -> int:
	var remaining := amount
	var absorbed := 0
	target.shields.sort_custom(_shield_precedes)
	for shield: BattleTimedState in target.shields:
		if remaining <= 0:
			break
		var used := mini(shield.amount, remaining)
		shield.amount -= used
		remaining -= used
		absorbed += used
	for index: int in range(target.shields.size() - 1, -1, -1):
		if target.shields[index].amount <= 0:
			target.shields.remove_at(index)
	return absorbed

func _grant_mana(
	state: BattleState,
	target: BattleEntityState,
	amount: int,
	reason: StringName
) -> void:
	if amount <= 0 or target.max_mana <= 0 or not target.alive:
		return
	var before := target.mana
	target.mana = mini(target.max_mana, target.mana + amount)
	if target.mana == before:
		return
	var payload := ManaEventPayload.new()
	payload.reason = reason
	payload.delta = target.mana - before
	payload.mana_after = target.mana
	_append_event(state, &"mana", &"", [target.instance_id], payload, false)

func _append_spawn_event(state: BattleState, entity: BattleEntityState) -> void:
	var payload := SpawnEventPayload.new()
	payload.unit_id = entity.unit_id
	payload.side = entity.side
	payload.origin = entity.origin
	payload.logical_y = entity.logical_y
	payload.logical_x = entity.logical_x
	_append_event(state, &"spawn", &"", [entity.instance_id], payload, false)

func _append_attack_event(
	state: BattleState,
	attacker: BattleEntityState,
	target: BattleEntityState
) -> void:
	var payload := AttackEventPayload.new()
	payload.raw_damage = attacker.attack
	payload.presentation_profile = attacker.basic_attack_profile
	_append_event(
		state, &"attack", attacker.instance_id, [target.instance_id], payload
	)

func _append_event(
	state: BattleState,
	type: StringName,
	source_id: StringName,
	target_ids: Array[StringName],
	payload: BattleEventPayload,
	has_source: bool = true
) -> void:
	var event := BattleEvent.new()
	event.tick = state.tick
	event.sequence = state.next_event_sequence
	event.type = type
	event.source_instance_id = OptionalStringNameValue.of(source_id) if has_source else null
	event.target_instance_ids = target_ids.duplicate()
	event.target_instance_ids.sort_custom(_name_less)
	event.payload = payload.deep_clone()
	state.next_event_sequence += 1
	state.events.append(event)

func _entity_by_id(
	entities: Array[BattleEntityState],
	instance_id: StringName
) -> BattleEntityState:
	for entity: BattleEntityState in entities:
		if entity.instance_id == instance_id:
			return entity
	return null

func _entity_by_optional(
	entities: Array[BattleEntityState],
	instance_id: OptionalStringNameValue
) -> BattleEntityState:
	return null if instance_id == null else _entity_by_id(entities, instance_id.value)

func _in_range(left: BattleEntityState, right: BattleEntityState) -> bool:
	return maxi(
		absi(left.logical_y - right.logical_y),
		absi(left.logical_x - right.logical_x)
	) <= left.attack_range_cells

func _entity_precedes(left: BattleEntityState, right: BattleEntityState) -> bool:
	if left.cell_index() != right.cell_index():
		return left.cell_index() < right.cell_index()
	return String(left.instance_id) < String(right.instance_id)

func _spawn_precedes(left: BattleEntityState, right: BattleEntityState) -> bool:
	var left_side := _side_rank(left.side)
	var right_side := _side_rank(right.side)
	if left_side != right_side:
		return left_side < right_side
	return _entity_precedes(left, right)

func _source_precedes(left: EffectSourceState, right: EffectSourceState) -> bool:
	var left_category := _source_category_rank(left.source_category)
	var right_category := _source_category_rank(right.source_category)
	if left_category != right_category:
		return left_category < right_category
	if left.source_category in [&"equipment", &"unit"]:
		var left_side := _side_rank(left.source_side)
		var right_side := _side_rank(right.source_side)
		if left_side != right_side:
			return left_side < right_side
		var left_cell := left.instantiated_y * 8 + left.instantiated_x
		var right_cell := right.instantiated_y * 8 + right.instantiated_x
		if left_cell != right_cell:
			return left_cell < right_cell
		var left_instance := "" if left.source_instance_id == null \
			else String(left.source_instance_id.value)
		var right_instance := "" if right.source_instance_id == null \
			else String(right.source_instance_id.value)
		if left_instance != right_instance:
			return left_instance < right_instance
	if left.source_slot != right.source_slot:
		return left.source_slot < right.source_slot
	if left.source_stable_id != right.source_stable_id:
		return String(left.source_stable_id) < String(right.source_stable_id)
	if left.priority != right.priority:
		return left.priority > right.priority
	if left.effect_id != right.effect_id:
		return String(left.effect_id) < String(right.effect_id)
	return left.effect_index < right.effect_index

func _source_category_rank(category: StringName) -> int:
	var order: Array[StringName] = [
		&"challenge", &"commander", &"relic", &"trait",
		&"encounter_affix", &"equipment", &"unit",
	]
	var index := order.find(category)
	return index if index >= 0 else order.size()

func _side_rank(side: StringName) -> int:
	if side == PLAYER:
		return 0
	if side == ENEMY:
		return 1
	return 2

func _move_precedes(left: BattleMoveProposal, right: BattleMoveProposal) -> bool:
	if left.effective_speed != right.effective_speed:
		return left.effective_speed > right.effective_speed
	var left_cell := left.start_y * 8 + left.start_x
	var right_cell := right.start_y * 8 + right.start_x
	if left_cell != right_cell:
		return left_cell < right_cell
	return String(left.instance_id) < String(right.instance_id)

func _timed_precedes(left: BattleTimedState, right: BattleTimedState) -> bool:
	if left.expires_tick != right.expires_tick:
		return left.expires_tick < right.expires_tick
	return left.applied_sequence < right.applied_sequence

func _shield_precedes(left: BattleTimedState, right: BattleTimedState) -> bool:
	return left.applied_sequence < right.applied_sequence

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _init_failure(code: StringName, path: StringName) -> BattleInitializationResult:
	return BattleInitializationResult.failure(BattleSimulationError.new(code, path))

func _step_failure(code: StringName, path: StringName) -> BattleStepResult:
	return BattleStepResult.failure(BattleSimulationError.new(code, path))

func _enter_failed(error: BattleSimulationError) -> BattleStepResult:
	_failed = true
	return BattleStepResult.failure(error)

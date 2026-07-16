extends GutTest

func test_all_nine_triggers_and_four_stacking_modes_are_accepted() -> void:
	for trigger: StringName in EffectTrigger.VALUES:
		var context := _context(_rule(trigger))
		var result := EffectResolver.new().resolve(EffectTrigger.new(trigger), context)
		assert_true(result.ok, "%s: %s" % [trigger, _error(result)])
		assert_true(result.resolution.matched)
	for stacking: StringName in EffectResolver.STACKING_VALUES:
		var rule := _rule(&"cast")
		rule.stacking = stacking
		var result := EffectResolver.new().resolve(
			EffectTrigger.new(&"cast"), _context(rule)
		)
		assert_true(result.ok, String(stacking))

func test_all_ten_conditions_have_matching_positive_fixture() -> void:
	var conditions: Array[BattleConditionRule] = [
		_condition_stable(&"source_tag", &"source", &"has", &"trait.source"),
		_condition_stable(&"target_tag", &"target", &"has", &"trait.target"),
		_condition_int(&"health_below_bps", &"source", &"lt", 6000),
		_condition_int(&"health_above_bps", &"target", &"gt", 4000),
		_condition_int(&"distance_at_most", &"source_target", &"lte", 2),
		_condition_int(&"distance_at_least", &"source_target", &"gte", 1),
		_condition_stable(&"has_status", &"source", &"has", &"status.test"),
		_condition_stable(&"lacks_status", &"target", &"not_has", &"status.test"),
		_condition_stable(&"has_equipment", &"source", &"has", &"equipment.test"),
		_max_uses_condition(1),
	]
	for condition: BattleConditionRule in conditions:
		var rule := _rule(&"cast")
		rule.conditions.append(condition)
		var result := EffectResolver.new().resolve(
			EffectTrigger.new(&"cast"), _context(rule)
		)
		assert_true(result.ok, "%s: %s" % [condition.kind, _error(result)])
		assert_true(result.resolution.matched, String(condition.kind))

func test_all_nine_battle_operations_produce_typed_atomic_operations() -> void:
	for kind: StringName in EffectResolver.OPERATION_KINDS:
		var rule := _rule(&"cast")
		rule.battle_operations.append(_operation(kind))
		var result := EffectResolver.new().resolve(
			EffectTrigger.new(&"cast"), _context(rule)
		)
		assert_true(result.ok, "%s: %s" % [kind, _error(result)])
		if not result.ok:
			continue
		var expected_count := 2 if kind in [&"move", &"summon"] else 1
		assert_eq(result.resolution.battle_operations.size(), expected_count)
		assert_eq(result.resolution.battle_operations[0].kind, kind)

func test_three_run_intents_are_descriptors_and_do_not_mutate_entities() -> void:
	var rule := _rule(&"battle_end")
	for index: int in range(RunMutationProposal.OPERATION_KINDS.size()):
		var operation := BattleRunOperationRule.new()
		operation.operation_index = index
		operation.kind = RunMutationProposal.OPERATION_KINDS[index]
		operation.amount = index + 1
		operation.claim_scope = &"once_per_node"
		rule.run_operations.append(operation)
	var context := _context(rule)
	var health_before := context.source_entity.health
	var result := EffectResolver.new().resolve(
		EffectTrigger.new(&"battle_end"), context
	)
	assert_true(result.ok, _error(result))
	assert_eq(result.resolution.run_effect_intents.size(), 3)
	assert_eq(context.source_entity.health, health_before)
	for proposal: RunMutationProposal in result.resolution.run_effect_intents:
		assert_true(ProposalSourceCodecV1.new().validate(
			proposal.source_instance_or_slot
		).ok)
		assert_false(proposal.payload_digest.is_empty())

func test_unknown_operation_and_budget_failure_return_no_partial_resolution() -> void:
	var invalid_rule := _rule(&"cast")
	var valid := _operation(&"damage")
	var invalid := BattleOperationRule.new()
	invalid.operation_index = 1
	invalid.kind = &"script_hook"
	var invalid_operations: Array[BattleOperationRule] = [valid, invalid]
	invalid_rule.battle_operations = invalid_operations
	var context := _context(invalid_rule)
	var before := context.budget.deep_clone()
	var rejected := EffectResolver.new().resolve(
		EffectTrigger.new(&"cast"), context
	)
	assert_false(rejected.ok)
	assert_null(rejected.resolution)
	assert_eq(context.budget.effect_count, before.effect_count)
	assert_eq(context.budget.operation_count, before.operation_count)
	var budget_rule := _rule(&"cast")
	budget_rule.battle_operations.append(_operation(&"summon"))
	var budget_context := _context(budget_rule)
	budget_context.budget = BattleTickBudget.new(1, 1, 64, 64)
	var exhausted := EffectResolver.new().resolve(
		EffectTrigger.new(&"cast"), budget_context
	)
	assert_false(exhausted.ok)
	assert_eq(exhausted.error.code, EffectResolverError.BUDGET_EXCEEDED)
	assert_eq(budget_context.budget.operation_count, 0)

func _context(rule: BattleEffectRuleSnapshot) -> EffectContext:
	var source := BattleEntityState.new()
	source.instance_id = &"u_0000000000000001"
	source.unit_id = &"unit.hero"
	source.side = &"player"
	source.logical_y = 3
	source.logical_x = 3
	source.max_health = 100
	source.health = 50
	source.attack = 20
	source.trait_ids = [&"trait.source"]
	source.equipment_ids = [&"equipment.test"]
	var status := BattleTimedState.new()
	status.state_id = &"status.test"
	source.statuses.append(status)
	var target := BattleEntityState.new()
	target.instance_id = &"e_0000000000000001"
	target.unit_id = &"unit.foe"
	target.side = &"enemy"
	target.logical_y = 4
	target.logical_x = 3
	target.max_health = 100
	target.health = 50
	target.trait_ids = [&"trait.target"]
	var source_state := EffectSourceState.new()
	source_state.source_category = &"unit"
	source_state.source_side = &"player"
	source_state.source_stable_id = &"unit.hero"
	source_state.source_instance_id = OptionalStringNameValue.of(source.instance_id)
	source_state.effect_id = rule.effect_id
	source_state.proposal_source_token = "u/u_0000000000000001"
	var context := EffectContext.new()
	context.effect_rule = rule
	context.source_state = source_state
	context.source_entity = source
	context.target_entity = target
	var ordered: Array[BattleEntityState] = [source, target]
	context.ordered_entities = ordered
	context.status_marker_ids = [&"status.test"]
	context.summoned_unit_ids = [&"unit.summon"]
	context.budget = BattleTickBudget.new(64, 64, 64, 64)
	context.rng_snapshot = RngSnapshot.create(
		1, U64Bits.zero(), U64Bits.one(), U64Bits.zero()
	).snapshot
	return context

func _rule(trigger: StringName) -> BattleEffectRuleSnapshot:
	var rule := BattleEffectRuleSnapshot.new()
	rule.effect_id = &"effect.matrix"
	rule.trigger = trigger
	rule.periodic_interval_ticks = 1 if trigger == &"periodic" else 0
	rule.stacking = &"replace"
	rule.max_stacks = 1
	rule.duration_ticks = 1
	return rule

func _operation(kind: StringName) -> BattleOperationRule:
	var operation := BattleOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	match kind:
		&"damage":
			operation.base_amount = 5
			operation.scaling = &"flat"
			operation.damage_type = &"physical"
			operation.target = &"target"
		&"heal":
			operation.base_amount = 5
			operation.scaling = &"flat"
			operation.target = &"self"
		&"shield":
			operation.amount = 5
			operation.duration_ticks = 2
			operation.target = &"self"
		&"modify_stat":
			operation.stat = &"attack"
			operation.mode = &"add"
			operation.amount = 5
			operation.duration_ticks = 2
			operation.target = &"self"
		&"apply_status":
			operation.status_id = OptionalStringNameValue.of(&"status.test")
			operation.stacks = 1
			operation.duration_ticks = 2
			operation.target = &"target"
		&"remove_status":
			operation.status_id = OptionalStringNameValue.of(&"status.test")
			operation.target = &"self"
		&"move":
			operation.direction = &"toward_target"
			operation.cells = 2
		&"summon":
			operation.unit_id = OptionalStringNameValue.of(&"unit.summon")
			operation.count = 2
			operation.max_active_per_source = 2
			operation.placement_rule = &"adjacent"
		&"grant_mana":
			operation.amount = 5
			operation.target = &"self"
	return operation

func _condition_stable(
	kind: StringName,
	subject: StringName,
	comparator: StringName,
	value: StringName
) -> BattleConditionRule:
	var condition := BattleConditionRule.new()
	condition.kind = kind
	condition.subject = subject
	condition.comparator = comparator
	condition.stable_id_value = OptionalStringNameValue.of(value)
	return condition

func _condition_int(
	kind: StringName,
	subject: StringName,
	comparator: StringName,
	value: int
) -> BattleConditionRule:
	var condition := BattleConditionRule.new()
	condition.kind = kind
	condition.subject = subject
	condition.comparator = comparator
	condition.int_value = OptionalIntValue.new(value)
	return condition

func _max_uses_condition(value: int) -> BattleConditionRule:
	var condition := BattleConditionRule.new()
	condition.kind = &"max_uses_per_battle"
	condition.subject = &"effect"
	condition.comparator = &"lt"
	condition.max_uses_per_battle = OptionalIntValue.new(value)
	return condition

func _error(result: EffectResolutionResult) -> String:
	return "%s at %s" % [
		String(result.error.code) if result.error != null else "unknown",
		String(result.error.field_path) if result.error != null else "unknown",
	]

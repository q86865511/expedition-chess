class_name EffectResolver
extends RefCounted

const MAX_I32: int = 2147483647
const CONDITION_KINDS: Array[StringName] = [
	&"source_tag", &"target_tag", &"health_below_bps", &"health_above_bps",
	&"distance_at_most", &"distance_at_least", &"has_status", &"lacks_status",
	&"has_equipment", &"max_uses_per_battle",
]
const OPERATION_KINDS: Array[StringName] = [
	&"damage", &"heal", &"shield", &"modify_stat", &"apply_status", &"remove_status",
	&"move", &"summon", &"grant_mana",
]
const STACKING_VALUES: Array[StringName] = [
	&"replace", &"refresh_duration", &"add_stacks", &"independent",
]
const TARGET_VALUES: Array[StringName] = [&"self", &"target", &"all_allies", &"all_enemies"]
const GLOBAL_CATEGORIES: Array[StringName] = [
	&"challenge", &"commander", &"relic", &"trait", &"encounter_affix",
]

var _stable_ids := StableIdValidator.new()

func resolve(trigger: EffectTrigger, context: EffectContext) -> EffectResolutionResult:
	var input_error := _validate_input(trigger, context)
	if input_error != null:
		return EffectResolutionResult.new(false, null, input_error)
	var budget := context.budget.deep_clone()
	if not budget.take_effect():
		return EffectResolutionResult.failure(
			EffectResolverError.BUDGET_EXCEEDED, &"effect_resolution_budget"
		)
	var resolution := EffectResolution.new()
	resolution.budget = budget
	resolution.rng_snapshot = context.rng_snapshot.deep_clone() if context.rng_snapshot != null else null
	if not _conditions_match(context):
		return EffectResolutionResult.success(resolution)
	resolution.matched = true
	for rule: BattleOperationRule in context.effect_rule.battle_operations:
		var operation_error := _append_battle_operation(rule, context, resolution)
		if operation_error != null:
			return EffectResolutionResult.new(false, null, operation_error)
	for rule: BattleRunOperationRule in context.effect_rule.run_operations:
		if not resolution.budget.take_operations(1):
			return EffectResolutionResult.failure(
				EffectResolverError.BUDGET_EXCEEDED, &"operation_budget"
			)
		var proposal := RunMutationProposal.create(
			rule.claim_scope,
			context.source_state.proposal_source_token,
			context.effect_rule.effect_id,
			rule.operation_index,
			rule.kind,
			rule.amount
		)
		if not proposal.ok:
			return EffectResolutionResult.failure(
				EffectResolverError.RUN_PROPOSAL_SOURCE_INVALID, &"run_operations"
			)
		resolution.run_effect_intents.append(proposal.proposal)
	resolution.use_count_delta = 1
	return EffectResolutionResult.success(resolution)

func _validate_input(trigger: EffectTrigger, context: EffectContext) -> EffectResolverError:
	if trigger == null or context == null or context.effect_rule == null \
		or context.source_state == null or context.budget == null:
		return _error(EffectResolverError.INPUT_INVALID, &"context")
	if not trigger.is_valid():
		return _error(EffectResolverError.TRIGGER_UNKNOWN, &"trigger")
	if not EffectTrigger.VALUES.has(context.effect_rule.trigger):
		return _error(EffectResolverError.TRIGGER_UNKNOWN, &"effect_rule.trigger")
	if trigger.kind != context.effect_rule.trigger:
		return _error(EffectResolverError.TRIGGER_MISMATCH, &"trigger")
	if context.effect_rule.effect_id != context.source_state.effect_id \
		or not _stable_ids.is_valid(context.effect_rule.effect_id):
		return _error(EffectResolverError.INPUT_INVALID, &"effect_rule.effect_id")
	if not STACKING_VALUES.has(context.effect_rule.stacking):
		return _error(EffectResolverError.STACKING_UNKNOWN, &"effect_rule.stacking")
	if context.effect_rule.max_stacks < 1 or context.effect_rule.max_stacks > 99 \
		or context.effect_rule.duration_ticks < 0 or context.effect_rule.duration_ticks > 1800:
		return _error(EffectResolverError.INPUT_INVALID, &"effect_rule.stacking")
	if context.effect_rule.trigger == &"periodic":
		if context.effect_rule.periodic_interval_ticks < 1 \
			or context.effect_rule.periodic_interval_ticks > 1800:
			return _error(EffectResolverError.INPUT_INVALID, &"periodic_interval_ticks")
	elif context.effect_rule.periodic_interval_ticks != 0:
		return _error(EffectResolverError.INPUT_INVALID, &"periodic_interval_ticks")
	var source_error := _validate_source_lifecycle(trigger, context)
	if source_error != null:
		return source_error
	for condition: BattleConditionRule in context.effect_rule.conditions:
		var condition_error := _validate_condition(condition, context)
		if condition_error != null:
			return condition_error
	for rule: BattleOperationRule in context.effect_rule.battle_operations:
		var operation_error := _validate_operation(rule, context)
		if operation_error != null:
			return operation_error
	for rule: BattleRunOperationRule in context.effect_rule.run_operations:
		if not RunMutationProposal.OPERATION_KINDS.has(rule.kind) or rule.amount < 0 \
			or rule.amount > MAX_I32 or not RunMutationProposal.CLAIM_SCOPES.has(rule.claim_scope) \
			or rule.operation_index < 0:
			return _error(EffectResolverError.OPERATION_INVALID, &"run_operations")
	return null

func _validate_source_lifecycle(
	trigger: EffectTrigger,
	context: EffectContext
) -> EffectResolverError:
	var category := context.source_state.source_category
	if not category in GLOBAL_CATEGORIES and not category in [&"unit", &"equipment"]:
		return _error(EffectResolverError.SOURCE_INVALID, &"source_category")
	if not context.source_state.source_side in [&"player", &"enemy", &"system"]:
		return _error(EffectResolverError.SOURCE_INVALID, &"source_side")
	if category in [&"unit", &"equipment"]:
		if context.source_entity == null or context.source_state.source_instance_id == null \
			or context.source_state.source_instance_id.value != context.source_entity.instance_id:
			return _error(EffectResolverError.SOURCE_INVALID, &"source_instance_id")
		if not context.effect_rule.run_operations.is_empty() \
			and context.source_state.proposal_source_token.is_empty():
			return _error(EffectResolverError.RUN_PROPOSAL_SOURCE_INVALID, &"proposal_source_token")
		return null
	if context.source_entity != null or context.source_state.source_instance_id != null:
		return _error(EffectResolverError.SOURCE_INVALID, &"source_instance_id")
	if not trigger.kind in [&"battle_start", &"periodic", &"battle_end"]:
		return _error(EffectResolverError.SOURCE_INVALID, &"trigger")
	if trigger.kind == &"battle_end" and not context.effect_rule.battle_operations.is_empty():
		return _error(EffectResolverError.OPERATION_INVALID, &"battle_operations")
	if (category in [&"challenge", &"encounter_affix"] \
		or context.source_state.source_side == &"enemy") \
		and not context.effect_rule.run_operations.is_empty():
		return _error(EffectResolverError.RUN_PROPOSAL_SOURCE_INVALID, &"run_operations")
	if not context.effect_rule.run_operations.is_empty() \
		and context.source_state.proposal_source_token.is_empty():
		return _error(EffectResolverError.RUN_PROPOSAL_SOURCE_INVALID, &"proposal_source_token")
	for condition: BattleConditionRule in context.effect_rule.conditions:
		if condition.kind != &"max_uses_per_battle":
			return _error(EffectResolverError.CONDITION_INVALID, &"conditions")
	for rule: BattleOperationRule in context.effect_rule.battle_operations:
		if rule.kind in [&"move", &"summon"] or rule.scaling == &"attack" \
			or rule.target in [&"self", &"target"]:
			return _error(EffectResolverError.OPERATION_INVALID, &"battle_operations")
	return null

func _validate_condition(
	condition: BattleConditionRule,
	context: EffectContext
) -> EffectResolverError:
	if condition == null or not CONDITION_KINDS.has(condition.kind):
		return _error(EffectResolverError.CONDITION_UNKNOWN, &"conditions")
	match condition.kind:
		&"source_tag", &"target_tag":
			var expected_subject := &"source" if condition.kind == &"source_tag" else &"target"
			if condition.subject != expected_subject or condition.comparator != &"has" \
				or condition.stable_id_value == null or condition.int_value != null \
				or condition.max_uses_per_battle != null \
				or not _stable_ids.is_valid(condition.stable_id_value.value):
				return _condition_invalid()
		&"health_below_bps", &"health_above_bps":
			var expected_comparator := &"lt" if condition.kind == &"health_below_bps" else &"gt"
			if not condition.subject in [&"source", &"target"] \
				or condition.comparator != expected_comparator or condition.int_value == null \
				or condition.int_value.value < 0 or condition.int_value.value > 10000 \
				or condition.stable_id_value != null or condition.max_uses_per_battle != null:
				return _condition_invalid()
		&"distance_at_most", &"distance_at_least":
			var expected_comparator := &"lte" if condition.kind == &"distance_at_most" else &"gte"
			if condition.subject != &"source_target" or condition.comparator != expected_comparator \
				or condition.int_value == null or condition.int_value.value < 0 \
				or condition.int_value.value > 7 or condition.stable_id_value != null \
				or condition.max_uses_per_battle != null:
				return _condition_invalid()
		&"has_status", &"lacks_status":
			var expected_comparator := &"has" if condition.kind == &"has_status" else &"not_has"
			if not condition.subject in [&"source", &"target"] \
				or condition.comparator != expected_comparator or condition.stable_id_value == null \
				or condition.int_value != null or condition.max_uses_per_battle != null \
				or not context.status_marker_ids.has(condition.stable_id_value.value):
				return _condition_invalid()
		&"has_equipment":
			if not condition.subject in [&"source", &"target"] or condition.comparator != &"has" \
				or condition.stable_id_value == null or condition.int_value != null \
				or condition.max_uses_per_battle != null \
				or not _stable_ids.is_valid(condition.stable_id_value.value):
				return _condition_invalid()
		&"max_uses_per_battle":
			if condition.subject != &"effect" or condition.comparator != &"lt" \
				or condition.max_uses_per_battle == null \
				or condition.max_uses_per_battle.value < 1 \
				or condition.max_uses_per_battle.value > 99 \
				or condition.int_value != null or condition.stable_id_value != null:
				return _condition_invalid()
	return null

func _validate_operation(
	rule: BattleOperationRule,
	context: EffectContext
) -> EffectResolverError:
	if rule == null or not OPERATION_KINDS.has(rule.kind):
		return _error(EffectResolverError.OPERATION_UNKNOWN, &"battle_operations")
	if rule.operation_index < 0:
		return _operation_invalid()
	match rule.kind:
		&"damage":
			if not _damage_or_heal_valid(rule, context) \
				or not rule.damage_type in [&"physical", &"magical", &"true"]:
				return _operation_invalid()
		&"heal":
			if not _damage_or_heal_valid(rule, context):
				return _operation_invalid()
		&"shield":
			if rule.amount < 0 or rule.amount > MAX_I32 or rule.duration_ticks < 1 \
				or rule.duration_ticks > 1800 or not TARGET_VALUES.has(rule.target):
				return _operation_invalid()
		&"modify_stat":
			if not rule.stat in [&"attack", &"armor", &"magic_resist", &"attack_speed_milli", &"move_speed_milli"] \
				or not rule.mode in [&"add", &"multiply_bps"] \
				or (rule.mode == &"multiply_bps" and (rule.amount < 0 or rule.amount > 100000)) \
				or rule.duration_ticks < 1 or rule.duration_ticks > 1800 \
				or not TARGET_VALUES.has(rule.target):
				return _operation_invalid()
		&"apply_status":
			if rule.status_id == null or not context.status_marker_ids.has(rule.status_id.value) \
				or rule.stacks < 1 or rule.stacks > 99 or rule.duration_ticks < 1 \
				or rule.duration_ticks > 1800 or not TARGET_VALUES.has(rule.target):
				return _error(EffectResolverError.STATUS_MARKER_MISSING, &"battle_operations")
		&"remove_status":
			if rule.status_id == null or not context.status_marker_ids.has(rule.status_id.value) \
				or not TARGET_VALUES.has(rule.target):
				return _error(EffectResolverError.STATUS_MARKER_MISSING, &"battle_operations")
		&"move":
			if context.source_entity == null \
				or not rule.direction in [&"forward", &"toward_target", &"away_from_target"] \
				or rule.cells < 1 or rule.cells > 7:
				return _operation_invalid()
		&"summon":
			if context.source_entity == null or rule.unit_id == null \
				or not context.summoned_unit_ids.has(rule.unit_id.value) \
				or rule.count < 1 or rule.count > 64 or rule.max_active_per_source < 1 \
				or rule.max_active_per_source > 64 or rule.placement_rule != &"adjacent":
				return _error(EffectResolverError.SUMMON_TEMPLATE_MISSING, &"battle_operations")
		&"grant_mana":
			if rule.amount < 0 or rule.amount > MAX_I32 or not TARGET_VALUES.has(rule.target):
				return _operation_invalid()
	if rule.kind in [&"damage", &"heal", &"shield", &"modify_stat", &"apply_status", &"remove_status", &"grant_mana"]:
		if rule.target == &"self" and context.source_entity == null:
			return _error(EffectResolverError.TARGET_INVALID, &"battle_operations.target")
		if rule.target == &"target" and context.target_entity == null:
			return _error(EffectResolverError.TARGET_INVALID, &"battle_operations.target")
	return null

func _damage_or_heal_valid(rule: BattleOperationRule, context: EffectContext) -> bool:
	if rule.base_amount < 0 or rule.base_amount > MAX_I32 \
		or not rule.scaling in [&"flat", &"attack"] or not TARGET_VALUES.has(rule.target):
		return false
	if rule.scaling == &"attack":
		return context.source_entity != null and context.source_entity.attack >= 0 \
			and rule.base_amount <= MAX_I32 - context.source_entity.attack
	return true

func _conditions_match(context: EffectContext) -> bool:
	for condition: BattleConditionRule in context.effect_rule.conditions:
		var entity := context.source_entity if condition.subject == &"source" else context.target_entity
		match condition.kind:
			&"source_tag", &"target_tag":
				if entity == null or not entity.trait_ids.has(condition.stable_id_value.value):
					return false
			&"health_below_bps", &"health_above_bps":
				if entity == null or entity.max_health <= 0:
					return false
				var left := entity.health * 10000
				var right := entity.max_health * condition.int_value.value
				if condition.kind == &"health_below_bps" and not left < right:
					return false
				if condition.kind == &"health_above_bps" and not left > right:
					return false
			&"distance_at_most", &"distance_at_least":
				if context.source_entity == null or context.target_entity == null:
					return false
				var distance := maxi(
					absi(context.source_entity.logical_y - context.target_entity.logical_y),
					absi(context.source_entity.logical_x - context.target_entity.logical_x)
				)
				if condition.kind == &"distance_at_most" and distance > condition.int_value.value:
					return false
				if condition.kind == &"distance_at_least" and distance < condition.int_value.value:
					return false
			&"has_status":
				if entity == null or not entity.has_status(condition.stable_id_value.value):
					return false
			&"lacks_status":
				if entity == null or entity.has_status(condition.stable_id_value.value):
					return false
			&"has_equipment":
				if entity == null or not entity.equipment_ids.has(condition.stable_id_value.value):
					return false
			&"max_uses_per_battle":
				if context.effect_use_count >= condition.max_uses_per_battle.value:
					return false
	return true

func _append_battle_operation(
	rule: BattleOperationRule,
	context: EffectContext,
	resolution: EffectResolution
) -> EffectResolverError:
	if rule.kind == &"move":
		if not resolution.budget.take_operations(rule.cells):
			return _error(EffectResolverError.BUDGET_EXCEEDED, &"operation_budget")
		for ordinal: int in range(rule.cells):
			var operation := _base_operation(rule, context, ordinal)
			operation.amount = 1
			operation.direction = rule.direction
			resolution.battle_operations.append(operation)
			resolution.event_proposals.append(_event_proposal(operation))
		return null
	if rule.kind == &"summon":
		if not resolution.budget.take_operations(rule.count):
			return _error(EffectResolverError.BUDGET_EXCEEDED, &"operation_budget")
		for ordinal: int in range(rule.count):
			var operation := _base_operation(rule, context, ordinal)
			operation.unit_id = rule.unit_id.deep_clone()
			operation.max_active_per_source = rule.max_active_per_source
			operation.placement_rule = rule.placement_rule
			resolution.battle_operations.append(operation)
			resolution.event_proposals.append(_event_proposal(operation))
		return null
	var targets := _targets(rule.target, context)
	if not resolution.budget.take_operations(targets.size()):
		return _error(EffectResolverError.BUDGET_EXCEEDED, &"operation_budget")
	for target: BattleEntityState in targets:
		var operation := _base_operation(rule, context, 0)
		operation.target_instance_id = OptionalStringNameValue.of(target.instance_id)
		match rule.kind:
			&"damage", &"heal":
				operation.amount = rule.base_amount
				if rule.scaling == &"attack":
					operation.amount += context.source_entity.attack
				operation.damage_type = rule.damage_type
			&"shield", &"grant_mana":
				operation.amount = rule.amount
				operation.duration_ticks = rule.duration_ticks
			&"modify_stat":
				operation.amount = rule.amount
				operation.stat = rule.stat
				operation.mode = rule.mode
				operation.duration_ticks = rule.duration_ticks
			&"apply_status":
				operation.status_id = rule.status_id.deep_clone()
				operation.stacks = rule.stacks
				operation.duration_ticks = rule.duration_ticks
			&"remove_status":
				operation.status_id = rule.status_id.deep_clone()
		resolution.battle_operations.append(operation)
		resolution.event_proposals.append(_event_proposal(operation))
	return null

func _base_operation(
	rule: BattleOperationRule,
	context: EffectContext,
	ordinal: int
) -> BattleOperation:
	var operation := BattleOperation.new()
	operation.kind = rule.kind
	operation.effect_id = context.effect_rule.effect_id
	operation.operation_index = rule.operation_index
	if context.source_entity != null:
		operation.source_instance_id = OptionalStringNameValue.of(context.source_entity.instance_id)
	operation.stacking = context.effect_rule.stacking
	operation.max_stacks = context.effect_rule.max_stacks
	operation.primitive_ordinal = ordinal
	return operation

func _event_proposal(operation: BattleOperation) -> BattleEventProposal:
	var proposal := BattleEventProposal.new()
	proposal.operation_kind = operation.kind
	proposal.effect_id = operation.effect_id
	proposal.operation_index = operation.operation_index
	proposal.source_instance_id = operation.source_instance_id.deep_clone() if operation.source_instance_id != null else null
	proposal.target_instance_id = operation.target_instance_id.deep_clone() if operation.target_instance_id != null else null
	proposal.primitive_ordinal = operation.primitive_ordinal
	return proposal

func _targets(target_rule: StringName, context: EffectContext) -> Array[BattleEntityState]:
	var values: Array[BattleEntityState] = []
	if target_rule == &"self":
		values.append(context.source_entity)
		return values
	if target_rule == &"target":
		values.append(context.target_entity)
		return values
	for entity: BattleEntityState in context.ordered_entities:
		if entity == null or not entity.alive or entity.death_pending:
			continue
		var same_side := entity.side == context.source_state.source_side
		if (target_rule == &"all_allies" and same_side) \
			or (target_rule == &"all_enemies" and not same_side):
			values.append(entity)
	values.sort_custom(_entity_precedes)
	return values

func _entity_precedes(left: BattleEntityState, right: BattleEntityState) -> bool:
	if left.cell_index() != right.cell_index():
		return left.cell_index() < right.cell_index()
	return String(left.instance_id) < String(right.instance_id)

func _condition_invalid() -> EffectResolverError:
	return _error(EffectResolverError.CONDITION_INVALID, &"conditions")

func _operation_invalid() -> EffectResolverError:
	return _error(EffectResolverError.OPERATION_INVALID, &"battle_operations")

func _error(code: StringName, path: StringName) -> EffectResolverError:
	return EffectResolverError.new(code, path)

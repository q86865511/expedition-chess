class_name EffectContext
extends RefCounted

var tick: int = 0
var effect_rule: BattleEffectRuleSnapshot
var source_state: EffectSourceState
var source_entity: BattleEntityState
var target_entity: BattleEntityState
var ordered_entities: Array[BattleEntityState] = []
var status_marker_ids: Array[StringName] = []
var summoned_unit_ids: Array[StringName] = []
var effect_use_count: int = 0
var budget: BattleTickBudget
var rng_snapshot: RngSnapshot

func deep_clone() -> EffectContext:
	var copied := EffectContext.new()
	copied.tick = tick
	copied.effect_rule = effect_rule.deep_clone() if effect_rule != null else null
	copied.source_state = source_state.deep_clone() if source_state != null else null
	copied.source_entity = source_entity.deep_clone() if source_entity != null else null
	copied.target_entity = target_entity.deep_clone() if target_entity != null else null
	for entity: BattleEntityState in ordered_entities:
		copied.ordered_entities.append(entity.deep_clone())
	copied.status_marker_ids = status_marker_ids.duplicate()
	copied.summoned_unit_ids = summoned_unit_ids.duplicate()
	copied.effect_use_count = effect_use_count
	copied.budget = budget.deep_clone() if budget != null else null
	copied.rng_snapshot = rng_snapshot.deep_clone() if rng_snapshot != null else null
	return copied

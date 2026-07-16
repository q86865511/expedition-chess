class_name BattleEffectSourceAssignmentSnapshot
extends BattleEffectSnapshot

func deep_clone() -> BattleEffectSourceAssignmentSnapshot:
	var copied := BattleEffectSourceAssignmentSnapshot.new()
	copied.priority = priority
	copied.source_category = source_category
	copied.source_side = source_side
	copied.source_stable_id = source_stable_id
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.source_slot = source_slot
	copied.effect_index = effect_index
	copied.effect_id = effect_id
	copied.target_ids = target_ids.duplicate()
	for parameter: BattleIntParam in integer_params:
		copied.integer_params.append(parameter.deep_clone())
	for parameter: BattleIdParam in id_params:
		copied.id_params.append(parameter.deep_clone())
	return copied

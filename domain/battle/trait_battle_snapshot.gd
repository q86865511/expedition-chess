class_name TraitBattleSnapshot
extends RefCounted

var trait_id: StringName = &""
var tier: int = 0
var member_instance_ids: Array[StringName] = []
var effect_assignments: Array[BattleEffectSnapshot] = []

func deep_clone() -> TraitBattleSnapshot:
	var copied := TraitBattleSnapshot.new()
	copied.trait_id = trait_id
	copied.tier = tier
	copied.member_instance_ids = member_instance_ids.duplicate()
	for assignment: BattleEffectSnapshot in effect_assignments:
		copied.effect_assignments.append(assignment.deep_clone())
	return copied

class_name TraitBattleSnapshot
extends RefCounted

var trait_id: StringName = &""
var tier: int = 0
var member_instance_ids: Array[StringName] = []

func deep_clone() -> TraitBattleSnapshot:
	var copied := TraitBattleSnapshot.new()
	copied.trait_id = trait_id
	copied.tier = tier
	copied.member_instance_ids = member_instance_ids.duplicate()
	return copied

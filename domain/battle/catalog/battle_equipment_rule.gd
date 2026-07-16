class_name BattleEquipmentRule
extends RefCounted

var equipment_id: StringName
var stat_modifiers: Array[BattleStatModifierRule] = []
var effect_ids: Array[StringName] = []
var unique_group: OptionalStringNameValue

func deep_clone() -> BattleEquipmentRule:
	var copied := BattleEquipmentRule.new()
	copied.equipment_id = equipment_id
	for modifier: BattleStatModifierRule in stat_modifiers:
		copied.stat_modifiers.append(modifier.deep_clone())
	copied.effect_ids = effect_ids.duplicate()
	copied.unique_group = unique_group.deep_clone() if unique_group != null else null
	return copied

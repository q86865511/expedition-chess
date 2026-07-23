class_name ForgeRecipeRule
extends RefCounted

var equipment_id: StringName
var component_ids: Array[StringName] = []

func deep_clone() -> ForgeRecipeRule:
	var copied := ForgeRecipeRule.new()
	copied.equipment_id = equipment_id
	copied.component_ids = component_ids.duplicate()
	return copied

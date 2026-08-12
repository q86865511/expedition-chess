class_name PrepareUnitInspectionSnapshot
extends RefCounted

## Clone-only presentation DTO composed from one pinned BattleRuleCatalog plus
## the committed roster and UnitStatsPreviewSnapshot projection.

var unit_instance_id: StringName = &""
var unit_id: StringName = &""
var unit_def_id: StringName = &""
var star: int = 0
var cost_tier: int = 0
var trait_ids: Array[StringName] = []
var ability_id: StringName = &""
var ai_profile: StringName = &""
var equipment_instance_ids: Array[String] = []
var stats: UnitStatsPreviewSnapshot


func deep_clone() -> PrepareUnitInspectionSnapshot:
	var clone := PrepareUnitInspectionSnapshot.new()
	clone.unit_instance_id = unit_instance_id
	clone.unit_id = unit_id
	clone.unit_def_id = unit_def_id
	clone.star = star
	clone.cost_tier = cost_tier
	clone.trait_ids.assign(trait_ids)
	clone.ability_id = ability_id
	clone.ai_profile = ai_profile
	clone.equipment_instance_ids.assign(equipment_instance_ids)
	clone.stats = stats.deep_clone() if stats != null else null
	return clone

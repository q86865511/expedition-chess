class_name SummonedUnitRuleSnapshot
extends RefCounted

var unit_id: StringName
var star: int = 1
var trait_ids: Array[StringName] = []
var health: int
var attack: int
var armor: int
var magic_resist: int
var attack_speed_milli: int
var attack_range_cells: int
var start_mana: int
var max_mana: int
var move_speed_milli: int
var ability_id: OptionalStringNameValue
var ai_profile: StringName
var basic_attack_profile: StringName
var unit_effect_assignments: Array[UnitEffectAssignmentSnapshot] = []

func deep_clone() -> SummonedUnitRuleSnapshot:
	var copied := SummonedUnitRuleSnapshot.new()
	copied.unit_id = unit_id
	copied.star = star
	copied.trait_ids = trait_ids.duplicate()
	copied.health = health
	copied.attack = attack
	copied.armor = armor
	copied.magic_resist = magic_resist
	copied.attack_speed_milli = attack_speed_milli
	copied.attack_range_cells = attack_range_cells
	copied.start_mana = start_mana
	copied.max_mana = max_mana
	copied.move_speed_milli = move_speed_milli
	copied.ability_id = ability_id.deep_clone() if ability_id != null else null
	copied.ai_profile = ai_profile
	copied.basic_attack_profile = basic_attack_profile
	for assignment: UnitEffectAssignmentSnapshot in unit_effect_assignments:
		copied.unit_effect_assignments.append(assignment.deep_clone())
	return copied

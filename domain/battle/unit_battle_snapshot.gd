class_name UnitBattleSnapshot
extends RefCounted

var instance_id: StringName = &""
var unit_id: StringName = &""
var side: StringName = &""
var logical_y: int = 0
var logical_x: int = 0
var star: int = 1
var health: int = 0
var attack: int = 0
var armor: int = 0
var magic_resist: int = 0
var attack_speed_milli: int = 0
var attack_range_cells: int = 0
var start_mana: int = 0
var max_mana: int = 0
var move_speed_milli: int = 0
var basic_attack_profile: StringName = &"melee"
var ability_id: OptionalStringNameValue = null
var effect_ids: Array[StringName] = []
var effect_assignments: Array[BattleEffectSnapshot] = []

func deep_clone() -> UnitBattleSnapshot:
	var copied := UnitBattleSnapshot.new()
	copied.instance_id = instance_id
	copied.unit_id = unit_id
	copied.side = side
	copied.logical_y = logical_y
	copied.logical_x = logical_x
	copied.star = star
	copied.health = health
	copied.attack = attack
	copied.armor = armor
	copied.magic_resist = magic_resist
	copied.attack_speed_milli = attack_speed_milli
	copied.attack_range_cells = attack_range_cells
	copied.start_mana = start_mana
	copied.max_mana = max_mana
	copied.move_speed_milli = move_speed_milli
	copied.basic_attack_profile = basic_attack_profile
	copied.ability_id = ability_id.deep_clone() if ability_id != null else null
	copied.effect_ids = effect_ids.duplicate()
	for assignment: BattleEffectSnapshot in effect_assignments:
		copied.effect_assignments.append(assignment.deep_clone())
	return copied

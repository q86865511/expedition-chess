class_name UnitStatsPreviewSnapshot
extends RefCounted

## 備戰期單位屬性預覽（IRH-REQ-016）。欄位與 UnitBattleSnapshot 的屬性段一對一，
## 因為兩者由 BattleSetupSourceCompiler 的同一條星級縮放路徑產生——
## 預覽值即 BattleSimulation 初始化時寫進 BattleEntityState 的 base 值。
## 不含 logical_x/logical_y：備戰席單位沒有格位，預覽不表態站位。

var instance_id: StringName = &""
var unit_id: StringName = &""
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
var equipment_instance_ids: Array[String] = []


func deep_clone() -> UnitStatsPreviewSnapshot:
	var copied := UnitStatsPreviewSnapshot.new()
	copied.instance_id = instance_id
	copied.unit_id = unit_id
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
	copied.equipment_instance_ids = equipment_instance_ids.duplicate()
	return copied

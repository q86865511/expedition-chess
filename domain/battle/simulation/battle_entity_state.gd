class_name BattleEntityState
extends RefCounted

var instance_id: StringName = &""
var unit_id: StringName = &""
var origin: StringName = &""
var summoner_instance_id: OptionalStringNameValue = null
var summon_effect_id: OptionalStringNameValue = null
var summon_operation_index: int = -1
var side: StringName = &""
var logical_y: int = 0
var logical_x: int = 0
var spawn_y: int = 0
var spawn_x: int = 0
var trait_ids: Array[StringName] = []
var equipment_ids: Array[StringName] = []
var max_health: int = 0
var health: int = 0
var base_attack: int = 0
var base_armor: int = 0
var base_magic_resist: int = 0
var base_attack_speed_milli: int = 0
var base_move_speed_milli: int = 0
var attack: int = 0
var armor: int = 0
var magic_resist: int = 0
var attack_speed_milli: int = 0
var move_speed_milli: int = 0
var attack_range_cells: int = 0
var mana: int = 0
var max_mana: int = 0
var ability_id: OptionalStringNameValue = null
var basic_attack_profile: StringName = &"basic.frontline"
var attack_progress: int = 0
var move_progress: int = 0
var last_main_action_tick: int = -1
var current_target_id: OptionalStringNameValue = null
var cast_ability_id: OptionalStringNameValue = null
var cast_target_id: OptionalStringNameValue = null
var cast_resolve_tick: int = -1
var alive: bool = true
var death_pending: bool = false
var shields: Array[BattleTimedState] = []
var modifiers: Array[BattleTimedState] = []
var statuses: Array[BattleTimedState] = []
var effect_assignments: Array[BattleEffectSnapshot] = []
var _effect_use_lookup: Dictionary = {}
var _summon_serial_lookup: Dictionary = {}

func cell_index(width: int = 8) -> int:
	return logical_y * width + logical_x

func has_status(status_id: StringName) -> bool:
	for status: BattleTimedState in statuses:
		if status.state_id == status_id:
			return true
	return false

func effect_use_count(effect_id: StringName) -> int:
	return int(_effect_use_lookup.get(String(effect_id), 0))

func record_effect_use(effect_id: StringName, count: int) -> void:
	_effect_use_lookup[String(effect_id)] = count

func next_summon_request_serial(
	effect_id: StringName,
	operation_index: int
) -> int:
	var key := "%s/%010d" % [String(effect_id), operation_index]
	var serial := int(_summon_serial_lookup.get(key, 0))
	_summon_serial_lookup[key] = serial + 1
	return serial

func deep_clone() -> BattleEntityState:
	var copied := BattleEntityState.new()
	copied.instance_id = instance_id
	copied.unit_id = unit_id
	copied.origin = origin
	copied.summoner_instance_id = summoner_instance_id.deep_clone() \
		if summoner_instance_id != null else null
	copied.summon_effect_id = summon_effect_id.deep_clone() \
		if summon_effect_id != null else null
	copied.summon_operation_index = summon_operation_index
	copied.side = side
	copied.logical_y = logical_y
	copied.logical_x = logical_x
	copied.spawn_y = spawn_y
	copied.spawn_x = spawn_x
	copied.trait_ids = trait_ids.duplicate()
	copied.equipment_ids = equipment_ids.duplicate()
	copied.max_health = max_health
	copied.health = health
	copied.base_attack = base_attack
	copied.base_armor = base_armor
	copied.base_magic_resist = base_magic_resist
	copied.base_attack_speed_milli = base_attack_speed_milli
	copied.base_move_speed_milli = base_move_speed_milli
	copied.attack = attack
	copied.armor = armor
	copied.magic_resist = magic_resist
	copied.attack_speed_milli = attack_speed_milli
	copied.move_speed_milli = move_speed_milli
	copied.attack_range_cells = attack_range_cells
	copied.mana = mana
	copied.max_mana = max_mana
	copied.ability_id = ability_id.deep_clone() if ability_id != null else null
	copied.basic_attack_profile = basic_attack_profile
	copied.attack_progress = attack_progress
	copied.move_progress = move_progress
	copied.last_main_action_tick = last_main_action_tick
	copied.current_target_id = current_target_id.deep_clone() if current_target_id != null else null
	copied.cast_ability_id = cast_ability_id.deep_clone() if cast_ability_id != null else null
	copied.cast_target_id = cast_target_id.deep_clone() if cast_target_id != null else null
	copied.cast_resolve_tick = cast_resolve_tick
	copied.alive = alive
	copied.death_pending = death_pending
	for state: BattleTimedState in shields:
		copied.shields.append(state.deep_clone())
	for state: BattleTimedState in modifiers:
		copied.modifiers.append(state.deep_clone())
	for state: BattleTimedState in statuses:
		copied.statuses.append(state.deep_clone())
	for assignment: BattleEffectSnapshot in effect_assignments:
		copied.effect_assignments.append(assignment.deep_clone())
	copied._effect_use_lookup = _effect_use_lookup.duplicate(true)
	copied._summon_serial_lookup = _summon_serial_lookup.duplicate(true)
	return copied

class_name BalanceBotActSnapshot
extends RefCounted

var act_index: int
var gold: int
var expedition_hp: int
var roster_unit_count: int
var board_unit_count: int
var stable_unit_ids: Array[StringName] = []


func _init(
	p_act_index: int,
	p_gold: int,
	p_expedition_hp: int,
	p_roster_unit_count: int,
	p_board_unit_count: int,
	p_stable_unit_ids: Array[StringName]
) -> void:
	act_index = p_act_index
	gold = p_gold
	expedition_hp = p_expedition_hp
	roster_unit_count = p_roster_unit_count
	board_unit_count = p_board_unit_count
	stable_unit_ids.assign(p_stable_unit_ids)
	stable_unit_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)


func deep_clone() -> BalanceBotActSnapshot:
	return BalanceBotActSnapshot.new(
		act_index, gold, expedition_hp, roster_unit_count,
		board_unit_count, stable_unit_ids
	)


func is_valid() -> bool:
	if act_index < 1 or act_index > 3 or gold < 0 or expedition_hp < 0 \
		or roster_unit_count < 0 or board_unit_count < 0 \
		or board_unit_count > roster_unit_count \
		or stable_unit_ids.size() != roster_unit_count:
		return false
	for unit_id: StringName in stable_unit_ids:
		if unit_id.is_empty():
			return false
	return true


func canonical_token() -> String:
	var ids: Array[String] = []
	for unit_id: StringName in stable_unit_ids:
		ids.append(String(unit_id))
	return "act:%d:%d:%d:%d:%d:%s" % [
		act_index, gold, expedition_hp, roster_unit_count,
		board_unit_count, ",".join(ids),
	]

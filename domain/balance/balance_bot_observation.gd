class_name BalanceBotObservation
extends RefCounted

var gold: int
var level: int
var expedition_hp: int
var act_index: int
var actions: Array[BalanceBotAction] = []


func _init(
	p_gold: int,
	p_level: int,
	p_expedition_hp: int,
	p_act_index: int,
	p_actions: Array[BalanceBotAction]
) -> void:
	gold = p_gold
	level = p_level
	expedition_hp = p_expedition_hp
	act_index = p_act_index
	for action: BalanceBotAction in p_actions:
		actions.append(action.deep_clone() if action != null else null)


func deep_clone() -> BalanceBotObservation:
	return BalanceBotObservation.new(gold, level, expedition_hp, act_index, actions)


func legal_actions() -> Array[BalanceBotAction]:
	var result: Array[BalanceBotAction] = []
	for action: BalanceBotAction in actions:
		if action != null and action.is_legal_for(gold):
			result.append(action.deep_clone())
	return result


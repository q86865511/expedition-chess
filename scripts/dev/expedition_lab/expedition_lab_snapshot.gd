class_name ExpeditionLabSnapshot
extends RefCounted

var act_index: int
var node_index: int
var expedition_hp: int
var gold: int
var phase: StringName
var reward_ready: bool

func _init(
	p_act_index: int,
	p_node_index: int,
	p_expedition_hp: int,
	p_gold: int,
	p_phase: StringName,
	p_reward_ready: bool
) -> void:
	act_index = p_act_index
	node_index = p_node_index
	expedition_hp = p_expedition_hp
	gold = p_gold
	phase = p_phase
	reward_ready = p_reward_ready

func deep_clone() -> ExpeditionLabSnapshot:
	return ExpeditionLabSnapshot.new(
		act_index, node_index, expedition_hp, gold, phase, reward_ready
	)

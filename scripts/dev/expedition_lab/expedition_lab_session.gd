class_name ExpeditionLabSession
extends RefCounted

var _act_index: int = 1
var _node_index: int = 0
var _expedition_hp: int = 100
var _gold: int = 10
var _phase: StringName = &"map"
var _reward_ready: bool = false

func snapshot() -> ExpeditionLabSnapshot:
	return ExpeditionLabSnapshot.new(
		_act_index, _node_index, _expedition_hp, _gold, _phase,
		_reward_ready
	)

func enter_node() -> ExpeditionLabSnapshot:
	if _phase == &"map":
		_node_index += 1
		_gold = mini(99, _gold + 5)
		_phase = &"prepare"
	return snapshot()

func settle_demo(win: bool, boss: bool) -> ExpeditionLabSnapshot:
	if _phase != &"prepare":
		return snapshot()
	if win:
		_phase = &"reward"
		_reward_ready = true
	else:
		_expedition_hp = maxi(0, _expedition_hp - (20 if boss else 10))
		_phase = &"prepare" if boss and _expedition_hp > 0 else &"map"
	return snapshot()

func choose_gold_reward() -> ExpeditionLabSnapshot:
	if _phase == &"reward" and _reward_ready:
		_gold = mini(99, _gold + 3)
		_reward_ready = false
		_phase = &"map"
		if _node_index >= 7:
			_node_index = 0
			_act_index = mini(3, _act_index + 1)
	return snapshot()

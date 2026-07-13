class_name BattleRulesSnapshot
extends RefCounted

var tick_rate: int = 20
var board_width: int = 8
var board_height: int = 8
var soft_limit_ticks: int = 1200
var hard_limit_ticks: int = 1800

func deep_clone() -> BattleRulesSnapshot:
	var copied := BattleRulesSnapshot.new()
	copied.tick_rate = tick_rate
	copied.board_width = board_width
	copied.board_height = board_height
	copied.soft_limit_ticks = soft_limit_ticks
	copied.hard_limit_ticks = hard_limit_ticks
	return copied

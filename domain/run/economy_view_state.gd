class_name EconomyViewState
extends RefCounted

var gold: int
var level: int
var xp: int
var win_streak: int
var loss_streak: int

func _init(p_gold: int, p_level: int, p_xp: int, p_win_streak: int, p_loss_streak: int) -> void:
	gold = p_gold
	level = p_level
	xp = p_xp
	win_streak = p_win_streak
	loss_streak = p_loss_streak

static func from_state(state: EconomyState) -> EconomyViewState:
	return EconomyViewState.new(state.gold, state.level, state.xp, state.win_streak, state.loss_streak)

func deep_clone() -> EconomyViewState:
	return EconomyViewState.new(gold, level, xp, win_streak, loss_streak)

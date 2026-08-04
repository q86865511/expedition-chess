class_name BalanceBotAction
extends RefCounted

enum Kind {
	BUY_UNIT, BUY_XP, REROLL, CHOOSE_NODE, CHOOSE_REWARD, EQUIP, HOLD, SELL_UNIT,
}

var kind: Kind
var stable_id: StringName
var gold_cost: int
var tempo_score: int
var economy_score: int
var synergy_score: int
var legal: bool


func _init(
	p_kind: Kind,
	p_stable_id: StringName,
	p_gold_cost: int,
	p_tempo_score: int,
	p_economy_score: int,
	p_synergy_score: int,
	p_legal: bool = true
) -> void:
	kind = p_kind
	stable_id = p_stable_id
	gold_cost = p_gold_cost
	tempo_score = p_tempo_score
	economy_score = p_economy_score
	synergy_score = p_synergy_score
	legal = p_legal


func deep_clone() -> BalanceBotAction:
	return BalanceBotAction.new(
		kind, stable_id, gold_cost, tempo_score, economy_score, synergy_score, legal
	)


func is_legal_for(gold: int) -> bool:
	return legal and not stable_id.is_empty() and gold_cost >= 0 and gold_cost <= gold

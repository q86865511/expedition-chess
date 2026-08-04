class_name BalanceBotStrategy
extends RefCounted

const TEMPO: StringName = &"tempo"
const ECONOMY: StringName = &"economy"
const SYNERGY: StringName = &"synergy"
const IDS: Array[StringName] = [TEMPO, ECONOMY, SYNERGY]

var strategy_id: StringName


func _init(p_strategy_id: StringName) -> void:
	strategy_id = p_strategy_id


func is_valid() -> bool:
	return IDS.has(strategy_id)


func try_choose_action(observation: BalanceBotObservation) -> BalanceBotAction:
	if not is_valid() or observation == null:
		return null
	var best: BalanceBotAction
	var best_score := -2147483648
	for action: BalanceBotAction in observation.legal_actions():
		var score := _score(action)
		if best == null or score > best_score \
			or (score == best_score and String(action.stable_id) < String(best.stable_id)):
			best = action.deep_clone()
			best_score = score
	return best.deep_clone() if best != null else null


func _score(action: BalanceBotAction) -> int:
	match strategy_id:
		TEMPO:
			return 5 * action.tempo_score + action.economy_score + action.synergy_score
		ECONOMY:
			return action.tempo_score + 5 * action.economy_score + action.synergy_score
		SYNERGY:
			return action.tempo_score + action.economy_score + 5 * action.synergy_score
	return -2147483648

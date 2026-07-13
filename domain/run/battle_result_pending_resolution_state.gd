class_name BattleResultPendingResolutionState
extends ResolutionState

var battle_setup_hash: String
var battle_result: BattleResult

func _init(p_battle_setup_hash: String, p_battle_result: BattleResult) -> void:
	super(Kind.BATTLE_RESULT_PENDING)
	battle_setup_hash = p_battle_setup_hash
	battle_result = p_battle_result.deep_clone()

func deep_clone() -> ResolutionState:
	return BattleResultPendingResolutionState.new(battle_setup_hash, battle_result)

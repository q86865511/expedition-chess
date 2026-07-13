class_name CombatPendingResolutionState
extends ResolutionState

var battle_setup: BattleSetup

func _init(p_battle_setup: BattleSetup) -> void:
	super(Kind.COMBAT_PENDING)
	battle_setup = p_battle_setup.deep_clone()

func deep_clone() -> ResolutionState:
	return CombatPendingResolutionState.new(battle_setup)

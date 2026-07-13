class_name ResolutionState
extends RefCounted

enum Kind { IDLE, COMBAT_PENDING, BATTLE_RESULT_PENDING, REWARD_PENDING }

var kind: Kind

func _init(p_kind: Kind) -> void:
	kind = p_kind

func deep_clone() -> ResolutionState:
	return ResolutionState.new(kind)

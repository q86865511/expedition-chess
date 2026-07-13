class_name RunEvent
extends RefCounted

var target_phase: RunState.RunPhase

func _init(p_target_phase: RunState.RunPhase) -> void:
	target_phase = p_target_phase

func is_concrete() -> bool:
	return false

func apply_to(_draft: RunState) -> CommandApplyResult:
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.ABSTRACT_EVENT, &"event")
	)

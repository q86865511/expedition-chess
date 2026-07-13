class_name IdleResolutionState
extends ResolutionState

func _init() -> void:
	super(Kind.IDLE)

func deep_clone() -> ResolutionState:
	return IdleResolutionState.new()

class_name TestRunEvent
extends RunEvent

var hp_value: int
var reject: bool

func _init(
	p_target_phase: RunState.RunPhase,
	p_hp_value: int = 100,
	p_reject: bool = false
) -> void:
	super(p_target_phase)
	hp_value = p_hp_value
	reject = p_reject

func is_concrete() -> bool:
	return true

func apply_to(draft: RunState) -> CommandApplyResult:
	if reject:
		return CommandApplyResult.failure(
			CommandApplyError.new(CommandApplyError.APPLY_REJECTED, &"test.event")
		)
	draft.expedition_hp = hp_value
	return CommandApplyResult.success(draft)

class_name RunCommand
extends RefCounted

func is_concrete() -> bool:
	return false

func apply_to(_draft: RunState) -> CommandApplyResult:
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.ABSTRACT_COMMAND, &"command")
	)

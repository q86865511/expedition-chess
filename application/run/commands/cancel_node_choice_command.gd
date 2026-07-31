class_name CancelNodeChoiceCommand
extends RunCommand

var _service: CommitNodeChoiceService


func _init(p_service: CommitNodeChoiceService = null) -> void:
	_service = p_service if p_service != null else CommitNodeChoiceService.new()


func is_concrete() -> bool:
	return _service != null


func apply_to(draft: RunState) -> CommandApplyResult:
	var result := _service.cancel(draft)
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(
			&"source_code", String(result.error.code)
		),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(
			CommandApplyError.APPLY_REJECTED,
			result.error.field_path,
			null,
			diagnostics
		)
	)

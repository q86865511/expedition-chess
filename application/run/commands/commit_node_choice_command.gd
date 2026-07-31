class_name CommitNodeChoiceCommand
extends RunCommand

var _choice_set: NodeChoiceSetRule
var _choice_id: StringName
var _catalog: EconomyExpeditionCatalog
var _service: CommitNodeChoiceService


func _init(
	p_choice_set: NodeChoiceSetRule,
	p_choice_id: StringName,
	p_catalog: EconomyExpeditionCatalog = null,
	p_service: CommitNodeChoiceService = null
) -> void:
	_choice_set = p_choice_set.deep_clone() if p_choice_set != null else null
	_choice_id = p_choice_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else CommitNodeChoiceService.new()


func is_concrete() -> bool:
	return _choice_set != null and not _choice_id.is_empty()


func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete():
		return _failure(ExpeditionActionError.INPUT_INVALID, &"choice_id")
	var result := _service.commit(draft, _choice_set, _choice_id, _catalog)
	if result.ok:
		return CommandApplyResult.success(result.run_state)
	return _failure(result.error.code, result.error.field_path)


func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(
			CommandApplyError.APPLY_REJECTED, path, null, diagnostics
		)
	)

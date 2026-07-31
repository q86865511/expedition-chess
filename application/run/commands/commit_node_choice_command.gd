class_name CommitNodeChoiceCommand
extends RunCommand

## design.md §5（:173-178）：command exact 攜帶 NodeChoiceCommitPayload 的十個欄位。
## payload 由呼叫端（presentation）從 committed snapshot 抄下並原樣傳入；本命令
## 只把它交給 CommitNodeChoiceService 逐欄比對，不從 draft 補齊任何缺欄，
## 否則 stale payload 會被靜默修正成合法值。

var _payload: NodeChoiceCommitPayload
var _choice_set: NodeChoiceSetRule
var _catalog: EconomyExpeditionCatalog
var _service: CommitNodeChoiceService


func _init(
	p_payload: NodeChoiceCommitPayload,
	p_choice_set: NodeChoiceSetRule,
	p_catalog: EconomyExpeditionCatalog = null,
	p_service: CommitNodeChoiceService = null
) -> void:
	_payload = p_payload.deep_clone() if p_payload != null else null
	_choice_set = p_choice_set.deep_clone() if p_choice_set != null else null
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else CommitNodeChoiceService.new()


func is_concrete() -> bool:
	return (
		_choice_set != null
		and _catalog != null
		and _payload != null
		and _payload.is_concrete()
	)


func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete():
		return _failure(ExpeditionActionError.INPUT_INVALID, &"payload")
	var result := _service.commit(draft, _payload, _choice_set, _catalog)
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

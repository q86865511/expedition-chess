class_name AcknowledgeNodeChoiceResultCommand
extends RunCommand

## design.md §5（:201-203）：`AcknowledgeNodeChoiceResultCommand(expected_run_id,
## receipt_digest)` 在**另一筆** copy-save-swap transaction 只把 ledger wrapper 的
## result_acknowledged 改 true，不刪 receipt、不改 digest、不碰 resolution/phase。
## commit 交易本身一律留 false，post-commit route failure／reload 才能重播結果。

var _expected_run_id: String
var _receipt_digest: String
var _service: CommitNodeChoiceService


func _init(
	p_expected_run_id: String,
	p_receipt_digest: String,
	p_service: CommitNodeChoiceService = null
) -> void:
	_expected_run_id = p_expected_run_id
	_receipt_digest = p_receipt_digest
	_service = p_service if p_service != null else CommitNodeChoiceService.new()


func is_concrete() -> bool:
	return not _expected_run_id.is_empty() and not _receipt_digest.is_empty()


func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete():
		return _failure(ExpeditionActionError.INPUT_INVALID, &"receipt_digest")
	var result := _service.acknowledge(
		draft, _expected_run_id, _receipt_digest
	)
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

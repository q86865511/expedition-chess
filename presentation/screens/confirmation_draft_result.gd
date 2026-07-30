class_name ConfirmationDraftResult
extends RefCounted

var ok: bool
var draft: ConfirmationDraft
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> ConfirmationDraftResult:
	return ConfirmationDraftResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_draft: ConfirmationDraft = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	draft = p_draft
	error = p_error.deep_clone() if p_error != null else null

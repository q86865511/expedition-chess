class_name ResultsRenderRetryCapabilityResult
extends RefCounted

var ok: bool
var capability: ResultsRenderRetryCapability
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> ResultsRenderRetryCapabilityResult:
	return ResultsRenderRetryCapabilityResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_capability: ResultsRenderRetryCapability = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	capability = p_capability
	error = p_error.deep_clone() if p_error != null else null

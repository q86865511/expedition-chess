class_name PreparedRunResult
extends RefCounted

var ok: bool
var capability: PreparedRunCapability
var error: DiagnosticError


static func success(
	p_capability: PreparedRunCapability
) -> PreparedRunResult:
	return PreparedRunResult.new(true, p_capability, null)


static func failure(p_error: DiagnosticError) -> PreparedRunResult:
	return PreparedRunResult.new(false, null, p_error)


func _init(
	p_ok: bool,
	p_capability: PreparedRunCapability,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, p_capability != null, p_capability == null
	)
	ok = p_ok
	capability = p_capability
	error = p_error.deep_clone() if p_error != null else null

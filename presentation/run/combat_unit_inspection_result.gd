class_name CombatUnitInspectionResult
extends RefCounted

var ok: bool
var snapshot: CombatUnitInspectionSnapshot
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> CombatUnitInspectionResult:
	return CombatUnitInspectionResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_snapshot: CombatUnitInspectionSnapshot = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null

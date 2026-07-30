class_name LiveScreenInspectionPort
extends RefCounted

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _inspect: Callable


func _init(
	p_lease: LiveScreenLease = null,
	p_registry: LiveScreenLeaseRegistry = null,
	p_inspection_source: Variant = null
) -> void:
	_lease = p_lease.deep_clone() if p_lease != null else null
	_registry = p_registry
	if p_inspection_source is Callable:
		_inspect = p_inspection_source
	elif (
		p_inspection_source is Object
		and (p_inspection_source as Object).has_method(
			&"inspect_combat_unit"
		)
	):
		_inspect = Callable(
			p_inspection_source as Object,
			&"inspect_combat_unit"
		)


func inspect_combat_unit(
	unit_serial: int
) -> CombatUnitInspectionResult:
	if not _is_active():
		return CombatUnitInspectionResult.failure(
			DiagnosticError.new(
				SCREEN_NOT_ACTIVE,
				&"error.presentation.screen_not_active"
			)
		)
	var result: Variant = _inspect.call(unit_serial)
	if result is CombatUnitInspectionResult:
		var typed := result as CombatUnitInspectionResult
		return CombatUnitInspectionResult.new(
			typed.ok,
			typed.snapshot,
			typed.error
		)
	return CombatUnitInspectionResult.failure(
		DiagnosticError.new(
			&"INSPECTION_DEPENDENCY_MISSING",
			&"error.presentation.combat_inspection_dependency_missing"
		)
	)


func _is_active() -> bool:
	return (
		_inspect.is_valid()
		and _registry != null
		and _registry.is_active(_lease)
	)

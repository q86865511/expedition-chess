class_name CombatUnitInspectionPresenter
extends RefCounted

const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"
const INSPECTION_DEPENDENCY_MISSING: StringName = \
	&"INSPECTION_DEPENDENCY_MISSING"

var _route_kind: StringName
var _inspect: Callable
var _current: CombatUnitInspectionSnapshot


func _init(
	p_route_kind: StringName = &"",
	p_inspect: Callable = Callable()
) -> void:
	_route_kind = p_route_kind
	_inspect = p_inspect


func select_mouse(unit_serial: int) -> CombatUnitInspectionResult:
	return _select(unit_serial)


func select_keyboard(unit_serial: int) -> CombatUnitInspectionResult:
	return _select(unit_serial)


func current_snapshot() -> CombatUnitInspectionSnapshot:
	return _current.deep_clone() if _current != null else null


func _select(unit_serial: int) -> CombatUnitInspectionResult:
	_current = null
	if _route_kind != &"RUN_COMBAT" or unit_serial <= 0:
		return CombatUnitInspectionResult.failure(
			DiagnosticError.new(
				ACTION_NOT_AVAILABLE,
				&"error.presentation.action_not_available"
			)
		)
	if not _inspect.is_valid():
		return CombatUnitInspectionResult.failure(
			DiagnosticError.new(
				INSPECTION_DEPENDENCY_MISSING,
				&"error.presentation.combat_inspection_dependency_missing"
			)
		)
	var result := _inspect.call(unit_serial) as CombatUnitInspectionResult
	if result == null:
		return CombatUnitInspectionResult.failure(
			DiagnosticError.new(
				INSPECTION_DEPENDENCY_MISSING,
				&"error.presentation.combat_inspection_dependency_missing"
			)
		)
	if not result.ok or result.snapshot == null:
		return CombatUnitInspectionResult.new(false, null, result.error)
	_current = result.snapshot.deep_clone()
	return CombatUnitInspectionResult.new(true, _current, null)

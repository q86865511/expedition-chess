class_name LiveScreenNavigationPort
extends RefCounted

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"
const NAVIGATION_DEPENDENCY_MISSING: StringName = &"NAVIGATION_DEPENDENCY_MISSING"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _navigate: Callable


func _init(
	p_lease: LiveScreenLease = null,
	p_registry: LiveScreenLeaseRegistry = null,
	p_navigate: Callable = Callable()
) -> void:
	_lease = p_lease.deep_clone() if p_lease != null else null
	_registry = p_registry
	_navigate = p_navigate


func navigate(target_route: StringName) -> AppActionResult:
	if _registry == null or not _registry.is_active(_lease):
		return AppActionResult.failure(
			DiagnosticError.new(SCREEN_NOT_ACTIVE, &"error.presentation.screen_not_active")
		)
	if not _navigate.is_valid():
		return AppActionResult.failure(
			DiagnosticError.new(
				NAVIGATION_DEPENDENCY_MISSING,
				&"error.presentation.navigation_dependency_missing"
			)
		)
	var result := _navigate.call(target_route) as AppActionResult
	if result != null:
		return result
	return AppActionResult.failure(
		DiagnosticError.new(
			NAVIGATION_DEPENDENCY_MISSING,
			&"error.presentation.navigation_dependency_missing"
		)
	)

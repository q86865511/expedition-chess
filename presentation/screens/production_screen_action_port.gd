class_name ProductionScreenActionPort
extends RefCounted

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"
const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _actions: Dictionary[StringName, Callable] = {}


func _init(
	lease: LiveScreenLease = null,
	registry: LiveScreenLeaseRegistry = null,
	actions: Dictionary = {}
) -> void:
	_lease = lease.deep_clone() if lease != null else null
	_registry = registry
	for key: Variant in actions.keys():
		var action := actions[key] as Callable
		if action.is_valid():
			_actions[StringName(key)] = action


func invoke(action_id: StringName) -> AppActionResult:
	if _registry == null or not _registry.is_active(_lease):
		return _failure(SCREEN_NOT_ACTIVE)
	if not _actions.has(action_id):
		return _failure(ACTION_NOT_AVAILABLE)
	var result := _actions[action_id].call() as AppActionResult
	return result if result != null else _failure(ACTION_NOT_AVAILABLE)


func action_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_actions.keys())
	result.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return result


func _failure(code: StringName) -> AppActionResult:
	return AppActionResult.failure(
		DiagnosticError.new(
			code,
			StringName("error.presentation.%s" % String(code).to_lower())
		)
	)

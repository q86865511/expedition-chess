class_name ResultsFallbackNavigationPort
extends RefCounted

const NOT_IMPLEMENTED: StringName = &"RESULTS_FALLBACK_NAVIGATION_NOT_IMPLEMENTED"
const UNBOUND: StringName = &"RESULTS_FALLBACK_NAVIGATION_UNBOUND"
const BUSY: StringName = &"RESULTS_FALLBACK_NAVIGATION_BUSY"
const STALE: StringName = &"RESULTS_FALLBACK_NAVIGATION_STALE"
const ACTION_FAILED: StringName = &"RESULTS_FALLBACK_NAVIGATION_ACTION_FAILED"

var _retry_authority: ResultsRenderRetryAuthorityPort
var _snapshot_provider: Callable
var _retry_callback: Callable
var _camp_callback: Callable
var _menu_callback: Callable
var _lease_registry: LiveScreenLeaseRegistry
var _route_generation: int = -1
var _installed_snapshot: ResultsPresentationSnapshot
var _attempt_generation: int = 1
var _single_flight: bool = false
var _begin_root_action: Callable
var _end_root_action: Callable
var _root_action_owned: bool = false


func bind_installed_results(
	retry_authority: ResultsRenderRetryAuthorityPort = null,
	snapshot_provider: Callable = Callable(),
	retry_callback: Callable = Callable(),
	camp_callback: Callable = Callable(),
	menu_callback: Callable = Callable(),
	lease_registry: LiveScreenLeaseRegistry = null,
	route_generation: int = -1,
	snapshot: ResultsPresentationSnapshot = null,
	begin_root_action: Callable = Callable(),
	end_root_action: Callable = Callable()
) -> StringName:
	if (
		retry_authority == null
		or not snapshot_provider.is_valid()
		or not retry_callback.is_valid()
		or lease_registry == null
		or route_generation < 0
		or snapshot == null
		or snapshot.presentation_digest().is_empty()
		or begin_root_action.is_valid() != end_root_action.is_valid()
	):
		return UNBOUND
	_retry_authority = retry_authority
	_snapshot_provider = snapshot_provider
	_retry_callback = retry_callback
	_camp_callback = camp_callback
	_menu_callback = menu_callback
	_lease_registry = lease_registry
	_route_generation = route_generation
	_installed_snapshot = snapshot.deep_clone()
	_begin_root_action = begin_root_action
	_end_root_action = end_root_action
	return &""


func retry_installed() -> AppActionResult:
	# Root ownership must precede every repository/lease operation. The guard
	# remains held through issue, consume, authoritative candidate read, route
	# commit, and all failure cleanup.
	if not _begin_action():
		return _failure(BUSY if _is_bound() else UNBOUND)
	var issued := _retry_authority.issue_retry_capability(
		_installed_snapshot,
		_route_generation,
		_attempt_generation
	)
	if issued == null or not issued.ok or issued.capability == null:
		return _finish_action(_failure(STALE))
	var capability := issued.capability
	var attempt_generation := _attempt_generation
	_attempt_generation += 1
	var consumed := _retry_authority.consume_retry_capability(
		capability,
		_installed_snapshot,
		_route_generation,
		attempt_generation
	)
	if not consumed:
		return _finish_action(_failure(STALE))
	var candidate: Variant = _snapshot_provider.call()
	if (
		not candidate is ResultsPresentationSnapshot
		or candidate.presentation_digest()
			!= _installed_snapshot.presentation_digest()
	):
		return _finish_action(_failure(STALE))
	var routed: Variant = _retry_callback.call(
		(candidate as ResultsPresentationSnapshot).deep_clone(),
		_route_generation
	)
	if not routed is AppActionResult:
		return _finish_action(_failure(ACTION_FAILED))
	return _finish_action(routed as AppActionResult)


func return_to_camp() -> AppActionResult:
	return _call_exit(_camp_callback)


func return_to_menu() -> AppActionResult:
	return _call_exit(_menu_callback)


func _not_implemented_error() -> DiagnosticError:
	return DiagnosticError.new(
		NOT_IMPLEMENTED,
		&"error.presentation.results_fallback_not_implemented"
	)


func update_active_route(
	route_generation: int,
	snapshot: ResultsPresentationSnapshot
) -> void:
	if route_generation < 0 or snapshot == null:
		return
	_route_generation = route_generation
	_installed_snapshot = snapshot.deep_clone()


func _call_exit(callback: Callable) -> AppActionResult:
	if not _begin_action():
		return _failure(BUSY if _is_bound() else UNBOUND)
	if not callback.is_valid():
		_end_action()
		return _failure(UNBOUND)
	var result: Variant = callback.call()
	if result is AppActionResult and result.ok:
		var active := _lease_registry.active_lease()
		if active != null:
			_lease_registry.revoke(active)
		_installed_snapshot = null
	_end_action()
	return (
		result as AppActionResult
		if result is AppActionResult
		else _failure(ACTION_FAILED)
	)


func _begin_action() -> bool:
	if _begin_root_action.is_valid():
		var acquired: Variant = _begin_root_action.call()
		if not bool(acquired):
			return false
		_root_action_owned = true
	if not _is_bound() or _single_flight:
		_release_root_action()
		return false
	_single_flight = true
	return true


func _end_action() -> void:
	_single_flight = false
	_release_root_action()


func _finish_action(result: AppActionResult) -> AppActionResult:
	_end_action()
	return result


func _release_root_action() -> void:
	if _root_action_owned and _end_root_action.is_valid():
		_end_root_action.call()
	_root_action_owned = false


func _is_bound() -> bool:
	var lease := (
		_lease_registry.active_lease()
		if _lease_registry != null
		else null
	)
	return (
		_retry_authority != null
		and _snapshot_provider.is_valid()
		and _retry_callback.is_valid()
		and _installed_snapshot != null
		and lease != null
		and lease.parent_state == AppStateMachine.State.RESULTS
		and lease.route_generation == _route_generation
	)


func _failure(code: StringName) -> AppActionResult:
	return AppActionResult.failure(_error(code))


func _error(code: StringName) -> DiagnosticError:
	return DiagnosticError.new(
		code,
		&"error.presentation.results_fallback_navigation"
	)

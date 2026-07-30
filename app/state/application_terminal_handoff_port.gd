class_name ApplicationTerminalHandoffPort
extends TerminalPresentationHandoffPort

const PRESENTATION_PORT_ALREADY_BOUND: StringName = \
	&"TERMINAL_PRESENTATION_PORT_ALREADY_BOUND"
const HANDOFF_INVALID: StringName = &"TERMINAL_HANDOFF_INVALID"
const HANDOFF_NOT_INSTALLED: StringName = &"TERMINAL_HANDOFF_NOT_INSTALLED"
const INSTALLED_CAPABILITY_NOT_CONSUMED: StringName = \
	&"INSTALLED_RESULTS_CAPABILITY_NOT_CONSUMED"

var _commit_callback: Callable
var _fail_closed_commit_callback: Callable
var _presentation_port: TerminalPresentationHandoffPort
var _installed_capability: InstalledResultsPresentationCapability
var _installed_snapshot: ResultsPresentationSnapshot


func _init(
	p_commit_callback: Callable,
	p_presentation_port: TerminalPresentationHandoffPort = null,
	p_fail_closed_commit_callback: Callable = Callable()
) -> void:
	_commit_callback = p_commit_callback
	_presentation_port = p_presentation_port
	_fail_closed_commit_callback = p_fail_closed_commit_callback


func bind_presentation_port(port: TerminalPresentationHandoffPort) -> StringName:
	if _presentation_port != null:
		return PRESENTATION_PORT_ALREADY_BOUND
	if port == null:
		return HANDOFF_INVALID
	_presentation_port = port
	return &""


func install_application_handoff(
	capability: TerminalSettlementPresentationCapability,
	snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	if (
		not _commit_callback.is_valid()
		or _presentation_port == null
		or _installed_capability != null
		or _installed_snapshot != null
		or capability == null
		or snapshot == null
		or not capability._claim_application_install(snapshot)
	):
		return _failure(HANDOFF_INVALID)
	var route_generation := _prepare_route_generation()
	if route_generation < 0:
		return _failure(HANDOFF_INVALID)
	var installed: AppActionResult = _commit_callback.call(
		capability,
		snapshot.deep_clone()
	)
	if not installed.ok:
		return installed
	_installed_capability = InstalledResultsPresentationCapability.new(
		snapshot.presentation_digest(),
		AppStateMachine.State.RESULTS,
		route_generation
	)
	_installed_snapshot = snapshot.deep_clone()
	return installed


func _install_fail_closed_application_handoff(
	capability: TerminalPostcommitFallbackCapability,
	snapshot: ResultsPresentationSnapshot,
	cause: StringName
) -> AppActionResult:
	if (
		not _fail_closed_commit_callback.is_valid()
		or _presentation_port == null
		or _installed_capability != null
		or _installed_snapshot != null
		or capability == null
		or snapshot == null
		or not capability._claim_application_install(snapshot)
	):
		return _failure(HANDOFF_INVALID)
	var route_generation := _prepare_route_generation()
	if route_generation < 0:
		return _failure(HANDOFF_INVALID)
	var installed: Variant = _fail_closed_commit_callback.call(
		snapshot.deep_clone(),
		cause
	)
	if not installed is AppActionResult or not installed.ok:
		return (
			installed as AppActionResult
			if installed is AppActionResult
			else _failure(HANDOFF_INVALID)
		)
	_installed_capability = InstalledResultsPresentationCapability.new(
		snapshot.presentation_digest(),
		AppStateMachine.State.RESULTS,
		route_generation
	)
	_installed_snapshot = snapshot.deep_clone()
	return installed


func present_installed_handoff() -> AppActionResult:
	if (
		_presentation_port == null
		or _installed_snapshot == null
		or _installed_capability == null
	):
		return _failure(HANDOFF_NOT_INSTALLED)
	var installed_capability := _installed_capability
	var result := _presentation_port.commit_installed_handoff(
		installed_capability,
		_installed_snapshot.deep_clone()
	)
	_installed_capability = null
	_installed_snapshot = null
	if not installed_capability._is_consumed():
		return _failure(INSTALLED_CAPABILITY_NOT_CONSUMED)
	return result


func commit_handoff(
	capability: TerminalSettlementPresentationCapability,
	snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	# R13 split authority is mandatory: callers cannot combine install and
	# presentation or replay a consumed repository proof through this surface.
	return _failure(HANDOFF_INVALID)


func _prepare_route_generation() -> int:
	return (
		_presentation_port.prepare_results_route_generation()
		if _presentation_port != null
		else -1
	)


func _failure(code: StringName) -> AppActionResult:
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(code, &"error.presentation.terminal_handoff")
	)

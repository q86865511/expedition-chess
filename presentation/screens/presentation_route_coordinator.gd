class_name PresentationRouteCoordinator
extends RefCounted

const ROUTE_PARENT_STALE: StringName = &"ROUTE_PARENT_STALE"
const ROUTE_GENERATION_STALE: StringName = &"ROUTE_GENERATION_STALE"
const ROUTE_ALREADY_ACTIVE: StringName = &"ROUTE_ALREADY_ACTIVE"
const ROUTE_SNAPSHOT_STALE: StringName = &"ROUTE_SNAPSHOT_STALE"
const ROUTE_TOKEN_INVALID: StringName = &"ROUTE_TOKEN_INVALID"
const ROUTE_TOKEN_CONSUMED: StringName = &"ROUTE_TOKEN_CONSUMED"
const ROUTE_TARGET_INVALID: StringName = &"ROUTE_TARGET_INVALID"
const ROUTE_NOT_INSTALLED: StringName = &"ROUTE_NOT_INSTALLED"
const ROUTE_ALREADY_INSTALLED: StringName = &"ROUTE_ALREADY_INSTALLED"
const ROUTE_SESSION_STALE: StringName = &"ROUTE_SESSION_STALE"

var _state: PresentationRouteState
var _lease_registry := LiveScreenLeaseRegistry.new()
var _session: RunPresentationSession
var _coordinator_id: StringName
var _next_token_sequence: int = 1
var _issued_tokens: Dictionary[StringName, PresentationSubrouteToken] = {}


func _init() -> void:
	_coordinator_id = StringName("route.coordinator.%d" % _next_coordinator_sequence())


func install_initial(
	parent_state: int,
	route: StringName,
	screen_identity: StringName,
	session: RunPresentationSession = null,
	snapshot_identity: StringName = &""
) -> PresentationRouteResult:
	if _state != null:
		return _failure(ROUTE_ALREADY_INSTALLED)
	if not _route_belongs_to_parent(parent_state, route):
		return _failure(ROUTE_TARGET_INVALID)
	if parent_state == AppStateMachine.State.RUN:
		if session == null or snapshot_identity.is_empty():
			return _failure(ROUTE_SNAPSHOT_STALE)
	else:
		session = null
		snapshot_identity = &""
	_state = PresentationRouteState.new(
		parent_state,
		route,
		1,
		screen_identity,
		snapshot_identity
	)
	_session = session
	_lease_registry.activate(parent_state, _state.route_generation)
	return PresentationRouteResult.success(_state)


func prepare_subroute(
	expected_parent: int,
	expected_generation: int,
	target_route: StringName,
	snapshot_identity: StringName = &""
) -> PresentationSubrouteTokenResult:
	if _state == null:
		return _token_failure(ROUTE_NOT_INSTALLED)
	if expected_parent != _state.parent_state:
		return _token_failure(ROUTE_PARENT_STALE)
	if expected_generation != _state.route_generation:
		return _token_failure(ROUTE_GENERATION_STALE)
	if target_route == _state.route_kind:
		return _token_failure(ROUTE_ALREADY_ACTIVE)
	if not _route_belongs_to_parent(expected_parent, target_route):
		return _token_failure(ROUTE_TARGET_INVALID)
	if expected_parent == AppStateMachine.State.RUN:
		if (
			snapshot_identity.is_empty()
			or snapshot_identity == _state.snapshot_identity
		):
			return _token_failure(ROUTE_SNAPSHOT_STALE)
	var token := PresentationSubrouteToken.new(
		_coordinator_id,
		StringName("route.token.%d" % _next_token_sequence),
		expected_parent,
		expected_generation,
		target_route,
		snapshot_identity
	)
	_next_token_sequence += 1
	_issued_tokens[token._token_id] = token
	return PresentationSubrouteTokenResult.success(token)


func commit_subroute(
	token: PresentationSubrouteToken,
	candidate_screen_identity: StringName,
	session: RunPresentationSession = null
) -> PresentationRouteResult:
	var validation_error := _validate_token(token)
	if not validation_error.is_empty():
		return _failure(validation_error)
	if token._expected_parent == AppStateMachine.State.RUN:
		if token._snapshot_identity.is_empty():
			return _failure(ROUTE_SNAPSHOT_STALE)
		if _session == null:
			return _failure(ROUTE_SESSION_STALE)
		if session != null and session != _session:
			return _failure(ROUTE_SESSION_STALE)
	token._consumed = true
	_issued_tokens.erase(token._token_id)
	var next_generation := _state.route_generation + 1
	_state = PresentationRouteState.new(
		_state.parent_state,
		token._target_route,
		next_generation,
		candidate_screen_identity,
		token._snapshot_identity
	)
	_lease_registry.activate(_state.parent_state, next_generation)
	return PresentationRouteResult.success(_state)


func current_state() -> PresentationRouteState:
	return _state.deep_clone() if _state != null else null


func active_lease() -> LiveScreenLease:
	return _lease_registry.active_lease()


func has_active_run_session() -> bool:
	return _session != null


func lease_is_active(lease: LiveScreenLease) -> bool:
	return _lease_registry.is_active(lease)


func leave_parent(
	expected_parent: int,
	expected_generation: int,
	target_parent: int,
	target_route: StringName,
	candidate_screen_identity: StringName
) -> PresentationRouteResult:
	if _state == null:
		return _failure(ROUTE_NOT_INSTALLED)
	if expected_parent != _state.parent_state:
		return _failure(ROUTE_PARENT_STALE)
	if expected_generation != _state.route_generation:
		return _failure(ROUTE_GENERATION_STALE)
	if target_parent == _state.parent_state:
		return _failure(ROUTE_PARENT_STALE)
	if not _route_belongs_to_parent(target_parent, target_route):
		return _failure(ROUTE_TARGET_INVALID)
	var next_generation := _state.route_generation + 1
	_state = PresentationRouteState.new(
		target_parent,
		target_route,
		next_generation,
		candidate_screen_identity,
		&""
	)
	_lease_registry.activate(target_parent, next_generation)
	if expected_parent == AppStateMachine.State.RUN:
		_session = null
	return PresentationRouteResult.success(_state)


func _validate_token(token: PresentationSubrouteToken) -> StringName:
	if _state == null:
		return ROUTE_NOT_INSTALLED
	if (
		token == null
		or token._coordinator_id != _coordinator_id
		or not _issued_tokens.has(token._token_id)
		or _issued_tokens[token._token_id] != token
	):
		return ROUTE_TOKEN_INVALID
	if token._consumed:
		return ROUTE_TOKEN_CONSUMED
	if token._expected_parent != _state.parent_state:
		return ROUTE_PARENT_STALE
	if token._expected_generation != _state.route_generation:
		return ROUTE_GENERATION_STALE
	if token._target_route == _state.route_kind:
		return ROUTE_ALREADY_ACTIVE
	if not _route_belongs_to_parent(_state.parent_state, token._target_route):
		return ROUTE_TARGET_INVALID
	return &""


func _route_belongs_to_parent(parent_state: int, route: StringName) -> bool:
	match parent_state:
		AppStateMachine.State.MENU:
			return route == &"MENU_MAIN" or route == &"SETTINGS"
		AppStateMachine.State.CAMP:
			return route in [
				&"CAMP_WORLD",
				&"FACILITY_EXPEDITION_GATE",
				&"FACILITY_COMMANDER_HALL",
				&"COLLECTION",
				&"FACILITY_UNLOCK_WORKSHOP",
				&"FACILITY_CHALLENGE_MONUMENT",
			]
		AppStateMachine.State.RUN:
			return route in [
				&"RUN_CONTAINER",
				&"RUN_MAP",
				&"RUN_PREPARE",
				&"RUN_COMBAT",
				&"RUN_REWARD",
			]
		AppStateMachine.State.RESULTS:
			return route == &"RESULTS" or route == &"RESULTS_FALLBACK"
	return false


func _failure(code: StringName) -> PresentationRouteResult:
	return PresentationRouteResult.failure(_error(code))


func _token_failure(code: StringName) -> PresentationSubrouteTokenResult:
	return PresentationSubrouteTokenResult.failure(_error(code))


func _error(code: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, StringName("error.presentation.%s" % String(code).to_lower()))


static var _coordinator_sequence: int = 1


static func _next_coordinator_sequence() -> int:
	var result := _coordinator_sequence
	_coordinator_sequence += 1
	return result

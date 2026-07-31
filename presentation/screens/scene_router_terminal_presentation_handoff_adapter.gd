class_name SceneRouterTerminalPresentationHandoffAdapter
extends TerminalPresentationHandoffPort

const RESULTS_ROUTE: StringName = &"RESULTS"
const RESULTS_FALLBACK: StringName = &"RESULTS_FALLBACK"

var _scene_router: SceneRouterService
var _lease_registry: LiveScreenLeaseRegistry
var _next_route_generation: int = 1
var _prepared_route_generation: int = -1
var _retry_authority: ResultsRenderRetryAuthorityPort
var _snapshot_provider: Callable
var _camp_callback: Callable
var _menu_callback: Callable
var _begin_results_action: Callable
var _end_results_action: Callable
var _staged_context_provider: Callable
var _fallback_navigation := ResultsFallbackNavigationPort.new()


func _init(
	p_scene_router: SceneRouterService,
	p_lease_registry: LiveScreenLeaseRegistry = null,
	p_retry_authority: ResultsRenderRetryAuthorityPort = null,
	p_snapshot_provider: Callable = Callable(),
	p_camp_callback: Callable = Callable(),
	p_menu_callback: Callable = Callable(),
	p_begin_results_action: Callable = Callable(),
	p_end_results_action: Callable = Callable(),
	p_staged_context_provider: Callable = Callable()
) -> void:
	_scene_router = p_scene_router
	_lease_registry = (
		p_lease_registry
		if p_lease_registry != null
		else LiveScreenLeaseRegistry.new()
	)
	_retry_authority = p_retry_authority
	_snapshot_provider = p_snapshot_provider
	_camp_callback = p_camp_callback
	_menu_callback = p_menu_callback
	_begin_results_action = p_begin_results_action
	_end_results_action = p_end_results_action
	_staged_context_provider = p_staged_context_provider


func commit_handoff(
	_capability: TerminalSettlementPresentationCapability,
	_snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	return _fallback(&"TERMINAL_HANDOFF_DIRECT_REJECTED")


func commit_installed_handoff(
	capability: InstalledResultsPresentationCapability,
	snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	var target_generation := _prepared_route_generation
	if (
		_scene_router == null
		or capability == null
		or snapshot == null
		or target_generation < 1
		or not capability._consume(
			snapshot,
			AppStateMachine.State.RESULTS,
			target_generation
		)
	):
		return _fallback(&"TERMINAL_HANDOFF_INVALID")
	_prepared_route_generation = -1
	# Terminal save/application install has already committed. From this point
	# no old RUN writer-capable callback may survive even if both target scenes
	# fail to instantiate or bind.
	_lease_registry.revoke_active()
	var route_snapshot := snapshot.deep_clone()
	var route_error := _scene_router.install_production(
		RESULTS_ROUTE,
		_results_staged_context(RESULTS_ROUTE, route_snapshot)
	)
	var installed_route := RESULTS_ROUTE
	if not route_error.is_empty():
		var fallback_error := _scene_router.install_production(
			RESULTS_FALLBACK,
			_results_staged_context(RESULTS_FALLBACK, route_snapshot)
		)
		if not fallback_error.is_empty():
			return _fallback(fallback_error)
		installed_route = RESULTS_FALLBACK
	_lease_registry.activate(
		AppStateMachine.State.RESULTS,
		target_generation
	)
	_next_route_generation = target_generation + 1
	_bind_navigation(route_snapshot)
	_activate_results_controls(installed_route, route_snapshot)
	return (
		_fallback(route_error)
		if not route_error.is_empty()
		else AppActionResult.success(true)
	)


func active_results_lease() -> LiveScreenLease:
	return _lease_registry.active_lease()


func fallback_navigation_port() -> ResultsFallbackNavigationPort:
	return _fallback_navigation


func prepare_results_route_generation() -> int:
	if _prepared_route_generation > 0:
		return _prepared_route_generation
	var active := _lease_registry.active_lease()
	var active_generation := (
		active.route_generation if active != null else 0
	)
	_prepared_route_generation = maxi(
		_next_route_generation,
		active_generation + 1
	)
	return _prepared_route_generation


func _retry_installed_snapshot(
	snapshot: ResultsPresentationSnapshot,
	expected_route_generation: int
) -> AppActionResult:
	var active := _lease_registry.active_lease()
	if (
		snapshot == null
		or active == null
		or expected_route_generation != active.route_generation
	):
		return _fallback(&"RESULTS_RETRY_GENERATION_STALE")
	var route_error := _scene_router.install_production(
		RESULTS_ROUTE,
		_results_staged_context(RESULTS_ROUTE, snapshot.deep_clone())
	)
	if not route_error.is_empty():
		return _fallback(route_error)
	var committed_generation := maxi(
		_next_route_generation,
		expected_route_generation + 1
	)
	_lease_registry.activate(
		AppStateMachine.State.RESULTS,
		committed_generation
	)
	_next_route_generation = committed_generation + 1
	_fallback_navigation.update_active_route(committed_generation, snapshot)
	_activate_results_controls(RESULTS_ROUTE, snapshot)
	return AppActionResult.success(false)


func _bind_navigation(snapshot: ResultsPresentationSnapshot) -> void:
	var active := _lease_registry.active_lease()
	var route_generation := (
		active.route_generation if active != null else -1
	)
	_fallback_navigation.bind_installed_results(
		_retry_authority,
		_snapshot_provider,
		_retry_installed_snapshot,
		_camp_callback,
		_menu_callback,
		_lease_registry,
		route_generation,
		snapshot,
		_begin_results_action,
		_end_results_action
	)


func _fallback(source_code: StringName) -> AppActionResult:
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(
			source_code if not source_code.is_empty() else RESULTS_FALLBACK,
			&"error.presentation.results_fallback"
		)
	)


func _activate_results_controls(
	route_kind: StringName,
	snapshot: ResultsPresentationSnapshot
) -> void:
	var host := _scene_router.presentation_host()
	if host == null or host.get_child_count() != 1:
		return
	var screen := host.get_child(0) as ProductionScreen
	var lease := _lease_registry.active_lease()
	if screen == null or lease == null or screen.route_kind != route_kind:
		return
	var actions: Dictionary = {
		&"results.retry": Callable(self, "_retry_action"),
		&"results.camp": Callable(self, "_camp_action"),
		&"results.menu": Callable(self, "_menu_action"),
	}
	var live := ProductionLiveScreenContext.new(
		route_kind,
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, _lease_registry, actions)
	)
	if screen.prepare_live_binding(live).is_empty():
		screen.activate_live()


func _retry_action() -> AppActionResult:
	return _fallback_navigation.retry_installed()


func _camp_action() -> AppActionResult:
	return _fallback_navigation.return_to_camp()


func _menu_action() -> AppActionResult:
	return _fallback_navigation.return_to_menu()


func _results_staged_context(
	route_kind: StringName,
	snapshot: ResultsPresentationSnapshot
) -> StagedScreenContext:
	if _staged_context_provider.is_valid():
		var provided := _staged_context_provider.call(
			route_kind,
			snapshot.deep_clone()
		) as StagedScreenContext
		if provided != null and provided.route_kind == route_kind:
			return provided
	# 正常路徑的 staged context 由 AppRoot 提供（其文案來源已是正式 catalog，
	# review N3）；只有 provider 失效／route 不符的降級路徑會走到這裡，
	# 用 restricted 退路目錄保證結算畫面仍有字可顯示。
	var localized: Dictionary = {}
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for key: StringName in catalog.keys_for_locale(&"zh_TW"):
		var resolved := catalog.resolve(&"zh_TW", key)
		if resolved.ok:
			localized[key] = resolved.value
	return StagedScreenContext.new(
		route_kind,
		snapshot,
		null,
		&"zh_TW",
		localized
	)

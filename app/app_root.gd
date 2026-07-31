class_name ApplicationRoot
extends Node

## S5 T11（specs/meta-progression/design.md §4.4）：正式 composition root。
## boot 先安裝內容（wave5 修正 A1：存檔解碼要靠 registry 的 receipt port），再以
## `SaveRepository.load()` 分流——`RunStatus.LOADED` 就接回 active run
## （RunSession 取 catalog lease ＋ RunController ＋ RunCommandFactory，
## `transition_after_active_run_load` → RUN）；否則 BOOT→MENU→CAMP，掛 CampController
## ＋ CampViewModel ＋ Camp 灰盒（存檔不存在時先建初始 profile 並落檔，wave5 修正 A2）。
## `SceneRouter` 依 app state 與 clone-only snapshot 安裝 `scenes/production/` 的正式 shell；
## 唯一保留的 dev route 是明示 `--combat-lab` CLI。
##
## 內容安裝只經 ProjectContentBootstrap；production root 不依賴 dev bootstrap。

signal boot_completed
signal boot_failed(error_code: StringName)
signal exit_requested

const COMBAT_LAB_SCENE_PATH: String = "res://scenes/dev/combat_lab/combat_lab.tscn"

## 單槽 profile 的固定 id：RunStateValidator 要求 32 位小寫 hex
## （run_state_validator.gd:8 的 _PROFILE_PATTERN），故不是 "profile.default" 這種 stable id。
## S5 明確不做多槽，全域只有這一個 profile。
const DEFAULT_PROFILE_ID: String = "00000000000000000000000000000001"
const DEFAULT_SETTINGS_REF: StringName = &"settings.default"

const ERROR_CONTENT_UNAVAILABLE: StringName = &"APP_CONTENT_UNAVAILABLE"
const ERROR_CAMP_UNAVAILABLE: StringName = &"APP_CAMP_UNAVAILABLE"
const ERROR_COMMANDER_UNKNOWN: StringName = &"APP_COMMANDER_UNKNOWN"
const ERROR_STATE_INVALID: StringName = &"APP_STATE_INVALID"
const ERROR_PROFILE_BOOTSTRAP_FAILED: StringName = &"APP_PROFILE_BOOTSTRAP_FAILED"
const ERROR_SERVICE_BIND_TOO_LATE: StringName = &"APP_SERVICE_BIND_TOO_LATE"
## _try_compose_active_run() 的具名失敗碼（wave5 修正 B3：世代不符與其餘組裝失敗必須可區分）。
const ERROR_RUN_INPUT_INVALID: StringName = &"APP_RUN_INPUT_INVALID"
const ERROR_RUN_GENERATION_MISMATCH: StringName = &"APP_RUN_GENERATION_MISMATCH"
const ERROR_RUN_SESSION_UNAVAILABLE: StringName = &"APP_RUN_SESSION_UNAVAILABLE"
const ERROR_RUN_MODIFIER_TABLE_FAILED: StringName = &"APP_RUN_MODIFIER_TABLE_FAILED"
const ERROR_RUN_BATTLE_CATALOG_FAILED: StringName = &"APP_RUN_BATTLE_CATALOG_FAILED"
const ERROR_RUN_CHALLENGE_AFFIX_FAILED: StringName = &"APP_RUN_CHALLENGE_AFFIX_FAILED"
const ERROR_ACTION_NOT_AVAILABLE: StringName = &"APP_ACTION_NOT_AVAILABLE"
const ERROR_EXIT_ALREADY_PENDING: StringName = &"EXIT_REQUEST_ALREADY_PENDING"
const ERROR_RETAINED_RUN_EXISTS: StringName = &"APP_RETAINED_RUN_EXISTS"
const ERROR_PREPARED_RUN_STALE: StringName = &"APP_PREPARED_RUN_STALE"
const ERROR_RUN_SNAPSHOT_UNAVAILABLE: StringName = &"APP_RUN_SNAPSHOT_UNAVAILABLE"
const ERROR_RUN_PHASE_INVALID: StringName = &"APP_RUN_PHASE_INVALID"
const ERROR_SETTINGS_RUNTIME_MISSING: StringName = &"APP_SETTINGS_RUNTIME_MISSING"
const ERROR_SETTINGS_REBUILD_FAILED: StringName = &"APP_SETTINGS_REBUILD_FAILED"
const RESULTS_ACTION_IN_PROGRESS: StringName = &"RESULTS_ACTION_IN_PROGRESS"
const ERROR_ROUTE_PREPARE_INVALID: StringName = &"APP_ROUTE_PREPARE_INVALID"
const ERROR_ROUTE_ACTIVATION_INVALID: StringName = \
	&"APP_ROUTE_ACTIVATION_INVALID"
const ERROR_CAMP_EXPEDITION_SELECTION_REQUIRED: StringName = \
	&"CAMP_EXPEDITION_SELECTION_REQUIRED"

@onready var presentation_host: Control = _resolve_presentation_host()

var _booted: bool = false
var _app_state_machine: AppStateMachine = AppStateMachine.new()
var _run_session: RunSession
var _run_controller: RunController
var _run_command_factory: RunCommandFactory
var _run_lab_session: RunLabSession
var _run_presentation_session: RunPresentationSession
var _camp_controller: CampController
var _camp_view_model: CampViewModel
var _camp_profile_snapshot: ProfileState
var _content_registry: ContentRegistryService
var _save_repository: SaveRepository
var _scene_router: SceneRouterService
var _services_bound: bool = false
var _content: ProjectContentBootstrapResult
var _content_bootstrap: ProjectContentBootstrap
var _content_bootstrap_result: ProjectContentBootstrapResult
var _content_attempted: bool = false
## 只有「持久化 active run 載入成功，但 production composition 失敗」才設定。
## 玩家明示棄置時同時作為 compare-and-clear 的 expected_run_id。
var _unresumable_run_id: String = ""
var _run_preparation_service: RunPreparationService
var _prepared_run_capability: PreparedRunCapability
var _retained_run_recovery_token: RetainedRunRecoveryToken
var _retained_run_recovery_service: RetainedRunRecoveryService
var _menu_snapshot: MainMenuSnapshot = MainMenuSnapshot.new()
var _exit_request_pending: bool = false
var _terminal_settlement_coordinator: TerminalSettlementCoordinator
var _terminal_presentation_snapshot: ResultsPresentationSnapshot
var _terminal_route_handoff_port: TerminalPresentationHandoffPort
var _settings_application: SettingsApplicationPort
var _settings_repository_override: Object
var _settings_audio_override: AudioCoordinator
var _settings_repository_runtime: Object
## review N3：正式 localization catalog 的補注入對象（boot 期先建、內容載好後綁）。
var _settings_runtime_consumer: PresentationSettingsRuntimeConsumer
var _live_lease_registry := LiveScreenLeaseRegistry.new()
var _route_generation: int = 0
var _active_route_kind: StringName
var _results_action_in_progress: bool = false
var _recovery_confirmation_presenter: RecoveryConfirmationPresenter
## `submit_discard()`（回傳型別是 SaveResult，裝不下換場失敗）在 durable 棄置成功、
## 但 MENU route 沒能 commit 時留下的具名碼；由 `_confirm_menu_recovery` 消費。
var _route_commit_failure: StringName = &""


## 服務來源：production（main.tscn）走 design.md §4.4 的五個 Autoload；本方法讓呼叫端在
## **加入場景樹之前**改綁自備的 registry／repository／router。boot 分流的回歸測試必須用它
## ——AppRoot 的 boot 會寫存檔（首次啟動建 profile），不換掉 storage 就會動到真實 user:// 檔。
func bind_services(
	p_content_registry: ContentRegistryService,
	p_save_repository: SaveRepository,
	p_scene_router: SceneRouterService
) -> StringName:
	# 依賴必須在場景樹觸發 _ready 前一次完成；過晚呼叫不得形成 boot 使用舊 repository、
	# 後續交易卻換成新 repository 的分裂狀態。
	if is_inside_tree() or _booted:
		return ERROR_SERVICE_BIND_TOO_LATE
	if p_content_registry == null or p_save_repository == null or p_scene_router == null:
		return &"APP_REQUIRED_SERVICE_MISSING"
	_content_registry = p_content_registry
	_save_repository = p_save_repository
	_scene_router = p_scene_router
	_services_bound = true
	return &""


## SettingsRepository／AudioCoordinator 與呈現 runtime 的綁定同樣只能發生在進樹之前。
## Port 只有在 repository fresh read 與四 adapter rebuild 全部完成後才會公開。
func bind_settings_runtime(
	p_repository: Object,
	p_audio_coordinator: AudioCoordinator,
	p_runtime_consumer: Object
) -> StringName:
	if is_inside_tree() or _booted:
		return ERROR_SERVICE_BIND_TOO_LATE
	return _configure_settings_runtime(
		p_repository,
		p_audio_coordinator,
		p_runtime_consumer
	)


func bind_settings_services(
	p_repository: Object,
	p_audio_coordinator: AudioCoordinator
) -> StringName:
	if is_inside_tree() or _booted:
		return ERROR_SERVICE_BIND_TOO_LATE
	if p_repository == null or p_audio_coordinator == null:
		return ERROR_SETTINGS_RUNTIME_MISSING
	_settings_repository_override = p_repository
	_settings_audio_override = p_audio_coordinator
	return &""


func settings_application_port() -> SettingsApplicationPort:
	return _settings_application


func bind_terminal_presentation_handoff(
	port: TerminalPresentationHandoffPort
) -> StringName:
	if is_inside_tree() or _booted:
		return ERROR_SERVICE_BIND_TOO_LATE
	if port == null:
		return &"APP_TERMINAL_HANDOFF_PORT_MISSING"
	_terminal_route_handoff_port = port
	return &""


func _ready() -> void:
	if presentation_host == null:
		boot_failed.emit(&"APP_PRESENTATION_HOST_MISSING")
		return
	if _settings_application == null:
		var settings_repository: Object = (
			_settings_repository_override
			if _settings_repository_override != null
			else get_node_or_null("/root/SettingsService")
		)
		var audio_coordinator := (
			_settings_audio_override
			if _settings_audio_override != null
			else get_node_or_null("/root/AudioService") as AudioCoordinator
		)
		_ensure_production_audio_buses()
		_settings_runtime_consumer = PresentationSettingsRuntimeConsumer.new(
			presentation_host,
			_production_viewport_runtime()
		)
		var settings_error := _configure_settings_runtime(
			settings_repository,
			audio_coordinator,
			_settings_runtime_consumer
		)
		if not settings_error.is_empty():
			boot_failed.emit(settings_error)
			return
	if not _services_bound:
		_content_registry = get_node_or_null("/root/ContentRegistry") as ContentRegistryService
		_save_repository = get_node_or_null("/root/SaveService") as SaveRepository
		_scene_router = get_node_or_null("/root/SceneRouter") as SceneRouterService
	if _content_registry == null or _save_repository == null or _scene_router == null:
		boot_failed.emit(&"APP_REQUIRED_SERVICE_MISSING")
		return
	# H3 修正:不得以硬編的內建 catalog 建構繞過 production catalog
	# 的 SHA/CSV 驗證。傳 null 讓 bootstrap 走真正的 typed load
	# (design.md:143-152);載入失敗會使 run() 回 ok=false,由既有的
	# _try_content()==null → ERROR_CONTENT_UNAVAILABLE → boot_failed 路徑
	# （與 INCOMPATIBLE_PRESERVED 等既有 boot failure 相同呈現）處理。
	_content_bootstrap = ProjectContentBootstrap.new()
	# B3 修正:codec 2→3 的 generation migration port 必須綁在「本次 boot 實際安裝
	# 的 pinned generation」上,所以內容安裝要先於 save content port 組裝
	# (先前順序相反,production 因此永遠只拿到 base port → PORT_UNCONFIGURED,
	# 歷史 schema 3／codec 2 save 一律 incompatible_preserved,升不了級)。
	# _try_content() 本來就會在同一個 _ready() 內由 _boot_route() 觸發,
	# 失敗碼與原路徑相同,只是提前發出。
	var content := _try_content()
	if content == null:
		boot_failed.emit(ERROR_CONTENT_UNAVAILABLE)
		return
	# review N3：正式 catalog 一載好就補注入 settings runtime，讓 accessibility host
	# 的文案與畫面其他文字同源（boot 順序上 settings runtime 早於內容載入）。
	if _settings_runtime_consumer != null:
		_settings_runtime_consumer.bind_localization_catalog(
			content.localization_catalog
		)
	var receipt_port := ContentRegistryReceiptAdapter.new(_content_registry)
	var migration_port := ContentRegistryMigrationAdapter.new(_content_registry)
	var generation_migration_port := (
		ProductionContentGenerationMigrationPortBuilder.new().build(
			_content_registry, content.receipt, content.localization_catalog
		)
	)
	var save_configuration: SaveConfigurationResult = (
		_save_repository._configure_content_ports(
			receipt_port, migration_port, generation_migration_port
		)
	)
	if not save_configuration.ok:
		boot_failed.emit(save_configuration.error.code)
		return
	_app_state_machine = AppStateMachine.new(_save_repository)
	_run_preparation_service = RunPreparationService.new(_save_repository)
	_retained_run_recovery_service = RetainedRunRecoveryService.new(
		_save_repository
	)
	_scene_router.bind_presentation_host(presentation_host)
	var catalog_error := _scene_router.bind_production_catalog(
		ProductionSceneCatalog.new()
	)
	if not catalog_error.is_empty():
		boot_failed.emit(catalog_error)
		return
	if _terminal_route_handoff_port == null:
		_terminal_route_handoff_port = (
			SceneRouterTerminalPresentationHandoffAdapter.new(
				_scene_router,
				_live_lease_registry,
				SaveRepositoryResultsRenderRetryAuthority.new(
					_save_repository
				),
				Callable(self, "_terminal_presentation_snapshot_clone"),
				Callable(self, "_return_results_to_camp_owned"),
				Callable(self, "_return_results_to_menu_owned"),
				Callable(self, "_begin_results_action"),
				Callable(self, "_end_results_action"),
				Callable(self, "_terminal_staged_context")
			)
		)
	# Exact G2 dev CLI allowlist: --combat-lab. It reuses the production
	# ProjectContentBootstrap and production facade/battle ports.
	if OS.get_cmdline_user_args().has("--combat-lab"):
		var lab_error := _boot_combat_lab()
		if not lab_error.is_empty():
			boot_failed.emit(lab_error)
			return
		_booted = true
		boot_completed.emit()
		return
	var boot_error := _boot_route()
	if not boot_error.is_empty():
		boot_failed.emit(boot_error)
		return
	_booted = true
	boot_completed.emit()


func _resolve_presentation_host() -> Control:
	var production_host := get_node_or_null(
		"UiLayer/UiRoot/PresentationHost"
	) as Control
	if production_host != null:
		return production_host
	return get_node_or_null("PresentationHost") as Control


func _production_viewport_runtime() -> Object:
	var runtime := get_node_or_null("ViewportCoordinator")
	if (
		runtime == null
		or not runtime.has_method(&"apply_ui_scale")
		or not runtime.has_method(&"window_size")
	):
		return null
	return runtime


func _configure_settings_runtime(
	repository: Object,
	audio_coordinator: AudioCoordinator,
	runtime_consumer: Object
) -> StringName:
	_settings_application = null
	if (
		repository == null
		or not repository.has_method("save")
		or not repository.has_method("current_snapshot")
		or audio_coordinator == null
		or runtime_consumer == null
		or not runtime_consumer.has_method("preflight")
		or not runtime_consumer.has_method("activate")
		or not runtime_consumer.has_method("activate_safe_fallback")
	):
		return ERROR_SETTINGS_RUNTIME_MISSING
	if repository.has_method("load"):
		var load_result: Variant = repository.call("load")
		if not _settings_result_ok(load_result):
			return ERROR_SETTINGS_REBUILD_FAILED
	var window_size := Vector2i(1280, 720)
	if is_inside_tree():
		window_size = Vector2i(get_viewport().get_visible_rect().size)
	var viewport_runtime := _production_viewport_runtime()
	var window_size_provider := Callable()
	if viewport_runtime != null:
		window_size_provider = Callable(viewport_runtime, &"window_size")
	var coordinator := SettingsApplicationCoordinator.new(
		repository,
		ThemeSettingsAdapter.new(runtime_consumer),
		ViewportSettingsAdapter.new(
			runtime_consumer,
			WorldViewportPolicy.new(),
			WindowCoordinateMapper.new(),
			window_size,
			window_size_provider
		),
		# settings runtime 必須早於內容載入(locale/縮放要在第一個畫面之前生效),
		# 此時正式 catalog 還沒載入;adapter 只讀 SUPPORTED_LOCALES(常數,兩份目錄
		# 相同),故用 restricted 退路目錄,不影響畫面文案來源(review N3)。
		LocalizationSettingsAdapter.new(
			runtime_consumer,
			LocalizationCatalog.restricted_emergency_catalog()
		),
		AudioSettingsAdapter.new(audio_coordinator)
	)
	var rebuilt: SettingsApplicationResult = (
		coordinator.rebuild_from_repository()
	)
	if not rebuilt.ok:
		return ERROR_SETTINGS_REBUILD_FAILED
	_settings_repository_runtime = repository
	_settings_application = coordinator
	return &""


func _settings_result_ok(value: Variant) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		return bool((value as Dictionary).get("ok", false))
	if value is Object:
		return bool((value as Object).get("ok"))
	return false


func _ensure_production_audio_buses() -> void:
	for bus: StringName in AudioBusKind.ordered_names():
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)


func is_booted() -> bool:
	return _booted


func get_presentation_host() -> Control:
	return presentation_host


func app_state() -> AppStateMachine.State:
	return _app_state_machine.state()


func has_active_run() -> bool:
	return _run_session != null and _run_controller != null


## active run 的存檔仍完整存在，但本程序無法組裝它時才為 true。
func has_unresumable_active_run() -> bool:
	return not _unresumable_run_id.is_empty()


## 營地五設施的唯讀投影（S5-AC-001）；尚未載入 profile 時為 null。
func try_camp_view_model() -> CampViewModel:
	return _camp_view_model


## 本 run 的命令唯一建構點（S5-AC-014：四命令＋board commit）；無 active run 時為 null。
## 實際的呼叫端是 RUN 灰盒的驅動器 RunLabSession（scripts/dev/run/），本存取器供測試與
## 未來的正式 run UI 取用。
func try_run_command_factory() -> RunCommandFactory:
	return _run_command_factory


func current_menu_snapshot() -> MainMenuSnapshot:
	return _menu_snapshot.deep_clone()


func current_run_presentation() -> RunPresentationSessionResult:
	if _run_presentation_session == null:
		return RunPresentationSessionResult.failure(
			DiagnosticError.new(
				ERROR_RUN_SESSION_UNAVAILABLE,
				&"error.presentation.run_session_unavailable"
			)
		)
	return RunPresentationSessionResult.success(_run_presentation_session)


func open_main_menu() -> AppActionResult:
	if _app_state_machine.state() == AppStateMachine.State.MENU:
		return AppActionResult.success(false)
	return return_to_menu()


func open_camp() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.MENU \
		or not _menu_snapshot.can_start:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var loaded := _save_repository.load()
	if not loaded.ok:
		return _action_failure(loaded.error.code)
	if loaded.run_status != LoadResult.RunStatus.NONE:
		_update_menu_from_load(loaded)
		return _action_failure(ERROR_RETAINED_RUN_EXISTS)
	_compose_camp(loaded.profile)
	var prepared := _prepare_route(
		AppStateMachine.State.CAMP,
		&"CAMP_WORLD",
		null,
		loaded.profile
	)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.OPEN_CAMP)
	)
	if not transitioned.ok:
		_discard_route(prepared)
		return _action_failure(transitioned.error.code)
	return _commit_route_or_fail_closed(prepared)


func continue_active_run() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.MENU \
		or not _menu_snapshot.can_continue:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var capability := _prepared_run_capability
	var consumed := (
		_run_preparation_service.consume(capability)
		if capability != null
		else null
	)
	if consumed == null or not consumed.ok:
		var loaded := _save_repository.load()
		if not loaded.ok or loaded.run_status != LoadResult.RunStatus.LOADED \
			or loaded.run == null:
			return _action_failure(ERROR_PREPARED_RUN_STALE)
		var compose_error := _try_compose_active_run(loaded.profile, loaded.run)
		if not compose_error.is_empty():
			_update_menu_from_load(loaded, compose_error)
			return _action_failure(compose_error)
		var prepared := _run_preparation_service.prepare(loaded)
		if not prepared.ok:
			return AppActionResult.failure(prepared.error)
		capability = prepared.capability
		consumed = _run_preparation_service.consume(capability)
	if consumed == null or not consumed.ok:
		return _action_failure(ERROR_PREPARED_RUN_STALE)
	var fresh_compose_error := _try_compose_active_run(
		consumed.profile, consumed.run
	)
	if not fresh_compose_error.is_empty():
		return _action_failure(fresh_compose_error)
	var run_snapshot := _run_presentation_session.snapshot()
	var target_route := _run_route_for_snapshot(run_snapshot)
	var prepared_route := _prepare_route(
		AppStateMachine.State.RUN,
		target_route,
		run_snapshot
	)
	if not bool(prepared_route.get("ok", false)):
		_release_active_run()
		return _action_failure(
			StringName(
				prepared_route.get("error", ERROR_ROUTE_PREPARE_INVALID)
			)
		)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.CONTINUE_RUN)
	)
	if not transitioned.ok:
		_discard_route(prepared_route)
		_release_active_run()
		return _action_failure(transitioned.error.code)
	_prepared_run_capability = null
	return _commit_route_or_fail_closed(prepared_route)


func return_to_menu() -> AppActionResult:
	if _app_state_machine.state() not in [
		AppStateMachine.State.CAMP,
		AppStateMachine.State.RUN,
	]:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var loaded := _save_repository.load()
	if loaded.ok:
		_update_menu_from_load(loaded)
	var prepared := _prepare_route(
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		_menu_snapshot
	)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.RETURN_TO_MENU)
	)
	if not transitioned.ok:
		_discard_route(prepared)
		return _action_failure(transitioned.error.code)
	var committed := _commit_route_or_fail_closed(prepared)
	_release_active_run()
	return committed


func start_expedition(request: StartExpeditionRequest) -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.CAMP:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	if _camp_controller == null:
		return _action_failure(ERROR_CAMP_UNAVAILABLE)
	if request == null:
		return _action_failure(StartExpeditionError.INPUT_INVALID)
	var content := _try_content()
	if content == null:
		return _action_failure(ERROR_CONTENT_UNAVAILABLE)
	var commander_def := _try_commander_def(content, request.commander_id)
	if commander_def == null:
		return _action_failure(ERROR_COMMANDER_UNKNOWN)
	var started := _camp_controller.dispatch_start_expedition(StartExpeditionCommand.new(
		request.commander_id,
		commander_def,
		request.challenge_level,
		content.receipt,
		content.economy_catalog
	))
	if not started.ok:
		return _action_failure(started.error.code)
	var compose_error := _try_compose_active_run(started.profile, started.run)
	if not compose_error.is_empty():
		return _enter_start_route_recovery(
			started.profile,
			started.run,
			compose_error
		)
	var run_snapshot := _run_presentation_session.snapshot()
	var target_route := _run_route_for_snapshot(run_snapshot)
	var prepared_route := _prepare_route(
		AppStateMachine.State.RUN,
		target_route,
		run_snapshot
	)
	if not bool(prepared_route.get("ok", false)):
		return _enter_start_route_recovery(
			started.profile,
			started.run,
			StringName(
				prepared_route.get("error", ERROR_ROUTE_PREPARE_INVALID)
			)
		)
	var transitioned := _app_state_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), started.save_result
	)
	if not transitioned.ok:
		_discard_route(prepared_route)
		return _enter_start_route_recovery(
			started.profile,
			started.run,
			transitioned.error.code
		)
	_camp_view_model = CampViewModel.new(started.profile)
	var commit_error := _commit_route(prepared_route)
	if not commit_error.is_empty():
		_discard_route(prepared_route)
		return _enter_start_route_recovery(
			started.profile,
			started.run,
			commit_error
		)
	return AppActionResult.success(true)


func _enter_start_route_recovery(
	profile: ProfileState,
	run: RunState,
	source_code: StringName
) -> AppActionResult:
	_release_active_run()
	_unresumable_run_id = run.run_id if run != null else ""
	var loaded := _save_repository.load()
	_compose_camp(loaded.profile if loaded.ok else profile)
	_update_menu_from_load(loaded, source_code)
	var prepared := _prepare_route(
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		_menu_snapshot
	)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.RETURN_TO_MENU)
	)
	if not transitioned.ok:
		if bool(prepared.get("ok", false)):
			_discard_route(prepared)
		_live_lease_registry.revoke_active()
	elif not bool(prepared.get("ok", false)):
		_live_lease_registry.revoke_active()
	else:
		var menu_commit_error := _commit_route(prepared)
		if not menu_commit_error.is_empty():
			_live_lease_registry.revoke_active()
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(
			source_code,
			&"error.presentation.start_postcommit"
		)
	)


func discard_retained_run(
	token: RetainedRunRecoveryToken
) -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.MENU \
		or token == null \
		or _retained_run_recovery_service == null:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var discarded := _retained_run_recovery_service.discard(token)
	if not discarded.ok:
		return _action_failure(discarded.error.code)
	var loaded := _save_repository.load()
	if not loaded.ok or loaded.run_status != LoadResult.RunStatus.NONE:
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				loaded.error.code if not loaded.ok else ERROR_RETAINED_RUN_EXISTS,
				&"error.presentation.recovery_postcommit"
			)
		)
	_unresumable_run_id = ""
	_compose_camp(loaded.profile)
	_update_menu_from_profile(loaded.profile)
	return AppActionResult.success(true)


func discard_unresumable_active_run() -> StringName:
	var result := discard_retained_run(_retained_run_recovery_token)
	return &"" if result.ok else result.error.source_code


func _begin_menu_recovery() -> AppActionResult:
	if (
		_app_state_machine.state() != AppStateMachine.State.MENU
		or not _menu_snapshot.has_recovery
		or _retained_run_recovery_token == null
	):
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	if _recovery_confirmation_presenter == null:
		_recovery_confirmation_presenter = RecoveryConfirmationPresenter.new()
		var bind_error := _recovery_confirmation_presenter.bind(self)
		if not bind_error.is_empty():
			return _action_failure(bind_error)
	var begin_error := _recovery_confirmation_presenter.begin_confirmation(
		_retained_run_recovery_token,
		_menu_snapshot.warning_key
	)
	return (
		AppActionResult.success(false)
		if begin_error.is_empty()
		else _action_failure(begin_error)
	)


func _confirm_menu_recovery() -> AppActionResult:
	if (
		_recovery_confirmation_presenter == null
		or not _recovery_confirmation_presenter.is_confirmation_open()
	):
		return _action_failure(
			RecoveryConfirmationPresenter.CONFIRMATION_NOT_OPEN
		)
	_route_commit_failure = &""
	var discarded := _recovery_confirmation_presenter.confirm_confirmation()
	if discarded == null or not discarded.ok:
		_route_commit_failure = &""
		return _action_failure(
			discarded.error.code
			if discarded != null and discarded.error != null
			else &"RECOVERY_DISCARD_FAILED"
		)
	var route_failure := _route_commit_failure
	_route_commit_failure = &""
	if not route_failure.is_empty():
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				route_failure,
				&"error.presentation.recovery_postcommit"
			)
		)
	return AppActionResult.success(true)


func _cancel_menu_recovery() -> AppActionResult:
	if _recovery_confirmation_presenter == null:
		return _action_failure(
			RecoveryConfirmationPresenter.CONFIRMATION_NOT_OPEN
		)
	var cancel_error := (
		_recovery_confirmation_presenter.cancel_confirmation()
	)
	return (
		AppActionResult.success(false)
		if cancel_error.is_empty()
		else _action_failure(cancel_error)
	)


func submit_discard(token: RetainedRunRecoveryToken) -> SaveResult:
	if _retained_run_recovery_service == null:
		return SaveResult.failure(
			SaveError.new(&"RECOVERY_SERVICE_INVALID", &"recovery.service")
		)
	var discarded := _retained_run_recovery_service.discard(token)
	if not discarded.ok:
		return discarded
	var loaded := _save_repository.load()
	if not loaded.ok:
		# G2 F8：棄置已落檔，但 load 失敗代表畫面沒有任何更新來源——舊寫法既不記碼
		# 也不換場，`_confirm_menu_recovery` 因此回 success(true)，玩家收到「成功」
		# 卻看不到任何變化。與 route 失敗同一族，一律 fail-closed 到 fallback。
		_route_commit_failure = _revoke_and_install_app_route_fallback(
			loaded.error.code
		)
		return discarded
	_unresumable_run_id = ""
	_compose_camp(loaded.profile)
	_update_menu_from_load(loaded)
	var prepared := _prepare_route(
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		_menu_snapshot
	)
	# 棄置本身已經落檔（durable），SaveResult 不能因為換場失敗而變成 false；
	# 但 route 失敗必須 fail-closed 並記錄下來，由 `_confirm_menu_recovery`
	# 轉成 committed_presentation_failure 回給呼叫端（G2 M1）。
	if not bool(prepared.get("ok", false)):
		_route_commit_failure = _revoke_and_install_app_route_fallback(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
		return discarded
	var commit_error := _commit_route(prepared)
	if not commit_error.is_empty():
		_route_commit_failure = _revoke_and_install_app_route_fallback(
			commit_error
		)
	return discarded


func open_settings() -> AppActionResult:
	if _app_state_machine.state() not in [
		AppStateMachine.State.MENU,
		AppStateMachine.State.CAMP,
	]:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	return _navigate_subroute(&"SETTINGS")


func close_settings() -> AppActionResult:
	var parent := _app_state_machine.state()
	if parent not in [
		AppStateMachine.State.MENU,
		AppStateMachine.State.CAMP,
	]:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	return _navigate_subroute(
		&"CAMP_WORLD"
		if parent == AppStateMachine.State.CAMP
		else &"MENU_MAIN"
	)


func _apply_settings_from_active_screen() -> AppActionResult:
	var screen := _active_production_screen()
	var composition := (
		screen.get_node_or_null("Composition") as SettingsScreenComposition
		if screen != null and screen.route_kind == &"SETTINGS"
		else null
	)
	if composition == null or _settings_application == null:
		return _action_failure(ERROR_SETTINGS_RUNTIME_MISSING)
	var draft := composition.settings_draft()
	if draft == null:
		composition.set_control_status_code(
			SettingsScreenComposition.DRAFT_INVALID
		)
		return _action_failure(SettingsScreenComposition.DRAFT_INVALID)
	var applied := _settings_application.apply(draft)
	if applied == null:
		composition.set_control_status_code(ERROR_SETTINGS_RUNTIME_MISSING)
		return _action_failure(ERROR_SETTINGS_RUNTIME_MISSING)
	if applied.snapshot != null:
		composition.mark_committed(applied.snapshot)
	var source_code := (
		applied.error.source_code
		if applied.error != null
		else &""
	)
	composition.set_control_status_code(source_code)
	if applied.ok:
		screen.relocalize(
			applied.snapshot.locale,
			_localized_text_map(applied.snapshot.locale)
		)
		return AppActionResult.success(true)
	if applied.committed:
		if applied.snapshot != null:
			screen.relocalize(
				applied.snapshot.locale,
				_localized_text_map(applied.snapshot.locale)
			)
		return AppActionResult.committed_presentation_failure(
			applied.error
			if applied.error != null
			else DiagnosticError.new(
				ERROR_SETTINGS_REBUILD_FAILED,
				&"error.settings.application_failed"
			)
		)
	return _action_failure(
		source_code
		if not source_code.is_empty()
		else ERROR_SETTINGS_REBUILD_FAILED
	)


func request_exit() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.MENU:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	if _exit_request_pending:
		return _action_failure(ERROR_EXIT_ALREADY_PENDING)
	_exit_request_pending = true
	exit_requested.emit()
	return AppActionResult.success(false)


func settle_active_run() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.RUN:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var content := _try_content()
	if content == null or content.meta_reward_table == null:
		return _action_failure(ERROR_CONTENT_UNAVAILABLE)
	if _terminal_settlement_coordinator == null:
		var application_handoff := ApplicationTerminalHandoffPort.new(
			_commit_terminal_handoff,
			null,
			_commit_fail_closed_terminal_handoff
		)
		var bind_error := application_handoff.bind_presentation_port(
			_terminal_route_handoff_port
		)
		if not bind_error.is_empty():
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					bind_error,
					&"error.presentation.terminal_handoff"
				)
			)
		_terminal_settlement_coordinator = TerminalSettlementCoordinator.new(
			_save_repository,
			application_handoff,
			_revoke_run_writers,
			_invalidate_run_session,
			_release_active_run,
			_commit_fail_closed_terminal_handoff
		)
	return _terminal_settlement_coordinator.settle(content.meta_reward_table)


func return_results_to_camp() -> AppActionResult:
	if not _begin_results_action():
		return _action_failure(RESULTS_ACTION_IN_PROGRESS)
	var result := _return_results_to_camp_owned()
	_end_results_action()
	return result


func _return_results_to_camp_owned() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.RESULTS:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	_refresh_camp_from_storage()
	var prepared := _prepare_route(
		AppStateMachine.State.CAMP,
		&"CAMP_WORLD",
		null,
		_camp_profile_snapshot
	)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.RETURN_RESULTS_TO_CAMP)
	)
	if not transitioned.ok:
		_discard_route(prepared)
		return _action_failure(transitioned.error.code)
	return _commit_route_or_fail_closed(prepared)


func return_results_to_menu() -> AppActionResult:
	if not _begin_results_action():
		return _action_failure(RESULTS_ACTION_IN_PROGRESS)
	var result := _return_results_to_menu_owned()
	_end_results_action()
	return result


func _return_results_to_menu_owned() -> AppActionResult:
	if _app_state_machine.state() != AppStateMachine.State.RESULTS:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var loaded := _save_repository.load()
	if loaded.ok:
		_update_menu_from_load(loaded)
	var prepared := _prepare_route(
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		_menu_snapshot
	)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.RETURN_RESULTS_TO_MENU)
	)
	if not transitioned.ok:
		_discard_route(prepared)
		return _action_failure(transitioned.error.code)
	return _commit_route_or_fail_closed(prepared)


func acknowledge_results() -> StringName:
	var result := return_results_to_camp()
	return &"" if result.ok else result.error.source_code


func _action_failure(code: StringName) -> AppActionResult:
	return AppActionResult.failure(
		DiagnosticError.new(code, &"error.presentation.app_action")
	)


func _update_menu_from_profile(profile: ProfileState) -> void:
	_prepared_run_capability = null
	_retained_run_recovery_token = null
	_menu_snapshot = MainMenuSnapshot.new()
	_menu_snapshot.can_start = profile != null


func _update_menu_from_load(
	loaded: LoadResult,
	compose_error: StringName = &""
) -> void:
	_prepared_run_capability = null
	_retained_run_recovery_token = null
	_menu_snapshot = MainMenuSnapshot.new()
	if loaded == null or not loaded.ok:
		_menu_snapshot.warning_key = &"error.presentation.save_unavailable"
		return
	match loaded.run_status:
		LoadResult.RunStatus.NONE:
			_menu_snapshot.can_start = true
		LoadResult.RunStatus.LOADED:
			if loaded.run == null:
				_menu_snapshot.warning_key = &"error.presentation.run_unavailable"
				return
			if compose_error.is_empty() and _run_presentation_session == null:
				compose_error = _try_compose_active_run(loaded.profile, loaded.run)
			if compose_error.is_empty():
				var prepared := _run_preparation_service.prepare(loaded)
				if prepared.ok:
					_prepared_run_capability = prepared.capability
					_menu_snapshot.can_continue = true
					_menu_snapshot.active_run_id_display = loaded.run.run_id
					return
				compose_error = prepared.error.source_code
			_unresumable_run_id = loaded.run.run_id
			_retained_run_recovery_token = (
				_retained_run_recovery_service.issue_token(
					loaded,
					StringName(loaded.run.run_id)
				)
			)
			_menu_snapshot.has_recovery = (
				_retained_run_recovery_token.is_issued()
			)
			_menu_snapshot.active_run_id_display = loaded.run.run_id
			_menu_snapshot.warning_key = &"error.presentation.run_recovery"
		LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
			_retained_run_recovery_token = (
				_retained_run_recovery_service.issue_token(loaded, &"")
			)
			_menu_snapshot.has_recovery = (
				_retained_run_recovery_token.is_issued()
			)
			_menu_snapshot.warning_key = &"error.presentation.run_incompatible"


func _commit_terminal_handoff(
	capability: TerminalSettlementPresentationCapability,
	snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	if (
		capability == null
		or snapshot == null
		or not capability._authorizes_snapshot(snapshot)
	):
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				&"RESULTS_FALLBACK", &"error.presentation.results_fallback"
			)
		)
	if _app_state_machine.state() == AppStateMachine.State.RESULTS:
		return (
			AppActionResult.success(true)
			if _terminal_snapshot_matches(snapshot)
			else AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"RESULTS_FALLBACK",
					&"error.presentation.results_fallback"
				)
			)
		)
	if _app_state_machine.state() != AppStateMachine.State.RUN:
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				&"RESULTS_FALLBACK", &"error.presentation.results_fallback"
			)
		)
	var transitioned := _app_state_machine.transition_after_terminal_handoff(
		AppEvent.new(AppEvent.Kind.FINISH_RUN)
	)
	if not transitioned.ok:
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				transitioned.error.code, &"error.presentation.results_fallback"
			)
		)
	_terminal_presentation_snapshot = snapshot.deep_clone()
	return AppActionResult.success(true)


func _commit_fail_closed_terminal_handoff(
	snapshot: ResultsPresentationSnapshot,
	_cause: StringName
) -> AppActionResult:
	if (
		snapshot == null
		or not snapshot.has_authoritative_pair()
	):
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				&"RESULTS_FALLBACK",
				&"error.presentation.results_fallback"
			)
		)
	if _app_state_machine.state() == AppStateMachine.State.RESULTS:
		return (
			AppActionResult.success(true)
			if _terminal_snapshot_matches(snapshot)
			else AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"RESULTS_FALLBACK",
					&"error.presentation.results_fallback"
				)
			)
		)
	if _app_state_machine.state() != AppStateMachine.State.RUN:
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				&"RESULTS_FALLBACK",
				&"error.presentation.results_fallback"
			)
		)
	var transitioned := _app_state_machine.transition_after_terminal_handoff(
		AppEvent.new(AppEvent.Kind.FINISH_RUN)
	)
	if not transitioned.ok:
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(
				transitioned.error.code,
				&"error.presentation.results_fallback"
			)
		)
	_terminal_presentation_snapshot = snapshot.deep_clone()
	return AppActionResult.success(true)


func _terminal_snapshot_matches(
	snapshot: ResultsPresentationSnapshot
) -> bool:
	return (
		snapshot != null
		and _terminal_presentation_snapshot != null
		and not snapshot.presentation_digest().is_empty()
		and snapshot.presentation_digest()
			== _terminal_presentation_snapshot.presentation_digest()
	)


func _terminal_presentation_snapshot_clone() -> ResultsPresentationSnapshot:
	return (
		_terminal_presentation_snapshot.deep_clone()
		if _terminal_presentation_snapshot != null
		else null
	)


func _revoke_run_writers() -> void:
	# Durable terminal commit invalidates the actual callback authority before
	# any repository proof or presentation route can fail.
	_live_lease_registry.revoke_active()
	_run_command_factory = null
	_run_controller = null


func _invalidate_run_session() -> void:
	# No facade or dev wrapper may retain a dispatch path after terminal save.
	_run_lab_session = null
	_release_run_presentation_session()


# === boot 分流 =============================================================

func _boot_combat_lab() -> StringName:
	if _try_content() == null:
		return ERROR_CONTENT_UNAVAILABLE
	var scene := load(COMBAT_LAB_SCENE_PATH) as PackedScene
	if scene == null:
		return SceneRouterService.ERROR_SCENE_INVALID
	var route_error := _scene_router.replace_presentation(scene)
	if not route_error.is_empty():
		return route_error
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)
	)
	return transitioned.error.code if not transitioned.ok else &""


## design.md §4.4 的分流。ACTIVE_RUN_LOADED 只有 BOOT 狀態可走（app_state_machine.gd:85-87），
## 故 load() 必須發生在 BOOT_COMPLETED 之前。
##
## wave5 修正 A1（順序）：內容安裝必須發生在 load() **之前**。SaveJsonCodec 解碼 run 時要靠
## ContentRegistryReceiptAdapter 把存檔裡的 pinned 內容參照解回 receipt（app_root.gd:58-62
## 裝上的 port），registry 是空的就會整段判成 INCOMPATIBLE_PRESERVED、run 變 null——續跑分支
## 因此永遠走不到，玩家一開遠征就把舊 run 覆蓋掉（資料遺失）。
## wave5 修正 A5：boot 路徑上的內容安裝失敗不再只是 push_warning——沒有內容連營地都組不起來，
## 直接以具名碼 boot_failed（懸而不決的半殘 boot 比明確失敗更難診斷）。
func _boot_route() -> StringName:
	var content := _try_content()
	if content == null:
		return ERROR_CONTENT_UNAVAILABLE
	var loaded := _save_repository.load()
	if not loaded.ok and loaded.profile_status != LoadResult.ProfileStatus.NOT_FOUND:
		return loaded.error.code
	var profile := loaded.profile if loaded.ok else null
	var compose_error: StringName = &""
	if loaded.ok and loaded.run_status == LoadResult.RunStatus.LOADED and loaded.run != null:
		compose_error = _try_compose_active_run(loaded.profile, loaded.run)
		if not compose_error.is_empty():
			_unresumable_run_id = loaded.run.run_id
			_release_active_run()
	if profile == null and loaded.profile_status == LoadResult.ProfileStatus.NOT_FOUND:
		profile = _try_bootstrap_profile(content)
		if profile == null:
			return ERROR_PROFILE_BOOTSTRAP_FAILED
	_compose_camp(profile)
	if loaded.ok:
		_update_menu_from_load(loaded, compose_error)
	else:
		_update_menu_from_profile(profile)
	var booted := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)
	)
	if not booted.ok:
		return booted.error.code
	return _route_for_state()


## 首次啟動的初始 profile：起始解鎖集合來自內容（unlock_kind == base_profile 的
## unlocked_content_refs），其餘欄位全是「什麼都還沒發生」的零值。建好即以單筆存檔提交，
## 失敗回 null（呼叫端轉成具名 boot 失敗）。
func _try_bootstrap_profile(content: ProjectContentBootstrapResult) -> ProfileState:
	var unlocked: Array[StringName] = content.base_profile_unlocked_content_ids.duplicate()
	unlocked.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var discovered: Array[StringName] = []
	var receipts: Array[SettlementReceiptState] = []
	var records: Array[CommanderChallengeRecordState] = []
	var profile := ProfileState.new(
		DEFAULT_PROFILE_ID, U64Bits.zero(), 0, unlocked, discovered, 0, receipts,
		DEFAULT_SETTINGS_REF, null, records
	)
	var saved := _save_repository.save(
		CampSaveRootFactory.new().build(profile, content.content_version)
	)
	if not saved.ok:
		push_warning(
			"AppRoot could not persist the initial profile: %s" % String(saved.error.code)
		)
		return null
	return profile


# === 換場（SceneRouter 依 app state）=======================================

func _route_for_state() -> StringName:
	var route_kind: StringName = &""
	var snapshot: RefCounted
	var profile: ProfileState
	match _app_state_machine.state():
		AppStateMachine.State.MENU:
			route_kind = &"MENU_MAIN"
			snapshot = _menu_snapshot
		AppStateMachine.State.CAMP:
			route_kind = &"CAMP_WORLD"
			profile = _camp_profile_snapshot
		AppStateMachine.State.RUN:
			if _run_presentation_session == null:
				return ERROR_RUN_SESSION_UNAVAILABLE
			var run_snapshot := _run_presentation_session.snapshot()
			if run_snapshot == null:
				return ERROR_RUN_SNAPSHOT_UNAVAILABLE
			match run_snapshot.app_phase:
				&"MAP":
					route_kind = &"RUN_MAP"
				&"PREPARE":
					route_kind = &"RUN_PREPARE"
				&"COMBAT":
					route_kind = &"RUN_COMBAT"
				&"REWARD":
					route_kind = &"RUN_REWARD"
				_:
					return ERROR_RUN_PHASE_INVALID
			snapshot = run_snapshot
		AppStateMachine.State.RESULTS:
			route_kind = &"RESULTS"
			snapshot = _terminal_presentation_snapshot
		_:
			return ERROR_STATE_INVALID
	var prepared := _prepare_route(
		_app_state_machine.state(),
		route_kind,
		snapshot,
		profile
	)
	if not bool(prepared.get("ok", false)):
		return StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
	return _commit_route(prepared)


func _prepare_route(
	target_parent_state: int,
	route_kind: StringName,
	snapshot: RefCounted = null,
	profile: ProfileState = null
) -> Dictionary:
	if _scene_router == null or route_kind.is_empty():
		return {"ok": false, "error": ERROR_ROUTE_PREPARE_INVALID}
	var generation := _next_route_generation()
	var activation := _live_lease_registry.prepare_activation(
		target_parent_state,
		generation
	)
	var lease := _live_lease_registry.prepared_lease(activation)
	if activation == null or lease == null:
		return {"ok": false, "error": ERROR_ROUTE_PREPARE_INVALID}
	var navigation_port := LiveScreenNavigationPort.new(
		lease,
		_live_lease_registry,
		Callable(self, "_navigate_subroute")
	)
	var intent_port: LiveScreenIntentPort
	var playback_port: LiveScreenPlaybackPort
	var inspection_port: LiveScreenInspectionPort
	if target_parent_state == AppStateMachine.State.RUN:
		if _run_presentation_session == null:
			_live_lease_registry.cancel_activation(activation)
			return {"ok": false, "error": ERROR_RUN_SESSION_UNAVAILABLE}
		intent_port = LiveScreenIntentPort.new(
			lease,
			_live_lease_registry,
			_run_presentation_session,
			Callable(self, "_handle_run_route_after_intent")
		)
		if route_kind == &"RUN_COMBAT":
			playback_port = LiveScreenPlaybackPort.new(
				lease,
				_live_lease_registry,
				_run_presentation_session
			)
			inspection_port = LiveScreenInspectionPort.new(
				lease,
				_live_lease_registry,
				_run_presentation_session
			)
	var action_port := ProductionScreenActionPort.new(
		lease,
		_live_lease_registry,
		_action_callbacks(route_kind)
	)
	var collection_projection: CollectionBrowserSnapshot
	if route_kind == &"COLLECTION":
		var content := _try_content()
		if content != null and content.ok:
			collection_projection = content.collection_snapshot(profile)
	var staged := _staged_context(route_kind, snapshot, profile)
	var live := ProductionLiveScreenContext.new(
		route_kind,
		snapshot,
		profile,
		action_port,
		navigation_port,
		intent_port,
		playback_port,
		inspection_port,
		collection_projection
	)
	# G2 F10：兩個 screen context 的 `snapshot_type_error` 以前只被寫入、沒有任何
	# production 讀者，等於「新增 snapshot 型別忘了加 clone 分支」仍舊靜默塌成 null，
	# 與「本來就不需要 snapshot」無從分辨。這裡是那個讀者：帶著具名 type error 就
	# fail-closed，不把半截畫面裝上去。
	var context_error := _screen_context_snapshot_error(staged, live)
	if not context_error.is_empty():
		_live_lease_registry.cancel_activation(activation)
		return {
			"ok": false,
			"error": context_error,
		}
	var prepared_result := _scene_router.prepare_production(
		route_kind,
		staged,
		live
	)
	if not prepared_result.ok:
		_live_lease_registry.cancel_activation(activation)
		return {
			"ok": false,
			"error": prepared_result.error.source_code,
		}
	return {
		"ok": true,
		"route_kind": route_kind,
		"generation": generation,
		"activation": activation,
		"prepared": prepared_result.prepared,
	}


func _screen_context_snapshot_error(
	staged: StagedScreenContext,
	live: ProductionLiveScreenContext
) -> StringName:
	if staged != null and not staged.snapshot_type_error.is_empty():
		return staged.snapshot_type_error
	if live != null and not live.snapshot_type_error.is_empty():
		return live.snapshot_type_error
	return &""


func _commit_route(prepared: Dictionary) -> StringName:
	if prepared == null or not bool(prepared.get("ok", false)):
		return ERROR_ROUTE_ACTIVATION_INVALID
	var activation := prepared.get("activation") as ScreenActivationCapability
	var route := prepared.get("prepared") as PreparedProductionRoute
	var staged_lease := _live_lease_registry.prepared_lease(activation)
	if staged_lease == null:
		# G2 F6：activation 在 prepare 與 commit 之間失效時，prepared candidate
		# 的整棵 Control 樹與未取消的 capability 同樣要收掉——這條分支以前是
		# 本函式唯一沒有 _discard_route 的早退。
		_discard_route(prepared)
		return ERROR_ROUTE_ACTIVATION_INVALID
	var prepared_error := _scene_router.prepared_error(route)
	if not prepared_error.is_empty():
		# 還沒 commit 場景：把準備中的 activation 與 prepared route 一起收掉，
		# 不留下永遠不會被消費的 pending capability。
		_discard_route(prepared)
		return prepared_error
	var route_error := _scene_router.commit_prepared(route)
	if not route_error.is_empty():
		# 準備好的候選畫面在 commit 失敗時同樣要收掉，否則每次失敗都漏一棵 Control 樹。
		_discard_route(prepared)
		return route_error
	var lease := _live_lease_registry.activate_prepared(activation)
	if lease == null:
		# G2 M1：場景已經換過去了，卻拿不到 active lease。維持現狀＝畫面顯示新畫面
		# 但每個按鈕都被 SCREEN_NOT_ACTIVE 拒絕（看得到、按不動）。
		# 只能 fail-closed：明確撤銷 active lease 並回報具名失敗，由呼叫端轉成
		# committed_presentation_failure，讓錯誤呈現面說明「已生效但畫面未更新」。
		_live_lease_registry.cancel_activation(activation)
		_live_lease_registry.revoke_active()
		return ERROR_ROUTE_ACTIVATION_INVALID
	_route_generation = int(prepared.get("generation", _route_generation))
	_active_route_kind = StringName(prepared.get("route_kind", &""))
	return &""


## G2 M1：state machine transition 之後才做的 route commit。commit 失敗代表
## 權威狀態已經前進、畫面卻沒跟上，回報 success 會讓玩家對著一個不接受輸入的畫面。
## 一律 fail-closed：撤銷 active lease（沒有任何畫面能繼續發命令）並回
## committed_presentation_failure 帶原始 source_code。
## G2 F4：fail-closed 不等於「沒有出路」。裸 revoke 會讓玩家對著一個所有按鈕都回
## SCREEN_NOT_ACTIVE 的舊畫面，連 R3 要求的 menu.exit 都按不動。與 RUN 既有的
## `_install_run_route_fallback` 對齊，改為撤銷後再裝一個帶重試／離開的 fallback。
func _commit_route_or_fail_closed(prepared: Dictionary) -> AppActionResult:
	var commit_error := _commit_route(prepared)
	if commit_error.is_empty():
		return AppActionResult.success(false)
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(
			_revoke_and_install_app_route_fallback(commit_error),
			&"error.presentation.route_commit_failed"
		)
	)


## post-commit 畫面失效時的統一收尾：先撤銷失效 lease（沒有任何舊畫面能繼續發命令），
## 再裝 APP_ROUTE_FALLBACK。回傳實際要回報的 source_code——fallback 自己也裝不起來時
## 回報 fallback 的失敗碼（那是更根本的問題），此時才真的只剩裸 revoke 的狀態。
func _revoke_and_install_app_route_fallback(
	source_code: StringName
) -> StringName:
	_live_lease_registry.revoke_active()
	var fallback_error := _install_app_route_fallback()
	return source_code if fallback_error.is_empty() else fallback_error


func _install_app_route_fallback() -> StringName:
	var prepared := _prepare_route(
		_app_state_machine.state(),
		&"APP_ROUTE_FALLBACK",
		_fallback_snapshot_for_state(),
		_fallback_profile_for_state()
	)
	if not bool(prepared.get("ok", false)):
		return StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
	return _commit_route(prepared)


func _fallback_snapshot_for_state() -> RefCounted:
	match _app_state_machine.state():
		AppStateMachine.State.MENU:
			return _menu_snapshot
		AppStateMachine.State.RUN:
			return (
				_run_presentation_session.snapshot()
				if _run_presentation_session != null
				else null
			)
		AppStateMachine.State.RESULTS:
			return _terminal_presentation_snapshot
	return null


func _fallback_profile_for_state() -> ProfileState:
	return (
		_camp_profile_snapshot
		if _app_state_machine.state() == AppStateMachine.State.CAMP
		else null
	)


## APP_ROUTE_FALLBACK 的重試：重算目前 app state 應有的正式 route 並換過去。
## 與 `run.retry_route` 同型（`_retry_run_route_presentation`），差別只在它涵蓋
## MENU／CAMP／RESULTS。
func _retry_app_route_presentation() -> AppActionResult:
	if _active_route_kind != &"APP_ROUTE_FALLBACK":
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var route_error := _route_for_state()
	return (
		AppActionResult.success(false)
		if route_error.is_empty()
		else _action_failure(route_error)
	)


func _discard_route(prepared: Dictionary) -> void:
	_live_lease_registry.cancel_activation(
		prepared.get("activation") as ScreenActivationCapability
	)
	_scene_router.discard_prepared(
		prepared.get("prepared") as PreparedProductionRoute
	)


func _next_route_generation() -> int:
	var active := _live_lease_registry.active_lease()
	var active_generation := (
		active.route_generation if active != null else 0
	)
	return maxi(_route_generation, active_generation) + 1


func _navigate_subroute(target_route: StringName) -> AppActionResult:
	var parent := _app_state_machine.state()
	var snapshot: RefCounted
	var profile: ProfileState
	if target_route == &"SETTINGS":
		if (
			parent not in [
				AppStateMachine.State.MENU,
				AppStateMachine.State.CAMP,
			]
			or _settings_repository_runtime == null
			or not _settings_repository_runtime.has_method("current_snapshot")
		):
			return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
		snapshot = (
			_settings_repository_runtime.call("current_snapshot")
			as SettingsSnapshot
		)
		if snapshot == null:
			return _action_failure(ERROR_SETTINGS_RUNTIME_MISSING)
	elif parent == AppStateMachine.State.RUN:
		if _run_presentation_session == null:
			return _action_failure(ERROR_RUN_SESSION_UNAVAILABLE)
		snapshot = _run_presentation_session.snapshot()
		var required := _run_route_for_snapshot(
			snapshot as RunPresentationSnapshot
		)
		if target_route != required:
			return _action_failure(PresentationRouteCoordinator.ROUTE_TARGET_INVALID)
	elif parent == AppStateMachine.State.CAMP:
		profile = _camp_profile_snapshot
	elif parent == AppStateMachine.State.MENU:
		snapshot = _menu_snapshot
	else:
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var prepared := _prepare_route(parent, target_route, snapshot, profile)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var commit_error := _commit_route(prepared)
	if not commit_error.is_empty():
		return _action_failure(commit_error)
	return AppActionResult.success(false)


func _handle_run_route_after_intent(
	result: RunPresentationResult
) -> AppActionResult:
	if (
		result == null
		or result.snapshot == null
		or _app_state_machine.state() != AppStateMachine.State.RUN
	):
		return _action_failure(ERROR_RUN_SNAPSHOT_UNAVAILABLE)
	var target := _run_route_for_snapshot(result.snapshot)
	if target.is_empty():
		return _action_failure(ERROR_RUN_PHASE_INVALID)
	var prepared := _prepare_route(
		AppStateMachine.State.RUN,
		target,
		result.snapshot
	)
	if not bool(prepared.get("ok", false)):
		return _install_run_route_fallback(
			result,
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var commit_error := _commit_route(prepared)
	if not commit_error.is_empty():
		return _install_run_route_fallback(result, commit_error)
	return AppActionResult.success(result.committed)


func _install_run_route_fallback(
	result: RunPresentationResult,
	source_code: StringName
) -> AppActionResult:
	var snapshot: RunPresentationSnapshot = (
		result.snapshot
		if result != null
		else null
	)
	if snapshot != null:
		var fallback := _prepare_route(
			AppStateMachine.State.RUN,
			&"RUN_ROUTE_FALLBACK",
			snapshot
		)
		if bool(fallback.get("ok", false)):
			var fallback_error := _commit_route(fallback)
			if not fallback_error.is_empty():
				source_code = fallback_error
		else:
			source_code = StringName(fallback.get("error", source_code))
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(
			source_code,
			&"error.presentation.run_route_fallback"
		)
	)


func _retry_run_route_presentation() -> AppActionResult:
	if (
		_app_state_machine.state() != AppStateMachine.State.RUN
		or _run_presentation_session == null
		or _active_route_kind != &"RUN_ROUTE_FALLBACK"
	):
		return _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	var snapshot := _run_presentation_session.snapshot()
	var target := _run_route_for_snapshot(snapshot)
	if target.is_empty():
		return _action_failure(ERROR_RUN_PHASE_INVALID)
	var prepared := _prepare_route(
		AppStateMachine.State.RUN,
		target,
		snapshot
	)
	if not bool(prepared.get("ok", false)):
		return _action_failure(
			StringName(prepared.get("error", ERROR_ROUTE_PREPARE_INVALID))
		)
	var commit_error := _commit_route(prepared)
	if not commit_error.is_empty():
		return _action_failure(commit_error)
	return AppActionResult.success(false)


func _run_route_for_snapshot(snapshot: RunPresentationSnapshot) -> StringName:
	if snapshot == null:
		return &""
	match snapshot.app_phase:
		&"MAP":
			return &"RUN_MAP"
		&"PREPARE":
			return &"RUN_PREPARE"
		&"COMBAT":
			return &"RUN_COMBAT"
		&"REWARD":
			return &"RUN_REWARD"
	return &""


## review N3：畫面文案的唯一來源是 boot 期驗過 SHA 的正式 catalog
## （`localization/catalog.v2.csv` → ProjectContentBootstrap → 這裡），不再由
## GDScript 內建目錄提供，否則改 CSV 不會改變任何畫面文字。內容尚未載入／boot
## 失敗時才退回 restricted 目錄，讓 boot failure 與 fallback 畫面仍有字可顯示。
func _localized_text_map(locale: StringName) -> Dictionary:
	var result: Dictionary = {}
	var catalog := _production_localization_catalog()
	for key: StringName in catalog.keys_for_locale(locale):
		var resolved := catalog.resolve(locale, key)
		if resolved.ok:
			result[key] = resolved.value
	return result


func _production_localization_catalog() -> LocalizationCatalog:
	if (
		_content != null
		and _content.localization_catalog != null
	):
		return _content.localization_catalog
	return LocalizationCatalog.restricted_emergency_catalog()


func _current_locale() -> StringName:
	if (
		_settings_repository_runtime != null
		and _settings_repository_runtime.has_method("current_snapshot")
	):
		var snapshot := (
			_settings_repository_runtime.call("current_snapshot")
			as SettingsSnapshot
		)
		if snapshot != null and snapshot.locale in [&"zh_TW", &"en"]:
			return snapshot.locale
	return &"zh_TW"


func _staged_context(
	route_kind: StringName,
	snapshot: RefCounted = null,
	profile: ProfileState = null
) -> StagedScreenContext:
	var locale := _current_locale()
	return StagedScreenContext.new(
		route_kind,
		snapshot,
		profile,
		locale,
		_localized_text_map(locale)
	)


func _terminal_staged_context(
	route_kind: StringName,
	snapshot: ResultsPresentationSnapshot
) -> StagedScreenContext:
	return _staged_context(route_kind, snapshot)


func _action_callbacks(route_kind: StringName) -> Dictionary:
	var actions: Dictionary = {}
	match route_kind:
		&"MENU_MAIN":
			actions[&"menu.continue"] = Callable(self, "continue_active_run")
			actions[&"menu.start"] = Callable(self, "open_camp")
			actions[&"menu.settings"] = Callable(self, "open_settings")
			if _menu_snapshot.has_recovery:
				actions[&"menu.recovery"] = Callable(
					self, "_begin_menu_recovery"
				)
				actions[&"menu.recovery.confirm"] = Callable(
					self, "_confirm_menu_recovery"
				)
				actions[&"menu.recovery.cancel"] = Callable(
					self, "_cancel_menu_recovery"
				)
			actions[&"menu.exit"] = Callable(self, "request_exit")
		&"SETTINGS":
			actions[&"settings.apply"] = Callable(
				self, "_apply_settings_from_active_screen"
			)
			actions[&"settings.back"] = Callable(self, "close_settings")
		&"CAMP_WORLD":
			actions[&"camp.expedition_gate"] = Callable(
				self, "_open_expedition_gate_route"
			)
			actions[&"camp.commander_hall"] = Callable(
				self, "_open_commander_hall_route"
			)
			actions[&"camp.collection"] = Callable(
				self, "_open_collection_route"
			)
			actions[&"camp.forge"] = Callable(
				self, "_open_workshop_route"
			)
			actions[&"camp.challenge_monument"] = Callable(
				self, "_open_challenge_monument_route"
			)
			actions[&"camp.settings"] = Callable(self, "open_settings")
			actions[&"camp.start"] = Callable(
				self, "_start_selected_camp_expedition"
			)
			actions[&"camp.menu"] = Callable(self, "return_to_menu")
		&"FACILITY_EXPEDITION_GATE", \
		&"FACILITY_COMMANDER_HALL", \
		&"COLLECTION", \
		&"FACILITY_UNLOCK_WORKSHOP", \
		&"FACILITY_CHALLENGE_MONUMENT":
			actions[&"camp.back"] = Callable(self, "_return_to_camp_route")
		&"RUN_MAP", &"RUN_PREPARE", &"RUN_COMBAT", &"RUN_REWARD":
			actions[&"run.menu"] = Callable(self, "return_to_menu")
		&"APP_ROUTE_FALLBACK":
			actions[&"app.retry_route"] = Callable(
				self, "_retry_app_route_presentation"
			)
			actions[&"menu.exit"] = Callable(self, "request_exit")
		&"RUN_ROUTE_FALLBACK":
			actions[&"run.retry_route"] = Callable(
				self, "_retry_run_route_presentation"
			)
			actions[&"run.menu"] = Callable(self, "return_to_menu")
		&"RESULTS", &"RESULTS_FALLBACK":
			actions[&"results.camp"] = Callable(
				self, "return_results_to_camp"
			)
			actions[&"results.menu"] = Callable(
				self, "return_results_to_menu"
			)
			actions[&"results.retry"] = Callable(
				self, "_retry_results_presentation"
			)
	return actions


func _open_collection_route() -> AppActionResult:
	return _navigate_subroute(&"COLLECTION")


func _open_expedition_gate_route() -> AppActionResult:
	return _navigate_subroute(&"FACILITY_EXPEDITION_GATE")


func _open_commander_hall_route() -> AppActionResult:
	return _navigate_subroute(&"FACILITY_COMMANDER_HALL")


func _open_workshop_route() -> AppActionResult:
	return _navigate_subroute(&"FACILITY_UNLOCK_WORKSHOP")


func _open_challenge_monument_route() -> AppActionResult:
	return _navigate_subroute(&"FACILITY_CHALLENGE_MONUMENT")


func _return_to_camp_route() -> AppActionResult:
	return _navigate_subroute(&"CAMP_WORLD")


func _start_selected_camp_expedition() -> AppActionResult:
	var screen := _active_production_screen()
	var composition := (
		screen.get_node_or_null("Composition") as CampWorldScreen
		if screen != null and screen.route_kind == &"CAMP_WORLD"
		else null
	)
	var request := (
		composition.selected_expedition_request()
		if composition != null
		else null
	)
	if request == null:
		return _action_failure(ERROR_CAMP_EXPEDITION_SELECTION_REQUIRED)
	return start_expedition(request)


func _active_production_screen() -> ProductionScreen:
	if presentation_host == null or presentation_host.get_child_count() != 1:
		return null
	return presentation_host.get_child(0) as ProductionScreen


func _retry_results_presentation() -> AppActionResult:
	var result := _action_failure(ERROR_ACTION_NOT_AVAILABLE)
	if _terminal_route_handoff_port is SceneRouterTerminalPresentationHandoffAdapter:
		var adapter := (
			_terminal_route_handoff_port
			as SceneRouterTerminalPresentationHandoffAdapter
		)
		var navigation := adapter.fallback_navigation_port()
		result = navigation.retry_installed()
	return result


func _begin_results_action() -> bool:
	if _results_action_in_progress:
		return false
	_results_action_in_progress = true
	return true


func _end_results_action() -> void:
	_results_action_in_progress = false


# === run 範疇組裝 ===========================================================

## RunSession（取 catalog lease）＋RunController＋RunCommandFactory＋run 灰盒驅動。
## 回 &"" 表組裝完成，否則為具名失敗碼（wave5 修正 B3：呼叫端能區分世代不符與其他原因）。
## 不動任何持久狀態，故失敗可安全回退。
func _try_compose_active_run(profile: ProfileState, run: RunState) -> StringName:
	if profile == null or run == null or run.content_snapshot == null:
		return ERROR_RUN_INPUT_INVALID
	var content := _try_content()
	if content == null:
		return ERROR_CONTENT_UNAVAILABLE
	var digest := run.content_snapshot.manifest_digest_value()
	if digest != content.manifest_digest:
		# 舊世代的 run 需要它自己的 pinned generation；目前只安裝當前世代（REQ-META-003 的
		# catalog lease 續持屬 registry 職責，尚無多世代常駐安裝）。
		return ERROR_RUN_GENERATION_MISMATCH
	var session_result := RunSessionFactory.new(_content_registry).create(profile, run)
	if not session_result.ok:
		return ERROR_RUN_SESSION_UNAVAILABLE
	# §6.1：relic（slot-gated）＋指揮官被動＋challenge 詞綴（always-active）同一張表。
	var table_result := RunModifierTableBuilder.new().build(
		_content_registry, digest, content.run_relic_ids, run.commander_id, run.challenge_level
	)
	if not table_result.ok:
		return ERROR_RUN_MODIFIER_TABLE_FAILED
	# G2 H1 前置：指揮官被動效果只從 commander 定義可達，不在 unit/encounter 的遞移閉包內。
	# 不把它們一起 pin，BattleSetupSourceCompiler 帶進來的 commander_effects 會讓
	# StartCombatEvent 以 BATTLE_RULES_REFERENCE_MISSING 被拒——正式路徑連 COMBAT 都進不去。
	var commander_passive_effect_ids := CommanderContentReader.new().passive_effect_ids(
		_content_registry, digest, run.commander_id
	)
	var battle_root_ids := _battle_root_ids(content)
	battle_root_ids.append_array(commander_passive_effect_ids)
	# 缺口 1（§6.3 軌 A）：required_ids 必須帶上 challenge unlock 鏈，否則挑戰詞綴只透過
	# unlock.slice_challenge_N 的 modifier_refs 可達、不在 unit/encounter 的遞移閉包內，
	# challenge>=1 的戰鬥節點會以 EncounterCompiler.RULE_MISSING 進不去。
	var battle_result := BattleRuleCatalogBuilder.new().build(
		_content_registry, digest,
		RunCompositionSupport.required_battle_ids(
			battle_root_ids, run.challenge_level
		)
	)
	if not battle_result.ok:
		return ERROR_RUN_BATTLE_CATALOG_FAILED
	var affix_result := ChallengeAffixResolver.new().resolve(
		_content_registry, digest, run.challenge_level
	)
	if not affix_result.ok:
		return ERROR_RUN_CHALLENGE_AFFIX_FAILED
	var battle_affix_ids: Array[StringName] = []
	for entry: ChallengeAffixEntryState in affix_result.entries:
		if entry.track == ChallengeAffixEntryState.BATTLE_AFFIX_TRACK:
			battle_affix_ids.append(entry.effect_id)
	_run_session = session_result.session
	_run_controller = RunController.new(
		_run_session, _save_repository, RunStateValidator.new(),
		RunSaveRootFactory.new(), battle_result.catalog
	)
	# S5-AC-014：四命令一律由 factory 建構、一律帶非 null relic_table；
	# 缺口 2：指揮官人口加成來源由 factory 於建構 CommitBoardLayoutCommand 時注入。
	_run_command_factory = RunCommandFactory.new(
		content.economy_catalog, table_result.table, battle_result.catalog,
		battle_affix_ids, run.commander_id,
		_commander_population_bonus(digest, run.commander_id),
		content.forge_table,
		content.consumable_rules
	)
	# wave5 修正 A4：RUN 狀態的驅動端。灰盒本身只是功能載體，但它推的是真的
	# RunController／RunCommandFactory——五個建構方法在此有唯一的正式呼叫端。
	_run_presentation_session = RunPresentationSession.new(
		_run_controller,
		_run_command_factory,
		battle_result.catalog,
		_battle_commander_passive_effect_ids(
			battle_result.catalog, commander_passive_effect_ids
		)
	)
	_run_lab_session = RunLabSession.new(_run_presentation_session)
	_unresumable_run_id = ""
	return &""


## BattleRuleCatalogBuilder 的 base roots：棋子／裝備／戰鬥遺物（build lab 既有集合）
## 再加遭遇——正式流程會在節點進入時編譯 encounter，故 encounter 必須是 root。
func _battle_root_ids(content: ProjectContentBootstrapResult) -> Array[StringName]:
	var roots: Array[StringName] = []
	roots.append_array(content.unit_ids)
	roots.append_array(content.equipment_ids)
	roots.append_array(content.battle_relic_ids)
	roots.append_array(content.encounter_ids)
	return roots


## G2 H1 前置：只有「純戰鬥」的指揮官被動能進 BattleSetupSourceCompiler。帶 scalar
## run_operations 的被動依內容契約一律 always-scope
## （content_validator._validate_always_only_claim_scope），而 battle setup 只接受
## once_per_node／on_first_clear，混進去會讓 StartCombatEvent 以 BATTLE_INPUT_INVALID 拒絕
## 整場戰鬥；那部分本來就由 RunModifierTable 的 always-active 路徑消費。
## G2 F5：這個判準的前提是「不存在同時帶 battle_operations 與 run_operations 的
## 指揮官被動」（混合型會連 battle 那半也被靜默丟掉）。前提由
## tests/unit/content_validation/test_commander_passive_effect_scope_is_single_sided.gd
## 對真實 pack 釘死——日後著作混合型被動時那條測試會紅，而不是戰鬥中被動悄悄失效。
func _battle_commander_passive_effect_ids(
	catalog: BattleRuleCatalog,
	passive_effect_ids: Array[StringName]
) -> Array[StringName]:
	var result: Array[StringName] = []
	if catalog == null:
		return result
	for effect_id: StringName in passive_effect_ids:
		var rule := catalog.try_effect_rule(effect_id)
		if (
			rule != null
			and not rule.battle_operations.is_empty()
			and rule.run_operations.is_empty()
		):
			result.append(effect_id)
	return result


func _release_active_run() -> void:
	_run_lab_session = null
	_release_run_presentation_session()
	_run_command_factory = null
	_run_controller = null
	_run_session = null


## facade 與 CombatCoordinator 互持強引用（皆為 RefCounted），只把 AppRoot 這一邊的
## 參照設 null 不會釋放任何一方；離開 run 範疇必須先顯式解綁。
func _release_run_presentation_session() -> void:
	if _run_presentation_session != null:
		_run_presentation_session.release()
	_run_presentation_session = null


# === camp 範疇組裝 =========================================================

func _compose_camp(profile: ProfileState) -> void:
	_camp_controller = null
	_camp_view_model = null
	_camp_profile_snapshot = null
	if profile == null:
		return
	_camp_profile_snapshot = profile.deep_clone()
	_camp_view_model = CampViewModel.new(profile)
	var content := _try_content()
	if content == null:
		return
	_camp_controller = CampController.new(profile, _save_repository, content.content_version)


## 結算/確認結果後重讀存檔，讓營地投影與 CampController 反映最新 profile。
func _refresh_camp_from_storage() -> void:
	var loaded := _save_repository.load()
	if loaded.ok and loaded.run_status == LoadResult.RunStatus.NONE:
		_unresumable_run_id = ""
	_compose_camp(loaded.profile if loaded.ok else null)


# === 內容 ==================================================================

## 安裝（並快取）當前 pinned generation。失敗只記一次、不重試（重試也只會撞同一份磁碟內容）。
## wave5 修正 A5：boot 路徑的呼叫端（_boot_route）把 null 轉成 boot_failed；boot 之後的
## lazy 呼叫端（start_expedition／settle_active_run）維持回傳具名錯誤碼。
func _try_content() -> ProjectContentBootstrapResult:
	if _content != null or _content_attempted:
		return _content
	_content_attempted = true
	_content_bootstrap_result = _content_bootstrap.run(_content_registry)
	if not _content_bootstrap_result.ok:
		push_warning(
			"AppRoot content bootstrap failed: %s"
			% _content_bootstrap_result.error_message
		)
		return null
	_content = _content_bootstrap_result
	return _content


## wave5 修正 B4（REQ-DATA-008）：指揮官定義一律經 CommanderContentReader 由 registry 的
## canonical view 重建，app 層不再碰 authoring 定義的共享實例。
func _try_commander_def(
	content: ProjectContentBootstrapResult,
	commander_id: StringName
) -> CommanderDef:
	return CommanderContentReader.new().try_read(
		_content_registry, content.manifest_digest, commander_id
	)


## 缺口 2 的來源值：指揮官的 population_bonus（無此指揮官＝無加成）。
func _commander_population_bonus(
	manifest_digest: String,
	commander_id: StringName
) -> int:
	var commander := CommanderContentReader.new().try_read(
		_content_registry, manifest_digest, commander_id
	)
	return commander.population_bonus if commander != null else 0

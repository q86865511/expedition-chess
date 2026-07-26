class_name ApplicationRoot
extends Node

## S5 T11（specs/meta-progression/design.md §4.4）：正式 composition root。
## boot 先安裝內容（wave5 修正 A1：存檔解碼要靠 registry 的 receipt port），再以
## `SaveRepository.load()` 分流——`RunStatus.LOADED` 就接回 active run
## （RunSession 取 catalog lease ＋ RunController ＋ RunCommandFactory，
## `transition_after_active_run_load` → RUN）；否則 BOOT→MENU→CAMP，掛 CampController
## ＋ CampViewModel ＋ Camp 灰盒（存檔不存在時先建初始 profile 並落檔，wave5 修正 A2）。
## `SceneRouter` 依 app state 換 Camp／Run／Results 場景（皆為 `scenes/dev/` 灰盒，比照
## combat_lab／build_lab 慣例；正式 UI 歸 Codex，見 HANDOFF.md）。
##
## 內容安裝委派給既有的 BuildLabContentBootstrap（`scripts/dev/build_lab/`）：它是本專案
## 唯一「從磁碟讀正式 .tres pack → ContentValidator → install_validated → 四個 production
## builder」的入口。app/ 層依 spec 契約不得直接載入 authoring Resource，故 AppRoot 只消費
## 它交出來的 pinned 產物，不自行 load 內容。

signal boot_completed
signal boot_failed(error_code: StringName)

const COMBAT_LAB_SCENE_PATH: String = "res://scenes/dev/combat_lab/combat_lab.tscn"
const CAMP_SCENE_PATH: String = "res://scenes/dev/camp/camp_scene.tscn"
const RESULTS_SCENE_PATH: String = "res://scenes/dev/results/results_scene.tscn"
## RUN 狀態的 presentation：wave5 修正 A4 起改成綁真 RunController／RunCommandFactory 的
## 最小 run 灰盒（scripts/dev/run/），取代原本純記憶體 demo 的 S3 expedition_lab。
const RUN_SCENE_PATH: String = "res://scenes/dev/run/run_scene.tscn"

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

@onready var presentation_host: Control = $PresentationHost

var _booted: bool = false
var _app_state_machine: AppStateMachine = AppStateMachine.new()
var _run_session: RunSession
var _run_controller: RunController
var _run_command_factory: RunCommandFactory
var _run_lab_session: RunLabSession
var _camp_controller: CampController
var _camp_view_model: CampViewModel
var _content_registry: ContentRegistryService
var _save_repository: SaveRepository
var _scene_router: SceneRouterService
var _services_bound: bool = false
var _content: BuildLabBootstrapResult
var _content_attempted: bool = false
## 只有「持久化 active run 載入成功，但 production composition 失敗」才設定。
## 玩家明示棄置時同時作為 compare-and-clear 的 expected_run_id。
var _unresumable_run_id: String = ""


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


func _ready() -> void:
	if presentation_host == null:
		boot_failed.emit(&"APP_PRESENTATION_HOST_MISSING")
		return
	if not _services_bound:
		_content_registry = get_node_or_null("/root/ContentRegistry") as ContentRegistryService
		_save_repository = get_node_or_null("/root/SaveService") as SaveRepository
		_scene_router = get_node_or_null("/root/SceneRouter") as SceneRouterService
	if _content_registry == null or _save_repository == null or _scene_router == null:
		boot_failed.emit(&"APP_REQUIRED_SERVICE_MISSING")
		return
	var receipt_port := ContentRegistryReceiptAdapter.new(_content_registry)
	var migration_port := ContentRegistryMigrationAdapter.new(_content_registry)
	var save_configuration: SaveConfigurationResult = (
		_save_repository._configure_content_ports(receipt_port, migration_port)
	)
	if not save_configuration.ok:
		boot_failed.emit(save_configuration.error.code)
		return
	_app_state_machine = AppStateMachine.new(_save_repository)
	_scene_router.bind_presentation_host(presentation_host)
	# S2 既有 dev override：--combat-lab 直接進 combat lab，不做 boot→load 分流。
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


## S5-AC-008：玩家明示棄置；expected id 由 composition 失敗當下釘住，CampController
## 仍會在交易內重新 load 比對。任何失敗都保留提示與持久化 run，成功才清除並刷新營地。
func discard_unresumable_active_run() -> StringName:
	if _app_state_machine.state() != AppStateMachine.State.CAMP:
		return ERROR_STATE_INVALID
	if _camp_controller == null:
		return ERROR_CAMP_UNAVAILABLE
	if _unresumable_run_id.is_empty():
		return DiscardActiveRunError.NOT_FOUND
	var discarded := _camp_controller.dispatch_discard_active_run(
		DiscardActiveRunCommand.new(_unresumable_run_id)
	)
	if not discarded.ok:
		return discarded.error.code
	_unresumable_run_id = ""
	_compose_camp(discarded.profile)
	_bind_routed_screen()
	return &""


## 營地五設施的唯讀投影（S5-AC-001）；尚未載入 profile 時為 null。
func try_camp_view_model() -> CampViewModel:
	return _camp_view_model


## 本 run 的命令唯一建構點（S5-AC-014：四命令＋board commit）；無 active run 時為 null。
## 實際的呼叫端是 RUN 灰盒的驅動器 RunLabSession（scripts/dev/run/），本存取器供測試與
## 未來的正式 run UI 取用。
func try_run_command_factory() -> RunCommandFactory:
	return _run_command_factory


## 遠征門：以已解鎖指揮官開新遠征。回 &"" 表成功，否則為具名失敗碼（結構性 APP_* 或
## CampController 傳回的 domain 拒絕碼）。成功時 CAMP→RUN 並換場。
func start_expedition(commander_id: StringName, challenge_level: int) -> StringName:
	if _app_state_machine.state() != AppStateMachine.State.CAMP:
		return ERROR_STATE_INVALID
	if _camp_controller == null:
		return ERROR_CAMP_UNAVAILABLE
	var content := _try_content()
	if content == null:
		return ERROR_CONTENT_UNAVAILABLE
	var commander_def := _try_commander_def(content, commander_id)
	if commander_def == null:
		return ERROR_COMMANDER_UNKNOWN
	var started := _camp_controller.dispatch_start_expedition(StartExpeditionCommand.new(
		commander_id, commander_def, challenge_level, content.receipt, content.economy_catalog
	))
	if not started.ok:
		return started.error.code
	# wave5 修正 A3：dispatch_start_expedition() 成功時 profile'＋新 run **已經**以單筆原子
	# 存檔提交、next_run_serial 已遞增——這裡的 compose 只是把記憶體物件接起來，不是
	# 「還沒動持久狀態」。因此 compose 失敗不會回滾任何東西：存檔裡已經有一個 active run，
	# 重開遊戲會走 boot 的續跑分流（A1 修好後成立），玩家不會失去這局。
	# 未消耗的一次性提交 token 隨 SaveResult 一起丟棄，不會被別的轉移冒用。
	var compose_error := _try_compose_active_run(started.profile, started.run)
	if not compose_error.is_empty():
		_unresumable_run_id = started.run.run_id
		# The transaction has already committed profile'+run. Keep CAMP's
		# projection/controller on that committed profile while exposing the
		# explicit discard entry; rebinding the old ViewModel would be stale.
		_compose_camp(started.profile)
		push_warning(
			"AppRoot started a run that could not be composed (the run is persisted and"
			+ " will resume on next boot): %s" % String(compose_error)
		)
		_bind_routed_screen()
		return compose_error
	var transitioned := _app_state_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), started.save_result
	)
	if not transitioned.ok:
		_release_active_run()
		_unresumable_run_id = started.run.run_id
		# transition failure also occurs after the atomic start commit.
		_compose_camp(started.profile)
		_bind_routed_screen()
		return transitioned.error.code
	_camp_view_model = CampViewModel.new(started.profile)
	return _route_for_state()


## 遠征終局的 meta 結算（design.md §5.1）：單一原子交易發貨幣/receipt/挑戰紀錄並清 active
## run，成功後 RUN→RESULTS 並換場。回 &"" 表成功。
func settle_active_run() -> StringName:
	if _app_state_machine.state() != AppStateMachine.State.RUN:
		return ERROR_STATE_INVALID
	var content := _try_content()
	if content == null or content.meta_reward_table == null:
		return ERROR_CONTENT_UNAVAILABLE
	var settled := MetaSettlementCommand.new(
		_save_repository, content.meta_reward_table
	).dispatch()
	if not settled.ok:
		return settled.error.code
	# wave5 修正 B2：dispatch 一旦成功，存檔裡的 active run 就已經被清掉、貨幣/receipt 也已
	# 發放——此時仍握著的 RunSession／RunController 是**已結算 run 的舊 session**，它的下一次
	# dispatch 會拿結算前的 profile 覆寫回去（等於讓已結算的 run 復活、獎勵二次發放）。
	# 故釋放必須綁在「dispatch 成功」而不是「轉移也成功」上。
	_release_active_run()
	var transitioned := _app_state_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.FINISH_RUN), settled.save_result
	)
	if not transitioned.ok:
		# run 已結算、session 已釋放，只是 app 狀態沒跟上：具名回報，重開遊戲會回到營地。
		_refresh_camp_from_storage()
		return transitioned.error.code
	_refresh_camp_from_storage()
	return _route_for_state()


## RESULTS→CAMP（無存檔提交）。回 &"" 表成功。
func acknowledge_results() -> StringName:
	if _app_state_machine.state() != AppStateMachine.State.RESULTS:
		return ERROR_STATE_INVALID
	var transitioned := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.ACKNOWLEDGE_RESULTS)
	)
	if not transitioned.ok:
		return transitioned.error.code
	_refresh_camp_from_storage()
	return _route_for_state()


# --- boot 分流 -------------------------------------------------------------

func _boot_combat_lab() -> StringName:
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
	if loaded.ok and loaded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
		# The profile is readable but opaque active-run bytes are intentionally
		# retained. Treating this as run-free CAMP would let ordinary writers
		# overwrite the preserved data without an expected run id.
		return MigrationError.RUN_INCOMPATIBLE_PRESERVED
	if loaded.ok and loaded.run_status == LoadResult.RunStatus.LOADED and loaded.run != null:
		var compose_error := _try_compose_active_run(loaded.profile, loaded.run)
		if compose_error.is_empty():
			var resumed := _app_state_machine.transition_after_active_run_load(
				AppEvent.new(AppEvent.Kind.ACTIVE_RUN_LOADED), loaded
			)
			if not resumed.ok:
				_release_active_run()
				return resumed.error.code
			_camp_view_model = CampViewModel.new(loaded.profile)
			return _route_for_state()
		# 接不回來（世代不符／內容不可用／表建不起來）時不吞掉存檔裡的 run：退回營地，
		# active run 仍持久，修好內容後重開即可續跑。wave5 修正 B3：各失敗原因具名可區分。
		push_warning("AppRoot could not resume the active run: %s" % String(compose_error))
		_unresumable_run_id = loaded.run.run_id
		_release_active_run()
	var booted := _app_state_machine.transition(AppEvent.new(AppEvent.Kind.BOOT_COMPLETED))
	if not booted.ok:
		return booted.error.code
	var camp := _app_state_machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP))
	if not camp.ok:
		return camp.error.code
	var profile := loaded.profile if loaded.ok else null
	if profile == null and loaded.profile_status == LoadResult.ProfileStatus.NOT_FOUND:
		# wave5 修正 A2：乾淨環境沒有任何 production 路徑會建 profile，營地因此一直是
		# 「尚未載入 profile」的死畫面。這裡建初始 profile 並**立即落檔**（run == null 的
		# CampSaveRootFactory 存檔），後續營地交易才有可寫回的基準。
		profile = _try_bootstrap_profile(content)
		if profile == null:
			return ERROR_PROFILE_BOOTSTRAP_FAILED
	_compose_camp(profile)
	return _route_for_state()


## 首次啟動的初始 profile：起始解鎖集合來自內容（unlock_kind == base_profile 的
## unlocked_content_refs），其餘欄位全是「什麼都還沒發生」的零值。建好即以單筆存檔提交，
## 失敗回 null（呼叫端轉成具名 boot 失敗）。
func _try_bootstrap_profile(content: BuildLabBootstrapResult) -> ProfileState:
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


# --- 換場（SceneRouter 依 app state）---------------------------------------

func _route_for_state() -> StringName:
	var scene_path := _scene_path_for_state()
	if scene_path.is_empty():
		# BOOT／MENU 無對應 presentation：不換場也不是錯誤。
		return &""
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return SceneRouterService.ERROR_SCENE_INVALID
	var route_error := _scene_router.replace_presentation(scene)
	if not route_error.is_empty():
		return route_error
	_bind_routed_screen()
	return &""


func _scene_path_for_state() -> String:
	match _app_state_machine.state():
		AppStateMachine.State.CAMP:
			return CAMP_SCENE_PATH
		AppStateMachine.State.RUN:
			return RUN_SCENE_PATH
		AppStateMachine.State.RESULTS:
			return RESULTS_SCENE_PATH
	return ""


## 灰盒場景由 SceneRouter 實例化，故建構後才由 composition root 餵 ViewModel。
func _bind_routed_screen() -> void:
	if presentation_host.get_child_count() == 0:
		return
	var screen := presentation_host.get_child(presentation_host.get_child_count() - 1)
	var camp_screen := screen as CampScreen
	if camp_screen != null:
		camp_screen.bind(self, _camp_view_model)
		return
	var run_screen := screen as RunScreen
	if run_screen != null:
		run_screen.bind(self, _run_lab_session)
		return
	var results_screen := screen as ResultsScreen
	if results_screen != null:
		results_screen.bind(self, _camp_view_model)


# --- run 範疇組裝 -----------------------------------------------------------

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
	# 缺口 1（§6.3 軌 A）：required_ids 必須帶上 challenge unlock 鏈，否則挑戰詞綴只透過
	# unlock.slice_challenge_N 的 modifier_refs 可達、不在 unit/encounter 的遞移閉包內，
	# challenge>=1 的戰鬥節點會以 EncounterCompiler.RULE_MISSING 進不去。
	var battle_result := BattleRuleCatalogBuilder.new().build(
		_content_registry, digest,
		RunCompositionSupport.required_battle_ids(
			_battle_root_ids(content), run.challenge_level
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
		_commander_population_bonus(digest, run.commander_id)
	)
	# wave5 修正 A4：RUN 狀態的驅動端。灰盒本身只是功能載體，但它推的是真的
	# RunController／RunCommandFactory——五個建構方法在此有唯一的正式呼叫端。
	_run_lab_session = RunLabSession.new(
		_run_controller, _run_command_factory, content.economy_catalog,
		battle_result.catalog,
		CommanderContentReader.new().passive_effect_ids(
			_content_registry, digest, run.commander_id
		)
	)
	_unresumable_run_id = ""
	return &""


## BattleRuleCatalogBuilder 的 base roots：棋子／裝備／戰鬥遺物（build lab 既有集合）
## 再加遭遇——正式流程會在節點進入時編譯 encounter，故 encounter 必須是 root。
func _battle_root_ids(content: BuildLabBootstrapResult) -> Array[StringName]:
	var roots: Array[StringName] = []
	roots.append_array(content.unit_ids)
	roots.append_array(content.equipment_ids)
	roots.append_array(content.battle_relic_ids)
	roots.append_array(content.encounter_ids)
	return roots


func _release_active_run() -> void:
	_run_lab_session = null
	_run_command_factory = null
	_run_controller = null
	_run_session = null


# --- camp 範疇組裝 ---------------------------------------------------------

func _compose_camp(profile: ProfileState) -> void:
	_release_active_run()
	_camp_controller = null
	_camp_view_model = null
	if profile == null:
		return
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


# --- 內容 ------------------------------------------------------------------

## 安裝（並快取）當前 pinned generation。失敗只記一次、不重試（重試也只會撞同一份磁碟內容）。
## wave5 修正 A5：boot 路徑的呼叫端（_boot_route）把 null 轉成 boot_failed；boot 之後的
## lazy 呼叫端（start_expedition／settle_active_run）維持回傳具名錯誤碼。
func _try_content() -> BuildLabBootstrapResult:
	if _content != null or _content_attempted:
		return _content
	_content_attempted = true
	var bootstrap := BuildLabContentBootstrap.new().run(_content_registry)
	if not bootstrap.ok:
		push_warning("AppRoot content bootstrap failed: %s" % bootstrap.error_message)
		return null
	_content = bootstrap
	return _content


## wave5 修正 B4（REQ-DATA-008）：指揮官定義一律經 CommanderContentReader 由 registry 的
## canonical view 重建，app 層不再碰 authoring 定義的共享實例。
func _try_commander_def(
	content: BuildLabBootstrapResult,
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

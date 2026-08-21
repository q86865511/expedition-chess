class_name ProductionScreen
extends Control

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"
const SCREEN_ALREADY_BOUND: StringName = &"SCREEN_ALREADY_BOUND"
const SCREEN_BIND_TOO_LATE: StringName = &"SCREEN_BIND_TOO_LATE"
const SCREEN_ROUTE_MISMATCH: StringName = &"SCREEN_ROUTE_MISMATCH"
const SCREEN_LIVE_CONTEXT_INVALID: StringName = &"SCREEN_LIVE_CONTEXT_INVALID"
const SCREEN_COMPOSITION_MISSING: StringName = &"SCREEN_COMPOSITION_MISSING"
const SCREEN_COMPOSITION_TYPE_INVALID: StringName = \
	&"SCREEN_COMPOSITION_TYPE_INVALID"
const SYSTEM_MENU_BIND_INVALID: StringName = &"SYSTEM_MENU_BIND_INVALID"
const SYSTEM_MENU_INPUT: StringName = &"system_menu"
const SYSTEM_MENU_BUTTON_NODE: StringName = &"SystemMenuButton"
const SYSTEM_MENU_BUTTON_LOCALIZATION_KEY: StringName = &"system_menu.open"
const RUN_ROUTES: Array[StringName] = [
	&"RUN_MAP",
	&"RUN_PREPARE",
	&"RUN_COMBAT",
	&"RUN_REWARD",
]
const CAMP_FACILITY_ROUTES: Array[StringName] = [
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
]
const SHELL_ROUTES: Array[StringName] = [
	&"SETTINGS",
	&"CAMP_WORLD",
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
	&"RUN_MAP",
	&"RUN_PREPARE",
	&"RUN_COMBAT",
	&"RUN_REWARD",
	&"RESULTS",
	&"RESULTS_FALLBACK",
]
const SYSTEM_MENU_ROUTES: Array[StringName] = [
	&"SETTINGS",
	&"CAMP_WORLD",
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
	&"RUN_MAP",
	&"RUN_PREPARE",
	&"RUN_COMBAT",
	&"RUN_REWARD",
	&"RUN_ROUTE_FALLBACK",
	&"APP_ROUTE_FALLBACK",
	&"RESULTS",
	&"RESULTS_FALLBACK",
]

const RECOVERY_MODAL_NODE: String = "RecoveryConfirmation"
## design :201「UI 只由 unacknowledged committed receipt 顯示 result」的顯示端節點名。
const NODE_CHOICE_RESULT_NODE: String = "NodeChoiceResult"
const PREPARE_ACTION_GROUP_SELECTOR: StringName = &"PrepareActionGroupSelector"
const PREPARE_ACTION_GROUPS: Array[Dictionary] = [
	{
		"id": &"forge_equipment",
		"label_key": &"prepare.group.forge_equipment",
		"actions": [
			&"prepare.forge", &"prepare.forge.confirm", &"prepare.forge.cancel",
			&"prepare.equip", &"prepare.dismantle", &"service.dismantle",
			&"service.exit",
		],
	},
	{
		"id": &"party",
		"label_key": &"prepare.group.party",
		"actions": [
			&"prepare.unit", &"prepare.move_board", &"prepare.move_bench",
			&"prepare.sell",
		],
	},
	{
		"id": &"advance",
		"label_key": &"prepare.group.advance",
		"actions": [
			&"choice.begin", &"choice.confirm", &"choice.cancel", &"choice.ack",
		],
	},
]
const PREPARE_PINNED_ACTIONS: Array[StringName] = [
	&"prepare.start",
]
## Action semantics remain keyed by `action_id`; only the compact visual label
## may use a shorter, already-localized sibling key. Assistive copy and tooltip
## keep resolving the full semantic action key.
const ACTION_VISUAL_LOCALIZATION_KEYS: Dictionary = {
	&"service.dismantle": &"prepare.dismantle",
}
## ShopQuoteSnapshot.rejection_code 是尚未 dispatch 的停用原因，不經
## PresentationErrorMapper；面板直接把 domain ShopError 具名碼對到玩家文案。
const _SHOP_REJECTION_MESSAGE_KEYS: Dictionary = {
	&"SHOP_GOLD_INSUFFICIENT": &"error.shop.gold_insufficient",
	&"SHOP_LEVEL_MAX": &"error.shop.level_max",
	&"SHOP_OFFER_STALE": &"error.shop.offer_stale",
	&"SHOP_ROSTER_FULL": &"error.shop.roster_full",
	&"SHOP_UNIT_MISSING": &"error.shop.unit_missing",
	&"SHOP_UNIT_RULE_MISSING": &"error.shop.unit_rule_missing",
	&"SHOP_UNIT_POOL_INVALID": &"error.shop.unit_pool_invalid",
	&"SHOP_RESERVATION_INVALID": &"error.shop.reservation_invalid",
	&"SHOP_CATALOG_GENERATION_MISMATCH": &"error.shop.generation_mismatch",
	&"SHOP_INPUT_INVALID": &"error.shop.input_invalid",
	&"SHOP_RNG_FAILED": &"error.shop.internal_failure",
	&"SHOP_KEY_FAILED": &"error.shop.internal_failure",
	&"SHOP_DIGEST_FAILED": &"error.shop.internal_failure",
	&"SHOP_CONFIG_INVALID": &"error.shop.internal_failure",
	&"SHOP_SERIAL_EXHAUSTED": &"error.shop.internal_failure",
	&"SHOP_MERGE_FAILED": &"error.shop.internal_failure",
}
const _SHOP_TRAIT_ATLAS: Texture2D = preload(
	"res://assets/production/shared/trait.png"
)

## G2 M2／建議項1：不可逆（或代價高）的離開動作先出確認 modal，確認前零 dispatch。
## `menu.recovery` 不在此表——它的確認狀態由 app 層的 RecoveryConfirmationPresenter 持有，
## 觸發鍵本身就要 dispatch 才能開啟 app 端 confirmation（見 `_show_recovery_confirmation`）。
const _PRESENTATION_CONFIRMATIONS: Dictionary = {
	&"run.menu": {
		"node": "RunMenuConfirmation",
		"status_key": &"run.menu.status",
		"confirm": &"run.menu.confirm",
		"cancel": &"run.menu.cancel",
	},
	&"menu.exit": {
		"node": "ExitConfirmation",
		"status_key": &"menu.exit.status",
		"confirm": &"menu.exit.confirm",
		"cancel": &"menu.exit.cancel",
	},
}

@export var route_kind: StringName

var _context: StagedScreenContext
var _live_context: ProductionLiveScreenContext
var _binding_closed: bool = false
var _live_active: bool = false
var _last_control_result: Variant
var _status_view := PresentationStatusView.new()
var _modal_open: bool = false
var _modal_node_name: String = ""
var _modal_confirm_action: StringName = &""
var _modal_cancel_action: StringName = &""
## 非空＝呈現層確認：confirm 之前完全不 dispatch，confirm 時才送出這個動作。
var _modal_deferred_action: StringName = &""
var _modal_deferred_payload: Dictionary = {}
var _modal_status_key: StringName = &""
var _modal_trigger: Button
var _modal_background_disabled: Dictionary[int, bool] = {}
var _modal_background_focus: Dictionary[int, int] = {}
var _modal_background_mouse: Dictionary[int, int] = {}
var _modal_background_controls: Dictionary[int, Control] = {}
var _modal_composition_focus_behavior: int = Control.FOCUS_BEHAVIOR_INHERITED
var _modal_composition_process_mode: int = Node.PROCESS_MODE_INHERIT
var _prepare_action_group_selector: OptionButton
var _prepare_action_group_pages: Array[GridContainer] = []
var _layout_shell: ProductionLayoutShell
var _system_menu_button: Button
var _system_menu_overlay: SystemMenuOverlay
var _system_menu_settings_snapshot: SettingsSnapshot
var _system_menu_settings_port: SettingsApplicationPort
var _system_menu_exit_handler: Callable
var _system_menu_pause_captured: bool = false
var _system_menu_previous_paused: bool = false
var _prepare_refresh_quote: ShopQuoteSnapshot
var _prepare_xp_quote: ShopXpQuoteSnapshot
var _route_ui_scale_percent: int = 100
var _audio_director: ProductionAudioDirector


func _ready() -> void:
	# RunMap/Prepare/Combat/Reward compositions also inherit ProductionScreen,
	# but only the route root owns audio. Their exported route_kind remains empty.
	if not route_kind.is_empty():
		_attach_audio_director()
	_binding_closed = true


## App composition root 可在 route activate 前注入目前 committed settings 與既有
## application port；overlay 只持 clone 與 typed port，不自行存檔或切換 route。
func bind_system_menu_settings(
	snapshot: SettingsSnapshot,
	port: SettingsApplicationPort
) -> StringName:
	if snapshot == null or port == null or (
		_system_menu_overlay != null and _system_menu_overlay.is_open()
	):
		return SYSTEM_MENU_BIND_INVALID
	_system_menu_settings_snapshot = snapshot.deep_clone()
	_system_menu_settings_port = port
	if _system_menu_overlay != null:
		_configure_system_menu_overlay()
	return &""


## 測試宿主或平台 shell 可攔截退出；未注入時 production 先走 action port，
## 若 route 沒提供 menu.exit 才使用 SceneTree.quit()，不新增 Autoload。
func bind_system_menu_exit_handler(handler: Callable) -> StringName:
	if not handler.is_valid():
		return SYSTEM_MENU_BIND_INVALID
	_system_menu_exit_handler = handler
	return &""


func system_menu_overlay() -> SystemMenuOverlay:
	return _system_menu_overlay


func system_menu_button() -> Button:
	return _system_menu_button


func system_menu_state() -> StringName:
	return (
		_system_menu_overlay.state_name()
		if _system_menu_overlay != null
		else &"CLOSED"
	)


## Child compositions use this query instead of reaching into route-shell
## modal/menu state. Background shortcuts stay blocked until the overlay closes.
func is_background_input_blocked() -> bool:
	if _modal_open:
		return true
	return (
		_system_menu_overlay != null
		and _system_menu_overlay.is_open()
	)


func open_system_menu() -> bool:
	if (
		route_kind not in SYSTEM_MENU_ROUTES
		or not _live_active
		or _modal_open
		or _system_menu_overlay == null
		or _system_menu_overlay.is_open()
	):
		return false
	if not _capture_combat_pause_for_system_menu():
		return false
	if _system_menu_overlay.open(_ordered_focus_controls(), self):
		_play_audio_cue(&"audio.ui_confirm", {"source": &"system_menu_open"})
		return true
	_restore_combat_pause_after_system_menu()
	return false


func close_system_menu() -> bool:
	return (
		_system_menu_overlay.close()
		if _system_menu_overlay != null
		else false
	)


func bind(context: StagedScreenContext) -> StringName:
	if _context != null:
		return SCREEN_ALREADY_BOUND
	if _binding_closed:
		return SCREEN_BIND_TOO_LATE
	if context == null or (
		not route_kind.is_empty() and context.route_kind != route_kind
	):
		return SCREEN_ROUTE_MISMATCH
	_context = context
	if route_kind == &"SETTINGS":
		var settings_composition := (
			get_node_or_null("Composition") as SettingsScreenComposition
		)
		if settings_composition == null:
			return SCREEN_COMPOSITION_TYPE_INVALID
		var settings_error := settings_composition.stage(
			context.snapshot_clone() as SettingsSnapshot,
			context.localized_text
		)
		if not settings_error.is_empty():
			return settings_error
	_bind_localized_controls()
	_attach_focus_indicator()
	return &""


func prepare_live_binding(
	context: ProductionLiveScreenContext
) -> StringName:
	if (
		_live_context != null
		or context == null
		or context.route_kind != route_kind
	):
		return SCREEN_LIVE_CONTEXT_INVALID
	_capture_prepare_shop_quotes(context)
	var composition_error := _compose_production_child(context)
	if not composition_error.is_empty():
		return composition_error
	_apply_prepare_shop_quote_controls()
	_live_context = context
	_configure_system_menu_overlay()
	return &""


## Live lease 只在 bind 事件讀一次；控制項後續只持 DTO clone，不逐幀查 supply。
func _capture_prepare_shop_quotes(context: ProductionLiveScreenContext) -> void:
	_prepare_refresh_quote = null
	_prepare_xp_quote = null
	if (
		route_kind != &"RUN_PREPARE"
		or context == null
		or context.supply_port == null
	):
		return
	var refresh := context.supply_port.shop_refresh_quote()
	var xp := context.supply_port.shop_buy_xp_quote()
	_prepare_refresh_quote = refresh.deep_clone() if refresh != null else null
	_prepare_xp_quote = xp.deep_clone() if xp != null else null


func activate_live() -> void:
	_live_active = _live_context != null
	if not _live_active:
		return
	var buttons := _action_buttons()
	for button: Button in buttons:
		if (
			button.has_meta(&"system_menu_owned")
			or button.has_meta(&"direct_action_owned")
			or button.has_meta(&"read_only_snapshot_control")
		):
			continue
		if not button.pressed.is_connected(_on_action_pressed.bind(button)):
			button.pressed.connect(_on_action_pressed.bind(button))
	if _system_menu_button != null:
		_system_menu_button.disabled = false
	refresh_interaction_state()
	var focusable := _ordered_focus_controls()
	if not focusable.is_empty():
		call_deferred(&"_grab_focus_deferred", focusable[0])


func _unhandled_input(event: InputEvent) -> void:
	if (
		route_kind not in SYSTEM_MENU_ROUTES
		or event == null
		or not event.is_action_pressed(SYSTEM_MENU_INPUT, false, true)
	):
		return
	var audio_sequence_before := _audio_playback_sequence()
	var handled := false
	if _modal_open:
		handled = _cancel_active_confirmation()
	elif _dismiss_visible_popup():
		handled = true
	elif _dismiss_focused_text_edit():
		handled = true
	elif _system_menu_overlay != null and _system_menu_overlay.is_open():
		handled = _system_menu_overlay.handle_system_menu_action()
	else:
		handled = open_system_menu()
	if handled and _audio_playback_sequence() == audio_sequence_before:
		_play_audio_cue(&"audio.ui_cancel", {"source": &"system_menu_input"})
	if handled and is_inside_tree():
		get_viewport().set_input_as_handled()


func request_intent(intent: RunPresentationIntent) -> RunPresentationResult:
	if _live_active and _live_context.intent_port != null:
		var result := _live_context.intent_port.dispatch(intent)
		if _audio_director != null and is_instance_valid(_audio_director):
			_audio_director.present_intent_result(intent, result)
		return result
	var failure := RunPresentationResult.failure(
		DiagnosticError.new(
			SCREEN_NOT_ACTIVE,
			&"error.presentation.screen_not_active"
		)
	)
	if _audio_director != null and is_instance_valid(_audio_director):
		_audio_director.present_intent_result(intent, failure)
	return failure


func present_combat_audio(events: Array) -> Dictionary:
	return (
		_audio_director.present_combat_events(events)
		if _audio_director != null and is_instance_valid(_audio_director)
		else {}
	)


func audio_playback_report() -> Dictionary:
	return (
		_audio_director.playback_report()
		if _audio_director != null and is_instance_valid(_audio_director)
		else {}
	)


## design :201-205：result 顯示與 ack 由 run-level ledger 驅動，不綁 resolution state
## 也不綁 phase——三種 outcome 分別落在 RUN_MAP／RUN_REWARD／RUN_PREPARE（design
## :206-209），所以顯示端與 ack 入口掛在 route 層，由各 composition 提供自己持有的
## snapshot 投影。不參與 node choice 的畫面沿用以下預設（無結果可播、ack 不可用）。
func pending_node_choice_result() -> NodeChoiceResultSnapshot:
	return null


func acknowledge_node_choice_result() -> RunPresentationResult:
	return RunPresentationResult.failure(
		DiagnosticError.new(
			SCREEN_NOT_ACTIVE,
			&"error.presentation.screen_not_active"
		)
	)


## ledger 依 transaction_serial 升冪；取最舊的一筆＝先播先 ack 的佇列語意。
## 每一筆 unacknowledged receipt 都會先被顯示、再被同一個 receipt_digest ack 掉，
## 因此不會有 receipt 被跳過而永久留在 ledger（review N1）。
static func _oldest_pending_node_choice_result(
	snapshot: RunPresentationSnapshot
) -> NodeChoiceResultSnapshot:
	if snapshot == null or snapshot.pending_node_choice_results.is_empty():
		return null
	return snapshot.pending_node_choice_results[0]


static func _node_choice_ack_intent(
	snapshot: RunPresentationSnapshot,
	result: NodeChoiceResultSnapshot
) -> RunPresentationIntent:
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT
	)
	intent.expected_run_id = String(snapshot.run_id)
	intent.receipt_digest = result.receipt_digest
	return intent


func last_control_result() -> Variant:
	return _last_control_result


## G2 H3：畫面上實際顯示的錯誤文字（成功／未操作時為空字串）。
func status_message_text() -> String:
	return _status_view.message_text()


## 對應的 `PresentationErrorMapper` 報告（committed／fallback_active／retryable／
## source_code／message_key）；沒有錯誤時為空 Dictionary。
func status_report() -> Dictionary:
	return _status_view.report()


## G2 F1：狀態列本體。測試據此驗「畫面上真的看得到」（rect／z 序），
## 只讀 `status_message_text()` 驗不到被蓋住或被壓成 1px 的缺陷。
func status_message_control() -> Label:
	return get_node_or_null(PresentationStatusView.NODE_NAME) as Label


## G2 F3：Composition 自行驅動（沒有對應按鈕）的動作失敗回饋出口。自動 SETTLE
## 這類動作若不接進狀態列，玩家會停在一個播完的戰鬥前面、零訊息也零出路。
## 只寫狀態列，不動 `_last_control_result`——那是按鈕 dispatch 的結果欄位。
func report_composition_result(result: Variant) -> void:
	_status_view.show_result(result, _text_resolver())
	_sync_status_band_visibility()


func is_confirmation_modal_open() -> bool:
	return (
		_modal_open
		or (
			_system_menu_overlay != null
			and _system_menu_overlay.is_confirmation_open()
		)
	)


func confirmation_modal_node_name() -> String:
	if _modal_open:
		return _modal_node_name
	return (
		_system_menu_overlay.confirmation_node_name()
		if _system_menu_overlay != null
		else ""
	)


func settings_draft() -> SettingsSnapshot:
	var composition := (
		get_node_or_null("Composition") as SettingsScreenComposition
	)
	return composition.settings_draft() if composition != null else null


func control_status_code() -> StringName:
	var composition := (
		get_node_or_null("Composition") as SettingsScreenComposition
	)
	return (
		composition.control_status_code()
		if composition != null
		else &""
	)


func localized_content_text(content_id: StringName) -> String:
	var fallback := String(content_id)
	if _context == null or content_id.is_empty():
		return fallback
	var key := StringName(
		"loc.%s" % fallback.replace(".", "_")
	)
	var resolved := _context.resolve_text(key)
	return fallback if resolved == String(key) else resolved


## G2 M5：Composition 子畫面取 UI 文案鍵的唯一出口（內容 id 走 localized_content_text）。
func localized_ui_text(text_key: StringName) -> String:
	if _context == null or text_key.is_empty():
		return String(text_key)
	return _context.resolve_text(text_key)


func layout_content(region: StringName) -> Control:
	return _layout_shell.content(region) if _layout_shell != null else null


func layout_region_content_rect(region: StringName) -> Rect2:
	return (
		_layout_shell.current_content_rect(region)
		if _layout_shell != null
		else Rect2()
	)


func content_tooltip_text(
	label_key: StringName,
	numeric_value: int,
	depth: int = 1
) -> String:
	if _context == null:
		return ""
	var formatted := ContentTooltipFormatter.new().format_value(
		label_key,
		localized_ui_text(label_key),
		numeric_value,
		_context.locale,
		0,
		depth
	)
	if not formatted.ok or formatted.snapshot == null:
		return ""
	return "%s: %d" % [
		formatted.snapshot.text,
		formatted.snapshot.numeric_value,
	]


func live_binding_report() -> Dictionary:
	return {
		"active": _live_active,
		"action": (
			_live_context != null and _live_context.action_port != null
		),
		"navigation": (
			_live_context != null and _live_context.navigation_port != null
		),
		"intent": (
			_live_context != null and _live_context.intent_port != null
		),
		"playback": (
			_live_context != null and _live_context.playback_port != null
		),
		"inspection": (
			_live_context != null and _live_context.inspection_port != null
		),
		"raw_session": false,
	}


func _bind_localized_controls() -> void:
	_install_b1_layout()
	_install_fullscreen_ui_background()
	var label := find_child("Label", true, false) as Label
	if label != null:
		label.text = _context.resolve_text(_route_title_key())
	_configure_non_b1_layout(label)
	# G2 H3：常駐錯誤呈現面。每個 staged route 都要有，才不會出現「某些畫面
	# 操作失敗完全沒回饋」的死角。
	var status_rect := (
		_layout_shell.current_content_rect(ProductionLayoutShell.REGION_STATUS)
		if _layout_shell != null
		else Rect2()
	)
	_status_view.attach(self, 0, status_rect)
	_status_view.clear(_text_resolver())
	_sync_status_band_visibility()
	var action_ids := _required_action_ids()
	if action_ids.is_empty():
		return
	if action_ids.has(&"choice.ack"):
		# design :201 的顯示端：文字在 refresh_interaction_state 由 unacknowledged
		# receipt 的 result_key 決定，沒有結果時整個節點隱藏。
		var result_label := Label.new()
		result_label.name = NODE_CHOICE_RESULT_NODE
		result_label.visible = false
		add_child(result_label)
	if route_kind == &"CAMP_WORLD" and _layout_shell != null:
		_build_camp_action_controls(action_ids)
	elif route_kind in CAMP_FACILITY_ROUTES and _layout_shell != null:
		var facility_actions := HBoxContainer.new()
		facility_actions.name = "Actions"
		facility_actions.alignment = BoxContainer.ALIGNMENT_END
		facility_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facility_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(
			facility_actions
		)
		for action_id: StringName in action_ids:
			var facility_action := _new_action_button(action_id)
			facility_action.theme_type_variation = \
				&"ExpeditionCampSecondaryAction"
			ExpeditionLayoutMetrics.set_fixed_min(
				facility_action, 240.0, 72.0
			)
			facility_action.size_flags_horizontal = Control.SIZE_SHRINK_END
			facility_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			facility_actions.add_child(facility_action)
	elif route_kind == &"RUN_PREPARE" and _layout_shell != null:
		var controls := HBoxContainer.new()
		controls.name = "Actions"
		controls.theme_type_variation = &"ExpeditionPrepareBottomBand"
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(controls)
		_build_prepare_action_controls(controls, action_ids)
	elif route_kind == &"RUN_COMBAT" and _layout_shell != null:
		var controls := VBoxContainer.new()
		controls.name = "Actions"
		controls.theme_type_variation = &"ExpeditionPrepareBottomBand"
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
		controls.clip_contents = true
		# The shell's bottom Content is the geometry authority. As its sole
		# expanding child, Actions follows scale/status relayout without copying
		# an absolute reference rect into the composition.
		var bottom_content := layout_content(
			ProductionLayoutShell.REGION_BOTTOM
		)
		bottom_content.add_child(controls)
		_build_combat_snapshot_controls(controls, action_ids)
	elif route_kind in RUN_ROUTES and _layout_shell != null:
		# MAP / REWARD share the same authored bottom action band as PREPARE.
		# Bottom Content is the sole geometry authority: Actions is its only
		# expanding child, so scale/status relayout is owned by Containers instead
		# of copying a cached shell rect onto a root-level control.
		var controls := HBoxContainer.new()
		controls.name = "Actions"
		controls.theme_type_variation = &"ExpeditionPrepareBottomBand"
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
		controls.alignment = BoxContainer.ALIGNMENT_END
		layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(controls)
		for action_id: StringName in action_ids:
			var action := _new_action_button(action_id)
			action.theme_type_variation = &"ExpeditionBottomAction"
			if route_kind == &"RUN_MAP":
				ExpeditionLayoutMetrics.set_fixed_min(
					action,
					ExpeditionLayoutMetrics.RUN_MAP_BOTTOM_ACTION_SIZE.x,
					ExpeditionLayoutMetrics.RUN_MAP_BOTTOM_ACTION_SIZE.y
				)
				action.size_flags_horizontal = Control.SIZE_SHRINK_END
				action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			else:
				action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			controls.add_child(action)
	else:
		var uses_outgame_shell := route_kind in [
			&"SETTINGS", &"RESULTS", &"RESULTS_FALLBACK",
		]
		var controls: BoxContainer = (
			HBoxContainer.new()
			if uses_outgame_shell
			else VBoxContainer.new()
		)
		controls.name = "Actions"
		if uses_outgame_shell:
			controls.z_index = 6
		else:
			# 動作欄真置中：PRESET_CENTER 的錨點在中心，但預設 grow 會讓
			# 左上角落在中心；grow BOTH 才是真置中（同 modal 的 P10 修法）。
			# `Actions` 維持為畫面直屬子節點——多處程式與測試以
			# `get_node(^"Actions")` 取用它，不得改變節點路徑。
			controls.set_anchors_preset(Control.PRESET_CENTER)
			controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
			controls.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(controls)
		for action_id: StringName in action_ids:
			var action := _new_action_button(action_id)
			if uses_outgame_shell:
				action.theme_type_variation = &"ExpeditionBottomAction"
				action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			controls.add_child(action)
		if route_kind == &"MENU_MAIN":
			_apply_menu_layout(controls)
		_apply_settings_layout(100)
		_apply_results_layout()
	_install_system_menu()


func _apply_menu_layout(controls: BoxContainer, scale_percent: int = 100) -> void:
	if route_kind != &"MENU_MAIN" or controls == null:
		return
	var factor := clampf(float(scale_percent) / 100.0, 1.0, 1.5)
	var actions_rect := ExpeditionLayoutMetrics.MENU_ACTIONS_RECT
	var actions_right := actions_rect.end.x
	actions_rect.size.x = roundf(actions_rect.size.x * factor)
	actions_rect.position.x = actions_right - actions_rect.size.x
	# MENU actions sit directly on the ImageGen-authored quiet area. The fixed
	# right edge keeps 100/125/150% hit-rect growth inside the safe canvas without
	# reintroducing a full-height backing panel.
	var obsolete_panel := get_node_or_null(^"MenuActionPanel")
	if obsolete_panel != null:
		obsolete_panel.queue_free()
	controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls.grow_horizontal = Control.GROW_DIRECTION_END
	controls.grow_vertical = Control.GROW_DIRECTION_END
	controls.position = actions_rect.position
	controls.size = actions_rect.size
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.z_index = 3
	for node: Node in controls.get_children():
		var button := node as Button
		if button == null:
			continue
		button.theme_type_variation = &"ExpeditionMenuAction"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not button.has_meta(ExpeditionLayoutMetrics.META_BASE_MINIMUM):
			ExpeditionLayoutMetrics.set_min(button, 0.0, 72.0)


func _install_system_menu() -> void:
	if route_kind not in SYSTEM_MENU_ROUTES or _system_menu_overlay != null:
		return
	_system_menu_button = Button.new()
	_system_menu_button.name = SYSTEM_MENU_BUTTON_NODE
	_system_menu_button.text = _context.resolve_text(
		SYSTEM_MENU_BUTTON_LOCALIZATION_KEY
	)
	_system_menu_button.focus_mode = Control.FOCUS_ALL
	_system_menu_button.disabled = true
	# Visible text, accessibility text, and stable metadata share one exact key.
	_system_menu_button.set_meta(
		&"localization_key", SYSTEM_MENU_BUTTON_LOCALIZATION_KEY
	)
	_system_menu_button.set_meta(
		&"accessible_text", _system_menu_button.text
	)
	_system_menu_button.set_meta(&"system_menu_owned", true)
	_system_menu_button.pressed.connect(_on_system_menu_button_pressed)
	ExpeditionLayoutMetrics.set_fixed_min(_system_menu_button, 270.0, 72.0)
	var button_host := layout_content(ProductionLayoutShell.REGION_OVERLAY)
	if button_host != null and _layout_shell != null:
		button_host.add_child(_system_menu_button)
		_system_menu_button.set_anchors_and_offsets_preset(
			Control.PRESET_TOP_LEFT
		)
		var top_rect := _layout_shell.current_content_rect(
			ProductionLayoutShell.REGION_TOP
		)
		_system_menu_button.position = Vector2(
			top_rect.end.x - 270.0, top_rect.position.y
		)
		_system_menu_button.size = Vector2(270.0, 72.0)
	else:
		_system_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_system_menu_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_system_menu_button.position = Vector2(-306.0, 36.0)
		add_child(_system_menu_button)
	_system_menu_overlay = SystemMenuOverlay.new()
	_system_menu_overlay.name = "SystemMenuOverlay"
	var overlay_host := layout_content(ProductionLayoutShell.REGION_OVERLAY)
	if overlay_host != null:
		overlay_host.add_child(_system_menu_overlay)
	else:
		add_child(_system_menu_overlay)
	_configure_system_menu_overlay()
	_system_menu_overlay.closed.connect(_on_system_menu_closed)
	_system_menu_overlay.return_to_menu_requested.connect(
		_on_system_menu_return_to_menu_requested
	)
	_system_menu_overlay.exit_requested.connect(
		_on_system_menu_exit_requested
	)
	_system_menu_overlay.settings_applied.connect(
		_on_system_menu_settings_applied
	)


func _on_system_menu_button_pressed() -> void:
	open_system_menu()


func _on_system_menu_closed() -> void:
	_restore_combat_pause_after_system_menu()
	_apply_keyboard_focus_graph()


func _on_system_menu_return_to_menu_requested() -> void:
	close_system_menu()
	var action_id := _system_menu_return_action_id()
	if (
		not action_id.is_empty()
		and _live_active
		and _live_context != null
		and _live_context.action_port != null
	):
		_dispatch_action(action_id, null)


func _configure_system_menu_overlay() -> void:
	if _system_menu_overlay == null:
		return
	_system_menu_overlay.configure(
		_localized_text_clone(),
		_system_menu_settings_snapshot,
		_system_menu_settings_port,
		not _system_menu_return_action_id().is_empty()
	)


func _system_menu_return_action_id() -> StringName:
	if _live_context == null or _live_context.action_port == null:
		return &""
	var available := _live_context.action_port.action_ids()
	for action_id: StringName in [
		&"run.menu", &"camp.menu", &"results.menu",
	]:
		if action_id in available:
			return action_id
	return &""


func _on_system_menu_exit_requested() -> void:
	close_system_menu()
	if _system_menu_exit_handler.is_valid():
		_system_menu_exit_handler.call()
		return
	if (
		_live_context != null
		and _live_context.action_port != null
		and _live_context.action_port.action_ids().has(&"menu.exit")
	):
		_dispatch_action(&"menu.exit", null)
		return
	if is_inside_tree():
		get_tree().quit()


func _on_system_menu_settings_applied(
	result: SettingsApplicationResult
) -> void:
	if result == null:
		return
	if result.snapshot != null:
		_system_menu_settings_snapshot = result.snapshot.deep_clone()
	_status_view.show_result(result, _text_resolver())
	_sync_status_band_visibility()


func _capture_combat_pause_for_system_menu() -> bool:
	if route_kind != &"RUN_COMBAT" or _system_menu_pause_captured:
		return true
	if _live_context == null or _live_context.playback_port == null:
		return false
	var current := _live_context.playback_port.try_playback()
	if not current.ok or current.state == null:
		_status_view.show_result(current, _text_resolver())
		_sync_status_band_visibility()
		return false
	var previous := current.state.paused
	var pause_result := _live_context.playback_port.set_paused(true)
	if not pause_result.ok:
		_status_view.show_result(pause_result, _text_resolver())
		_sync_status_band_visibility()
		return false
	_system_menu_previous_paused = previous
	_system_menu_pause_captured = true
	return true


func _restore_combat_pause_after_system_menu() -> void:
	if not _system_menu_pause_captured:
		return
	var previous := _system_menu_previous_paused
	_system_menu_pause_captured = false
	_system_menu_previous_paused = false
	if _live_context == null or _live_context.playback_port == null:
		return
	var restore_result := _live_context.playback_port.set_paused(previous)
	if not restore_result.ok:
		_status_view.show_result(restore_result, _text_resolver())
		_sync_status_band_visibility()


func _cancel_active_confirmation() -> bool:
	if not _modal_open:
		return false
	var cancel := _action_button(_modal_cancel_action)
	if cancel != null:
		_on_action_pressed(cancel)
	else:
		_close_confirmation_modal()
	return true


func _dismiss_visible_popup() -> bool:
	if not is_inside_tree():
		return false
	var root := get_tree().root
	if root == null:
		return false
	var popups := root.find_children("*", "Popup", true, false)
	for index: int in range(popups.size() - 1, -1, -1):
		var popup := popups[index] as Window
		if popup != null and popup.visible:
			popup.hide()
			return true
	return false


func _dismiss_focused_text_edit() -> bool:
	if not is_inside_tree():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		(focus as Control).release_focus()
		return true
	return false


func _install_b1_layout() -> void:
	if route_kind not in SHELL_ROUTES:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_shell = ProductionLayoutShell.new()
	_layout_shell.name = "B1Layout"
	add_child(_layout_shell)
	move_child(_layout_shell, 0)
	_layout_shell.build(route_kind)
	var title := get_node_or_null(^"Label") as Label
	if title != null:
		var title_rect := _layout_shell.current_content_rect(
			ProductionLayoutShell.REGION_TOP
		)
		title_rect.position.x += ProductionLayoutShell.TITLE_INSET
		title_rect.size.x = ProductionLayoutShell.TITLE_WIDTH
		title.position = title_rect.position
		title.size = title_rect.size
		title.theme_type_variation = &"ExpeditionTitle"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		ExpeditionLayoutMetrics.set_fixed_min(
			title, ProductionLayoutShell.TITLE_WIDTH, 0.0
		)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		composition.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _install_fullscreen_ui_background() -> void:
	if route_kind != &"MENU_MAIN":
		return
	var background := Panel.new()
	background.name = "FullscreenBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme_type_variation = &"ExpeditionBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)


func _configure_non_b1_layout(title: Label) -> void:
	if route_kind != &"MENU_MAIN":
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if route_kind == &"MENU_MAIN":
		_install_menu_key_art()
		if title != null:
			title.position = ExpeditionLayoutMetrics.MENU_TITLE_RECT.position
			title.size = ExpeditionLayoutMetrics.MENU_TITLE_RECT.size
			ExpeditionLayoutMetrics.set_fixed_min(
				title,
				ExpeditionLayoutMetrics.MENU_TITLE_RECT.size.x,
				ExpeditionLayoutMetrics.MENU_TITLE_RECT.size.y
			)
			title.theme_type_variation = &"ExpeditionTitle"
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title.z_index = 3
		return


func _install_menu_key_art() -> void:
	if route_kind != &"MENU_MAIN" or get_node_or_null(^"MenuKeyArt") != null:
		return
	var visuals := ProductionEnvironmentVisualCatalog.new()
	var texture := visuals.try_texture(&"key_art.menu_main")
	if texture == null:
		return
	var key_art := TextureRect.new()
	key_art.name = "MenuKeyArt"
	key_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key_art.texture = texture
	key_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	key_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	key_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	key_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_art.set_meta(&"visual_id", &"key_art.menu_main")
	add_child(key_art)
	move_child(key_art, mini(1, get_child_count() - 1))


func apply_theme_scale_layout(scale_percent: int) -> void:
	_route_ui_scale_percent = clampi(scale_percent, 100, 150)
	if route_kind == &"MENU_MAIN":
		_apply_menu_layout(
			get_node_or_null(^"Actions") as BoxContainer, scale_percent
		)
	if _layout_shell != null:
		_layout_shell.set_scale_factor(
			float(_route_ui_scale_percent) / 100.0
		)
		var title := get_node_or_null(^"Label") as Label
		if title != null:
			var title_rect := _layout_shell.current_content_rect(
				ProductionLayoutShell.REGION_TOP
			)
			title_rect.position.x += ProductionLayoutShell.TITLE_INSET
			title_rect.size.x = ProductionLayoutShell.TITLE_WIDTH
			title.position = title_rect.position
			title.size = title_rect.size
		_refresh_route_layout()
		_sync_status_band_visibility()
		# 主題切換後子節點 minimum 的重算是延遲的；立即量測會拿到舊值。
		# 下一影格再收斂一次（shell 帶高實測＋composition rect 重排）。
		call_deferred(&"_deferred_layout_settle")


## SETTINGS 版面的單一權威（P3/P4/P5）：由下往上排——動作列貼安全區底、
## 其上為畫面狀態帶、其上為 Composition（draft 驗證列保留在 Composition
## 可見高度內）。所有高度隨 UI 縮放 ×factor，任何縮放下不出安全區。
func _apply_settings_layout(scale_percent: int) -> void:
	if route_kind != &"SETTINGS" or _layout_shell == null:
		return
	var factor := float(scale_percent) / 100.0
	var center := _layout_shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	var bottom := _layout_shell.current_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	var draft_status_height := ceilf(
		ExpeditionLayoutMetrics.SETTINGS_DRAFT_STATUS_HEIGHT * factor
	)
	var actions := get_node_or_null(^"Actions") as Control
	if actions != null:
		actions.position = bottom.position
		actions.size = bottom.size
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.set_anchors_preset(Control.PRESET_TOP_LEFT)
		composition.grow_horizontal = Control.GROW_DIRECTION_END
		composition.grow_vertical = Control.GROW_DIRECTION_END
		composition.position = center.position
		ExpeditionLayoutMetrics.set_fixed_min(
			composition, center.size.x, center.size.y
		)
		composition.size = center.size
		composition.clip_contents = true
		if composition.has_method(&"apply_status_rect"):
			composition.call(
				&"apply_status_rect",
				Rect2(
					0.0,
					center.size.y - draft_status_height,
					center.size.x,
					draft_status_height
				)
			)


func _apply_results_layout() -> void:
	if (
		route_kind not in [&"RESULTS", &"RESULTS_FALLBACK"]
		or _layout_shell == null
	):
		return
	var center := _layout_shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	var bottom := _layout_shell.current_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	var actions := get_node_or_null(^"Actions") as Control
	if actions != null:
		actions.position = bottom.position
		actions.size = bottom.size
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.set_anchors_preset(Control.PRESET_TOP_LEFT)
		composition.grow_horizontal = Control.GROW_DIRECTION_END
		composition.grow_vertical = Control.GROW_DIRECTION_END
		composition.position = center.position
		composition.size = center.size
		composition.clip_contents = true
		if composition.has_method(&"refresh_layout_rects"):
			composition.call(&"refresh_layout_rects")


func _refresh_route_layout() -> void:
	_apply_settings_layout(_route_ui_scale_percent)
	_apply_results_layout()


func _build_camp_action_controls(action_ids: Array[StringName]) -> void:
	var composition := get_node_or_null(^"Composition") as CampWorldScreen
	var staging := Control.new()
	staging.name = "CampActionStaging"
	staging.visible = false
	staging.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if composition != null:
		composition.add_child(staging)
	else:
		add_child(staging)
	var first_facility_text := ""
	for action_id: StringName in action_ids.slice(0, 5):
		var facility := _new_action_button(action_id)
		facility.theme_type_variation = &"ExpeditionCampFacilityMarker"
		staging.add_child(facility)
		if first_facility_text.is_empty():
			first_facility_text = facility.text
	var start := _new_action_button(&"camp.start")
	start.theme_type_variation = &"ExpeditionCampStartAction"
	staging.add_child(start)
	var secondary := HBoxContainer.new()
	secondary.name = "CampSecondaryActions"
	secondary.alignment = BoxContainer.ALIGNMENT_END
	secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(secondary)
	# B-out-2：左半帶作為目前設施的情境提示，不再是無意義留白；文字沿用
	# 已解析的設施 loc key，避免新增另一套玩家可見字串。
	var facility_context := Label.new()
	facility_context.name = "CampFacilityContext"
	facility_context.text = first_facility_text
	facility_context.theme_type_variation = &"ExpeditionCampFooterContext"
	facility_context.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facility_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facility_context.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	secondary.add_child(facility_context)
	for action_id: StringName in [&"camp.settings", &"camp.menu"]:
		var button := _new_action_button(action_id)
		button.theme_type_variation = &"ExpeditionCampSecondaryAction"
		ExpeditionLayoutMetrics.set_fixed_min(button, 240.0, 72.0)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		secondary.add_child(button)


func _new_action_button(action_id: StringName) -> Button:
	var button := Button.new()
	button.name = _button_name(action_id)
	var visual_key := StringName(
		ACTION_VISUAL_LOCALIZATION_KEYS.get(action_id, action_id)
	)
	var accessible_text := _context.resolve_text(action_id)
	button.text = _context.resolve_text(visual_key)
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta(&"action_id", action_id)
	button.set_meta(&"localization_key", visual_key)
	button.set_meta(&"visual_localization_key", visual_key)
	button.set_meta(&"accessibility_localization_key", action_id)
	button.set_meta(&"accessible_text", accessible_text)
	if visual_key != action_id:
		button.tooltip_text = accessible_text
	return button


func _build_prepare_action_controls(
	controls: HBoxContainer,
	action_ids: Array[StringName]
) -> void:
	var default_group_index := 0
	var staged_snapshot := _context.snapshot_clone() as RunPresentationSnapshot
	if staged_snapshot != null and staged_snapshot.node_choice_overlay != null:
		for index: int in PREPARE_ACTION_GROUPS.size():
			if StringName(PREPARE_ACTION_GROUPS[index]["id"]) == &"advance":
				default_group_index = index
				break
	_prepare_action_group_pages.clear()
	_build_prepare_shop_controls(controls, action_ids, staged_snapshot)

	var secondary := VBoxContainer.new()
	secondary.name = "PrepareSecondaryActions"
	ExpeditionLayoutMetrics.set_fixed_min(
		secondary, ExpeditionLayoutMetrics.PREPARE_ACTION_COLUMN_WIDTH, 0.0
	)
	secondary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(secondary)
	_prepare_action_group_selector = OptionButton.new()
	_prepare_action_group_selector.name = PREPARE_ACTION_GROUP_SELECTOR
	_prepare_action_group_selector.focus_mode = Control.FOCUS_ALL
	_prepare_action_group_selector.theme_type_variation = &"ExpeditionBottomAction"
	_prepare_action_group_selector.allow_reselect = true
	ExpeditionLayoutMetrics.set_fixed_min(
		_prepare_action_group_selector,
		0.0,
		ExpeditionLayoutMetrics.PREPARE_ACTION_ROW_HEIGHT
	)
	_prepare_action_group_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prepare_action_group_selector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prepare_action_group_selector.set_meta(
		&"accessible_text",
		&"prepare.action_group_selector"
	)
	for group: Dictionary in PREPARE_ACTION_GROUPS:
		var label_key := StringName(group["label_key"])
		_prepare_action_group_selector.add_item(
			_context.resolve_text(label_key)
		)
		var group_index := _prepare_action_group_selector.item_count - 1
		_prepare_action_group_selector.set_item_metadata(group_index, label_key)
	secondary.add_child(_prepare_action_group_selector)

	var page_scroll := ScrollContainer.new()
	page_scroll.name = "PrepareActionGroupScroll"
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_scroll.follow_focus = true
	# The selector and page share a secondary column. Reserve one authored
	# action row for the inner viewport so a focused button always fits fully;
	# the outer BottomContentScroll absorbs the combined column height.
	ExpeditionLayoutMetrics.set_fixed_min(
		page_scroll, 0.0, ExpeditionLayoutMetrics.PREPARE_ACTION_ROW_HEIGHT
	)
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	secondary.add_child(page_scroll)
	# Keep the authored column width independent from localized text minima.
	# Height is synchronized from the visible page by
	# _refresh_prepare_action_pages_minimum(), so the vertical scroll range still
	# follows theme-scale and localization changes without widening the band.
	var pages := Control.new()
	pages.name = "PrepareActionGroupPages"
	ExpeditionLayoutMetrics.set_fixed_min(
		pages, ExpeditionLayoutMetrics.PREPARE_ACTION_COLUMN_WIDTH, 0.0
	)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(pages)
	for group_index: int in PREPARE_ACTION_GROUPS.size():
		var group: Dictionary = PREPARE_ACTION_GROUPS[group_index]
		var page := GridContainer.new()
		page.name = "Group%s" % String(group["id"]).to_pascal_case()
		page.columns = 1
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = group_index == default_group_index
		pages.add_child(page)
		_prepare_action_group_pages.append(page)
		page.minimum_size_changed.connect(
			_on_prepare_action_page_minimum_changed.bind(group_index)
		)
		for action_value: Variant in group["actions"]:
			var action_id := StringName(action_value)
			if action_ids.has(action_id):
				var action := _new_action_button(action_id)
				action.theme_type_variation = &"ExpeditionBottomAction"
				ExpeditionLayoutMetrics.set_fixed_min(
					action, 0.0, ExpeditionLayoutMetrics.PREPARE_ACTION_ROW_HEIGHT
				)
				# The column is intentionally fixed at 309 reference pixels. Preserve
				# the complete localized label for tooltip/accessibility while allowing
				# an ellipsis to prevent a long translation from widening the HBox.
				action.clip_text = true
				action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				var accessible_text := String(
					action.get_meta(&"accessible_text", action.text)
				)
				action.tooltip_text = accessible_text
				action.set_meta(&"accessible_text", accessible_text)
				action.set_meta(
					ExpeditionLayoutMetrics.META_ALLOW_TEXT_CLIP, true
				)
				action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				page.add_child(action)
				action.focus_entered.connect(
					_on_prepare_action_focus_entered.bind(page_scroll, action)
				)

	var pinned := VBoxContainer.new()
	pinned.name = "PinnedActions"
	ExpeditionLayoutMetrics.set_fixed_min(
		pinned, ExpeditionLayoutMetrics.PREPARE_PINNED_COLUMN_WIDTH, 0.0
	)
	pinned.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(pinned)
	for action_id: StringName in PREPARE_PINNED_ACTIONS:
		if action_ids.has(action_id):
			var action := _new_action_button(action_id)
			action.theme_type_variation = &"ExpeditionBottomAction"
			ExpeditionLayoutMetrics.set_fixed_min(
				action, 0.0, ExpeditionLayoutMetrics.PREPARE_ACTION_ROW_HEIGHT
			)
			pinned.add_child(action)
	_prepare_action_group_selector.item_selected.connect(
		_on_prepare_action_group_selected
	)
	_prepare_action_group_selector.select(default_group_index)
	# select() 不發 item_selected（P1）：初始分組頁的高度與可見性
	# 必須顯式初始化，否則預設組只露出第一顆動作。
	_on_prepare_action_group_selected(default_group_index)


## T23：COMBAT 沿用相同底帶骨架，但 shop／bench 只投影 bind 時取得的
## RunPresentationSnapshot clone。唯讀 controls 沒有 action_id 或 signal handler；
## playback 三動作仍使用正式 action button path。
func _build_combat_snapshot_controls(
	controls: VBoxContainer,
	action_ids: Array[StringName]
) -> void:
	var snapshot := _context.snapshot_clone() as RunPresentationSnapshot
	if snapshot != null:
		# StagedScreenContext 已 clone；這裡再切一份局部讀模型，避免未來 helper
		# 意外把 presentation surface 與 context 的 mutable DTO 共用。
		snapshot = snapshot.deep_clone()

	var shop_and_actions := HBoxContainer.new()
	shop_and_actions.name = "CombatShopAndPlaybackRow"
	shop_and_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_fixed_min(shop_and_actions, 0.0, 108.0)
	controls.add_child(shop_and_actions)

	var shop_cards := HBoxContainer.new()
	shop_cards.name = "CombatShopCards"
	shop_cards.theme_type_variation = &"ExpeditionShopCardsRow"
	shop_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_cards.set_meta(
		&"accessible_text", _context.resolve_text(&"prepare.panel.shop")
	)
	ExpeditionLayoutMetrics.set_fixed_min(shop_cards, 900.0, 108.0)
	shop_and_actions.add_child(shop_cards)
	_build_shop_card_row(shop_cards, snapshot, false)

	var playback_actions := HBoxContainer.new()
	playback_actions.name = "CombatPlaybackActions"
	playback_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_fixed_min(playback_actions, 540.0, 108.0)
	shop_and_actions.add_child(playback_actions)
	for action_id: StringName in action_ids:
		var action := _new_action_button(action_id)
		action.theme_type_variation = &"ExpeditionBottomAction"
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.size_flags_vertical = Control.SIZE_EXPAND_FILL
		playback_actions.add_child(action)

	var bench_row := HBoxContainer.new()
	bench_row.name = "CombatBenchRow"
	bench_row.theme_type_variation = &"ExpeditionBenchRow"
	bench_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench_row.set_meta(
		&"accessible_text", _context.resolve_text(&"prepare.panel.bench")
	)
	ExpeditionLayoutMetrics.set_fixed_min(bench_row, 0.0, 48.0)
	controls.add_child(bench_row)
	var roster := snapshot.roster.deep_clone() if (
		snapshot != null and snapshot.roster != null
	) else null
	for slot_index: int in range(BoardPreparationValidator.BENCH_CAPACITY):
		var unit_instance_id := (
			roster.bench_unit_instance_ids[slot_index]
			if roster != null and slot_index < roster.bench_unit_instance_ids.size()
			else ""
		)
		var display_text := _combat_bench_unit_text(roster, unit_instance_id)
		var occupied := not unit_instance_id.is_empty()
		var cell := Button.new()
		cell.name = "CombatBenchSlot%d" % slot_index
		cell.text = display_text if occupied else "◇"
		cell.theme_type_variation = &"ExpeditionGridCell"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.disabled = true
		cell.focus_mode = Control.FOCUS_NONE
		cell.set_meta(&"read_only_snapshot_control", true)
		cell.set_meta(&"typed_data_kind", &"combat_bench_slot")
		cell.set_meta(&"bench_slot", slot_index)
		cell.set_meta(&"unit_instance_id", unit_instance_id)
		cell.self_modulate.a = (
			1.0 if occupied else ExpeditionLayoutMetrics.BENCH_EMPTY_ALPHA
		)
		cell.set_meta(
			&"accessible_text",
			display_text if occupied else "%s %d" % [
				_context.resolve_text(&"prepare.panel.bench"), slot_index + 1
			]
		)
		cell.tooltip_text = display_text if occupied else ""
		ExpeditionLayoutMetrics.set_fixed_cell(cell, 180.0, 48.0)
		bench_row.add_child(cell)


func _combat_bench_unit_text(
	roster: RosterState,
	unit_instance_id: String
) -> String:
	if roster != null and not unit_instance_id.is_empty():
		for unit: UnitInstance in roster.unit_instances:
			if unit != null and unit.instance_id == unit_instance_id:
				return "%s · %s %d" % [
					localized_content_text(unit.def_id),
					_context.resolve_text(&"combat.stat.star"),
					unit.star,
				]
	return ""


func _build_prepare_shop_controls(
	controls: HBoxContainer,
	action_ids: Array[StringName],
	snapshot: RunPresentationSnapshot
) -> void:
	var shop_shell := HBoxContainer.new()
	shop_shell.name = "PrepareShopBand"
	shop_shell.theme_type_variation = &"ExpeditionPrepareShopBand"
	ExpeditionLayoutMetrics.set_fixed_min(shop_shell, 990.0, 0.0)
	shop_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(shop_shell)
	var cards_column := VBoxContainer.new()
	cards_column.name = "PrepareShopCardsColumn"
	cards_column.theme_type_variation = &"ExpeditionShopColumn"
	cards_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_shell.add_child(cards_column)
	var shop_header := HBoxContainer.new()
	shop_header.name = "PrepareShopHeader"
	cards_column.add_child(shop_header)
	var heading := Label.new()
	heading.text = _context.resolve_text(&"prepare.panel.shop")
	heading.theme_type_variation = &"ExpeditionSection"
	ExpeditionLayoutMetrics.set_fixed_min(heading, 180.0, 0.0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shop_header.add_child(heading)
	# 金幣/等級已由頂部資源列常駐顯示，商店帶不再重複（B1R2 審查風格項）。
	var cards := HBoxContainer.new()
	cards.name = "PrepareShopCards"
	cards.theme_type_variation = &"ExpeditionShopCardsRow"
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_column.add_child(cards)
	_build_shop_card_row(cards, snapshot, true)
	var shop_action_scroll := ScrollContainer.new()
	shop_action_scroll.name = "PrepareShopActionsScroll"
	shop_action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shop_action_scroll.follow_focus = true
	shop_action_scroll.clip_contents = true
	ExpeditionLayoutMetrics.set_min(
		shop_action_scroll,
		ExpeditionLayoutMetrics.PREPARE_SHOP_ACTION_VIEWPORT_WIDTH,
		ExpeditionLayoutMetrics.PREPARE_SHOP_ACTION_VIEWPORT_HEIGHT
	)
	# 一次只露出一個完整動作列；其餘動作由明確的垂直捲動邊界承接，
	# 避免底帶裁出下一顆按鈕的半截。
	shop_action_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	shop_shell.add_child(shop_action_scroll)
	var shop_actions := GridContainer.new()
	shop_actions.name = "PrepareShopActions"
	shop_actions.columns = 1
	ExpeditionLayoutMetrics.set_min(
		shop_actions,
		ExpeditionLayoutMetrics.PREPARE_SHOP_ACTION_CONTENT_WIDTH,
		0.0
	)
	shop_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_action_scroll.add_child(shop_actions)
	for action_id: StringName in [
		&"prepare.refresh", &"prepare.xp",
	]:
		if action_ids.has(action_id):
			var action := _new_action_button(action_id)
			action.theme_type_variation = &"ExpeditionBottomAction"
			# staged bind 尚未取得 live supply；報價套用前先 fail-closed。
			action.disabled = true
			action.set_meta(&"shop_quote_owned", true)
			ExpeditionLayoutMetrics.set_min(
				action,
				ExpeditionLayoutMetrics.PREPARE_SHOP_ACTION_CONTENT_WIDTH,
				ExpeditionLayoutMetrics.PREPARE_SHOP_ACTION_VIEWPORT_HEIGHT
			)
			shop_actions.add_child(action)
			var reason := Label.new()
			reason.name = (
				"RefreshShopReason"
				if action_id == &"prepare.refresh"
				else "BuyXpReason"
			)
			reason.theme_type_variation = &"ExpeditionAuxiliary"
			reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
			reason.focus_mode = Control.FOCUS_NONE
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason.visible = false
			reason.set_meta(&"accessibility_role", &"status")
			reason.set_meta(&"shop_quote_reason_for", action_id)
			shop_actions.add_child(reason)


func _apply_prepare_shop_quote_controls() -> void:
	if route_kind != &"RUN_PREPARE" or _context == null:
		return
	var refresh := _action_button(&"prepare.refresh")
	if refresh != null:
		_apply_shop_quote_button(
			refresh, &"prepare.refresh", _prepare_refresh_quote
		)
	var xp := _action_button(&"prepare.xp")
	if xp != null:
		_apply_xp_quote_button(xp, _prepare_xp_quote)
	var sell := _action_button(&"prepare.sell")
	var composition := get_node_or_null("Composition") as RunPrepareScreen
	if sell != null:
		_apply_sell_quote_button(
			sell,
			composition.selected_unit_sell_quote()
			if composition != null
			else null,
			composition.selected_unit_inspection_available()
			if composition != null
			else false
		)


func _apply_shop_quote_button(
	button: Button,
	action_key: StringName,
	quote: ShopQuoteSnapshot
) -> void:
	var valid := (
		quote != null
		and quote.available
		and quote.affordable
		and quote.quotable
		and quote.rejection_code.is_empty()
	)
	var action_text := _context.resolve_text(action_key)
	button.text = (
		"%s · %d" % [action_text, quote.gold_cost]
		if quote != null and quote.quotable
		else action_text
	)
	button.disabled = not valid
	_apply_shop_quote_metadata(button, action_text, quote, valid)


func _apply_xp_quote_button(
	button: Button,
	quote: ShopXpQuoteSnapshot
) -> void:
	var valid := (
		quote != null
		and quote.available
		and quote.affordable
		and quote.quotable
		and not quote.at_max_level
		and quote.rejection_code.is_empty()
	)
	var action_text := _context.resolve_text(&"prepare.xp")
	if quote != null and quote.at_max_level:
		button.text = "%s · %s" % [
			action_text,
			_context.resolve_text(&"prepare.resource.level_xp_max"),
		]
	elif quote != null and quote.quotable:
		button.text = "%s · %d" % [action_text, quote.gold_cost]
	else:
		button.text = action_text
	button.disabled = not valid
	_apply_shop_quote_metadata(button, action_text, quote, valid)


func _apply_sell_quote_button(
	button: Button,
	quote: ShopQuoteSnapshot,
	inspection_available: bool
) -> void:
	var valid := (
		inspection_available
		and quote != null
		and quote.available
		and quote.affordable
		and quote.quotable
		and quote.rejection_code.is_empty()
	)
	var action_text := _context.resolve_text(&"prepare.sell")
	button.text = (
		"%s · %d" % [action_text, quote.gold_gain]
		if quote != null and quote.quotable
		else action_text
	)
	button.disabled = not valid
	_apply_shop_quote_metadata(button, action_text, quote, valid)
	if not inspection_available:
		var message_key := &"error.presentation.action_not_available"
		var reason := _context.resolve_text(message_key)
		button.disabled = true
		button.set_meta(&"shop_quote_available", false)
		button.set_meta(&"shop_quote_message_key", message_key)
		button.tooltip_text = "%s · %s" % [action_text, reason]
		button.set_meta(&"accessible_text", button.tooltip_text)


func _apply_shop_quote_metadata(
	button: Button,
	action_text: String,
	quote: Variant,
	valid: bool
) -> void:
	var rejection_code: StringName = (
		StringName(quote.rejection_code) if quote != null else &""
	)
	var message_key := &""
	if not valid:
		# SCREEN_NOT_ACTIVE／未知／不一致 DTO 都採中性的 input_invalid；不從
		# SHOP_INPUT_INVALID 猜測 phase，且 revoked supply 絕不復活按鈕。
		message_key = StringName(_SHOP_REJECTION_MESSAGE_KEYS.get(
			rejection_code, &"error.shop.input_invalid"
		))
	button.set_meta(&"shop_quote_available", valid)
	button.set_meta(&"shop_quote_rejection_code", rejection_code)
	button.set_meta(&"shop_quote_message_key", message_key)
	if quote != null:
		button.set_meta(&"shop_quote_gold_cost", int(quote.gold_cost))
		if quote is ShopQuoteSnapshot:
			button.set_meta(
				&"shop_quote_gold_gain",
				(quote as ShopQuoteSnapshot).gold_gain
			)
		else:
			button.remove_meta(&"shop_quote_gold_gain")
	else:
		button.remove_meta(&"shop_quote_gold_cost")
		button.remove_meta(&"shop_quote_gold_gain")
	var accessible_text := action_text
	if not message_key.is_empty():
		accessible_text = "%s · %s" % [
			action_text, _context.resolve_text(message_key),
		]
	button.tooltip_text = accessible_text
	button.set_meta(&"accessible_text", accessible_text)
	var reason := _shop_quote_reason_label(button)
	if reason != null:
		reason.visible = not message_key.is_empty()
		reason.text = (
			_context.resolve_text(message_key)
			if not message_key.is_empty()
			else ""
		)
		reason.set_meta(&"localization_key", message_key)
		reason.set_meta(&"accessible_text", reason.text)


func _shop_quote_reason_label(button: Button) -> Label:
	if button == null or button.get_parent() == null:
		return null
	var action_id := StringName(button.get_meta(&"action_id", &""))
	var reason_name := (
		"RefreshShopReason"
		if action_id == &"prepare.refresh"
		else "BuyXpReason" if action_id == &"prepare.xp" else ""
	)
	return (
		button.get_parent().get_node_or_null(reason_name) as Label
		if not reason_name.is_empty()
		else null
	)


func _build_shop_card_row(
	cards: HBoxContainer,
	snapshot: RunPresentationSnapshot,
	interactive: bool
) -> void:
	var offer_by_slot: Dictionary = {}
	var duplicate_offer_slots: Dictionary = {}
	var preview_by_slot: Dictionary = {}
	if snapshot != null:
		var economy := (
			snapshot.economy.deep_clone()
			if snapshot.economy != null
			else null
		)
		if economy != null:
			for offer: ShopOffer in economy.shop_offers:
				if offer == null or offer.slot_index < 0 or offer.slot_index >= 5:
					continue
				if offer_by_slot.has(offer.slot_index):
					duplicate_offer_slots[offer.slot_index] = true
				else:
					offer_by_slot[offer.slot_index] = offer.deep_clone()
	var duplicate_preview_slots: Dictionary = {}
	if snapshot != null:
		for preview: ShopOfferPreviewSnapshot in snapshot.shop_offer_previews:
			if preview == null or preview.slot_index < 0 or preview.slot_index >= 5:
				continue
			if preview_by_slot.has(preview.slot_index):
				duplicate_preview_slots[preview.slot_index] = true
			else:
				preview_by_slot[preview.slot_index] = preview.deep_clone()
	var visuals := ProductionUnitVisualCatalog.new()
	for slot_index: int in range(5):
		var offer := offer_by_slot.get(slot_index) as ShopOffer
		var preview := preview_by_slot.get(slot_index) as ShopOfferPreviewSnapshot
		var unavailable := (
			duplicate_offer_slots.has(slot_index)
			or duplicate_preview_slots.has(slot_index)
			or (offer == null) != (preview == null)
			or (
				offer != null
				and preview != null
				and not _shop_preview_matches_offer(preview, offer)
			)
		)
		cards.add_child(_new_shop_card(
			slot_index,
			null if unavailable else preview,
			visuals,
			interactive,
			unavailable
		))


func _shop_preview_matches_offer(
	preview: ShopOfferPreviewSnapshot,
	offer: ShopOffer
) -> bool:
	return (
		preview != null
		and offer != null
		and preview.slot_index == offer.slot_index
		and not String(preview.offer_id).is_empty()
		and preview.offer_id == StringName(offer.offer_id)
		and not String(preview.unit_def_id).is_empty()
		and preview.unit_def_id == offer.unit_def_id
		and preview.cost == offer.cost
		and preview.cost_tier >= 1
		and preview.cost_tier <= 5
	)


func _new_shop_card(
	slot_index: int,
	preview: ShopOfferPreviewSnapshot,
	visuals: ProductionUnitVisualCatalog,
	interactive: bool,
	unavailable: bool = false
) -> Button:
	var card := Button.new()
	card.name = (
		(
			(
				"ShopCardSlot%dUnavailable" % slot_index
				if unavailable
				else "ShopCardSlot%dEmpty" % slot_index
			)
			if preview == null
			else "ShopCard%s" % String(preview.offer_id).to_pascal_case()
		)
		if interactive
		else "CombatShopCardSlot%d" % slot_index
	)
	card.theme_type_variation = &"ExpeditionShopCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PREPARE 的相鄰分組動作頁可能高於商店列；卡片維持 layout-reference
	# 的固定高度，不被整條 bottom scroll content 拉伸而把底列推到 viewport 外。
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.set_meta(&"shop_slot_index", slot_index)
	card.set_meta(
		&"shop_offer_id",
		"" if preview == null else String(preview.offer_id)
	)
	if interactive:
		# Select/dispatch is owned by the exact offer card. It must never join the
		# generic action_id lookup or activation wiring used by action-band buttons.
		card.set_meta(&"direct_action_owned", true)
	card.set_meta(
		&"typed_data_kind",
		(
			&"combat_shop_slot"
			if not interactive
			else (
				&"shop_offer"
				if preview != null
				else &"shop_offer_unavailable" if unavailable
				else &"empty_shop_slot"
			)
		)
	)
	ExpeditionLayoutMetrics.set_fixed_min(
		card,
		ExpeditionLayoutMetrics.SHOP_CARD_SIZE.x,
		ExpeditionLayoutMetrics.SHOP_CARD_SIZE.y
	)
	if preview == null:
		var empty_key := (
			&"error.presentation.action_not_available"
			if unavailable
			else &"combat.inspection.none"
		)
		var empty_text := _context.resolve_text(empty_key)
		card.text = empty_text
		card.tooltip_text = empty_text
		card.disabled = true
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta(&"localization_key", empty_key)
		card.set_meta(&"accessible_text", empty_text)
		if not interactive:
			card.set_meta(&"read_only_snapshot_control", true)
		return card

	# Keep only immutable presentation data on the card. Locale changes rebuild
	# every player-visible string from these cloned snapshot fields, while the
	# authoritative quoted cost is carried through unchanged.
	card.set_meta(&"shop_unit_def_id", preview.unit_def_id)
	card.set_meta(&"shop_cost", preview.cost)
	card.set_meta(&"shop_cost_tier", preview.cost_tier)
	card.set_meta(&"shop_trait_ids", preview.trait_ids.duplicate())
	card.set_meta(&"shop_owned_unit_count", preview.owned_unit_count)
	card.set_meta(
		&"shop_star_up_after_purchase", preview.star_up_after_purchase
	)
	card.theme_type_variation = StringName(
		"ExpeditionShopCardTier%d" % preview.cost_tier
	)
	# Button icon/autowrap would feed the portrait's intrinsic size into the
	# Container minimum. The established overlay renderer keeps geometry fixed.
	card.text = ""
	card.clip_contents = true
	_add_shop_card_content(
		card,
		visuals.try_portrait(preview.unit_def_id)
	)
	_refresh_shop_card_localization(card)
	if interactive:
		card.focus_mode = Control.FOCUS_ALL
		card.pressed.connect(
			_on_prepare_shop_card_pressed.bind(preview.offer_id)
		)
	else:
		card.disabled = true
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta(&"read_only_snapshot_control", true)
	return card


func _add_shop_card_content(
	card: Button,
	portrait: Texture2D
) -> void:
	var content := MarginContainer.new()
	content.name = "CardContent"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.theme_type_variation = &"ExpeditionShopCardInnerMargin"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.clip_contents = true
	card.add_child(content)

	var portrait_view := TextureRect.new()
	portrait_view.name = "Portrait"
	portrait_view.texture = portrait
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(portrait_view)

	var gradient_texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([
		0.0,
		ExpeditionLayoutMetrics.SHOP_CARD_BOTTOM_GRADIENT_START,
		1.0,
	])
	gradient.colors = PackedColorArray([
		Color(0.0156863, 0.027451, 0.0470588, 0.0),
		Color(0.0156863, 0.027451, 0.0470588, 0.72),
		Color(0.0156863, 0.027451, 0.0470588, 0.98),
	])
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	var gradient_view := TextureRect.new()
	gradient_view.name = "BottomReadabilityGradient"
	gradient_view.texture = gradient_texture
	gradient_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_view.stretch_mode = TextureRect.STRETCH_SCALE
	gradient_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(gradient_view)

	var foreground_margin := MarginContainer.new()
	foreground_margin.name = "ForegroundMargin"
	foreground_margin.theme_type_variation = &"ExpeditionShopForegroundMargin"
	foreground_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(foreground_margin)

	var foreground := VBoxContainer.new()
	foreground.name = "ForegroundLayout"
	foreground.theme_type_variation = &"ExpeditionShopForegroundLayout"
	foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground_margin.add_child(foreground)

	var top_info := HBoxContainer.new()
	top_info.name = "TopInfo"
	top_info.theme_type_variation = &"ExpeditionShopTopInfo"
	top_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.add_child(top_info)

	var badge_stack := VBoxContainer.new()
	badge_stack.name = "TraitBadges"
	badge_stack.theme_type_variation = &"ExpeditionShopTraitBadgeStack"
	badge_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_stack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_info.add_child(badge_stack)

	var top_spacer := Control.new()
	top_spacer.name = "TopSpacer"
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_info.add_child(top_spacer)

	var ownership_cues := HBoxContainer.new()
	ownership_cues.name = "OwnershipCues"
	ownership_cues.theme_type_variation = &"ExpeditionShopOwnershipCues"
	ownership_cues.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ownership_cues.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_info.add_child(ownership_cues)

	var owned_cue := HBoxContainer.new()
	owned_cue.name = "OwnedCueShapes"
	owned_cue.theme_type_variation = &"ExpeditionShopTinyCueRow"
	owned_cue.alignment = BoxContainer.ALIGNMENT_END
	owned_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		owned_cue,
		ExpeditionLayoutMetrics.SHOP_CARD_OWNED_CUE_WIDTH,
		ExpeditionLayoutMetrics.SHOP_CARD_STAR_CUE_SIZE.y
	)
	ownership_cues.add_child(owned_cue)

	var star_cue := HBoxContainer.new()
	star_cue.name = "StarUpCueShape"
	star_cue.theme_type_variation = &"ExpeditionShopTinyCueRow"
	star_cue.alignment = BoxContainer.ALIGNMENT_END
	star_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		star_cue,
		ExpeditionLayoutMetrics.SHOP_CARD_STAR_CUE_SIZE.x,
		ExpeditionLayoutMetrics.SHOP_CARD_STAR_CUE_SIZE.y
	)
	ownership_cues.add_child(star_cue)

	var vertical_spacer := Control.new()
	vertical_spacer.name = "VerticalSpacer"
	vertical_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	foreground.add_child(vertical_spacer)

	var bottom_info := HBoxContainer.new()
	bottom_info.name = "BottomInfo"
	bottom_info.theme_type_variation = &"ExpeditionShopCardBottomInfo"
	bottom_info.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		bottom_info,
		0.0,
		ExpeditionLayoutMetrics.SHOP_CARD_BOTTOM_INFO_HEIGHT
	)
	foreground.add_child(bottom_info)

	var name_label := Label.new()
	name_label.name = "UnitName"
	name_label.theme_type_variation = &"ExpeditionShopCardName"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_info.add_child(name_label)

	var cost_block := HBoxContainer.new()
	cost_block.name = "CostBlock"
	cost_block.theme_type_variation = &"ExpeditionShopCardCostBlock"
	cost_block.alignment = BoxContainer.ALIGNMENT_END
	cost_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_info.add_child(cost_block)

	var coin_icon := Label.new()
	coin_icon.name = "CoinIcon"
	coin_icon.theme_type_variation = &"ExpeditionShopCoinGlyph"
	coin_icon.text = "●"
	coin_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		coin_icon,
		ExpeditionLayoutMetrics.SHOP_CARD_COST_ICON_SIZE,
		ExpeditionLayoutMetrics.SHOP_CARD_BOTTOM_INFO_HEIGHT
	)
	cost_block.add_child(coin_icon)

	var price_label := Label.new()
	price_label.name = "CostValue"
	price_label.theme_type_variation = &"ExpeditionShopCardCost"
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_block.add_child(price_label)

	var tier_cues := HBoxContainer.new()
	tier_cues.name = "TierCueShapes"
	tier_cues.theme_type_variation = &"ExpeditionShopTinyCueRow"
	tier_cues.alignment = BoxContainer.ALIGNMENT_END
	tier_cues.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		tier_cues,
		ExpeditionLayoutMetrics.SHOP_CARD_TIER_CUE_WIDTH,
		ExpeditionLayoutMetrics.SHOP_CARD_BOTTOM_INFO_HEIGHT
	)
	cost_block.add_child(tier_cues)

	# 舊路徑降為不可見的 accessible compatibility copy：既有唯讀語意
	# probe／screen-reader metadata 可繼續讀取，玩家可見卡面不會出現長句。
	var legacy_identity := HBoxContainer.new()
	legacy_identity.name = "IdentityRow"
	legacy_identity.visible = false
	content.add_child(legacy_identity)
	var legacy_identity_text := VBoxContainer.new()
	legacy_identity_text.name = "IdentityText"
	legacy_identity.add_child(legacy_identity_text)
	var legacy_name := Label.new()
	legacy_name.name = "UnitName"
	legacy_identity_text.add_child(legacy_name)
	var legacy_price := Label.new()
	legacy_price.name = "PriceTier"
	legacy_identity_text.add_child(legacy_price)
	var legacy_tier_cues := HBoxContainer.new()
	legacy_tier_cues.name = "TierCueShapes"
	legacy_price.add_child(legacy_tier_cues)
	var legacy_traits := Label.new()
	legacy_traits.name = "Traits"
	legacy_traits.visible = false
	content.add_child(legacy_traits)
	var legacy_ownership := Label.new()
	legacy_ownership.name = "OwnedAndStarUp"
	legacy_ownership.visible = false
	content.add_child(legacy_ownership)
	var legacy_star_cue := HBoxContainer.new()
	legacy_star_cue.name = "StarUpCueShape"
	legacy_ownership.add_child(legacy_star_cue)


func _refresh_shop_card_localization(card: Button) -> void:
	if card == null:
		return
	var offer_id := String(card.get_meta(&"shop_offer_id", ""))
	if offer_id.is_empty():
		var empty_key := StringName(
			card.get_meta(&"localization_key", &"combat.inspection.none")
		)
		var empty_text := _context.resolve_text(empty_key)
		card.text = empty_text
		card.tooltip_text = empty_text
		card.set_meta(&"accessible_text", empty_text)
		return

	var unit_def_id := StringName(
		card.get_meta(&"shop_unit_def_id", &"")
	)
	var cost := int(card.get_meta(&"shop_cost", 0))
	var cost_tier := int(card.get_meta(&"shop_cost_tier", 0))
	var owned_unit_count := int(
		card.get_meta(&"shop_owned_unit_count", 0)
	)
	var star_up_after_purchase := bool(
		card.get_meta(&"shop_star_up_after_purchase", false)
	)
	var trait_labels: Array[String] = []
	var stored_trait_ids := card.get_meta(&"shop_trait_ids", []) as Array
	for raw_trait_id: Variant in stored_trait_ids:
		trait_labels.append(localized_content_text(StringName(raw_trait_id)))

	var unit_name := localized_content_text(unit_def_id)
	var cost_key: StringName = &"tooltip.cost"
	var star_key: StringName = &"tooltip.star"
	var ownership_key: StringName = &"prepare.panel.units"
	var name_label := card.get_node_or_null(
		"CardContent/ForegroundMargin/ForegroundLayout/BottomInfo/UnitName"
	) as Label
	if name_label != null:
		name_label.text = unit_name
		name_label.set_meta(&"content_localization_id", unit_def_id)
		name_label.set_meta(&"accessible_text", unit_name)
	var legacy_name := card.get_node_or_null(
		"CardContent/IdentityRow/IdentityText/UnitName"
	) as Label
	if legacy_name != null:
		legacy_name.text = unit_name
		legacy_name.set_meta(&"content_localization_id", unit_def_id)
		legacy_name.set_meta(&"accessible_text", unit_name)
	var price_label := card.get_node_or_null(
		"CardContent/ForegroundMargin/ForegroundLayout/BottomInfo/CostBlock/CostValue"
	) as Label
	if price_label != null:
		price_label.text = str(cost)
		price_label.set_meta(&"localization_key", cost_key)
		price_label.set_meta(&"authoritative_cost", cost)
		price_label.set_meta(&"authoritative_cost_tier", cost_tier)
		price_label.set_meta(
			&"accessible_text",
			"%s %d" % [_context.resolve_text(cost_key), cost]
		)
		_refresh_shop_tier_cue(
			card.get_node_or_null(
				"CardContent/ForegroundMargin/ForegroundLayout/BottomInfo/CostBlock/TierCueShapes"
			) as HBoxContainer,
			price_label.get_theme_color(&"font_color"),
			cost_tier
		)
	var legacy_price := card.get_node_or_null(
		"CardContent/IdentityRow/IdentityText/PriceTier"
	) as Label
	if legacy_price != null:
		legacy_price.text = "%s %d" % [
			_context.resolve_text(cost_key), cost,
		]
		legacy_price.set_meta(&"localization_key", cost_key)
		legacy_price.set_meta(&"authoritative_cost", cost)
		legacy_price.set_meta(&"authoritative_cost_tier", cost_tier)
		legacy_price.set_meta(&"accessible_text", legacy_price.text)
		_refresh_shop_tier_cue(
			legacy_price.get_node_or_null(^"TierCueShapes") as HBoxContainer,
			price_label.get_theme_color(&"font_color") if price_label != null else Color.WHITE,
			cost_tier
		)
	var badge_stack := card.get_node_or_null(
		"CardContent/ForegroundMargin/ForegroundLayout/TopInfo/TraitBadges"
	) as VBoxContainer
	_refresh_shop_trait_badges(
		badge_stack,
		stored_trait_ids,
		trait_labels
	)
	var legacy_traits := card.get_node_or_null(
		"CardContent/Traits"
	) as Label
	if legacy_traits != null:
		legacy_traits.text = " / ".join(trait_labels)
		legacy_traits.set_meta(
			&"content_localization_ids", stored_trait_ids.duplicate()
		)
		legacy_traits.set_meta(&"accessible_text", legacy_traits.text)
	var ownership_cues := card.get_node_or_null(
		"CardContent/ForegroundMargin/ForegroundLayout/TopInfo/OwnershipCues"
	) as HBoxContainer
	var star_result := (
		_context.resolve_text(star_key)
		if star_up_after_purchase
		else ""
	)
	if ownership_cues != null:
		var ownership_accessible := "%s %d" % [
			_context.resolve_text(ownership_key), owned_unit_count,
		]
		if star_up_after_purchase:
			ownership_accessible += " · %s" % star_result
		ownership_cues.set_meta(
			&"localization_keys",
			[ownership_key, star_key]
		)
		ownership_cues.set_meta(
			&"star_up_after_purchase_value",
			1 if star_up_after_purchase else 0
		)
		ownership_cues.set_meta(&"accessible_text", ownership_accessible)
		var cue_color := (
			price_label.get_theme_color(&"font_color")
			if price_label != null
			else Color(0.960784, 0.941176, 0.87451, 1.0)
		)
		_refresh_shop_owned_cue(
			ownership_cues.get_node_or_null(^"OwnedCueShapes") as HBoxContainer,
			cue_color,
			owned_unit_count
		)
		_refresh_shop_star_cue(
			ownership_cues.get_node_or_null(^"StarUpCueShape") as HBoxContainer,
			cue_color,
			star_up_after_purchase
		)
	var legacy_ownership := card.get_node_or_null(
		"CardContent/OwnedAndStarUp"
	) as Label
	if legacy_ownership != null:
		legacy_ownership.text = "%s %d" % [
			_context.resolve_text(ownership_key), owned_unit_count,
		]
		if star_up_after_purchase:
			legacy_ownership.text += " · %s" % star_result
		legacy_ownership.set_meta(
			&"localization_keys", [ownership_key, star_key]
		)
		legacy_ownership.set_meta(
			&"star_up_after_purchase_value",
			1 if star_up_after_purchase else 0
		)
		legacy_ownership.set_meta(
			&"accessible_text", legacy_ownership.text
		)
		_refresh_shop_star_cue(
			legacy_ownership.get_node_or_null(^"StarUpCueShape") as HBoxContainer,
			price_label.get_theme_color(&"font_color") if price_label != null else Color.WHITE,
			star_up_after_purchase
		)

	var detail_lines: Array[String] = [
		unit_name,
		"%s %d" % [
			_context.resolve_text(cost_key), cost,
		],
		"%s %d" % [
			_context.resolve_text(ownership_key),
			owned_unit_count,
		],
	]
	if not trait_labels.is_empty():
		detail_lines.append(" / ".join(trait_labels))
	if not star_result.is_empty():
		detail_lines.append(star_result)
	var detail_text := "\n".join(detail_lines)
	card.tooltip_text = detail_text
	card.set_meta(
		&"localization_keys",
		[cost_key, ownership_key, star_key]
	)
	card.set_meta(&"accessible_text", detail_text)


func _refresh_shop_trait_badges(
	badge_stack: VBoxContainer,
	trait_ids: Array,
	trait_labels: Array[String]
) -> void:
	if badge_stack == null:
		return
	_clear_shop_cue_children(badge_stack)
	badge_stack.set_meta(&"content_localization_ids", trait_ids.duplicate())
	badge_stack.set_meta(&"accessible_text", " / ".join(trait_labels))
	var visible_count := mini(
		ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_MAX,
		mini(trait_ids.size(), trait_labels.size())
	)
	badge_stack.set_meta(&"visible_badge_count", visible_count)
	for index: int in visible_count:
		var trait_id := StringName(trait_ids[index])
		var badge := PanelContainer.new()
		badge.name = "TraitBadge%d" % index
		badge.theme_type_variation = &"ExpeditionShopTraitBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionLayoutMetrics.set_fixed_min(
			badge,
			ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_WIDTH,
			ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_HEIGHT
		)
		badge_stack.add_child(badge)
		var row := HBoxContainer.new()
		row.name = "BadgeContent"
		row.theme_type_variation = &"ExpeditionShopTraitBadgeContent"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(row)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = _shop_trait_icon_texture(trait_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionLayoutMetrics.set_fixed_min(
			icon,
			ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_ICON_SIZE,
			ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_ICON_SIZE
		)
		row.add_child(icon)
		var label := Label.new()
		label.name = "TraitName"
		label.theme_type_variation = &"ExpeditionShopTraitBadgeLabel"
		label.text = trait_labels[index]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.set_meta(&"content_localization_id", trait_id)
		label.set_meta(&"accessible_text", label.text)
		row.add_child(label)


func _shop_trait_icon_texture(trait_id: StringName) -> AtlasTexture:
	var cell := _shop_trait_atlas_cell(trait_id)
	var icon := AtlasTexture.new()
	icon.atlas = _SHOP_TRAIT_ATLAS
	icon.region = Rect2(
		Vector2(cell) * ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_ATLAS_CELL_SIZE,
		ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_ATLAS_CELL_SIZE
	)
	return icon


func _shop_trait_atlas_cell(trait_id: StringName) -> Vector2i:
	var token := String(trait_id)
	var faction_tokens := ["arcane", "ember", "frost", "iron", "shadow", "verdant"]
	if token.begins_with("trait.faction_"):
		return Vector2i(maxi(0, faction_tokens.find(token.trim_prefix("trait.faction_"))), 0)
	var role_tokens := ["marksman", "mystic", "sentinel", "trickster", "vanguard", "warden"]
	if token.begins_with("trait.role_"):
		return Vector2i(0, maxi(0, role_tokens.find(token.trim_prefix("trait.role_"))) + 1)
	return Vector2i(0, 7)


func _refresh_shop_tier_cue(
	cue: HBoxContainer,
	color: Color,
	cost_tier: int
) -> void:
	if cue == null:
		return
	_clear_shop_cue_children(cue)
	cue.set_meta(&"authoritative_cost_tier", cost_tier)
	cue.set_meta(&"non_color_cue", &"tier-pips")
	for index: int in maxi(1, cost_tier):
		var pip := ColorRect.new()
		pip.name = "TierPip%d" % index
		pip.color = color
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionLayoutMetrics.set_fixed_min(
			pip,
			ExpeditionLayoutMetrics.SHOP_CARD_TIER_PIP_SIZE,
			ExpeditionLayoutMetrics.SHOP_CARD_TIER_PIP_SIZE
		)
		cue.add_child(pip)


func _refresh_shop_owned_cue(
	cue: HBoxContainer,
	color: Color,
	owned_unit_count: int
) -> void:
	if cue == null:
		return
	_clear_shop_cue_children(cue)
	cue.set_meta(&"owned_unit_count", owned_unit_count)
	cue.set_meta(&"non_color_cue", &"owned-copy-pips")
	for index: int in mini(3, maxi(0, owned_unit_count)):
		var pip := ColorRect.new()
		pip.name = "OwnedPip%d" % index
		pip.color = color
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionLayoutMetrics.set_fixed_min(
			pip,
			ExpeditionLayoutMetrics.SHOP_CARD_OWNED_PIP_SIZE,
			ExpeditionLayoutMetrics.SHOP_CARD_OWNED_PIP_SIZE
		)
		cue.add_child(pip)


func _refresh_shop_star_cue(
	cue: HBoxContainer,
	color: Color,
	star_up_after_purchase: bool
) -> void:
	if cue == null:
		return
	_clear_shop_cue_children(cue)
	cue.set_meta(&"star_up_after_purchase_value", star_up_after_purchase)
	cue.set_meta(
		&"non_color_cue",
		&"star-rise" if star_up_after_purchase else &"star-flat"
	)
	var primary := ColorRect.new()
	primary.name = "PrimaryShape"
	primary.color = color
	primary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_fixed_min(
		primary,
		5.0 if star_up_after_purchase else 16.0,
		10.0 if star_up_after_purchase else 4.0
	)
	cue.add_child(primary)
	if star_up_after_purchase:
		var secondary := ColorRect.new()
		secondary.name = "SecondaryShape"
		secondary.color = primary.color
		secondary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionLayoutMetrics.set_fixed_min(secondary, 10.0, 5.0)
		cue.add_child(secondary)


func _clear_shop_cue_children(cue: Control) -> void:
	for child: Node in cue.get_children():
		cue.remove_child(child)
		child.free()


func _on_prepare_shop_card_pressed(offer_id: StringName) -> void:
	var composition := get_node_or_null(^"Composition") as RunPrepareScreen
	if composition != null:
		composition.select_shop_offer(offer_id)
	var trigger: Button
	for node: Node in find_children("ShopCard*", "Button", true, false):
		var card := node as Button
		if card != null and StringName(
			card.get_meta(&"shop_offer_id", &"")
		) == offer_id:
			trigger = card
			break
	if trigger != null:
		_dispatch_action(&"prepare.buy", trigger)


func _on_prepare_action_group_selected(index: int) -> void:
	if index < 0 or index >= _prepare_action_group_pages.size():
		return
	for page_index: int in _prepare_action_group_pages.size():
		_prepare_action_group_pages[page_index].visible = page_index == index
	_refresh_prepare_action_pages_minimum()
	# Visibility and Container minimum invalidation settle at frame end.
	call_deferred(&"_refresh_prepare_action_pages_minimum")
	_apply_keyboard_focus_graph()


func _on_prepare_action_page_minimum_changed(group_index: int) -> void:
	if (
		group_index < 0
		or group_index >= _prepare_action_group_pages.size()
		or not _prepare_action_group_pages[group_index].visible
	):
		return
	call_deferred(&"_refresh_prepare_action_pages_minimum")


func _refresh_prepare_action_pages_minimum() -> void:
	var pages := find_child(
		"PrepareActionGroupPages", true, false
	) as Control
	var page_scroll := find_child(
		"PrepareActionGroupScroll", true, false
	) as ScrollContainer
	if pages == null or page_scroll == null:
		return
	var visible_page: GridContainer
	for page: GridContainer in _prepare_action_group_pages:
		if page.visible:
			visible_page = page
			break
	if visible_page == null:
		return
	# Runtime size is already theme-scaled; do not replace the 1920-reference
	# base metric or the next theme apply would scale a measured value again.
	ExpeditionLayoutMetrics.set_runtime_min(
		pages,
		Vector2(
			ExpeditionLayoutMetrics.PREPARE_ACTION_COLUMN_WIDTH,
			visible_page.get_combined_minimum_size().y
		)
	)
	var action_row_height := 0.0
	for child: Node in visible_page.get_children():
		var action := child as Control
		if action != null and action.visible:
			action_row_height = maxf(
				action_row_height,
				action.get_combined_minimum_size().y
			)
	# This is a post-theme runtime measurement, not a new reference literal.
	# Keeping one complete action row in the inner viewport lets the outer
	# BottomContentScroll own the remaining vertical overflow.
	ExpeditionLayoutMetrics.set_runtime_min(
		page_scroll,
		Vector2(0.0, action_row_height)
	)
	if _layout_shell != null:
		_layout_shell.relayout()


func _on_prepare_action_focus_entered(
	scroll: ScrollContainer,
	action: Control
) -> void:
	# Focus may move in the same frame as a group switch/container sort. Defer
	# until the minimum-size propagation and scroll range have both settled.
	call_deferred(&"_ensure_prepare_action_visible", scroll, action)


func _ensure_prepare_action_visible(
	scroll: ScrollContainer,
	action: Control
) -> void:
	if (
		scroll == null
		or action == null
		or not is_instance_valid(scroll)
		or not is_instance_valid(action)
		or not scroll.is_inside_tree()
		or not action.is_inside_tree()
		or not action.is_visible_in_tree()
		or not action.has_focus()
	):
		return
	scroll.ensure_control_visible(action)
	call_deferred(
		&"_ensure_prepare_action_visible_in_outer",
		scroll,
		action
	)


func _ensure_prepare_action_visible_in_outer(
	inner_scroll: ScrollContainer,
	action: Control
) -> void:
	if not _prepare_action_focus_is_valid(inner_scroll, action):
		return
	inner_scroll.ensure_control_visible(action)
	var outer_scroll := _scroll_ancestor_named(
		inner_scroll,
		&"BottomContentScroll"
	)
	if outer_scroll == null:
		return
	outer_scroll.ensure_control_visible(action)
	call_deferred(
		&"_finalize_prepare_action_visibility",
		inner_scroll,
		outer_scroll,
		action
	)


func _finalize_prepare_action_visibility(
	inner_scroll: ScrollContainer,
	outer_scroll: ScrollContainer,
	action: Control
) -> void:
	if (
		not _prepare_action_focus_is_valid(inner_scroll, action)
		or outer_scroll == null
		or not is_instance_valid(outer_scroll)
		or not outer_scroll.is_inside_tree()
		or not outer_scroll.is_ancestor_of(action)
	):
		return
	# The outer scroll moves the complete secondary column. Re-apply the inner
	# range after that movement, then settle the outer range against the final
	# action rect so both nested viewports contain the focused control.
	inner_scroll.ensure_control_visible(action)
	outer_scroll.ensure_control_visible(action)


func _prepare_action_focus_is_valid(
	scroll: ScrollContainer,
	action: Control
) -> bool:
	return (
		scroll != null
		and action != null
		and is_instance_valid(scroll)
		and is_instance_valid(action)
		and scroll.is_inside_tree()
		and action.is_inside_tree()
		and action.is_visible_in_tree()
		and action.has_focus()
		and scroll.is_ancestor_of(action)
	)


func _scroll_ancestor_named(
	control: Control,
	target_name: StringName
) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null and ancestor != self:
		var scroll := ancestor as ScrollContainer
		if scroll != null and scroll.name == target_name:
			return scroll
		ancestor = ancestor.get_parent()
	return null


func _attach_focus_indicator() -> void:
	if get_node_or_null(^"FocusIndicator") != null:
		return
	var indicator := ProductionFocusIndicator.new()
	indicator.name = "FocusIndicator"
	indicator.bind_owner(self)
	add_child(indicator)


func _compose_production_child(
	context: ProductionLiveScreenContext
) -> StringName:
	var composition := get_node_or_null("Composition")
	if composition == null:
		return (
			SCREEN_COMPOSITION_MISSING
			if _composition_required()
			else &""
		)
	match route_kind:
		&"CAMP_WORLD":
			if not composition is CampWorldScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as CampWorldScreen).compose(
				context.profile_clone(),
				context.navigation_port
			)
		&"FACILITY_EXPEDITION_GATE", \
		&"FACILITY_COMMANDER_HALL", \
		&"FACILITY_UNLOCK_WORKSHOP", \
		&"FACILITY_CHALLENGE_MONUMENT":
			if not composition is CampFacilityScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as CampFacilityScreen).compose(
				context.profile_clone(),
				context.navigation_port
			)
		&"COLLECTION":
			if not composition is CollectionScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as CollectionScreen).compose_collection(
				context.profile_clone(),
				context.navigation_port,
				context.collection_projection_clone(),
				_localized_text_clone()
			)
		&"RUN_MAP":
			if not composition is RunMapScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as RunMapScreen).compose(
				context.snapshot_clone() as RunPresentationSnapshot,
				context.intent_port,
				context.supply_port
			)
		&"RUN_PREPARE":
			if not composition is RunPrepareScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			var prepare_snapshot := (
				context.snapshot_clone() as RunPresentationSnapshot
			)
			var report := _snapshot_board_validation_report(
				prepare_snapshot
			)
			if report == null:
				return RunPrepareScreen.COMPOSE_INVALID
			return (composition as RunPrepareScreen).compose(
				prepare_snapshot,
				report,
				context.intent_port,
				context.supply_port
			)
		&"RUN_COMBAT":
			if not composition is RunCombatScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			var combat := composition as RunCombatScreen
			var compose_error := combat.compose(
				context.snapshot_clone() as RunPresentationSnapshot,
				context.intent_port,
				context.supply_port
			)
			if not compose_error.is_empty():
				return compose_error
			var playback_error := combat.bind_playback_port(
				context.playback_port
			)
			if not playback_error.is_empty():
				return playback_error
			if context.inspection_port != null:
				return combat.bind_inspection_port(
					context.inspection_port
				)
			return &""
		&"RUN_REWARD":
			if not composition is RunRewardScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as RunRewardScreen).compose(
				context.snapshot_clone() as RunPresentationSnapshot,
				context.intent_port,
				context.supply_port
			)
		&"RESULTS", &"RESULTS_FALLBACK":
			if not composition is ResultsScreenComposition:
				return SCREEN_COMPOSITION_TYPE_INVALID
			return (composition as ResultsScreenComposition).compose(
				context.snapshot_clone() as ResultsPresentationSnapshot,
				_localized_text_clone()
			)
	return &""


func _composition_required() -> bool:
	return route_kind in [
		&"CAMP_WORLD",
		&"FACILITY_EXPEDITION_GATE",
		&"FACILITY_COMMANDER_HALL",
		&"COLLECTION",
		&"FACILITY_UNLOCK_WORKSHOP",
		&"FACILITY_CHALLENGE_MONUMENT",
		&"RUN_MAP",
		&"RUN_PREPARE",
		&"RUN_COMBAT",
		&"RUN_REWARD",
		&"RESULTS",
		&"RESULTS_FALLBACK",
	]


func _on_action_pressed(button: Button) -> void:
	if (
		not _live_active
		or _live_context == null
		or _live_context.action_port == null
		or button == null
		or not button.has_meta(&"action_id")
	):
		return
	var action_id := StringName(button.get_meta(&"action_id"))
	if _modal_open:
		if action_id not in [_modal_confirm_action, _modal_cancel_action]:
			return
		if not _modal_deferred_action.is_empty():
			# 呈現層確認：取消是零 dispatch，確認才把原動作送出去。
			var deferred := _modal_deferred_action
			var deferred_payload := _modal_deferred_payload.duplicate(true)
			var confirmed := action_id == _modal_confirm_action
			_close_confirmation_modal()
			if confirmed:
				if (
					deferred == &"prepare.sell"
					and deferred_payload.has(&"unit_instance_id")
				):
					_dispatch_sell_unit_payload(deferred_payload)
				else:
					_dispatch_action(deferred, null)
			else:
				_play_audio_cue(&"audio.ui_cancel", {
					"source": &"confirmation_cancel",
					"action_id": action_id,
				})
			return
	elif _PRESENTATION_CONFIRMATIONS.has(action_id):
		_open_presentation_confirmation(action_id, button)
		return
	elif action_id == &"prepare.sell":
		var prepare := get_node_or_null("Composition") as RunPrepareScreen
		if prepare == null or not prepare.selected_unit_inspection_available():
			_apply_prepare_shop_quote_controls()
			return
		if prepare != null and prepare.selected_unit_requires_sell_confirmation():
			var captured_unit_id := prepare.selected_unit_instance_id()
			_show_confirmation_modal(
				"SellUnitConfirmation",
				&"prepare.sell",
				&"run.menu.confirm",
				&"run.menu.cancel",
				action_id,
				button,
				{&"unit_instance_id": captured_unit_id}
			)
			return
	_dispatch_action(action_id, button)


func _dispatch_sell_unit_payload(payload: Dictionary) -> void:
	var prepare := get_node_or_null("Composition") as RunPrepareScreen
	var unit_id := String(payload.get(&"unit_instance_id", ""))
	if prepare == null or unit_id.is_empty():
		return
	_last_control_result = prepare.sell_unit_by_instance_id(unit_id)
	_status_view.show_result(_last_control_result, _text_resolver())
	_sync_status_band_visibility()
	refresh_interaction_state()


func _dispatch_action(action_id: StringName, trigger: Button) -> void:
	var audio_sequence_before := _audio_playback_sequence()
	var local_result: Variant = _invoke_local_control(action_id)
	_last_control_result = (
		local_result
		if local_result != null
		else _live_context.action_port.invoke(action_id)
	)
	_status_view.show_result(_last_control_result, _text_resolver())
	_sync_status_band_visibility()
	if (
		_audio_director != null
		and is_instance_valid(_audio_director)
		and _audio_director.playback_sequence() == audio_sequence_before
	):
		_audio_director.present_action_result(action_id, _last_control_result)
	if (
		String(action_id).begins_with("prepare.")
		or String(action_id).begins_with("service.")
		or action_id == &"choice.ack"
	):
		refresh_interaction_state()
	if (
		action_id == &"menu.recovery"
		and _last_control_result is AppActionResult
		and (_last_control_result as AppActionResult).ok
	):
		_show_recovery_confirmation(trigger)
	elif (
		action_id == &"choice.begin"
		and _last_control_result is ConfirmationDraftResult
		and (_last_control_result as ConfirmationDraftResult).ok
	):
		_show_node_choice_confirmation(trigger)
	elif action_id in [&"menu.recovery.cancel", &"menu.recovery.confirm"]:
		# G2 F2：不能只在 ok 時關 modal。app 層的 confirmation 在
		# RecoveryConfirmationPresenter.confirm_confirmation()／cancel_confirmation()
		# 一進去就關掉了，之後的失敗（例如 discard 成功但 route commit 失敗）
		# 只影響畫面。此時若 modal 不關，背景按鈕還被 _disable_modal_background()
		# 停用，玩家只剩 confirm/cancel 兩顆——而它們的 lease 已被撤銷，
		# 永遠回 SCREEN_NOT_ACTIVE，App 就此鎖死。失敗訊息已經進狀態列，
		# 關掉 modal 才有出路。
		_close_confirmation_modal()
	elif action_id in [&"choice.cancel", &"choice.confirm"]:
		# draft 已被消費後，不論 runtime 結果都關閉 modal。錯誤由 status
		# view 呈現，背景控制與焦點則必須恢復，避免留下無效 lease。
		_close_confirmation_modal()


func _attach_audio_director() -> void:
	if _audio_director != null and is_instance_valid(_audio_director):
		return
	_audio_director = ProductionAudioDirector.new()
	_audio_director.name = "ProductionAudioDirector"
	add_child(_audio_director)
	_audio_director.present_route(route_kind)


func _audio_playback_sequence() -> int:
	return (
		_audio_director.playback_sequence()
		if _audio_director != null and is_instance_valid(_audio_director)
		else -1
	)


func _play_audio_cue(cue_id: StringName, context: Dictionary = {}) -> void:
	if _audio_director != null and is_instance_valid(_audio_director):
		_audio_director.play_cue(cue_id, context)


func _invoke_local_control(action_id: StringName) -> Variant:
	var composition := get_node_or_null("Composition")
	match action_id:
		&"map.select":
			return (
				(composition as RunMapScreen).open_node_selection()
				if composition is RunMapScreen
				else null
			)
		&"map.confirm":
			return (
				(composition as RunMapScreen).confirm_selection()
				if composition is RunMapScreen
				else null
			)
		&"prepare.unit":
			return (
				(composition as RunPrepareScreen).commit_board_draft()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.refresh":
			return (
				(composition as RunPrepareScreen).refresh_shop()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.buy":
			return (
				(composition as RunPrepareScreen).buy_selected_offer()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.xp":
			return (
				(composition as RunPrepareScreen).buy_xp()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.sell":
			return (
				(composition as RunPrepareScreen).sell_selected_unit()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.forge":
			return (
				(composition as RunPrepareScreen).begin_forge_selected()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.forge.confirm":
			return (
				(composition as RunPrepareScreen).confirm_forge()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.forge.cancel":
			return (
				(composition as RunPrepareScreen).cancel_forge()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.equip":
			return (
				(composition as RunPrepareScreen).equip_selected_item()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.dismantle":
			return (
				(composition as RunPrepareScreen).dismantle_selected_equipment()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.move_board":
			return (
				(composition as RunPrepareScreen).move_selected_to_board()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.move_bench":
			return (
				(composition as RunPrepareScreen).move_selected_to_bench()
				if composition is RunPrepareScreen
				else null
			)
		&"prepare.start":
			return (
				(composition as RunPrepareScreen).start_combat()
				if composition is RunPrepareScreen
				else null
			)
		&"choice.begin":
			return (
				(composition as RunPrepareScreen).begin_selected_node_choice()
				if composition is RunPrepareScreen
				else null
			)
		&"choice.confirm":
			return (
				(composition as RunPrepareScreen).confirm_node_choice()
				if composition is RunPrepareScreen
				else null
			)
		&"choice.cancel":
			return (
				(composition as RunPrepareScreen).cancel_node_choice()
				if composition is RunPrepareScreen
				else null
			)
		&"choice.ack":
			# review N1：ack 不是 prepare 專屬動作——APPLY 出口落在 RUN_MAP、
			# REWARD 出口落在 RUN_REWARD，三個 composition 都要能送出 ack。
			return (
				(composition as ProductionScreen).acknowledge_node_choice_result()
				if composition is ProductionScreen
				else null
			)
		&"service.dismantle":
			return (
				(composition as RunPrepareScreen).dismantle_selected_with_node_service()
				if composition is RunPrepareScreen
				else null
			)
		&"service.exit":
			return (
				(composition as RunPrepareScreen).exit_node_service()
				if composition is RunPrepareScreen
				else null
			)
		&"combat.pause":
			return (
				(composition as RunCombatScreen).toggle_pause()
				if composition is RunCombatScreen
				else null
			)
		&"combat.inspect":
			return (
				(composition as RunCombatScreen).inspect()
				if composition is RunCombatScreen
				else null
			)
		&"combat.speed":
			return (
				(composition as RunCombatScreen).cycle_speed()
				if composition is RunCombatScreen
				else null
			)
		&"reward.select":
			return (
				(composition as RunRewardScreen).accept_visible_reward_result()
				if composition is RunRewardScreen
				else null
			)
		&"reward.confirm":
			return (
				(composition as RunRewardScreen).confirm_selection()
				if composition is RunRewardScreen
				else null
			)
	return null


func relocalize(locale: StringName, localized_text: Dictionary) -> void:
	if _context == null:
		return
	_context.locale = locale
	_context.localized_text.clear()
	for key: Variant in localized_text.keys():
		_context.localized_text[StringName(key)] = String(localized_text[key])
	var title := get_node_or_null("Label") as Label
	if title != null:
		title.text = _context.resolve_text(_route_title_key())
	for button: Button in _action_buttons():
		if button.has_meta(&"action_id"):
			var action_id := StringName(button.get_meta(&"action_id"))
			var visual_key := StringName(
				button.get_meta(&"visual_localization_key", action_id)
			)
			var accessible_text := _context.resolve_text(action_id)
			button.text = _context.resolve_text(visual_key)
			button.set_meta(&"localization_key", visual_key)
			button.set_meta(&"accessible_text", accessible_text)
			if visual_key != action_id:
				button.tooltip_text = accessible_text
	_apply_prepare_shop_quote_controls()
	var composition := get_node_or_null(^"Composition")
	if composition != null:
		var hud_shell := composition.find_child(
			"InRunHudShell", true, false
		) as InRunHudShell
		if hud_shell != null:
			hud_shell.relocalize(
				Callable(self, &"localized_ui_text"),
				Callable(self, &"localized_content_text")
			)
	# Shop cards are direct-owned controls, not generic action-band buttons.
	# Recompose active and empty card copy from immutable snapshot metadata so a
	# locale switch updates every visible/accessibility string without changing
	# exact-offer ownership or the authored focus order.
	for node: Node in find_children("*ShopCard*", "Button", true, false):
		var card := node as Button
		if card == null or not card.has_meta(&"shop_offer_id"):
			continue
		_refresh_shop_card_localization(card)
	if _system_menu_button != null:
		_system_menu_button.text = _context.resolve_text(
			&"screen.run_container.title"
		)
		_system_menu_button.set_meta(
			&"accessible_text", _system_menu_button.text
		)
	if _system_menu_overlay != null:
		_system_menu_overlay.relocalize(localized_text)
	if _prepare_action_group_selector != null:
		for index: int in _prepare_action_group_selector.item_count:
			var label_key := StringName(
				_prepare_action_group_selector.get_item_metadata(index)
			)
			_prepare_action_group_selector.set_item_text(
				index,
				_context.resolve_text(label_key)
			)
	if not _modal_node_name.is_empty():
		var status := get_node_or_null(
			"%s/Content/Status" % _modal_node_name
		) as Label
		if status != null:
			status.text = _context.resolve_text(_modal_status_key)
	_status_view.relocalize(_text_resolver())
	_refresh_node_choice_result_view()
	var settings := get_node_or_null("Composition") as SettingsScreenComposition
	if settings != null:
		settings.relocalize(localized_text)


func refresh_interaction_state() -> void:
	if (
		_modal_open
		or (
			_system_menu_overlay != null
			and _system_menu_overlay.is_open()
		)
	):
		return
	var composition := get_node_or_null("Composition")
	var camp_start := _action_button(&"camp.start")
	if camp_start != null and composition is CampWorldScreen:
		camp_start.disabled = (
			(composition as CampWorldScreen).selected_expedition_request()
			== null
		)
	var reward_confirm := _action_button(&"reward.confirm")
	if reward_confirm != null and composition is RunRewardScreen:
		reward_confirm.disabled = (
			(composition as RunRewardScreen).selected_reward_id().is_empty()
		)
	var combat_inspect := _action_button(&"combat.inspect")
	if combat_inspect != null and composition is RunCombatScreen:
		combat_inspect.disabled = (
			(composition as RunCombatScreen).selected_unit_serial() <= 0
		)
	var prepare_start := _action_button(&"prepare.start")
	if prepare_start != null and composition is RunPrepareScreen:
		var prepare_screen := composition as RunPrepareScreen
		prepare_start.disabled = not prepare_screen.start_enabled()
		var forge_confirm := _action_button(&"prepare.forge.confirm")
		var forge_cancel := _action_button(&"prepare.forge.cancel")
		var has_confirmation := (
			prepare_screen.has_pending_forge_confirmation()
		)
		if forge_confirm != null:
			forge_confirm.disabled = not has_confirmation
		if forge_cancel != null:
			forge_cancel.disabled = not has_confirmation
		var choice_begin := _action_button(&"choice.begin")
		var choice_confirm := _action_button(&"choice.confirm")
		var choice_cancel := _action_button(&"choice.cancel")
		var has_choice := prepare_screen.has_node_choice_overlay()
		for node: Node in find_children("ShopCard*", "Button", true, false):
			var shop_card := node as Button
			if shop_card != null and shop_card.has_meta(&"shop_offer_id"):
				var has_offer := not String(
					shop_card.get_meta(&"shop_offer_id", "")
				).is_empty()
				shop_card.disabled = has_choice or not has_offer
				shop_card.focus_mode = (
					Control.FOCUS_ALL
					if has_offer and not has_choice
					else Control.FOCUS_NONE
				)
		var has_choice_confirmation := (
			prepare_screen.has_pending_node_choice_confirmation()
		)
		if choice_begin != null:
			choice_begin.disabled = (
				not has_choice or has_choice_confirmation
			)
		if choice_confirm != null:
			choice_confirm.disabled = not has_choice_confirmation
		if choice_cancel != null:
			choice_cancel.disabled = not has_choice_confirmation
		var has_node_service := prepare_screen.has_node_service_pending()
		var service_dismantle := _action_button(&"service.dismantle")
		if service_dismantle != null:
			service_dismantle.disabled = not has_node_service
		var service_exit := _action_button(&"service.exit")
		if service_exit != null:
			service_exit.disabled = not has_node_service
		if has_choice:
			for blocked_action: StringName in [
				&"prepare.unit",
				&"prepare.refresh",
				&"prepare.buy",
				&"prepare.xp",
				&"prepare.sell",
				&"prepare.forge",
				&"prepare.forge.confirm",
				&"prepare.forge.cancel",
				&"prepare.equip",
				&"prepare.dismantle",
				&"prepare.move_board",
				&"prepare.move_bench",
				&"prepare.start",
			]:
				var blocked_button := _action_button(blocked_action)
				if blocked_button != null:
					blocked_button.disabled = true
		else:
			# refresh/xp 的 enabled 狀態只有 typed quote 能決定；一般 refresh
			# 不可沿用舊 generic action 邏輯把 fail-closed 控制項重新打開。
			_apply_prepare_shop_quote_controls()
	_refresh_node_choice_result_view()
	_apply_keyboard_focus_graph()


## review N1／N2：ack 按鈕的可用性與 result 文字都只由 unacknowledged receipt 決定
## （design :201），與 route／resolution state 無關，故所有掛了 `choice.ack` 的畫面
## 共用同一段（APPLY→RUN_MAP、REWARD→RUN_REWARD、DISMANTLE→RUN_PREPARE）。
func _refresh_node_choice_result_view() -> void:
	var composition := get_node_or_null("Composition") as ProductionScreen
	var result: NodeChoiceResultSnapshot = (
		composition.pending_node_choice_result()
		if composition != null
		else null
	)
	var choice_ack := _action_button(&"choice.ack")
	# modal 開著時背景按鈕的 disabled 由 _disable_modal_background 接管，
	# 這裡只更新文字面（與 refresh_interaction_state 的 modal 守衛同義務）。
	if choice_ack != null and not _modal_open:
		choice_ack.disabled = result == null
	var label := get_node_or_null(NODE_CHOICE_RESULT_NODE) as Label
	if label == null:
		return
	label.visible = result != null
	# 缺文案時 resolve_text 回鍵名本身：漏鍵要看得見，不要靜默空白。
	label.text = (
		_context.resolve_text(result.result_key)
		if result != null and _context != null
		else ""
	)


func _show_recovery_confirmation(trigger: Button) -> void:
	_show_confirmation_modal(
		RECOVERY_MODAL_NODE,
		&"menu.recovery.status",
		&"menu.recovery.confirm",
		&"menu.recovery.cancel",
		&"",
		trigger
	)


func _show_node_choice_confirmation(trigger: Button) -> void:
	var composition := get_node_or_null("Composition") as RunPrepareScreen
	if composition == null:
		return
	_show_confirmation_modal(
		"NodeChoiceConfirmation",
		composition.selected_node_choice_preview_key(),
		&"choice.confirm",
		&"choice.cancel",
		&"",
		trigger
	)


func _open_presentation_confirmation(
	action_id: StringName,
	trigger: Button
) -> void:
	var plan: Dictionary = _PRESENTATION_CONFIRMATIONS[action_id]
	_show_confirmation_modal(
		String(plan["node"]),
		StringName(plan["status_key"]),
		StringName(plan["confirm"]),
		StringName(plan["cancel"]),
		action_id,
		trigger
	)


## `deferred_action` 非空＝呈現層確認（確認前零 dispatch）；空字串＝app 層已持有
## confirmation 狀態，confirm／cancel 都要照常 dispatch 回去（recovery 流程）。
func _show_confirmation_modal(
	node_name: String,
	status_key: StringName,
	confirm_action: StringName,
	cancel_action: StringName,
	deferred_action: StringName,
	trigger: Button,
	deferred_payload: Dictionary = {}
) -> void:
	# G2 L4：舊寫法在「節點還在（queue_free 尚未生效）」時直接 return 而不設旗標，
	# 同幀二次觸發就會留下「app 層 confirmation 開著、畫面卻沒有 modal」的狀態。
	# 關閉時已改為立即 remove_child，這裡的守衛因此只代表「真的已經開著」。
	if _modal_open or get_node_or_null(node_name) != null:
		return
	_modal_open = true
	_modal_node_name = node_name
	_modal_status_key = status_key
	_modal_confirm_action = confirm_action
	_modal_cancel_action = cancel_action
	_modal_deferred_action = deferred_action
	_modal_deferred_payload = deferred_payload.duplicate(true)
	_modal_trigger = trigger
	_disable_modal_background()
	var blocker := ColorRect.new()
	blocker.name = "ModalInputBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(0.0, 0.0, 0.0, 0.72)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.focus_mode = Control.FOCUS_NONE
	blocker.z_index = 99
	add_child(blocker)
	var dialog := PanelContainer.new()
	dialog.name = node_name
	# P10：PRESET_CENTER 的錨點在中心，但預設 grow 會讓左上角落在畫面中心；
	# grow BOTH 才是真置中。
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	ExpeditionLayoutMetrics.set_fixed_min(dialog, 840.0, 330.0)
	dialog.theme_type_variation = &"ExpeditionModalPanel"
	dialog.z_index = 100
	add_child(dialog)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(content)
	var status := Label.new()
	status.name = "Status"
	status.text = _context.resolve_text(status_key)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(status)
	for action_id: StringName in [confirm_action, cancel_action]:
		var button := Button.new()
		button.name = _button_name(action_id)
		button.text = _context.resolve_text(action_id)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta(&"action_id", action_id)
		content.add_child(button)
		button.pressed.connect(_on_action_pressed.bind(button))
	var confirm := content.get_child(1) as Button
	var cancel := content.get_child(2) as Button
	if confirm != null and cancel != null:
		var dialog_controls: Array[Control] = [confirm, cancel]
		_link_focus_cycle(dialog_controls)
	if confirm != null:
		call_deferred(&"_grab_focus_deferred", confirm)


func _deferred_layout_settle() -> void:
	if not is_inside_tree():
		return
	if route_kind == &"RUN_PREPARE":
		_refresh_prepare_action_pages_minimum()
	_sync_status_band_visibility()


func _sync_status_band_visibility() -> void:
	if _layout_shell == null:
		return
	var visible := not _status_view.message_text().is_empty()
	_layout_shell.set_status_visible(visible)
	_refresh_route_layout()
	_status_view.attach(
		self,
		0,
		_layout_shell.current_content_rect(
			ProductionLayoutShell.REGION_STATUS
		)
	)
	_refresh_in_run_hud_shell_layout()
	var composition := get_node_or_null(^"Composition")
	if composition != null and composition.has_method(&"refresh_layout_rects"):
		composition.call(&"refresh_layout_rects")


## 四個局內 route 的共用 HUD 不隸屬 layout shell 的 host，因此 shell
## scale/status 改變後要在同一事件結尾套用最新 content rect。這裡不輪詢。
func _refresh_in_run_hud_shell_layout() -> void:
	if route_kind not in RUN_ROUTES:
		return
	var composition := get_node_or_null(^"Composition")
	if composition == null:
		return
	var hud_shell := composition.find_child(
		"InRunHudShell", true, false
	) as InRunHudShell
	if hud_shell != null:
		hud_shell.refresh_layout_rects()


func _close_confirmation_modal() -> void:
	var dialog := (
		get_node_or_null(_modal_node_name)
		if not _modal_node_name.is_empty()
		else null
	)
	if dialog != null:
		# 先讓出節點名稱再排隊釋放：queue_free 要到影格結束才生效，光靠它會讓同幀的
		# 重新開啟被「節點還在」的守衛擋掉（G2 L4）。改名而非 remove_child，
		# 是為了讓待釋放的節點留在樹上（離開樹會被判定成 orphan）。
		dialog.name = "%sRetired" % _modal_node_name
		dialog.queue_free()
	_modal_open = false
	_modal_node_name = ""
	_modal_status_key = &""
	_modal_confirm_action = &""
	_modal_cancel_action = &""
	_modal_deferred_action = &""
	_modal_deferred_payload.clear()
	var blocker := get_node_or_null(^"ModalInputBlocker")
	if blocker != null:
		(blocker as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		blocker.name = "ModalInputBlockerRetired"
		blocker.queue_free()
	_restore_modal_background()
	refresh_interaction_state()
	call_deferred(&"_restore_modal_trigger_focus")


func _disable_modal_background() -> void:
	_modal_background_disabled.clear()
	_modal_background_focus.clear()
	_modal_background_mouse.clear()
	_modal_background_controls.clear()
	for node: Node in find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or control == _system_menu_overlay:
			continue
		var identity := control.get_instance_id()
		_modal_background_controls[identity] = control
		_modal_background_focus[identity] = control.focus_mode
		_modal_background_mouse[identity] = control.mouse_filter
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if control is BaseButton:
			_modal_background_disabled[identity] = (control as BaseButton).disabled
			(control as BaseButton).disabled = true
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		_modal_composition_focus_behavior = composition.focus_behavior_recursive
		_modal_composition_process_mode = composition.process_mode
		composition.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		composition.process_mode = Node.PROCESS_MODE_DISABLED


func _restore_modal_background() -> void:
	for identity: int in _modal_background_controls:
		var control := _modal_background_controls[identity]
		if control == null or not is_instance_valid(control):
			continue
		control.focus_mode = int(_modal_background_focus.get(
			identity, Control.FOCUS_NONE
		))
		control.mouse_filter = int(_modal_background_mouse.get(
			identity, Control.MOUSE_FILTER_IGNORE
		))
		if control is BaseButton and _modal_background_disabled.has(identity):
			(control as BaseButton).disabled = bool(
				_modal_background_disabled[identity]
			)
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.focus_behavior_recursive = _modal_composition_focus_behavior
		composition.process_mode = _modal_composition_process_mode
	_modal_background_disabled.clear()
	_modal_background_focus.clear()
	_modal_background_mouse.clear()
	_modal_background_controls.clear()


## 延後取得焦點的統一入口：目標可能在同一影格內被關閉／換場而離開場景樹，
## 直接 `grab_focus.call_deferred()` 會在引擎層噴 "!is_inside_tree()"。
func _grab_focus_deferred(control: Control) -> void:
	if (
		control != null
		and is_instance_valid(control)
		and control.is_inside_tree()
	):
		control.grab_focus()


func _restore_modal_trigger_focus() -> void:
	if (
		_modal_trigger != null
		and is_instance_valid(_modal_trigger)
		and _modal_trigger.is_inside_tree()
	):
		_modal_trigger.grab_focus()
	_modal_trigger = null


func _apply_keyboard_focus_graph() -> void:
	if (
		_modal_open
		or (
			_system_menu_overlay != null
			and _system_menu_overlay.is_open()
		)
	):
		return
	var controls := _ordered_focus_controls()
	_link_focus_cycle(controls)


func _ordered_focus_controls() -> Array[Control]:
	var result: Array[Control] = []
	# Staged-only composition tests run before activate_live() enables this
	# button. Keep its stable first-stop position in the authored graph; the
	# live activation enables it before focus is actually grabbed.
	if (
		_system_menu_button != null
		and _system_menu_button.is_visible_in_tree()
		and _system_menu_button.focus_mode != Control.FOCUS_NONE
	):
		result.append(_system_menu_button)
	if (
		route_kind == &"RUN_PREPARE"
		and _control_is_focusable(_prepare_action_group_selector)
	):
		result.append(_prepare_action_group_selector)
	var settings := (
		get_node_or_null("Composition") as SettingsScreenComposition
	)
	if settings != null:
		for editor: Control in settings.focus_controls():
			if _control_is_focusable(editor) and not result.has(editor):
				result.append(editor)
	var blocked: Array[StringName] = []
	for action_id: StringName in _required_action_ids():
		var button := _action_button(action_id)
		if not _control_is_focusable(button):
			blocked.append(action_id)
	var scale_percent := 100
	var host := get_parent() as Control
	if host != null:
		scale_percent = int(
			host.get_meta(&"ui_scale_percent", 100)
		)
	var focus_graph := KeyboardFocusGraph.new()
	var action_order := focus_graph.focus_order(
		route_kind,
		scale_percent,
		blocked
	)
	# G2 F9：延後名單的權威只有 KeyboardFocusGraph 一處（以前 ProductionScreen
	# 另存一份常數，改焦點圖不會反映到畫面）。
	var deferred := focus_graph.deferred_actions(route_kind)
	for action_id: StringName in action_order:
		if action_id in deferred:
			continue
		var button := _action_button(action_id)
		if _control_is_focusable(button) and not result.has(button):
			result.append(button)
	for action_id: StringName in _required_action_ids():
		if action_id in deferred:
			continue
		var button := _action_button(action_id)
		if _control_is_focusable(button) and not result.has(button):
			result.append(button)
	# P2：商店卡帶 pressed handler 而無 action_id meta，必須顯式納入焦點環，
	# 鍵盤玩家才能 Tab 到卡片按 Enter 購買。排在一般動作之後、
	# 誤觸代價高的 deferred 動作之前。
	for node: Node in find_children("ShopCard*", "Button", true, false):
		var card := node as Button
		if (
			card != null
			and card.has_meta(&"shop_offer_id")
			and _control_is_focusable(card)
			and not result.has(card)
		):
			result.append(card)
	# BoardGrid is a hidden metadata contract. Keyboard board targeting is owned
	# by BuildUnitSelector + W and the existing Move Board/Bench actions.
	var bench_row := find_child("BenchRow", true, false) as HBoxContainer
	if bench_row != null:
		for node: Node in bench_row.get_children():
			var bench_cell := node as Control
			if _control_is_focusable(bench_cell) and not result.has(bench_cell):
				result.append(bench_cell)
	# 誤觸代價高的動作排在所有同畫面「動作按鈕」之後（下面的 selector 仍排在它後面；
	# 焦點環涵蓋它，只是不在按鈕段的前面）。
	for action_id: StringName in deferred:
		var button := _action_button(action_id)
		if _control_is_focusable(button) and not result.has(button):
			result.append(button)
	for selector_name: StringName in [
		&"CommanderSelector",
		&"ChallengeSelector",
		&"FacilityData",
		&"NodeSelector",
		&"OverflowSelector",
		&"DeploymentIssues",
		&"UnitSelector",
		&"OfferSelector",
		&"TraitList",
		&"HudInventory",
		&"HudRelicSlots",
		&"BoardSelector",
		&"BenchSelector",
		&"ShopSelector",
		&"InventorySelector",
		&"BuildUnitSelector",
		&"ChoiceSelector",
		&"CategorySelector",
		&"SearchInput",
		&"EntrySelector",
		&"CompareSelector",
	]:
		var selector := find_child(
			String(selector_name),
			true,
			false
		) as Control
		if _control_is_focusable(selector) and not result.has(selector):
			result.append(selector)
	return result


## G2 L3：`visible` 只看節點自己。整列 row（或整個 Composition）被隱藏時，
## 子控制項的 `visible` 仍是 true，焦點環會把看不見的編輯器收進去。
func _control_is_focusable(control: Control) -> bool:
	if (
		control == null
		or not control.is_visible_in_tree()
		or control.focus_mode == Control.FOCUS_NONE
	):
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		# Quote-owned shop actions stay in the authored keyboard cycle even
		# while rejected. Their adjacent status label carries the localized
		# reason, and keeping the stable stop lets keyboard/assistive users
		# discover that reason instead of silently losing the action.
		var action_id := StringName(control.get_meta(&"action_id", &""))
		if action_id not in [&"prepare.refresh", &"prepare.xp"]:
			return false
	return true


func _link_focus_cycle(controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	for index: int in controls.size():
		var current := controls[index]
		var previous := controls[posmod(index - 1, controls.size())]
		var next := controls[posmod(index + 1, controls.size())]
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_bottom = current.get_path_to(next)


func _action_button(action_id: StringName) -> Button:
	for button: Button in _action_buttons():
		if (
			button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _action_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for node: Node in find_children("*", "Button", true, false):
		result.append(node as Button)
	return result


func _required_action_ids() -> Array[StringName]:
	match route_kind:
		&"MENU_MAIN":
			var menu := (
				_context.snapshot_clone() as MainMenuSnapshot
				if _context != null
				else null
			)
			var menu_actions: Array[StringName] = []
			if menu != null and menu.can_continue:
				menu_actions.append(&"menu.continue")
			if menu != null and menu.can_start:
				menu_actions.append(&"menu.start")
			if menu != null and menu.has_recovery:
				menu_actions.append(&"menu.recovery")
			menu_actions.append(&"menu.settings")
			menu_actions.append(&"menu.exit")
			return menu_actions
		&"SETTINGS":
			return [&"settings.apply", &"settings.back"]
		&"CAMP_WORLD":
			return [
				&"camp.expedition_gate",
				&"camp.commander_hall",
				&"camp.collection",
				&"camp.forge",
				&"camp.challenge_monument",
				&"camp.settings",
				&"camp.start",
				&"camp.menu",
			]
		&"FACILITY_EXPEDITION_GATE", \
		&"FACILITY_COMMANDER_HALL", \
		&"COLLECTION", \
		&"FACILITY_UNLOCK_WORKSHOP", \
		&"FACILITY_CHALLENGE_MONUMENT":
			return [&"camp.back"]
		&"RUN_MAP":
			# `choice.ack`：APPLY_AND_COMPLETE 出口把 phase 切成 MAP（design :206），
			# 未 ack 的結果因此要在這裡播完並確認（review N1）。
			return [
				&"map.select",
				&"map.confirm",
				&"choice.ack",
			]
		&"RUN_PREPARE":
			return [
				&"prepare.unit",
				&"prepare.refresh",
				&"prepare.buy",
				&"prepare.xp",
				&"prepare.sell",
				&"prepare.forge",
				&"prepare.forge.confirm",
				&"prepare.forge.cancel",
				&"prepare.equip",
				&"prepare.dismantle",
				&"service.dismantle",
				&"service.exit",
				&"prepare.move_board",
				&"prepare.move_bench",
				&"prepare.start",
				&"choice.begin",
				&"choice.confirm",
				&"choice.cancel",
				&"choice.ack",
			]
		&"RUN_COMBAT":
			return [
				&"combat.pause",
				&"combat.inspect",
				&"combat.speed",
			]
		&"RUN_REWARD":
			# `choice.ack`：OPEN_REWARD_STAGE 出口把 phase 切成 REWARD（design :207）。
			return [
				&"reward.select",
				&"reward.confirm",
				&"choice.ack",
			]
		&"RUN_ROUTE_FALLBACK":
			return [&"run.retry_route", &"run.menu"]
		&"APP_ROUTE_FALLBACK":
			return [&"app.retry_route", &"menu.exit"]
		&"RESULTS":
			return [&"results.camp", &"results.menu"]
		&"RESULTS_FALLBACK":
			return [
				&"results.retry",
				&"results.camp",
				&"results.menu",
			]
	return []


func _route_title_key() -> StringName:
	return StringName("screen.%s.title" % String(route_kind).to_lower())


func _button_name(action_id: StringName) -> String:
	var stable_name := String(action_id).replace(".", "_").to_pascal_case()
	return "%sButton" % stable_name


func _snapshot_board_validation_report(
	snapshot: RunPresentationSnapshot
) -> BoardValidationReport:
	if snapshot == null:
		return null
	for property: Dictionary in snapshot.get_property_list():
		if StringName(property.get("name", &"")) == &"board_validation_report":
			var report: Variant = snapshot.get(&"board_validation_report")
			return (
				(report as BoardValidationReport).deep_clone()
				if report is BoardValidationReport
				else null
			)
	return null


## 錯誤呈現面的在地化出口：staged context 尚未繫結時退回鍵名本身（測試與
## boot 早期路徑都可能在沒有 context 的情況下觸發顯示）。
func _text_resolver() -> Callable:
	return func(key: StringName) -> String:
		return (
			_context.resolve_text(key)
			if _context != null
			else String(key)
		)


func _localized_text_clone() -> Dictionary:
	return (
		_context.localized_text.duplicate(true)
		if _context != null
		else {}
	)

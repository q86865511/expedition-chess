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

const RECOVERY_MODAL_NODE: String = "RecoveryConfirmation"

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
var _modal_status_key: StringName = &""
var _modal_trigger: Button
var _modal_background_disabled: Dictionary[int, bool] = {}
var _modal_background_focus: Dictionary[int, int] = {}


func _ready() -> void:
	_binding_closed = true


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
	var composition_error := _compose_production_child(context)
	if not composition_error.is_empty():
		return composition_error
	_live_context = context
	return &""


func activate_live() -> void:
	_live_active = _live_context != null
	if not _live_active:
		return
	var buttons := _action_buttons()
	for button: Button in buttons:
		if not button.pressed.is_connected(_on_action_pressed.bind(button)):
			button.pressed.connect(_on_action_pressed.bind(button))
	refresh_interaction_state()
	var focusable := _ordered_focus_controls()
	if not focusable.is_empty():
		call_deferred(&"_grab_focus_deferred", focusable[0])


func request_intent(intent: RunPresentationIntent) -> RunPresentationResult:
	if _live_active and _live_context.intent_port != null:
		return _live_context.intent_port.dispatch(intent)
	return RunPresentationResult.failure(
		DiagnosticError.new(
			SCREEN_NOT_ACTIVE,
			&"error.presentation.screen_not_active"
		)
	)


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


func is_confirmation_modal_open() -> bool:
	return _modal_open


func confirmation_modal_node_name() -> String:
	return _modal_node_name


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
	var label := get_node_or_null("Label") as Label
	if label != null:
		label.text = _context.resolve_text(_route_title_key())
	# G2 H3：常駐錯誤呈現面。每個 staged route 都要有，才不會出現「某些畫面
	# 操作失敗完全沒回饋」的死角。
	_status_view.attach(self)
	_status_view.clear(_text_resolver())
	var action_ids := _required_action_ids()
	if action_ids.is_empty():
		return
	var controls := VBoxContainer.new()
	controls.name = "Actions"
	controls.set_anchors_preset(Control.PRESET_CENTER)
	add_child(controls)
	for action_id: StringName in action_ids:
		var button := Button.new()
		button.name = _button_name(action_id)
		button.text = _context.resolve_text(action_id)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta(&"action_id", action_id)
		controls.add_child(button)


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
				context.intent_port
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
				context.intent_port
			)
		&"RUN_COMBAT":
			if not composition is RunCombatScreen:
				return SCREEN_COMPOSITION_TYPE_INVALID
			var combat := composition as RunCombatScreen
			var compose_error := combat.compose(
				context.snapshot_clone() as RunPresentationSnapshot,
				context.intent_port
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
				context.intent_port
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
			var confirmed := action_id == _modal_confirm_action
			_close_confirmation_modal()
			if confirmed:
				_dispatch_action(deferred, null)
			return
	elif _PRESENTATION_CONFIRMATIONS.has(action_id):
		_open_presentation_confirmation(action_id, button)
		return
	_dispatch_action(action_id, button)


func _dispatch_action(action_id: StringName, trigger: Button) -> void:
	var local_result: Variant = _invoke_local_control(action_id)
	_last_control_result = (
		local_result
		if local_result != null
		else _live_context.action_port.invoke(action_id)
	)
	_status_view.show_result(_last_control_result, _text_resolver())
	if String(action_id).begins_with("prepare."):
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


func _invoke_local_control(action_id: StringName) -> Variant:
	var composition := get_node_or_null("Composition")
	match action_id:
		&"map.select":
			return (
				(composition as RunMapScreen).accept_visible_node_result()
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
			button.text = _context.resolve_text(
				StringName(button.get_meta(&"action_id"))
			)
	if not _modal_node_name.is_empty():
		var status := get_node_or_null(
			"%s/Status" % _modal_node_name
		) as Label
		if status != null:
			status.text = _context.resolve_text(_modal_status_key)
	_status_view.relocalize(_text_resolver())
	var settings := get_node_or_null("Composition") as SettingsScreenComposition
	if settings != null:
		settings.relocalize(localized_text)


func refresh_interaction_state() -> void:
	if _modal_open:
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
	_apply_keyboard_focus_graph()


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
	trigger: Button
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
	_modal_trigger = trigger
	_disable_modal_background()
	var dialog := VBoxContainer.new()
	dialog.name = node_name
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	add_child(dialog)
	var status := Label.new()
	status.name = "Status"
	status.text = _context.resolve_text(status_key)
	dialog.add_child(status)
	for action_id: StringName in [confirm_action, cancel_action]:
		var button := Button.new()
		button.name = _button_name(action_id)
		button.text = _context.resolve_text(action_id)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta(&"action_id", action_id)
		dialog.add_child(button)
		button.pressed.connect(_on_action_pressed.bind(button))
	var confirm := dialog.get_child(1) as Button
	var cancel := dialog.get_child(2) as Button
	if confirm != null and cancel != null:
		var dialog_controls: Array[Control] = [confirm, cancel]
		_link_focus_cycle(dialog_controls)
	if confirm != null:
		call_deferred(&"_grab_focus_deferred", confirm)


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
	_restore_modal_background()
	refresh_interaction_state()
	call_deferred(&"_restore_modal_trigger_focus")


func _disable_modal_background() -> void:
	_modal_background_disabled.clear()
	_modal_background_focus.clear()
	var actions := get_node_or_null("Actions")
	if actions == null:
		return
	for node: Node in actions.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		var identity := button.get_instance_id()
		_modal_background_disabled[identity] = button.disabled
		_modal_background_focus[identity] = button.focus_mode
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE


func _restore_modal_background() -> void:
	var actions := get_node_or_null("Actions")
	if actions != null:
		for node: Node in actions.find_children(
			"*",
			"Button",
			true,
			false
		):
			var button := node as Button
			if button == null:
				continue
			var identity := button.get_instance_id()
			if _modal_background_disabled.has(identity):
				button.disabled = bool(
					_modal_background_disabled[identity]
				)
			if _modal_background_focus.has(identity):
				button.focus_mode = int(
					_modal_background_focus[identity]
				)
	_modal_background_disabled.clear()
	_modal_background_focus.clear()


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
	if _modal_open:
		return
	var controls := _ordered_focus_controls()
	_link_focus_cycle(controls)


func _ordered_focus_controls() -> Array[Control]:
	var result: Array[Control] = []
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
		if _control_is_focusable(selector):
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
			return [&"map.select", &"map.confirm", &"run.menu"]
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
				&"prepare.move_board",
				&"prepare.move_bench",
				&"prepare.start",
				&"choice.begin",
				&"choice.confirm",
				&"choice.cancel",
				&"run.menu",
			]
		&"RUN_COMBAT":
			return [
				&"combat.pause",
				&"combat.inspect",
				&"combat.speed",
				&"run.menu",
			]
		&"RUN_REWARD":
			return [&"reward.select", &"reward.confirm", &"run.menu"]
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

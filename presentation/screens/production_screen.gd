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
	&"run.menu", &"prepare.start",
]

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
var _prepare_action_group_selector: OptionButton
var _prepare_action_group_pages: Array[GridContainer] = []
var _layout_shell: ProductionLayoutShell


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
	elif route_kind == &"RUN_PREPARE" and _layout_shell != null:
		var controls := HBoxContainer.new()
		controls.name = "Actions"
		controls.theme_type_variation = &"ExpeditionPrepareBottomBand"
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(controls)
		_build_prepare_action_controls(controls, action_ids)
	else:
		var controls: BoxContainer = (
			HBoxContainer.new()
			if route_kind == &"SETTINGS"
			else VBoxContainer.new()
		)
		controls.name = "Actions"
		if route_kind == &"SETTINGS":
			controls.z_index = 6
			add_child(controls)
		else:
			# 動作欄真置中：CenterContainer 承擔錨定，欄位大小變動
			# （縮放、文案）時仍保持水平垂直置中。
			var center := CenterContainer.new()
			center.name = "ActionsHost"
			center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			center.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(center)
			center.add_child(controls)
		for action_id: StringName in action_ids:
			var action := _new_action_button(action_id)
			if route_kind == &"SETTINGS":
				action.theme_type_variation = &"ExpeditionBottomAction"
				action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			controls.add_child(action)
		_apply_settings_layout(100)


func _install_b1_layout() -> void:
	if route_kind not in [&"CAMP_WORLD", &"RUN_PREPARE"]:
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
		title.custom_minimum_size = Vector2(
			ProductionLayoutShell.TITLE_WIDTH, 0.0
		)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		composition.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _install_fullscreen_ui_background() -> void:
	if route_kind not in [&"MENU_MAIN", &"SETTINGS"]:
		return
	var background := Panel.new()
	background.name = "FullscreenBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme_type_variation = &"ExpeditionBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)


func _configure_non_b1_layout(title: Label) -> void:
	if route_kind not in [&"MENU_MAIN", &"SETTINGS"]:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if title != null:
		title.position = Vector2(72.0, 28.0)
		title.size = Vector2(1136.0, 56.0)
		title.custom_minimum_size = Vector2(0.0, 56.0)
		title.theme_type_variation = &"ExpeditionTitle"
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if route_kind != &"SETTINGS":
		return
	_apply_settings_layout(100)


func apply_theme_scale_layout(scale_percent: int) -> void:
	_apply_settings_layout(scale_percent)
	if _layout_shell != null:
		_layout_shell.set_scale_factor(float(scale_percent) / 100.0)
		var title := get_node_or_null(^"Label") as Label
		if title != null:
			var title_rect := _layout_shell.current_content_rect(
				ProductionLayoutShell.REGION_TOP
			)
			title_rect.position.x += ProductionLayoutShell.TITLE_INSET
			title_rect.size.x = ProductionLayoutShell.TITLE_WIDTH
			title.position = title_rect.position
			title.size = title_rect.size
		_sync_status_band_visibility()


## SETTINGS 版面的單一權威（P3/P4/P5）：由下往上排——動作列貼安全區底、
## 其上為畫面狀態帶、其上為 Composition（draft 驗證列保留在 Composition
## 可見高度內）。所有高度隨 UI 縮放 ×factor，任何縮放下不出安全區。
func _apply_settings_layout(scale_percent: int) -> void:
	if route_kind != &"SETTINGS":
		return
	var factor := float(scale_percent) / 100.0
	var safe_bottom := 720.0 - ProductionLayoutShell.SAFE_MARGIN
	var actions_height := ceilf(48.0 * factor)
	var actions_top := safe_bottom - actions_height
	var status_height := ceilf(44.0 * factor)
	var gap := ceilf(8.0 * factor)
	var status_top := actions_top - gap - status_height
	var composition_top := 100.0
	var composition_height := status_top - gap - composition_top
	var actions := get_node_or_null(^"Actions") as Control
	if actions != null:
		actions.position = Vector2(72.0, actions_top)
		actions.size = Vector2(1136.0, actions_height)
	var composition := get_node_or_null(^"Composition") as Control
	if composition != null:
		composition.position = Vector2(72.0, composition_top)
		composition.custom_minimum_size = Vector2(1136.0, composition_height)
		composition.size = Vector2(1136.0, composition_height)
		composition.clip_contents = true
		if composition.has_method(&"apply_status_rect"):
			composition.call(
				&"apply_status_rect",
				Rect2(
					0.0,
					composition_height - status_height,
					1136.0,
					status_height
				)
			)
	_status_view.attach(
		self,
		0,
		Rect2(72.0, status_top, 1136.0, status_height)
	)


func _build_camp_action_controls(action_ids: Array[StringName]) -> void:
	var facilities := VBoxContainer.new()
	facilities.name = "Actions"
	facilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facilities.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 設施鈕在左欄垂直置中，不留「上滿下空」的殘缺觀感。
	facilities.alignment = BoxContainer.ALIGNMENT_CENTER
	layout_content(ProductionLayoutShell.REGION_LEFT).add_child(facilities)
	for action_id: StringName in action_ids.slice(0, 5):
		var facility := _new_action_button(action_id)
		facility.set_meta(&"expedition_theme_fixed_minimum", true)
		facilities.add_child(facility)
	var primary := HBoxContainer.new()
	primary.name = "CampPrimaryActions"
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_content(ProductionLayoutShell.REGION_BOTTOM).add_child(primary)
	for action_id: StringName in action_ids.slice(5):
		var button := _new_action_button(action_id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.add_child(button)


func _new_action_button(action_id: StringName) -> Button:
	var button := Button.new()
	button.name = _button_name(action_id)
	button.text = _context.resolve_text(action_id)
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta(&"action_id", action_id)
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
	ExpeditionLayoutMetrics.set_fixed_min(secondary, 206.0, 0.0)
	secondary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(secondary)
	_prepare_action_group_selector = OptionButton.new()
	_prepare_action_group_selector.name = PREPARE_ACTION_GROUP_SELECTOR
	_prepare_action_group_selector.focus_mode = Control.FOCUS_ALL
	_prepare_action_group_selector.theme_type_variation = &"ExpeditionBottomAction"
	_prepare_action_group_selector.allow_reselect = true
	ExpeditionLayoutMetrics.set_fixed_min(
		_prepare_action_group_selector, 0.0, 48.0
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
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	secondary.add_child(page_scroll)
	var pages := Control.new()
	pages.name = "PrepareActionGroupPages"
	ExpeditionLayoutMetrics.set_fixed_min(pages, 206.0, 0.0)
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
		for action_value: Variant in group["actions"]:
			var action_id := StringName(action_value)
			if action_ids.has(action_id):
				var action := _new_action_button(action_id)
				action.theme_type_variation = &"ExpeditionBottomAction"
				action.set_meta(&"expedition_theme_fixed_minimum", true)
				page.add_child(action)

	var pinned := VBoxContainer.new()
	pinned.name = "PinnedActions"
	ExpeditionLayoutMetrics.set_fixed_min(pinned, 180.0, 0.0)
	pinned.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(pinned)
	for action_id: StringName in PREPARE_PINNED_ACTIONS:
		if action_ids.has(action_id):
			var action := _new_action_button(action_id)
			action.theme_type_variation = &"ExpeditionBottomAction"
			action.set_meta(&"expedition_theme_fixed_minimum", true)
			pinned.add_child(action)
	_prepare_action_group_selector.item_selected.connect(
		_on_prepare_action_group_selected
	)
	_prepare_action_group_selector.select(default_group_index)
	# select() 不發 item_selected（P1）：初始分組頁的高度與可見性
	# 必須顯式初始化，否則預設組只露出第一顆動作。
	_on_prepare_action_group_selected(default_group_index)


func _build_prepare_shop_controls(
	controls: HBoxContainer,
	action_ids: Array[StringName],
	snapshot: RunPresentationSnapshot
) -> void:
	var shop_shell := HBoxContainer.new()
	shop_shell.name = "PrepareShopBand"
	shop_shell.theme_type_variation = &"ExpeditionPrepareShopBand"
	ExpeditionLayoutMetrics.set_fixed_min(shop_shell, 660.0, 0.0)
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
	ExpeditionLayoutMetrics.set_fixed_min(heading, 120.0, 0.0)
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
	if snapshot != null and snapshot.economy != null:
		for offer: ShopOffer in snapshot.economy.shop_offers:
			var card := Button.new()
			card.name = "ShopCard%s" % String(offer.offer_id).to_pascal_case()
			card.text = "%s\n%s %d  ·  ★1" % [
				localized_content_text(offer.unit_def_id),
				_context.resolve_text(&"prepare.resource.gold"),
				offer.cost,
			]
			card.theme_type_variation = &"ExpeditionShopCard"
			# 寬度預算（1200 內容寬扣兩側欄與縮放後的分隔）允許 112；
			# 長內容名靠 autowrap 換行，卡片高度由帶區吸收，不截字。
			ExpeditionLayoutMetrics.set_fixed_min(card, 112.0, 72.0)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.size_flags_vertical = Control.SIZE_EXPAND_FILL
			card.focus_mode = Control.FOCUS_ALL
			card.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			card.toggle_mode = false
			card.set_meta(&"shop_offer_id", offer.offer_id)
			card.set_meta(&"accessible_text", card.text)
			card.pressed.connect(
				_on_prepare_shop_card_pressed.bind(offer.offer_id)
			)
			cards.add_child(card)
	if cards.get_child_count() == 0 and action_ids.has(&"prepare.buy"):
		var empty_buy := _new_action_button(&"prepare.buy")
		empty_buy.theme_type_variation = &"ExpeditionShopCard"
		ExpeditionLayoutMetrics.set_fixed_min(empty_buy, 112.0, 72.0)
		empty_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_buy.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_buy.disabled = true
		cards.add_child(empty_buy)
	var shop_actions := GridContainer.new()
	shop_actions.name = "PrepareShopActions"
	shop_actions.columns = 1
	ExpeditionLayoutMetrics.set_fixed_min(shop_actions, 140.0, 0.0)
	shop_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_shell.add_child(shop_actions)
	for action_id: StringName in [
		&"prepare.refresh", &"prepare.xp",
	]:
		if action_ids.has(action_id):
			var action := _new_action_button(action_id)
			action.theme_type_variation = &"ExpeditionBottomAction"
			ExpeditionLayoutMetrics.set_fixed_min(action, 140.0, 48.0)
			shop_actions.add_child(action)


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
	var pages := find_child("PrepareActionGroupPages", true, false) as Control
	if pages != null:
		# 用 helper 寫回 base meta，否則 theme runtime 下次 apply 會把
		# 高度重設回登記值 0（P1 回歸的第二種路徑）。
		ExpeditionLayoutMetrics.set_fixed_min(
			pages,
			206.0,
			_prepare_action_group_pages[index].get_combined_minimum_size().y
		)
	_apply_keyboard_focus_graph()


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
	_sync_status_band_visibility()
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
			button.text = _context.resolve_text(
				StringName(button.get_meta(&"action_id"))
			)
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
		for node: Node in find_children("ShopCard*", "Button", true, false):
			var shop_card := node as Button
			if shop_card != null and shop_card.has_meta(&"shop_offer_id"):
				shop_card.disabled = has_choice
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
	var dialog := PanelContainer.new()
	dialog.name = node_name
	# P10：PRESET_CENTER 的錨點在中心，但預設 grow 會讓左上角落在畫面中心；
	# grow BOTH 才是真置中。
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	ExpeditionLayoutMetrics.set_fixed_min(dialog, 560.0, 220.0)
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


func _sync_status_band_visibility() -> void:
	if _layout_shell == null:
		return
	var visible := not _status_view.message_text().is_empty()
	_layout_shell.set_status_visible(visible)
	_status_view.attach(
		self,
		0,
		_layout_shell.current_content_rect(
			ProductionLayoutShell.REGION_STATUS
		)
	)
	var composition := get_node_or_null(^"Composition")
	if composition != null and composition.has_method(&"refresh_layout_rects"):
		composition.call(&"refresh_layout_rects")


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
	var actions := find_child("Actions", true, false)
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
	var actions := find_child("Actions", true, false)
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
			# `choice.ack`：APPLY_AND_COMPLETE 出口把 phase 切成 MAP（design :206），
			# 未 ack 的結果因此要在這裡播完並確認（review N1）。
			return [
				&"map.select",
				&"map.confirm",
				&"choice.ack",
				&"run.menu",
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
			# `choice.ack`：OPEN_REWARD_STAGE 出口把 phase 切成 REWARD（design :207）。
			return [
				&"reward.select",
				&"reward.confirm",
				&"choice.ack",
				&"run.menu",
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

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

@export var route_kind: StringName

var _context: StagedScreenContext
var _live_context: ProductionLiveScreenContext
var _binding_closed: bool = false
var _live_active: bool = false
var _last_control_result: Variant
var _recovery_modal_open: bool = false
var _recovery_trigger: Button
var _recovery_background_disabled: Dictionary[int, bool] = {}
var _recovery_background_focus: Dictionary[int, int] = {}


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
		focusable[0].grab_focus.call_deferred()


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
	if (
		_recovery_modal_open
		and action_id not in [
			&"menu.recovery.confirm",
			&"menu.recovery.cancel",
		]
	):
		return
	var local_result: Variant = _invoke_local_control(action_id)
	_last_control_result = (
		local_result
		if local_result != null
		else _live_context.action_port.invoke(action_id)
	)
	if String(action_id).begins_with("prepare."):
		refresh_interaction_state()
	if (
		action_id == &"menu.recovery"
		and _last_control_result is AppActionResult
		and (_last_control_result as AppActionResult).ok
	):
		_show_recovery_confirmation(button)
	elif (
		action_id in [&"menu.recovery.cancel", &"menu.recovery.confirm"]
		and _last_control_result is AppActionResult
		and (_last_control_result as AppActionResult).ok
	):
		_close_recovery_confirmation()


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
	var status := get_node_or_null("RecoveryConfirmation/Status") as Label
	if status != null:
		status.text = _context.resolve_text(&"menu.recovery.status")
	var settings := get_node_or_null("Composition") as SettingsScreenComposition
	if settings != null:
		settings.relocalize(localized_text)


func refresh_interaction_state() -> void:
	if _recovery_modal_open:
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
	_apply_keyboard_focus_graph()


func _show_recovery_confirmation(trigger: Button) -> void:
	if get_node_or_null("RecoveryConfirmation") != null:
		return
	_recovery_modal_open = true
	_recovery_trigger = trigger
	_disable_recovery_background()
	var dialog := VBoxContainer.new()
	dialog.name = "RecoveryConfirmation"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	add_child(dialog)
	var status := Label.new()
	status.name = "Status"
	status.text = _context.resolve_text(&"menu.recovery.status")
	dialog.add_child(status)
	for action_id: StringName in [
		&"menu.recovery.confirm",
		&"menu.recovery.cancel",
	]:
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
	var first := confirm
	if first != null:
		first.grab_focus.call_deferred()


func _close_recovery_confirmation() -> void:
	var dialog := get_node_or_null("RecoveryConfirmation")
	if dialog != null:
		dialog.queue_free()
	_recovery_modal_open = false
	_restore_recovery_background()
	refresh_interaction_state()
	call_deferred(&"_restore_recovery_trigger_focus")


func _disable_recovery_background() -> void:
	_recovery_background_disabled.clear()
	_recovery_background_focus.clear()
	var actions := get_node_or_null("Actions")
	if actions == null:
		return
	for node: Node in actions.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		var identity := button.get_instance_id()
		_recovery_background_disabled[identity] = button.disabled
		_recovery_background_focus[identity] = button.focus_mode
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE


func _restore_recovery_background() -> void:
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
			if _recovery_background_disabled.has(identity):
				button.disabled = bool(
					_recovery_background_disabled[identity]
				)
			if _recovery_background_focus.has(identity):
				button.focus_mode = int(
					_recovery_background_focus[identity]
				)
	_recovery_background_disabled.clear()
	_recovery_background_focus.clear()


func _restore_recovery_trigger_focus() -> void:
	if (
		_recovery_trigger != null
		and is_instance_valid(_recovery_trigger)
		and _recovery_trigger.is_inside_tree()
	):
		_recovery_trigger.grab_focus()
	_recovery_trigger = null


func _apply_keyboard_focus_graph() -> void:
	if _recovery_modal_open:
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
	var action_order := KeyboardFocusGraph.new().focus_order(
		route_kind,
		scale_percent,
		blocked
	)
	for action_id: StringName in action_order:
		var button := _action_button(action_id)
		if _control_is_focusable(button) and not result.has(button):
			result.append(button)
	for action_id: StringName in _required_action_ids():
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


func _control_is_focusable(control: Control) -> bool:
	if (
		control == null
		or not control.visible
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


func _localized_text_clone() -> Dictionary:
	return (
		_context.localized_text.duplicate(true)
		if _context != null
		else {}
	)

class_name RunRewardScreen
extends ProductionScreen

const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"

var _model := RunRewardScreenModel.new()
var _presenter: RunScreenPresenter
var _selected_reward_id: String = ""
var _offer_selector: ItemList
var _hud_shell: InRunHudShell
var _world_board_clear_error: StringName = &""
var _world_board_clear_deferred_pending: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		# Production candidates compose while detached. Retry the clear when the
		# exact candidate becomes part of the committed SceneTree; the latch keeps
		# compose and ENTER_TREE idempotent without frame polling.
		_schedule_world_board_clear()


func compose(
	snapshot: RunPresentationSnapshot,
	intent_port: LiveScreenIntentPort,
	supply_port: LiveScreenSupplyPort = null
) -> StringName:
	var error_code := _model.compose(snapshot)
	if not error_code.is_empty():
		_presenter = null
		return error_code
	_presenter = RunScreenPresenter.new(&"RUN_REWARD", intent_port)
	_selected_reward_id = ""
	_build_hud_shell(_model.snapshot_clone(), supply_port)
	_build_offer_selector()
	_schedule_world_board_clear()
	return &""


func _schedule_world_board_clear() -> void:
	if _presenter == null or _world_board_clear_deferred_pending:
		return
	_world_board_clear_deferred_pending = true
	call_deferred(&"_clear_world_board")


func _clear_world_board() -> void:
	# Release even on the detached path so NOTIFICATION_ENTER_TREE can retry.
	_world_board_clear_deferred_pending = false
	if not is_inside_tree() or _presenter == null:
		return
	_world_board_clear_error = WorldBoardMountAdapter.clear(get_tree())
	if not _world_board_clear_error.is_empty():
		_report_world_board_clear_error(_world_board_clear_error)


func world_board_clear_error() -> StringName:
	return _world_board_clear_error


func _report_world_board_clear_error(_error_code: StringName) -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen == null:
		return
	parent_screen.report_composition_result(AppActionResult.failure(
		DiagnosticError.new(
			&"RENDER_FAILED",
			&"error.presentation.render_failed"
		)
	))


func reward_identity() -> String:
	return _model.reward_identity()


func stage_id() -> int:
	return _model.stage_id()


func phase_id() -> int:
	return _model.phase_id()


func offer_ids() -> Array[String]:
	return _model.offer_ids()


func available_action_kinds() -> Array[int]:
	return _model.available_action_kinds()


func overflow_ids() -> Array[String]:
	return _model.overflow_ids()


func shop_retained_visible() -> bool:
	return _model.shop_retained_visible()


func request(intent: RunPresentationIntent) -> RunPresentationResult:
	if intent == null or _presenter == null:
		return _action_not_available()
	# review N1：ack 不是 reward 動作，其可用性只由 unacknowledged ledger 決定
	# （design :201）。OPEN_REWARD_STAGE 出口把 phase 切成 REWARD（design :207），
	# 若也套 `_model.allows` 的 reward phase 白名單，這條出口就永遠 ack 不掉。
	if (
		intent.kind != RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT
		and not _model.allows(intent.kind)
	):
		return _action_not_available()
	var result := _presenter.request(intent)
	if (result.ok or result.committed) and result.snapshot != null:
		var compose_error := _model.compose(result.snapshot)
		if not compose_error.is_empty():
			return RunPresentationResult.postcommit_failure(
				DiagnosticError.new(
					compose_error,
					&"error.presentation.reward_snapshot_invalid"
				),
				result.snapshot
			)
		_build_hud_shell(_model.snapshot_clone())
		_build_offer_selector()
	return result


func _action_not_available() -> RunPresentationResult:
	var error := DiagnosticError.new(
		ACTION_NOT_AVAILABLE,
		&"error.presentation.action_not_available"
	)
	var snapshot := _model.snapshot_clone()
	return (
		RunPresentationResult.precommit_failure(error, snapshot)
		if snapshot != null
		else RunPresentationResult.failure(error)
	)


func selected_reward_id() -> String:
	return _selected_reward_id


func select_first_reward_result() -> AppActionResult:
	var offers := offer_ids()
	_selected_reward_id = offers[0] if not offers.is_empty() else ""
	if _offer_selector != null and _offer_selector.item_count > 0:
		_offer_selector.select(0)
		_on_offer_selected(0)
	if _selected_reward_id.is_empty():
		return AppActionResult.failure(
			DiagnosticError.new(
				&"RUN_REWARD_SELECTION_REQUIRED",
				&"error.presentation.run_reward_selection_required"
			)
		)
	return AppActionResult.success(false)


func accept_visible_reward_result() -> AppActionResult:
	if _selected_reward_id.is_empty():
		return AppActionResult.failure(
			DiagnosticError.new(
				&"RUN_REWARD_SELECTION_REQUIRED",
				&"error.presentation.run_reward_selection_required"
			)
		)
	return AppActionResult.success(false)


func pending_node_choice_result() -> NodeChoiceResultSnapshot:
	return _oldest_pending_node_choice_result(_model.snapshot_clone())


func acknowledge_node_choice_result() -> RunPresentationResult:
	var snapshot := _model.snapshot_clone()
	var result := pending_node_choice_result()
	if snapshot == null or result == null:
		return _action_not_available()
	return request(_node_choice_ack_intent(snapshot, result))


func confirm_selection() -> RunPresentationResult:
	if _selected_reward_id.is_empty():
		return _action_not_available()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
	)
	intent.offer_id = _selected_reward_id
	intent.choice_id = _selected_reward_id
	return request(intent)


func _build_offer_selector() -> void:
	var existing := find_child("OfferSelector", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_offer_selector = ItemList.new()
	_offer_selector.name = "OfferSelector"
	ExpeditionLayoutMetrics.set_min(_offer_selector, 840.0, 420.0)
	_offer_selector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_offer_selector.focus_mode = Control.FOCUS_ALL
	_offer_selector.select_mode = ItemList.SELECT_SINGLE
	_offer_selector.set_meta(&"typed_choice_kind", &"reward_offer")
	_offer_selector.set_meta(&"semantic_kind", &"rarity")
	_offer_selector.set_meta(
		&"semantic_pattern",
		&"double-frame"
	)
	_offer_selector.set_meta(
		&"accessible_text",
		_localized_ui_text(&"reward.select")
	)
	for offer: RewardOfferState in _model.offers():
		var offer_id := offer.choice_id
		_offer_selector.add_item(
			_reward_offer_text(offer)
		)
		var index := _offer_selector.item_count - 1
		_offer_selector.set_item_metadata(index, offer_id)
		_offer_selector.set_item_tooltip(
			index,
			_tooltip_text(&"tooltip.reward_amount", offer.amount)
		)
	_offer_selector.item_selected.connect(_on_offer_selected)
	var center_host := _hud_shell.host(
		ProductionLayoutShell.REGION_CENTER
	) if _hud_shell != null else self
	center_host.add_child(_offer_selector)
	if _offer_selector.item_count > 0:
		_offer_selector.select(0)
		_on_offer_selected(0)


func _on_offer_selected(index: int) -> void:
	if (
		_offer_selector == null
		or index < 0
		or index >= _offer_selector.item_count
	):
		_selected_reward_id = ""
	else:
		_selected_reward_id = String(
			_offer_selector.get_item_metadata(index)
		)
	_refresh_reward_preview()
	_update_parent_action_state()


func _build_hud_shell(
	snapshot: RunPresentationSnapshot,
	supply_port: LiveScreenSupplyPort = null
) -> void:
	var existing := find_child("InRunHudShell", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_hud_shell = InRunHudShell.new()
	_hud_shell.name = "InRunHudShell"
	add_child(_hud_shell)
	_hud_shell.bind(
		snapshot,
		&"RUN_REWARD",
		Callable(self, "_hud_region_rect"),
		Callable(self, "_localized_ui_text"),
		Callable(self, "_localized_content_text"),
		supply_port
	)
	var right_host := _hud_shell.host(ProductionLayoutShell.REGION_RIGHT)
	var common_inspector := right_host.get_node_or_null(^"UnitInspector")
	if common_inspector != null:
		right_host.remove_child(common_inspector)
		common_inspector.free()
	var preview := VBoxContainer.new()
	preview.name = "RewardPreview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right_host.add_child(preview)
	_refresh_reward_preview()


func _refresh_reward_preview() -> void:
	if _hud_shell == null:
		return
	var preview := _hud_shell.find_child(
		"RewardPreview", true, false
	) as VBoxContainer
	if preview == null:
		return
	for child: Node in preview.get_children():
		preview.remove_child(child)
		child.free()
	var selected: RewardOfferState
	for offer: RewardOfferState in _model.offers():
		if offer != null and offer.choice_id == _selected_reward_id:
			selected = offer
			break
	var label := Label.new()
	label.theme_type_variation = &"ExpeditionSection"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = _localized_ui_text(&"reward.select")
	if selected != null:
		label.text += "\n%s\n%s  %d" % [
			_reward_offer_text(selected),
			_localized_ui_text(&"tooltip.reward_amount"),
			selected.amount,
		]
	else:
		label.text += "\n%s" % _localized_ui_text(&"reward.select")
	preview.add_child(label)


func _reward_offer_text(offer: RewardOfferState) -> String:
	if (
		offer != null
		and offer.content_id != null
		and not offer.content_id.value.is_empty()
	):
		return _localized_content_text(offer.content_id.value)
	return _localized_ui_text(&"loc.reward_table_slice_standard")


func _hud_region_rect(region: StringName) -> Rect2:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.layout_region_content_rect(region)
		if parent_screen != null
		else Rect2()
	)


func _localized_ui_text(key: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_ui_text(key)
		if parent_screen != null
		else String(key)
	)


func _update_parent_action_state() -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.refresh_interaction_state()


func _localized_content_text(content_id: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_content_text(content_id)
		if parent_screen != null
		else String(content_id)
	)


func _tooltip_text(
	label_key: StringName,
	numeric_value: int,
	depth: int = 1
) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.content_tooltip_text(
			label_key, numeric_value, depth
		)
		if parent_screen != null
		else ""
	)

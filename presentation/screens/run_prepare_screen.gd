class_name RunPrepareScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"RUN_PREPARE_COMPOSE_INVALID"
const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"
const START_NOT_READY: StringName = &"RUN_PREPARE_START_NOT_READY"
const SELECTION_REQUIRED: StringName = &"PREPARE_SELECTION_REQUIRED"
const BOARD_FULL: StringName = &"PREPARE_BOARD_FULL"
const BENCH_FULL: StringName = &"PREPARE_BENCH_FULL"

var _model: RunPrepareScreenModel
var _presenter: RunScreenPresenter
var _draft_board: BoardState
var _draft_bench_unit_instance_ids: Array[String] = []
var _pending_forge_confirmation: ConfirmationDraft
var _pending_node_choice_confirmation: ConfirmationDraft
var _selected_node_choice_id: StringName


func compose(
	snapshot: RunPresentationSnapshot,
	report: BoardValidationReport,
	intent_port: LiveScreenIntentPort
) -> StringName:
	if snapshot == null or report == null or intent_port == null:
		return COMPOSE_INVALID
	_model = RunPrepareScreenModel.new(snapshot, report)
	_presenter = RunScreenPresenter.new(&"RUN_PREPARE", intent_port)
	_reset_consumer_draft(snapshot)
	_build_prepare_controls()
	return &""


func deployment_issue_codes() -> Array[StringName]:
	var result: Array[StringName] = []
	if _model != null:
		result.assign(_model.deployment_issue_codes())
	return result


func deployment_issue_message_keys() -> Array[StringName]:
	var result: Array[StringName] = []
	if _model != null:
		result.assign(_model.deployment_issue_message_keys())
	return result


func displayed_capacity() -> int:
	return _model.displayed_capacity() if _model != null else 0


func start_enabled() -> bool:
	var snapshot := _model.snapshot_clone() if _model != null else null
	return (
		_model != null
		and _model.start_enabled()
		and (snapshot == null or snapshot.node_choice_overlay == null)
	)


func request(intent: RunPresentationIntent) -> RunPresentationResult:
	if (
		_presenter == null
		or intent == null
	):
		return RunPresentationResult.failure(
			DiagnosticError.new(
				ACTION_NOT_AVAILABLE,
				&"error.presentation.action_not_available"
			)
		)
	var snapshot := _model.snapshot_clone() if _model != null else null
	if (
		snapshot != null
		and snapshot.node_choice_overlay != null
		and intent.kind != RunPresentationIntent.Kind.COMMIT_NODE_CHOICE
	):
		return RunPresentationResult.failure(
			DiagnosticError.new(
				ACTION_NOT_AVAILABLE,
				&"error.presentation.action_not_available"
			)
		)
	if (
		intent.kind == RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
		and not start_enabled()
	):
		return RunPresentationResult.failure(
			DiagnosticError.new(
				START_NOT_READY,
				&"error.presentation.run_prepare_start_not_ready"
			)
		)
	var result: RunPresentationResult = _presenter.request(intent)
	if result.ok and result.snapshot != null:
		_model.replace_snapshot(result.snapshot)
	return result


func recovery_action_kinds() -> Array[int]:
	var result: Array[int] = []
	if _model != null:
		result.assign(_model.recovery_action_kinds())
	return result


func overflow_ids() -> Array[String]:
	var result: Array[String] = []
	if _model != null:
		result.assign(_model.overflow_ids())
	return result


func focused_action_id() -> StringName:
	return _model.focused_action_id() if _model != null else &""


func commit_board_draft() -> RunPresentationResult:
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
	)
	if _draft_board != null:
		intent.board = _draft_board.deep_clone()
		intent.bench_unit_instance_ids.assign(
			_draft_bench_unit_instance_ids
		)
	return request(intent)


func start_combat() -> RunPresentationResult:
	return request(RunPresentationIntent.new(
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	))


func refresh_shop() -> RunPresentationResult:
	return request(RunPresentationIntent.new(
		RunPresentationIntent.Kind.REFRESH_SHOP
	))


func buy_selected_offer() -> RunPresentationResult:
	var offer_id := _single_selected_metadata(&"ShopSelector")
	if offer_id.is_empty():
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.BUY_UNIT
	)
	intent.offer_id = offer_id
	return request(intent)


func select_shop_offer(offer_id: StringName) -> bool:
	return _select_item_by_metadata(&"ShopSelector", String(offer_id))


func buy_xp() -> RunPresentationResult:
	return request(RunPresentationIntent.new(
		RunPresentationIntent.Kind.BUY_XP
	))


func sell_selected_unit() -> RunPresentationResult:
	var unit_id := _single_selected_metadata(&"BuildUnitSelector")
	if unit_id.is_empty():
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.SELL_UNIT
	)
	intent.unit_instance_id = unit_id
	return request(intent)


func begin_forge_selected() -> ConfirmationDraftResult:
	var item_ids := _selected_metadata(&"InventorySelector")
	if item_ids.size() < 2 or _presenter == null:
		return ConfirmationDraftResult.failure(_selection_error())
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.FORGE_EQUIPMENT
	)
	intent.item_instance_id = item_ids[0]
	intent.secondary_item_instance_id = item_ids[1]
	var result := _presenter.begin_confirmation(intent)
	_pending_forge_confirmation = (
		result.draft if result != null and result.ok else null
	)
	return result


func confirm_forge() -> RunPresentationResult:
	if _presenter == null or _pending_forge_confirmation == null:
		return _selection_failure()
	var draft := _pending_forge_confirmation
	_pending_forge_confirmation = null
	return _presenter.confirm_confirmation(draft)


func cancel_forge() -> ConfirmationCancelResult:
	if _presenter == null or _pending_forge_confirmation == null:
		return ConfirmationCancelResult.failure(_selection_error())
	var draft := _pending_forge_confirmation
	_pending_forge_confirmation = null
	return _presenter.cancel_confirmation(draft)


func has_pending_forge_confirmation() -> bool:
	return _pending_forge_confirmation != null


func select_first_node_choice() -> StringName:
	var snapshot := _model.snapshot_clone() if _model != null else null
	if snapshot == null or snapshot.node_choice_overlay == null:
		_selected_node_choice_id = &""
		return &""
	var selector := _control(&"ChoiceSelector") as ItemList
	if selector == null or selector.item_count == 0:
		_selected_node_choice_id = &""
		return &""
	selector.select(0)
	_selected_node_choice_id = StringName(selector.get_item_metadata(0))
	return _selected_node_choice_id


func begin_selected_node_choice() -> ConfirmationDraftResult:
	var snapshot := _model.snapshot_clone() if _model != null else null
	if (
		_presenter == null
		or snapshot == null
		or snapshot.node_choice_overlay == null
		or _selected_node_choice_id.is_empty()
	):
		return ConfirmationDraftResult.failure(_selection_error())
	var option := snapshot.node_choice_overlay.try_option(
		_selected_node_choice_id
	)
	if option == null or not option.confirmation_required:
		return ConfirmationDraftResult.failure(_selection_error())
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.COMMIT_NODE_CHOICE
	)
	intent.choice_set_id = snapshot.node_choice_overlay.choice_set_id
	intent.choice_id = String(_selected_node_choice_id)
	# design :173-178：payload 在這一刻（overlay 仍是 committed 投影時）抄完整；
	# confirm 之前 canonical 若被換掉，commit 會回 PENDING_DIGEST_MISMATCH／
	# NONCE_MISMATCH 而不是靜默套用到新的 pending 上。
	intent.node_choice_payload = snapshot.node_choice_overlay.commit_payload(
		snapshot.run_id,
		_selected_node_choice_id
	)
	var result := _presenter.begin_confirmation(intent)
	_pending_node_choice_confirmation = (
		result.draft if result != null and result.ok else null
	)
	return result


func confirm_node_choice() -> RunPresentationResult:
	if _presenter == null or _pending_node_choice_confirmation == null:
		return _selection_failure()
	var draft := _pending_node_choice_confirmation
	_pending_node_choice_confirmation = null
	var result := _presenter.confirm_confirmation(draft)
	if (result.ok or result.committed) and result.snapshot != null:
		_model.replace_snapshot(result.snapshot)
	return result


func cancel_node_choice() -> ConfirmationCancelResult:
	if _presenter == null or _pending_node_choice_confirmation == null:
		return ConfirmationCancelResult.failure(_selection_error())
	var draft := _pending_node_choice_confirmation
	_pending_node_choice_confirmation = null
	return _presenter.cancel_confirmation(draft)


func has_pending_node_choice_confirmation() -> bool:
	return _pending_node_choice_confirmation != null


func selected_node_choice_preview_key() -> StringName:
	var snapshot := _model.snapshot_clone() if _model != null else null
	if snapshot == null or snapshot.node_choice_overlay == null:
		return &"error.presentation.action_not_available"
	var option := snapshot.node_choice_overlay.try_option(
		_selected_node_choice_id
	)
	return (
		option.preview_key
		if option != null
		else &"error.presentation.action_not_available"
	)


func has_node_choice_overlay() -> bool:
	var snapshot := _model.snapshot_clone() if _model != null else null
	return snapshot != null and snapshot.node_choice_overlay != null


func has_node_service_pending() -> bool:
	var snapshot := _model.snapshot_clone() if _model != null else null
	return snapshot != null and snapshot.node_service_overlay != null


## design :210-212：服務期間不限次數、不要求耗材的拆解。與一般
## dismantle_selected_equipment 的差別只在「不必再選一個耗材」。
func dismantle_selected_with_node_service() -> RunPresentationResult:
	var snapshot := _model.snapshot_clone() if _model != null else null
	if snapshot == null or snapshot.node_service_overlay == null:
		return _selection_failure()
	var item_id := _single_selected_metadata(&"InventorySelector")
	if item_id.is_empty():
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE
	)
	intent.expected_run_id = String(snapshot.run_id)
	intent.node_id = snapshot.node_service_overlay.node_id
	intent.choice_receipt_digest = (
		snapshot.node_service_overlay.choice_receipt_digest
	)
	intent.item_instance_id = item_id
	return request(intent)


## design :213-214：離開 node service 的唯一出口（也是節點完成的唯一時機）。
func exit_node_service() -> RunPresentationResult:
	var snapshot := _model.snapshot_clone() if _model != null else null
	if snapshot == null or snapshot.node_service_overlay == null:
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE
	)
	intent.expected_run_id = String(snapshot.run_id)
	intent.node_id = snapshot.node_service_overlay.node_id
	intent.choice_receipt_digest = (
		snapshot.node_service_overlay.choice_receipt_digest
	)
	return request(intent)


## design :201-203：結果播完後才由玩家（或畫面）顯式 ack；未 ack 的 receipt 會在
## reload 後再次出現在 snapshot.pending_node_choice_results。
## OPEN_DISMANTLE_SERVICE 出口留在 PREPARE，另兩種 outcome 的 ack 入口見
## RunMapScreen／RunRewardScreen（review N1）。
func pending_node_choice_result() -> NodeChoiceResultSnapshot:
	var snapshot: RunPresentationSnapshot = (
		_model.snapshot_clone() if _model != null else null
	)
	return _oldest_pending_node_choice_result(snapshot)


func acknowledge_node_choice_result() -> RunPresentationResult:
	var snapshot := _model.snapshot_clone() if _model != null else null
	var result := pending_node_choice_result()
	if snapshot == null or result == null:
		return _selection_failure()
	return request(_node_choice_ack_intent(snapshot, result))


func equip_selected_item() -> RunPresentationResult:
	var unit_id := _single_selected_metadata(&"BuildUnitSelector")
	var item_id := _single_selected_metadata(&"InventorySelector")
	if unit_id.is_empty() or item_id.is_empty():
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.EQUIP_ITEM
	)
	intent.unit_instance_id = unit_id
	intent.item_instance_id = item_id
	return request(intent)


func dismantle_selected_equipment() -> RunPresentationResult:
	var item_ids := _selected_metadata(&"InventorySelector")
	if item_ids.size() < 2:
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT
	)
	intent.item_instance_id = item_ids[0]
	intent.secondary_item_instance_id = item_ids[1]
	return request(intent)


func move_selected_to_board() -> AppActionResult:
	var unit_id := _single_selected_metadata(&"BenchSelector")
	if unit_id.is_empty():
		unit_id = _single_selected_metadata(&"BuildUnitSelector")
	if unit_id.is_empty():
		return AppActionResult.failure(_selection_error())
	var open_cell := _first_open_player_cell()
	if open_cell.x < 0:
		return AppActionResult.failure(
			DiagnosticError.new(
				BOARD_FULL,
				&"error.presentation.prepare_board_full"
			)
		)
	_remove_from_board(unit_id)
	_draft_bench_unit_instance_ids.erase(unit_id)
	_draft_board.placements.append(
		BoardPlacementState.new(
			int(open_cell.y),
			int(open_cell.x),
			unit_id
		)
	)
	_refresh_draft_selectors()
	return AppActionResult.success(false)


func move_selected_to_bench() -> AppActionResult:
	var unit_id := _single_selected_metadata(&"BoardSelector")
	if unit_id.is_empty():
		unit_id = _single_selected_metadata(&"BuildUnitSelector")
	if unit_id.is_empty():
		return AppActionResult.failure(_selection_error())
	if (
		not _draft_bench_unit_instance_ids.has(unit_id)
		and _draft_bench_unit_instance_ids.size() >= 9
	):
		return AppActionResult.failure(
			DiagnosticError.new(
				BENCH_FULL,
				&"error.presentation.prepare_bench_full"
			)
		)
	_remove_from_board(unit_id)
	if not _draft_bench_unit_instance_ids.has(unit_id):
		_draft_bench_unit_instance_ids.append(unit_id)
	_refresh_draft_selectors()
	return AppActionResult.success(false)


func _build_prepare_controls() -> void:
	var existing := find_child("PrepareContent", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.queue_free()
	var layout := Control.new()
	layout.name = "PrepareContent"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var snapshot := _model.snapshot_clone() if _model != null else null
	var metrics := Control.new()
	metrics.name = "PrepareMetrics"
	var metrics_rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
	metrics_rect.position.x += 320.0
	metrics_rect.size.x -= 320.0
	metrics.position = metrics_rect.position
	metrics.size = metrics_rect.size
	metrics.clip_contents = true
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(metrics)
	var metric_labels: Array[Label] = []
	metric_labels.append(_metric_label(
		&"prepare.resource.hp",
		str(snapshot.view.expedition_hp) if snapshot != null and snapshot.view != null else "-"
	))
	metric_labels.append(_metric_label(
		&"prepare.resource.gold",
		str(snapshot.economy.gold) if snapshot != null and snapshot.economy != null else "-"
	))
	metric_labels.append(_metric_label(
		&"prepare.resource.level_xp",
		"%s / %s" % [snapshot.economy.level, snapshot.economy.xp] if snapshot != null and snapshot.economy != null else "-"
	))
	var capacity := Label.new()
	capacity.name = "CapacityValue"
	capacity.text = "%s  %s" % [
		_localized_ui_text(&"prepare.resource.capacity"),
		str(displayed_capacity()),
	]
	capacity.theme_type_variation = &"ExpeditionMetric"
	capacity.custom_minimum_size = Vector2(88.0, 0.0)
	capacity.clip_text = true
	capacity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	capacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capacity.set_meta(&"typed_data_kind", &"population_capacity")
	capacity.set_meta(&"accessible_text", capacity.text)
	metric_labels.append(capacity)
	for index: int in metric_labels.size():
		var metric := metric_labels[index]
		metric.anchor_left = float(index) / float(metric_labels.size())
		metric.anchor_right = float(index + 1) / float(metric_labels.size())
		metric.anchor_top = 0.0
		metric.anchor_bottom = 1.0
		metric.offset_left = 8.0
		metric.offset_right = -8.0
		metric.offset_top = 0.0
		metric.offset_bottom = 0.0
		metrics.add_child(metric)

	var contracts := VBoxContainer.new()
	contracts.name = "PrepareContractSelectors"
	contracts.visible = false
	layout.add_child(contracts)
	_add_selector(contracts, &"BoardSelector", Vector2.ZERO, &"board_draft")
	_add_selector(contracts, &"BenchSelector", Vector2.ZERO, &"bench_draft")
	_add_selector(contracts, &"ShopSelector", Vector2.ZERO, &"shop_offer")
	_add_selector(
		contracts,
		&"InventorySelector",
		Vector2.ZERO,
		&"item_instance",
		true
	)

	var left := VBoxContainer.new()
	left.name = "PrepareLeftContent"
	var left_rect := _region_content_rect(ProductionLayoutShell.REGION_LEFT)
	left.position = left_rect.position
	left.size = left_rect.size
	layout.add_child(left)
	left.add_child(_heading(&"prepare.panel.party"))
	_add_selector(
		left,
		&"BuildUnitSelector",
		Vector2(0.0, 116.0),
		&"unit_instance"
	)
	left.add_child(_heading(&"prepare.panel.synergies"))
	left.add_child(_empty_label(&"prepare.empty.synergies"))

	var center := VBoxContainer.new()
	center.name = "PrepareCenterContent"
	center.theme_type_variation = &"ExpeditionBoardStack"
	var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
	center.position = center_rect.position
	center.size = center_rect.size
	layout.add_child(center)
	center.add_child(_heading(&"prepare.panel.board"))
	_build_board_grid(center)
	center.add_child(_heading(&"prepare.panel.bench"))
	_build_bench_row(center)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "PrepareRightScroll"
	var right_rect := _region_content_rect(ProductionLayoutShell.REGION_RIGHT)
	right_scroll.position = right_rect.position
	right_scroll.size = right_rect.size
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.name = "PrepareRightContent"
	right.custom_minimum_size = Vector2(maxf(220.0, right_rect.size.x - 20.0), 0.0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	right.add_child(_heading(&"prepare.panel.overflow"))
	var overflow_values := overflow_ids()
	if overflow_values.is_empty():
		right.add_child(_empty_label(&"prepare.empty.overflow"))
	else:
		var overflow := ItemList.new()
		overflow.name = "OverflowSelector"
		overflow.custom_minimum_size = Vector2(0.0, 84.0)
		overflow.focus_mode = Control.FOCUS_ALL
		overflow.set_meta(&"typed_data_kind", &"item_overflow")
		for item_id: String in overflow_values:
			overflow.add_item(_item_display_name(item_id, snapshot))
			overflow.set_item_metadata(overflow.item_count - 1, item_id)
		right.add_child(overflow)

	right.add_child(_heading(&"prepare.panel.issues"))
	var issue_codes := deployment_issue_codes()
	var issue_message_keys := deployment_issue_message_keys()
	if issue_codes.is_empty():
		right.add_child(_empty_label(&"prepare.empty.issues"))
	else:
		var issues := ItemList.new()
		issues.name = "DeploymentIssues"
		issues.custom_minimum_size = Vector2(0.0, 84.0)
		issues.focus_mode = Control.FOCUS_ALL
		issues.set_meta(&"typed_data_kind", &"deployment_issue")
		for index: int in issue_codes.size():
			issues.add_item(_localized_ui_text(issue_message_keys[index]))
			issues.set_item_metadata(issues.item_count - 1, issue_codes[index])
		right.add_child(issues)
	if snapshot == null or snapshot.node_choice_overlay == null:
		right.add_child(_heading(&"prepare.panel.expedition"))
		right.add_child(_empty_label(&"prepare.empty.expedition"))
	_build_node_choice_overlay(snapshot, right)
	_refresh_draft_selectors()


func _build_board_grid(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.name = "BoardGrid"
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(grid)
	for logical_y: int in range(4):
		for logical_x: int in range(8):
			var cell := Button.new()
			cell.name = "BoardCell_%d_%d" % [logical_y, logical_x]
			cell.custom_minimum_size = Vector2(56.0, 40.0)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cell.focus_mode = Control.FOCUS_ALL
			cell.clip_text = true
			cell.set_meta(&"board_x", logical_x)
			cell.set_meta(&"board_y", logical_y)
			cell.set_meta(&"unit_instance_id", "")
			cell.set_meta(&"expedition_theme_fixed_minimum", true)
			cell.pressed.connect(_on_board_cell_pressed.bind(cell))
			grid.add_child(cell)


func _build_bench_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "BenchRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	for index: int in range(9):
		var cell := Button.new()
		cell.name = "BenchCell%d" % index
		cell.custom_minimum_size = Vector2(48.0, 44.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.focus_mode = Control.FOCUS_ALL
		cell.clip_text = true
		cell.set_meta(&"unit_instance_id", "")
		cell.set_meta(&"expedition_theme_fixed_minimum", true)
		cell.pressed.connect(_on_bench_cell_pressed.bind(cell))
		row.add_child(cell)


func _empty_label(key: StringName) -> Label:
	var label := Label.new()
	label.text = _localized_ui_text(key)
	label.theme_type_variation = &"ExpeditionAuxiliary"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _heading(key: StringName) -> Label:
	var label := Label.new()
	label.text = _localized_ui_text(key)
	label.theme_type_variation = &"ExpeditionSection"
	return label


func _region_content_rect(region: StringName) -> Rect2:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.layout_region_content_rect(region)
		if parent_screen != null
		else Rect2()
	)


func _metric_label(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.text = "%s  %s" % [_localized_ui_text(key), value]
	label.theme_type_variation = &"ExpeditionMetric"
	label.custom_minimum_size = Vector2(108.0, 0.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _build_node_choice_overlay(
	snapshot: RunPresentationSnapshot,
	parent: VBoxContainer
) -> void:
	_selected_node_choice_id = &""
	_pending_node_choice_confirmation = null
	if snapshot == null or snapshot.node_choice_overlay == null:
		return
	var selector := ItemList.new()
	selector.name = "ChoiceSelector"
	selector.custom_minimum_size = Vector2(248.0, 120.0)
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_ALL
	selector.select_mode = ItemList.SELECT_SINGLE
	selector.set_meta(&"typed_data_kind", &"node_choice")
	selector.set_meta(
		&"accessible_text",
		String(snapshot.node_choice_overlay.display_name_key)
	)
	for option: NodeChoiceOptionSnapshot in snapshot.node_choice_overlay.options:
		selector.add_item(
			"%s\n%s" % [
				_localized_ui_text(option.title_key),
				_localized_ui_text(option.preview_key),
			]
		)
		selector.set_item_metadata(
			selector.item_count - 1,
			String(option.choice_id)
		)
	selector.item_selected.connect(_on_node_choice_selected)
	parent.add_child(selector)
	select_first_node_choice()


func _on_node_choice_selected(index: int) -> void:
	var selector := _control(&"ChoiceSelector") as ItemList
	if selector == null or index < 0 or index >= selector.item_count:
		_selected_node_choice_id = &""
	else:
		_selected_node_choice_id = StringName(
			selector.get_item_metadata(index)
		)
	_update_parent_action_state()


func _update_parent_action_state() -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.refresh_interaction_state()


func _add_selector(
	parent: Container,
	control_name: StringName,
	minimum_size: Vector2,
	data_kind: StringName,
	multi_select: bool = false
) -> void:
	var selector := ItemList.new()
	selector.name = String(control_name)
	selector.custom_minimum_size = minimum_size
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_ALL
	selector.select_mode = (
		ItemList.SELECT_MULTI
		if multi_select
		else ItemList.SELECT_SINGLE
	)
	selector.set_meta(&"typed_data_kind", data_kind)
	selector.set_meta(&"accessible_text", String(control_name))
	parent.add_child(selector)


func _refresh_draft_selectors() -> void:
	var snapshot := (
		_model.snapshot_clone()
		if _model != null
		else null
	)
	if snapshot == null or snapshot.roster == null:
		return
	var board := _control(&"BoardSelector") as ItemList
	var bench := _control(&"BenchSelector") as ItemList
	var shop := _control(&"ShopSelector") as ItemList
	var inventory := _control(&"InventorySelector") as ItemList
	var units := _control(&"BuildUnitSelector") as ItemList
	if board != null:
		board.clear()
		for placement: BoardPlacementState in _draft_board.placements:
			_append_typed_item(
				board,
				"%s [%d,%d]" % [
					_unit_display_name(placement.unit_instance_id, snapshot),
					placement.logical_y,
					placement.logical_x,
				],
				placement.unit_instance_id
			)
	if bench != null:
		bench.clear()
		for unit_id: String in _draft_bench_unit_instance_ids:
			_append_typed_item(
				bench,
				_unit_display_name(unit_id, snapshot),
				unit_id
			)
	if shop != null:
		shop.clear()
		if snapshot.economy != null:
			for offer: ShopOffer in snapshot.economy.shop_offers:
				_append_typed_item(
					shop,
					"%s · %d" % [
						_localized_content_text(offer.unit_def_id),
						offer.cost,
					],
					offer.offer_id,
					_tooltip_text(&"tooltip.cost", offer.cost)
				)
	if inventory != null:
		inventory.clear()
		for item: ItemInstanceState in snapshot.roster.item_instances:
			_append_typed_item(
				inventory,
				"%s · %s" % [
					_localized_content_text(item.def_id),
					item.instance_id,
				],
				item.instance_id
			)
	if units != null:
		units.clear()
		for unit: UnitInstance in snapshot.roster.unit_instances:
			_append_typed_item(
				units,
				"%s ★%d" % [_localized_content_text(unit.def_id), unit.star],
				unit.instance_id,
				_tooltip_text(&"tooltip.star", unit.star)
			)
	_refresh_board_grid(snapshot)
	_refresh_bench_row(snapshot)


func _refresh_board_grid(snapshot: RunPresentationSnapshot) -> void:
	var occupants: Dictionary = {}
	if _draft_board != null:
		for placement: BoardPlacementState in _draft_board.placements:
			occupants[Vector2i(placement.logical_x, placement.logical_y)] = placement.unit_instance_id
	var grid := _control(&"BoardGrid") as GridContainer
	if grid == null:
		return
	for node: Node in grid.get_children():
		var cell := node as Button
		if cell == null:
			continue
		var coordinate := Vector2i(
			int(cell.get_meta(&"board_x", -1)),
			int(cell.get_meta(&"board_y", -1))
		)
		var unit_id := String(occupants.get(coordinate, ""))
		cell.set_meta(&"unit_instance_id", unit_id)
		cell.text = _unit_display_name(unit_id, snapshot) if not unit_id.is_empty() else ""
		cell.tooltip_text = cell.text


func _refresh_bench_row(snapshot: RunPresentationSnapshot) -> void:
	var row := _control(&"BenchRow") as HBoxContainer
	if row == null:
		return
	for index: int in row.get_child_count():
		var cell := row.get_child(index) as Button
		if cell == null:
			continue
		var unit_id := (
			_draft_bench_unit_instance_ids[index]
			if index < _draft_bench_unit_instance_ids.size()
			else ""
		)
		cell.set_meta(&"unit_instance_id", unit_id)
		cell.text = _unit_display_name(unit_id, snapshot) if not unit_id.is_empty() else ""
		cell.tooltip_text = cell.text


func _on_board_cell_pressed(cell: Button) -> void:
	var unit_id := String(cell.get_meta(&"unit_instance_id", "")) if cell != null else ""
	if not unit_id.is_empty():
		_select_item_by_metadata(&"BoardSelector", unit_id)
		_select_item_by_metadata(&"BuildUnitSelector", unit_id)


func _on_bench_cell_pressed(cell: Button) -> void:
	var unit_id := String(cell.get_meta(&"unit_instance_id", "")) if cell != null else ""
	if not unit_id.is_empty():
		_select_item_by_metadata(&"BenchSelector", unit_id)
		_select_item_by_metadata(&"BuildUnitSelector", unit_id)


func _select_item_by_metadata(selector_name: StringName, identity: String) -> bool:
	var selector := _control(selector_name) as ItemList
	if selector == null or identity.is_empty():
		return false
	selector.deselect_all()
	for index: int in selector.item_count:
		if String(selector.get_item_metadata(index)) == identity:
			selector.select(index)
			return true
	return false


func _append_typed_item(
	selector: ItemList,
	label: String,
	identity: String,
	tooltip: String = ""
) -> void:
	selector.add_item(label)
	var index := selector.item_count - 1
	selector.set_item_metadata(index, identity)
	if not tooltip.is_empty():
		selector.set_item_tooltip(index, tooltip)


func _reset_consumer_draft(snapshot: RunPresentationSnapshot) -> void:
	_draft_board = null
	_draft_bench_unit_instance_ids.clear()
	_pending_forge_confirmation = null
	_pending_node_choice_confirmation = null
	_selected_node_choice_id = &""
	if snapshot == null or snapshot.roster == null:
		return
	_draft_board = snapshot.roster.board.deep_clone()
	_draft_bench_unit_instance_ids.assign(
		snapshot.roster.bench_unit_instance_ids
	)


func _selected_metadata(selector_name: StringName) -> Array[String]:
	var result: Array[String] = []
	var selector := _control(selector_name) as ItemList
	if selector == null:
		return result
	for index: int in selector.get_selected_items():
		result.append(String(selector.get_item_metadata(index)))
	return result


func _single_selected_metadata(selector_name: StringName) -> String:
	var selected := _selected_metadata(selector_name)
	return selected[0] if not selected.is_empty() else ""


func _control(control_name: StringName) -> Control:
	return find_child(String(control_name), true, false) as Control


func _remove_from_board(unit_id: String) -> void:
	if _draft_board == null:
		return
	for index: int in range(_draft_board.placements.size() - 1, -1, -1):
		if _draft_board.placements[index].unit_instance_id == unit_id:
			_draft_board.placements.remove_at(index)


func _first_open_player_cell() -> Vector2i:
	if _draft_board == null:
		return Vector2i(-1, -1)
	for logical_y: int in range(4):
		for logical_x: int in range(8):
			var occupied := false
			for placement: BoardPlacementState in _draft_board.placements:
				if (
					placement.logical_y == logical_y
					and placement.logical_x == logical_x
				):
					occupied = true
					break
			if not occupied:
				return Vector2i(logical_x, logical_y)
	return Vector2i(-1, -1)


func _unit_display_name(
	unit_instance_id: String,
	snapshot: RunPresentationSnapshot
) -> String:
	if snapshot != null and snapshot.roster != null:
		for unit: UnitInstance in snapshot.roster.unit_instances:
			if unit.instance_id == unit_instance_id:
				return _localized_content_text(unit.def_id)
	return unit_instance_id


func _item_display_name(
	item_instance_id: String,
	snapshot: RunPresentationSnapshot
) -> String:
	if snapshot != null and snapshot.roster != null:
		for item: ItemInstanceState in snapshot.roster.item_instances:
			if item.instance_id == item_instance_id:
				return _localized_content_text(item.def_id)
	return item_instance_id


func _localized_content_text(content_id: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_content_text(content_id)
		if parent_screen != null
		else String(content_id)
	)


func _localized_ui_text(text_key: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_ui_text(text_key)
		if parent_screen != null
		else String(text_key)
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


func _selection_failure() -> RunPresentationResult:
	return RunPresentationResult.failure(_selection_error())


func _selection_error() -> DiagnosticError:
	return DiagnosticError.new(
		SELECTION_REQUIRED,
		&"error.presentation.prepare_selection_required"
	)

class_name RunPrepareScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"RUN_PREPARE_COMPOSE_INVALID"
const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"
const START_NOT_READY: StringName = &"RUN_PREPARE_START_NOT_READY"
const SELECTION_REQUIRED: StringName = &"PREPARE_SELECTION_REQUIRED"
const BOARD_FULL: StringName = &"PREPARE_BOARD_FULL"
const BENCH_FULL: StringName = &"PREPARE_BENCH_FULL"
const BENCH_ROW_HEIGHT: float = 72.0


class PrepareQuickToggleItemList:
	extends ItemList

	signal quick_toggle_requested()


	func _gui_input(event: InputEvent) -> void:
		if event == null:
			return
		if event.is_action_pressed(&"ui_up", false, true):
			_move_keyboard_selection(-1)
			accept_event()
			return
		if event.is_action_pressed(&"ui_down", false, true):
			_move_keyboard_selection(1)
			accept_event()
			return
		if not event.is_action_pressed(
			&"prepare_quick_toggle_unit", false, true
		):
			return
		# Focused ItemList otherwise consumes printable W for incremental search
		# before the screen's unhandled-input path can observe it.
		accept_event()
		quick_toggle_requested.emit()


	func _move_keyboard_selection(direction: int) -> void:
		if item_count <= 0:
			return
		var selected := get_selected_items()
		var current := selected[0] if not selected.is_empty() else 0
		var target := clampi(current + direction, 0, item_count - 1)
		select(target)
		item_selected.emit(target)

var _model: RunPrepareScreenModel
var _presenter: RunScreenPresenter
var _draft_board: BoardState
var _draft_bench_unit_instance_ids: Array[String] = []
var _pending_forge_confirmation: ConfirmationDraft
var _pending_node_choice_confirmation: ConfirmationDraft
var _selected_node_choice_id: StringName
var _hud_shell: InRunHudShell
var _supply_port: LiveScreenSupplyPort
var _world_snapshot_factory := WorldBoardSnapshotFactory.new()
var _draft_move_adapter := BoardDraftMoveAdapter.new()
var _quick_toggle_unit_id: String = ""
var _keyboard_move_unit_id: String = ""
var _selected_inspector_unit_id: String = ""
var _selected_sell_quote: ShopQuoteSnapshot
var _world_board_mount_error: StringName = &""
var _world_board_mount_deferred_pending: bool = false
var _committed_board_preview: BoardDraftPreviewSnapshot
var _candidate_board_preview: BoardDraftPreviewSnapshot
var _draft_revision: int = 0
var _board_preview_cache: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		# Production routes compose while detached. A compose-time deferred call
		# may therefore run and safely return before SceneRouter commits the
		# candidate; entering the tree is the event boundary that guarantees one
		# fresh mount attempt without polling.
		_schedule_world_board_mount()


func compose(
	snapshot: RunPresentationSnapshot,
	report: BoardValidationReport,
	intent_port: LiveScreenIntentPort,
	supply_port: LiveScreenSupplyPort = null
) -> StringName:
	if snapshot == null or report == null or intent_port == null:
		return COMPOSE_INVALID
	_model = RunPrepareScreenModel.new(snapshot, report)
	_presenter = RunScreenPresenter.new(&"RUN_PREPARE", intent_port)
	_supply_port = supply_port
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
	var result := request(intent)
	if result != null and result.ok and result.snapshot != null:
		_post_commit_board_draft(result.snapshot)
	return result


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
	return sell_unit_by_instance_id(selected_unit_instance_id())


func sell_unit_by_instance_id(unit_id: String) -> RunPresentationResult:
	if unit_id.is_empty():
		return _selection_failure()
	if _prepare_inspection_for(unit_id) == null:
		return _selection_failure()
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.SELL_UNIT
	)
	intent.unit_instance_id = unit_id
	return request(intent)


func selected_unit_instance_id() -> String:
	return _single_selected_metadata(&"BuildUnitSelector")


func selected_unit_sell_quote() -> ShopQuoteSnapshot:
	return (
		_selected_sell_quote.deep_clone()
		if _selected_sell_quote != null
		else null
	)


func selected_unit_requires_sell_confirmation() -> bool:
	var unit_id := selected_unit_instance_id()
	var inspection := _prepare_inspection_for(unit_id)
	return (
		inspection != null
		and (
			inspection.star >= 2
			or not inspection.equipment_instance_ids.is_empty()
		)
	)


func selected_unit_inspection_available() -> bool:
	return _prepare_inspection_for(selected_unit_instance_id()) != null


func _prepare_inspection_for(
	unit_id: String
) -> PrepareUnitInspectionSnapshot:
	if unit_id.is_empty() or _model == null:
		return null
	var snapshot := _model.snapshot_clone()
	if snapshot == null:
		return null
	for inspection: PrepareUnitInspectionSnapshot in snapshot.prepare_unit_inspections:
		if inspection != null and inspection.unit_instance_id == unit_id:
			return inspection.deep_clone()
	return null


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
	return _stage_adapter_move(
		unit_id,
		Callable(_draft_move_adapter, &"move_to_first_open_board").bind(unit_id)
	)


func move_selected_to_bench() -> AppActionResult:
	var unit_id := _single_selected_metadata(&"BoardSelector")
	if unit_id.is_empty():
		unit_id = _single_selected_metadata(&"BuildUnitSelector")
	if unit_id.is_empty():
		return AppActionResult.failure(_selection_error())
	return _stage_adapter_move(
		unit_id,
		Callable(_draft_move_adapter, &"move_to_first_open_bench").bind(unit_id)
	)


func _stage_adapter_move(unit_id: String, operation: Callable) -> AppActionResult:
	if unit_id.is_empty() or not operation.is_valid() or _draft_board == null:
		return AppActionResult.failure(_selection_error())
	_draft_move_adapter.reset(_draft_board, _draft_bench_unit_instance_ids)
	var error_code: StringName = operation.call()
	if not error_code.is_empty():
		return AppActionResult.failure(_draft_move_error(error_code))
	_apply_adapter_draft()
	return AppActionResult.success(false)


func _draft_move_error(error_code: StringName) -> DiagnosticError:
	match error_code:
		BoardDraftMoveAdapter.BOARD_FULL:
			return DiagnosticError.new(
				BOARD_FULL, &"error.presentation.prepare_board_full"
			)
		BoardDraftMoveAdapter.BENCH_FULL:
			return DiagnosticError.new(
				BENCH_FULL, &"error.presentation.prepare_bench_full"
			)
	return _selection_error()


func _build_prepare_controls() -> void:
	var existing := find_child("PrepareContent", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	var layout := Control.new()
	layout.name = "PrepareContent"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var snapshot := _model.snapshot_clone() if _model != null else null
	_hud_shell = InRunHudShell.new()
	_hud_shell.name = "InRunHudShell"
	layout.add_child(_hud_shell)
	_hud_shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, &"_region_content_rect"),
		Callable(self, &"_localized_ui_text"),
		Callable(self, &"_localized_content_text"),
		_supply_port
	)
	var metrics := Control.new()
	metrics.name = "PrepareMetrics"
	var metrics_rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
	metrics_rect.position.x += ProductionLayoutShell.TITLE_COLUMN_WIDTH
	metrics_rect.size.x -= ProductionLayoutShell.TITLE_COLUMN_WIDTH
	metrics.position = metrics_rect.position
	metrics.size = metrics_rect.size
	metrics.clip_contents = true
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(metrics)
	var metric_labels: Array[Label] = []
	metric_labels.append(_metric_label(
		&"prepare.resource.hp",
		str(snapshot.view.expedition_hp) if snapshot != null and snapshot.view != null else _unavailable_text()
	))
	metric_labels.append(_metric_label(
		&"prepare.resource.gold",
		str(snapshot.economy.gold) if snapshot != null and snapshot.economy != null else _unavailable_text()
	))
	metric_labels.append(_metric_label(
		&"prepare.resource.level_xp",
		"%s / %s" % [snapshot.economy.level, snapshot.economy.xp] if snapshot != null and snapshot.economy != null else _unavailable_text()
	))
	var capacity := Label.new()
	capacity.name = "CapacityValue"
	capacity.text = "%s  %s" % [
		_localized_ui_text(&"prepare.resource.capacity"),
		str(displayed_capacity()),
	]
	capacity.theme_type_variation = &"ExpeditionMetric"
	ExpeditionLayoutMetrics.set_reference_min(capacity, Vector2(132.0, 0.0))
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
	# Resource/progress values are rendered by InRunHudShell. Preserve this
	# legacy probe node for older geometry contracts without painting a second
	# top row through the shared HUD.
	metrics.visible = false

	var contracts := VBoxContainer.new()
	contracts.name = "PrepareContractSelectors"
	contracts.visible = false
	layout.add_child(contracts)
	_add_selector(contracts, &"BoardSelector", Vector2.ZERO, &"board_draft")
	_add_selector(contracts, &"BenchSelector", Vector2.ZERO, &"bench_draft")
	_add_selector(contracts, &"ShopSelector", Vector2.ZERO, &"shop_offer")

	var left_scroll := ScrollContainer.new()
	left_scroll.name = "PrepareLeftContent"
	var left_rect := _region_content_rect(ProductionLayoutShell.REGION_LEFT)
	left_scroll.position = left_rect.position
	left_scroll.size = left_rect.size
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	left_scroll.follow_focus = true
	left_scroll.visible = false
	layout.add_child(left_scroll)
	var left := _hud_shell.find_child(
		"InRunLeftStack", true, false
	) as VBoxContainer
	if left == null:
		left = VBoxContainer.new()
		left.name = "PrepareLeftStack"
		left_scroll.add_child(left)
	var party_heading := _heading(&"prepare.panel.party")
	left.add_child(party_heading)
	left.move_child(party_heading, 0)
	_add_selector(
		left,
		&"BuildUnitSelector",
		# min 72：清單內部可捲動、EXPAND 會吃滿剩餘高；min 過大會在 150%
		# 讓左欄 combined min 超出區域預算（見 refresh_layout_rects 註解）。
		Vector2(0.0, 84.0),
		&"unit_instance"
	)
	var build_selector := left.get_node(^"BuildUnitSelector") as ItemList
	if build_selector != null:
		left.move_child(build_selector, 1)
		build_selector.item_selected.connect(_on_build_unit_selected)
		build_selector.focus_entered.connect(
			_on_build_unit_selector_focus_entered
		)
	# Reuse the shared HUD's item-bench heading/scroll position. The prepare
	# route replaces its generic read-only list with the drag-capable selector;
	# keeping both would render duplicate inventory lists.
	var shared_inventory := left.get_node_or_null(^"HudInventory") as ItemList
	var inventory_index := (
		shared_inventory.get_index()
		if shared_inventory != null
		else left.get_child_count()
	)
	if shared_inventory != null:
		left.remove_child(shared_inventory)
		shared_inventory.free()
	_add_selector(
		left,
		&"InventorySelector",
		Vector2(0.0, 108.0),
		&"item_instance",
		true
	)
	var inventory_selector := left.get_node(^"InventorySelector") as ItemList
	if inventory_selector != null:
		inventory_selector.focus_entered.connect(
			_on_inventory_selector_focus_entered
		)
	if inventory_selector != null:
		left.move_child(inventory_selector, inventory_index)
	var forge_preview := Label.new()
	forge_preview.name = "ForgeRecipePreview"
	forge_preview.text = _localized_ui_text(&"collection.category.recipe")
	forge_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forge_preview.theme_type_variation = &"ExpeditionDetail"
	forge_preview.set_meta(&"forge_preview_state", &"idle")
	forge_preview.set_meta(&"accessible_text", forge_preview.text)
	ExpeditionLayoutMetrics.set_reference_min(forge_preview, Vector2(0.0, 78.0))
	left.add_child(forge_preview)
	left.move_child(forge_preview, inventory_index)

	var center_scroll := ScrollContainer.new()
	center_scroll.name = "PrepareCenterScroll"
	var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
	center_scroll.position = center_rect.position
	center_scroll.size = center_rect.size
	center_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center_scroll.follow_focus = false
	center_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(center_scroll)
	var center := VBoxContainer.new()
	center.name = "PrepareCenterContent"
	center.theme_type_variation = &"ExpeditionBoardStack"
	ExpeditionLayoutMetrics.set_reference_min(
		center,
		Vector2(maxf(840.0, center_rect.size.x - 30.0), 0.0)
	)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_scroll.add_child(center)
	_build_board_grid(center)
	# Bench is a HUD strip, not part of the theme-scaled VBox flow. Keeping it
	# after a heading pushed it into the projected board at 125%/150% UI scale.
	# Anchor it to the center panel's top edge so all nine slots remain above the
	# projection without shrinking any of the board's 64 legal hit cells.
	_build_bench_row(layout)
	_place_bench_row()
	_build_board_draft_preview(layout)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "PrepareRightScroll"
	var right_rect := _region_content_rect(ProductionLayoutShell.REGION_RIGHT)
	right_scroll.position = right_rect.position
	right_scroll.size = right_rect.size
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_scroll.follow_focus = true
	layout.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.name = "PrepareRightContent"
	ExpeditionLayoutMetrics.set_reference_min(
		right,
		Vector2(maxf(330.0, right_rect.size.x - 30.0), 0.0)
	)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	_hud_shell.mount_unit_inspector(right)
	# The projected world board deliberately owns no Control-sized cells. This
	# side proxy is therefore the keyboard-only destination picker: board cells
	# are authored row-major, followed by bench slots in slot order. Its child is
	# named UnitSelector so ProductionScreen's existing focus collector includes
	# it without introducing a second focus-graph authority.
	right.add_child(_heading(&"prepare.panel.board"))
	_build_keyboard_placement_targets(right)
	right.add_child(_heading(&"prepare.panel.overflow"))
	var overflow_values := overflow_ids()
	if overflow_values.is_empty():
		right.add_child(_empty_label(&"prepare.empty.overflow"))
	else:
		var overflow := ItemList.new()
		overflow.name = "OverflowSelector"
		ExpeditionLayoutMetrics.set_reference_min(overflow, Vector2(0.0, 126.0))
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
		ExpeditionLayoutMetrics.set_reference_min(issues, Vector2(0.0, 126.0))
		issues.focus_mode = Control.FOCUS_ALL
		issues.set_meta(&"typed_data_kind", &"deployment_issue")
		for index: int in issue_codes.size():
			issues.add_item(_localized_ui_text(issue_message_keys[index]))
			issues.set_item_metadata(issues.item_count - 1, issue_codes[index])
		right.add_child(issues)
	_build_node_choice_overlay(snapshot, right)
	_refresh_draft_selectors()
	# 建構期間 shell 可能尚未套用目前 UI 縮放（consumer 的 apply 是
	# deferred）；建構完成後補一次 deferred 重排，收斂到最終 rect，
	# 避免停在「建構時 factor」與「套用後 factor」混合的過渡版面。
	call_deferred(&"refresh_layout_rects")


func _build_board_grid(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.name = "BoardGrid"
	grid.columns = 8
	grid.theme_type_variation = &"ExpeditionBoardGrid"
	grid.visible = false
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionLayoutMetrics.set_reference_min(grid, Vector2.ZERO)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(grid)
	for logical_y: int in range(BoardPreparationValidator.PLAYER_MAX_Y + 1):
		for logical_x: int in range(BoardPreparationValidator.BOARD_WIDTH):
			var cell := PrepareUnitDragButton.new()
			cell.name = "BoardCell_%d_%d" % [logical_y, logical_x]
			# WorldBoard is authoritative. These nodes remain only as a hidden
			# metadata contract and own neither layout nor UI input.
			ExpeditionLayoutMetrics.set_reference_min(cell, Vector2.ZERO)
			cell.flat = true
			cell.disabled = true
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.focus_mode = Control.FOCUS_NONE
			cell.theme_type_variation = &"ExpeditionGridCell"
			cell.set_meta(&"board_x", logical_x)
			cell.set_meta(&"board_y", logical_y)
			cell.set_meta(&"unit_instance_id", "")
			cell.set_meta(&"drag_target_kind", &"board")
			grid.add_child(cell)


func _build_bench_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "BenchRow"
	row.theme_type_variation = &"ExpeditionBenchRow"
	ExpeditionLayoutMetrics.set_fixed_min(row, 0.0, BENCH_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	for index: int in range(BoardPreparationValidator.BENCH_CAPACITY):
		var cell := PrepareUnitDragButton.new()
		cell.name = "BenchCell%d" % index
		# Nine slots plus scaled theme separation stay inside the fixed center
		# column through 150% UI reflow.
		ExpeditionLayoutMetrics.set_fixed_cell(cell, 54.0, 72.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.focus_mode = Control.FOCUS_ALL
		cell.theme_type_variation = &"ExpeditionGridCell"
		cell.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		cell.set_meta(&"unit_instance_id", "")
		cell.set_meta(&"drag_target_kind", &"bench")
		cell.set_meta(&"bench_slot", index)
		cell.pressed.connect(_on_bench_cell_pressed.bind(cell))
		cell.unit_dropped.connect(_on_unit_dropped)
		cell.configure_unit_drop_resolver(
			Callable(self, &"_resolve_unit_drop")
		)
		cell.unit_preview_cleared.connect(_clear_board_draft_preview)
		cell.equipment_dropped.connect(_on_equipment_dropped)
		cell.mouse_entered.connect(_on_unit_interaction_targeted.bind(cell))
		cell.focus_entered.connect(_on_unit_interaction_targeted.bind(cell))
		row.add_child(cell)


func _place_bench_row() -> void:
	var row := find_child("BenchRow", true, false) as HBoxContainer
	if row == null:
		return
	var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
	# layout_region_content_rect excludes the panel's content margin. The board
	# begins at reference y=324. Preserve the authored 72px strip's intended
	# bottom edge while letting the theme-scaled combined minimum grow upward;
	# otherwise 125%/150% make the slots grow downward into the world board.
	var authored_top := (
		center_rect.position.y
		- ProductionLayoutShell.PANEL_CONTENT_MARGIN.y
	)
	var authored_bottom := authored_top + BENCH_ROW_HEIGHT
	var rendered_height := maxf(
		BENCH_ROW_HEIGHT,
		row.get_combined_minimum_size().y
	)
	row.position = Vector2(
		center_rect.position.x,
		authored_bottom - rendered_height
	).round()
	row.size = Vector2(center_rect.size.x, rendered_height).round()


func _build_board_draft_preview(parent: Control) -> void:
	var panel := Label.new()
	panel.name = "BoardDraftPreview"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.theme_type_variation = &"ExpeditionDetail"
	panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.clip_text = true
	panel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.z_index = 45
	# Keep the typed drag summary clear of the fixed bench strip at 150%.
	# It intentionally overlays the world board: drag feedback belongs to the
	# UI overlay layer and must remain above sprites without moving board cells.
	panel.position = Vector2(724.0, 330.0)
	ExpeditionLayoutMetrics.set_reference_min(panel, Vector2(472.0, 96.0))
	panel.size = panel.custom_minimum_size
	panel.set_meta(&"typed_data_kind", &"board_draft_preview")
	parent.add_child(panel)
	_committed_board_preview = (
		_supply_port.try_committed_board_preview()
		if _supply_port != null
		else null
	)


func _resolve_unit_drop(
	unit_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int,
	force_refresh: bool = false
) -> Dictionary:
	var result := {"legal": false, "preview": null}
	if (
		_background_input_blocked()
		or unit_id.is_empty()
		or _draft_board == null
		or _supply_port == null
	):
		_clear_board_draft_preview()
		return result
	var cache_key := _board_preview_cache_key(
		unit_id, target_kind, target_cell, target_slot
	)
	if not force_refresh and _board_preview_cache.has(cache_key):
		var cached: Variant = _board_preview_cache[cache_key]
		_candidate_board_preview = (
			(cached as BoardDraftPreviewSnapshot).deep_clone()
			if cached is BoardDraftPreviewSnapshot
			else null
		)
		result["preview"] = (
			_candidate_board_preview.deep_clone()
			if _candidate_board_preview != null
			else null
		)
		result["legal"] = (
			_candidate_board_preview != null
			and _candidate_board_preview.valid
		)
		_render_board_draft_preview()
		return result
	_draft_move_adapter.reset(_draft_board, _draft_bench_unit_instance_ids)
	var move_error := (
		_draft_move_adapter.move_to_board(unit_id, target_cell)
		if target_kind == &"board"
		else _draft_move_adapter.move_to_bench(unit_id, target_slot)
		if target_kind == &"bench"
		else BoardDraftMoveAdapter.TARGET_INVALID
	)
	if not move_error.is_empty():
		_clear_board_draft_preview()
		return result
	var candidate_board := _draft_move_adapter.board_clone()
	var candidate_bench := _draft_move_adapter.bench_clone()
	if candidate_board == null:
		_clear_board_draft_preview()
		return result
	_candidate_board_preview = _supply_port.try_board_draft_preview(
		candidate_board.placements,
		candidate_bench
	)
	_board_preview_cache[cache_key] = (
		_candidate_board_preview.deep_clone()
		if _candidate_board_preview != null
		else null
	)
	result["preview"] = (
		_candidate_board_preview.deep_clone()
		if _candidate_board_preview != null
		else null
	)
	result["legal"] = (
		_candidate_board_preview != null and _candidate_board_preview.valid
	)
	_render_board_draft_preview()
	return result


func _board_preview_cache_key(
	unit_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
) -> String:
	return "%d|%s|%s|%d|%d|%d" % [
		_draft_revision,
		unit_id,
		String(target_kind),
		target_cell.x,
		target_cell.y,
		target_slot,
	]


func _advance_draft_revision() -> void:
	_draft_revision += 1
	_board_preview_cache.clear()
	_clear_board_draft_preview()


func _world_unit_drop_is_legal(
	unit_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
) -> bool:
	return bool(_resolve_unit_drop(
		unit_id, target_kind, target_cell, target_slot
	).get("legal", false))


func _render_board_draft_preview() -> void:
	var panel := _control(&"BoardDraftPreview") as Label
	if panel == null or _candidate_board_preview == null:
		return
	var before := _committed_board_preview
	var lines := PackedStringArray()
	lines.append("%s  %d / %d → %d / %d" % [
		_localized_ui_text(&"prepare.resource.capacity"),
		before.used_population if before != null else 0,
		before.derived_capacity if before != null else 0,
		_candidate_board_preview.used_population,
		_candidate_board_preview.derived_capacity,
	])
	for after_trait: TraitProgressSnapshot in _candidate_board_preview.trait_progress:
		if after_trait == null:
			continue
		var before_trait := _trait_progress_for(
			before, after_trait.trait_id
		)
		if (
			before_trait == null
			or before_trait.distinct_count != after_trait.distinct_count
			or before_trait.active_tier != after_trait.active_tier
		):
			lines.append("%s  %d / %d → %d / %d" % [
				_localized_content_text(after_trait.trait_id),
				before_trait.distinct_count if before_trait != null else 0,
				before_trait.active_tier if before_trait != null else 0,
				after_trait.distinct_count,
				after_trait.active_tier,
			])
	var issue_keys: Array[StringName] = []
	for issue_code: StringName in _candidate_board_preview.issue_codes():
		var key := StringName("error.board.%s" % String(issue_code).to_lower())
		issue_keys.append(key)
		lines.append(_localized_ui_text(key))
	panel.text = "\n".join(lines)
	panel.tooltip_text = panel.text
	panel.set_meta(&"accessible_text", panel.text)
	panel.set_meta(&"preview_valid", _candidate_board_preview.valid)
	panel.set_meta(&"issue_codes", _candidate_board_preview.issue_codes())
	panel.set_meta(&"issue_message_keys", issue_keys)
	panel.visible = true


func _trait_progress_for(
	preview: BoardDraftPreviewSnapshot,
	trait_id: StringName
) -> TraitProgressSnapshot:
	if preview != null:
		for progress: TraitProgressSnapshot in preview.trait_progress:
			if progress != null and progress.trait_id == trait_id:
				return progress
	return null


func _clear_board_draft_preview() -> void:
	_candidate_board_preview = null
	var panel := _control(&"BoardDraftPreview") as Label
	if panel != null:
		panel.visible = false
		panel.text = ""
		panel.tooltip_text = ""
		panel.remove_meta(&"preview_valid")
		panel.remove_meta(&"issue_codes")
		panel.remove_meta(&"issue_message_keys")


func _build_keyboard_placement_targets(parent: VBoxContainer) -> void:
	var selector := PrepareQuickToggleItemList.new()
	selector.name = "UnitSelector"
	ExpeditionLayoutMetrics.set_reference_min(selector, Vector2(0.0, 168.0))
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_ALL
	selector.select_mode = ItemList.SELECT_SINGLE
	selector.set_meta(&"typed_data_kind", &"prepare_placement_target")
	selector.set_meta(&"stable_focus_id", &"prepare.placement_targets")
	selector.set_meta(
		&"target_order",
		&"board_row_major_then_bench_slot"
	)
	selector.set_meta(
		&"accessible_text",
		_localized_ui_text(&"prepare.panel.board")
	)
	selector.item_selected.connect(_on_keyboard_target_selected)
	selector.item_activated.connect(_on_keyboard_target_activated)
	selector.focus_entered.connect(_on_keyboard_target_focus_entered)
	selector.quick_toggle_requested.connect(
		_on_selector_quick_toggle_requested
	)
	parent.add_child(selector)


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


func refresh_layout_rects() -> void:
	var metrics := find_child("PrepareMetrics", true, false) as Control
	if metrics != null:
		var metrics_rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
		metrics_rect.position.x += ProductionLayoutShell.TITLE_COLUMN_WIDTH
		metrics_rect.size.x -= ProductionLayoutShell.TITLE_COLUMN_WIDTH
		metrics.position = metrics_rect.position
		metrics.size = metrics_rect.size
	var left := find_child("PrepareLeftContent", true, false) as Control
	if left != null:
		var left_rect := _region_content_rect(ProductionLayoutShell.REGION_LEFT)
		left.position = left_rect.position
		# autowrap 子 Label 在 reflow 前寬度可能只有 1px，使 VBox 的
		# combined min 短暫暴漲、size 指派被向上夾制且不會自動縮回；
		# deferred 再指派一次，等子節點取得實際寬度後讓目標尺寸生效。
		left.size = left_rect.size
		left.set_deferred(&"size", left_rect.size)
	var center_scroll := find_child("PrepareCenterScroll", true, false) as Control
	if center_scroll != null:
		var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
		center_scroll.position = center_rect.position
		center_scroll.size = center_rect.size
	_place_bench_row()
	var right_scroll := find_child("PrepareRightScroll", true, false) as Control
	if right_scroll != null:
		var right_rect := _region_content_rect(ProductionLayoutShell.REGION_RIGHT)
		right_scroll.position = right_rect.position
		right_scroll.size = right_rect.size
	var draft_preview := _control(&"BoardDraftPreview") as Label
	if draft_preview != null:
		draft_preview.size = draft_preview.custom_minimum_size


func _metric_label(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.text = "%s  %s" % [_localized_ui_text(key), value]
	label.theme_type_variation = &"ExpeditionMetric"
	ExpeditionLayoutMetrics.set_reference_min(label, Vector2(162.0, 0.0))
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
	ExpeditionLayoutMetrics.set_reference_min(selector, Vector2(372.0, 180.0))
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
	var selector: ItemList
	if data_kind == &"item_instance":
		selector = PrepareEquipmentDragList.new()
	elif control_name == &"BuildUnitSelector":
		selector = PrepareQuickToggleItemList.new()
	else:
		selector = ItemList.new()
	selector.name = String(control_name)
	ExpeditionLayoutMetrics.set_reference_min(selector, minimum_size)
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
	if selector is PrepareEquipmentDragList:
		(selector as PrepareEquipmentDragList).forge_pair_dropped.connect(
			_on_forge_pair_dropped
		)
	elif selector is PrepareQuickToggleItemList:
		(selector as PrepareQuickToggleItemList).quick_toggle_requested.connect(
			_on_selector_quick_toggle_requested
		)


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
		# item_instances is the resolver table, not the inventory membership
		# authority. Iterating it directly exposes equipped and overflow items as
		# draggable/forgeable sources. Resolve only canonical inventory ids and
		# skip missing ids (fail closed) without inferring membership.
		var item_by_id: Dictionary = {}
		for item: ItemInstanceState in snapshot.roster.item_instances:
			if item != null and not item.instance_id.is_empty():
				item_by_id[item.instance_id] = item
		var appended_ids: Dictionary = {}
		for item_id: String in snapshot.roster.inventory_item_instance_ids:
			if appended_ids.has(item_id):
				continue
			var resolved: Variant = item_by_id.get(item_id)
			if not resolved is ItemInstanceState:
				continue
			var item := resolved as ItemInstanceState
			_append_typed_item(
				inventory,
				"%s · %s" % [
					_localized_content_text(item.def_id),
					item.instance_id,
				],
				item.instance_id
			)
			appended_ids[item_id] = true
		if inventory is PrepareEquipmentDragList:
			var component_ids: Array[String] = []
			if _supply_port != null:
				for component: ItemInstanceState in (
					_supply_port.forge_inventory_components()
				):
					if component != null and not component.instance_id.is_empty():
						component_ids.append(component.instance_id)
			(inventory as PrepareEquipmentDragList).configure_forge_components(
				component_ids,
				Callable(self, &"_preview_forge_pair"),
				_component_equip_rejection_text()
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
	_refresh_keyboard_placement_targets(snapshot)
	# Initial compose happens before ProductionScreen is attached to the tree.
	# Schedule unconditionally (same contract as RUN_COMBAT); by deferred time
	# the route is installed and the production world/coordinator groups exist.
	_schedule_world_board_mount()


func _schedule_world_board_mount() -> void:
	if _world_board_mount_deferred_pending:
		return
	_world_board_mount_deferred_pending = true
	call_deferred(&"_mount_world_board")


func _mount_world_board() -> void:
	_world_board_mount_deferred_pending = false
	if (
		not is_inside_tree()
		or not can_process()
		or _model == null
		or _draft_board == null
	):
		return
	var overlay_mount: Control = (
		_hud_shell.host(ProductionLayoutShell.REGION_OVERLAY)
		if _hud_shell != null
		else null
	)
	var mount_error := ProductionWorldSurface.INVALID_OVERLAY_MOUNT
	if overlay_mount != null:
		mount_error = WorldBoardMountAdapter.mount(
			get_tree(),
			_world_snapshot_factory.build_prepare(
				_model.snapshot_clone(),
				_draft_board.deep_clone()
			),
			Callable(self, &"_world_cell_is_draft_eligible"),
			overlay_mount
		)
	_world_board_mount_error = mount_error
	if not mount_error.is_empty():
		_report_world_board_mount_error(mount_error)
		return
	_connect_world_surface_inputs()


func world_board_mount_error() -> StringName:
	return _world_board_mount_error


func _report_world_board_mount_error(_error_code: StringName) -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen == null:
		return
	parent_screen.report_composition_result(AppActionResult.failure(
		DiagnosticError.new(
			&"RENDER_FAILED",
			&"error.presentation.render_failed"
		)
	))


func _connect_world_surface_inputs() -> void:
	for node: Node in get_tree().get_nodes_in_group(
		ProductionWorldSurface.MOUNT_GROUP
	):
		var surface := node as ProductionWorldSurface
		if surface == null:
			continue
		if not surface.unit_dropped.is_connected(_on_world_unit_dropped):
			surface.unit_dropped.connect(_on_world_unit_dropped)
		if not surface.equipment_dropped.is_connected(
			_on_equipment_dropped
		):
			surface.equipment_dropped.connect(_on_equipment_dropped)
		if not surface.unit_targeted.is_connected(_on_world_unit_targeted):
			surface.unit_targeted.connect(_on_world_unit_targeted)
		if not surface.unit_hovered.is_connected(_on_world_unit_hovered):
			surface.unit_hovered.connect(_on_world_unit_hovered)
		var overlay := surface.ui_overlay()
		if overlay != null:
			_clear_board_draft_preview()
			var drag_target := overlay.drag_target()
			drag_target.configure_unit_drop_resolver(
				Callable(self, &"_world_unit_drop_is_legal")
			)
			if not drag_target.preview_cleared.is_connected(
				_clear_board_draft_preview
			):
				drag_target.preview_cleared.connect(
					_clear_board_draft_preview
				)


func _world_cell_is_draft_eligible(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < BoardPreparationValidator.BOARD_WIDTH
		and cell.y >= 0
		and cell.y <= BoardPreparationValidator.PLAYER_MAX_Y
	)


func _on_world_unit_dropped(unit_id: String, target_cell: Vector2i) -> void:
	_on_unit_dropped(unit_id, &"board", target_cell, -1)


func _on_world_unit_targeted(unit_id: String) -> void:
	_quick_toggle_unit_id = unit_id
	_keyboard_move_unit_id = unit_id
	if unit_id.is_empty():
		return
	_select_item_by_metadata(&"BuildUnitSelector", unit_id)
	_select_inspector_unit(unit_id)


func _on_world_unit_hovered(unit_id: String) -> void:
	# Hover only supplies the TFT-style W target. It must not silently replace
	# the keyboard move source selected in BuildUnitSelector.
	_quick_toggle_unit_id = unit_id
	_preview_inspector_unit(unit_id)


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
		var accessible_name := (
			_unit_display_name(unit_id, snapshot)
			if not unit_id.is_empty()
			else ""
		)
		cell.text = ""
		cell.tooltip_text = accessible_name
		cell.set_meta(&"accessible_text", accessible_name)


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
		var occupied := not unit_id.is_empty()
		cell.text = _unit_display_name(unit_id, snapshot) if occupied else "◇"
		cell.self_modulate.a = (
			1.0 if occupied else ExpeditionLayoutMetrics.BENCH_EMPTY_ALPHA
		)
		cell.tooltip_text = cell.text if occupied else ""
		cell.set_meta(
			&"accessible_text",
			cell.text if occupied else "%s %d" % [
				_localized_ui_text(&"prepare.panel.bench"), index + 1
			]
		)


func _refresh_keyboard_placement_targets(
	snapshot: RunPresentationSnapshot
) -> void:
	var selector := _control(&"UnitSelector") as ItemList
	if selector == null:
		return
	var occupants: Dictionary = {}
	if _draft_board != null:
		for placement: BoardPlacementState in _draft_board.placements:
			if placement != null:
				occupants[Vector2i(
					placement.logical_x,
					placement.logical_y
				)] = placement.unit_instance_id
	selector.clear()
	var board_name := _localized_ui_text(&"prepare.panel.board")
	for logical_y: int in range(BoardPreparationValidator.PLAYER_MAX_Y + 1):
		for logical_x: int in range(BoardPreparationValidator.BOARD_WIDTH):
			var cell := Vector2i(logical_x, logical_y)
			var unit_id := String(occupants.get(cell, ""))
			var label := "%s [%d,%d]" % [
				board_name,
				logical_y,
				logical_x,
			]
			if not unit_id.is_empty():
				label = "%s · %s" % [
					label,
					_unit_display_name(unit_id, snapshot),
				]
			_append_keyboard_target(
				selector,
				label,
				&"board",
				cell,
				-1,
				unit_id
			)
	var bench_name := _localized_ui_text(&"prepare.panel.bench")
	for slot: int in range(BoardDraftMoveAdapter.BENCH_SIZE):
		var unit_id := (
			_draft_bench_unit_instance_ids[slot]
			if slot < _draft_bench_unit_instance_ids.size()
			else ""
		)
		var label := "%s [%d]" % [bench_name, slot]
		if not unit_id.is_empty():
			label = "%s · %s" % [
				label,
				_unit_display_name(unit_id, snapshot),
			]
		_append_keyboard_target(
			selector,
			label,
			&"bench",
			Vector2i(-1, -1),
			slot,
			unit_id
		)
	if selector.item_count > 0:
		selector.select(0)


func _append_keyboard_target(
	selector: ItemList,
	label: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int,
	unit_id: String
) -> void:
	selector.add_item(label)
	var index := selector.item_count - 1
	selector.set_item_metadata(index, {
		"target_kind": target_kind,
		"target_cell": target_cell,
		"target_slot": target_slot,
		"unit_instance_id": unit_id,
	})
	selector.set_item_tooltip(index, label)


func _on_keyboard_target_focus_entered() -> void:
	var selector := _control(&"UnitSelector") as ItemList
	if selector == null or selector.item_count <= 0:
		_quick_toggle_unit_id = ""
		return
	var selected := selector.get_selected_items()
	if selected.is_empty():
		selector.select(0)
		_on_keyboard_target_selected(0)
	else:
		_on_keyboard_target_selected(selected[0])


func _on_keyboard_target_selected(index: int) -> void:
	var target := _keyboard_target_metadata(index)
	_quick_toggle_unit_id = String(target.get("unit_instance_id", ""))
	_preview_inspector_unit(_quick_toggle_unit_id)


func _on_keyboard_target_activated(index: int) -> void:
	if _background_input_blocked() or _keyboard_move_unit_id.is_empty():
		return
	var target := _keyboard_target_metadata(index)
	if target.is_empty():
		return
	var target_cell: Vector2i = target.get(
		"target_cell",
		Vector2i(-1, -1)
	)
	_on_unit_dropped(
		_keyboard_move_unit_id,
		StringName(target.get("target_kind", &"")),
		target_cell,
		int(target.get("target_slot", -1))
	)


func _keyboard_target_metadata(index: int) -> Dictionary:
	var selector := _control(&"UnitSelector") as ItemList
	if selector == null or index < 0 or index >= selector.item_count:
		return {}
	var value: Variant = selector.get_item_metadata(index)
	return value.duplicate(true) if value is Dictionary else {}


func _on_board_cell_pressed(cell: Button) -> void:
	var unit_id := String(cell.get_meta(&"unit_instance_id", "")) if cell != null else ""
	if not unit_id.is_empty():
		_select_item_by_metadata(&"BoardSelector", unit_id)
		_select_item_by_metadata(&"BuildUnitSelector", unit_id)
		_select_inspector_unit(unit_id)


func _on_build_unit_selected(index: int) -> void:
	var selector := _control(&"BuildUnitSelector") as ItemList
	if selector == null or index < 0 or index >= selector.item_count:
		_quick_toggle_unit_id = ""
		_keyboard_move_unit_id = ""
		_select_inspector_unit("")
		return
	var unit_id := String(selector.get_item_metadata(index))
	_quick_toggle_unit_id = unit_id
	_keyboard_move_unit_id = unit_id
	_select_inspector_unit(unit_id)


func _on_build_unit_selector_focus_entered() -> void:
	var selector := _control(&"BuildUnitSelector") as ItemList
	if selector == null or selector.item_count <= 0:
		return
	var selected := selector.get_selected_items()
	if selected.is_empty():
		selector.select(0)
		_on_build_unit_selected(0)


func _on_inventory_selector_focus_entered() -> void:
	var selector := _control(&"InventorySelector") as ItemList
	if selector == null or selector.item_count <= 0:
		return
	if selector.get_selected_items().is_empty():
		selector.select(0)


func _on_bench_cell_pressed(cell: Button) -> void:
	var unit_id := String(cell.get_meta(&"unit_instance_id", "")) if cell != null else ""
	if not unit_id.is_empty():
		_quick_toggle_unit_id = unit_id
		_keyboard_move_unit_id = unit_id
		_select_item_by_metadata(&"BenchSelector", unit_id)
		_select_item_by_metadata(&"BuildUnitSelector", unit_id)
		_select_inspector_unit(unit_id)


func _select_inspector_unit(unit_id: String) -> void:
	_selected_inspector_unit_id = unit_id
	_selected_sell_quote = _sell_quote_for(unit_id)
	_restore_selected_inspector()
	_update_parent_action_state()


func _preview_inspector_unit(unit_id: String) -> void:
	if _hud_shell == null:
		return
	if unit_id.is_empty():
		_restore_selected_inspector()
	else:
		_hud_shell.show_prepare_unit(unit_id, _sell_quote_for(unit_id))


func _restore_selected_inspector() -> void:
	if _hud_shell == null:
		return
	if _selected_inspector_unit_id.is_empty():
		_hud_shell.show_inspector_empty()
	else:
		_hud_shell.show_prepare_unit(
			_selected_inspector_unit_id, _selected_sell_quote
		)


func _sell_quote_for(unit_id: String) -> ShopQuoteSnapshot:
	if unit_id.is_empty() or _supply_port == null:
		return null
	var quote := _supply_port.shop_sell_quote(unit_id)
	return quote.deep_clone() if quote != null else null


func _on_unit_interaction_targeted(cell: Button) -> void:
	if cell == null:
		return
	var unit_id := String(cell.get_meta(&"unit_instance_id", ""))
	# Focus metadata is the keyboard authority. Empty cells deliberately clear a
	# previously focused unit so W cannot act on a stale hover/focus target.
	_quick_toggle_unit_id = unit_id


func _unhandled_input(event: InputEvent) -> void:
	if (
		event == null
		or not event.is_action_pressed(&"prepare_quick_toggle_unit", false, true)
	):
		return
	_handle_quick_toggle_input()
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_selector_quick_toggle_requested() -> void:
	_handle_quick_toggle_input()


func _handle_quick_toggle_input() -> void:
	if _background_input_blocked() or _quick_toggle_unit_id.is_empty():
		return
	var result := quick_toggle_unit(_quick_toggle_unit_id)
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.report_composition_result(result)


func quick_toggle_unit(unit_id: String) -> RunPresentationResult:
	_draft_move_adapter.reset(_draft_board, _draft_bench_unit_instance_ids)
	var error_code := (
		_draft_move_adapter.move_to_first_open_bench(unit_id)
		if _unit_is_on_board(unit_id)
		else _draft_move_adapter.move_to_first_open_board(unit_id)
	)
	if not error_code.is_empty():
		return RunPresentationResult.failure(_draft_move_error(error_code))
	_apply_adapter_draft()
	return _commit_immediate_draft()


func _on_unit_dropped(
	unit_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
) -> void:
	if _background_input_blocked():
		return
	var preview_result := _resolve_unit_drop(
		unit_id, target_kind, target_cell, target_slot, true
	)
	if not bool(preview_result.get("legal", false)):
		return
	_draft_move_adapter.reset(_draft_board, _draft_bench_unit_instance_ids)
	var error_code := (
		_draft_move_adapter.move_to_board(unit_id, target_cell)
		if target_kind == &"board"
		else _draft_move_adapter.move_to_bench(unit_id, target_slot)
		if target_kind == &"bench"
		else BoardDraftMoveAdapter.TARGET_INVALID
	)
	var result: Variant
	if error_code.is_empty():
		_apply_adapter_draft()
		result = _commit_immediate_draft()
	else:
		result = AppActionResult.failure(_draft_move_error(error_code))
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.report_composition_result(result)
	_clear_board_draft_preview()


func _on_equipment_dropped(item_id: String, unit_id: String) -> void:
	if _background_input_blocked():
		return
	if (
		not _select_item_by_metadata(&"InventorySelector", item_id)
		or not _select_item_by_metadata(&"BuildUnitSelector", unit_id)
	):
		return
	var result := equip_selected_item()
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.report_composition_result(result)


func _on_forge_pair_dropped(first_item_id: String, second_item_id: String) -> void:
	if _background_input_blocked():
		return
	if (
		_supply_port == null
		or _supply_port.try_forge_pair_recipe(
			first_item_id, second_item_id
		) == null
	):
		var rejected := ConfirmationDraftResult.failure(_selection_error())
		var rejected_parent := get_parent() as ProductionScreen
		if rejected_parent != null:
			rejected_parent.report_composition_result(rejected)
		return
	var inventory := _control(&"InventorySelector") as ItemList
	if inventory == null:
		return
	inventory.deselect_all()
	for index: int in inventory.item_count:
		var value := String(inventory.get_item_metadata(index))
		if value == first_item_id or value == second_item_id:
			inventory.select(index, false)
	var result := begin_forge_selected()
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.report_composition_result(result)
		parent_screen.refresh_interaction_state()


func _preview_forge_pair(first_item_id: String, second_item_id: String) -> bool:
	var preview := _control(&"ForgeRecipePreview") as Label
	if preview == null:
		return false
	var heading := _localized_ui_text(&"collection.category.recipe")
	if first_item_id.is_empty() or second_item_id.is_empty():
		preview.text = heading
		preview.set_meta(&"forge_preview_state", &"idle")
		preview.set_meta(&"result_equipment_id", &"")
		preview.set_meta(&"accessible_text", preview.text)
		return false
	var recipe := (
		_supply_port.try_forge_pair_recipe(first_item_id, second_item_id)
		if _supply_port != null
		else null
	)
	if recipe == null:
		preview.text = "✕ %s · %s" % [
			heading,
			_localized_ui_text(&"error.presentation.action_not_available"),
		]
		preview.set_meta(&"forge_preview_state", &"invalid")
		preview.set_meta(&"result_equipment_id", &"")
		preview.set_meta(&"accessible_text", preview.text)
		return false
	var snapshot := _model.snapshot_clone() if _model != null else null
	preview.text = "✓ %s: %s + %s → %s · %s" % [
		heading,
		_item_display_name(first_item_id, snapshot),
		_item_display_name(second_item_id, snapshot),
		_localized_content_text(recipe.equipment_id),
		_localized_ui_text(&"prepare.forge.confirm"),
	]
	preview.set_meta(&"forge_preview_state", &"valid")
	preview.set_meta(&"result_equipment_id", recipe.equipment_id)
	preview.set_meta(&"accessible_text", preview.text)
	return true


func _component_equip_rejection_text() -> String:
	return "✕ %s · %s" % [
		_localized_ui_text(&"prepare.equip"),
		_localized_ui_text(&"error.presentation.action_not_available"),
	]


func _apply_adapter_draft() -> void:
	_draft_board = _draft_move_adapter.board_clone()
	_draft_bench_unit_instance_ids.assign(_draft_move_adapter.bench_clone())
	_advance_draft_revision()
	_refresh_draft_selectors()


func _commit_immediate_draft() -> RunPresentationResult:
	return commit_board_draft()


func _post_commit_board_draft(canonical: RunPresentationSnapshot) -> void:
	_reset_consumer_draft(canonical)
	_committed_board_preview = (
		_supply_port.try_committed_board_preview()
		if _supply_port != null
		else null
	)
	_refresh_draft_selectors()


func _unit_is_on_board(unit_id: String) -> bool:
	if _draft_board != null:
		for placement: BoardPlacementState in _draft_board.placements:
			if placement != null and placement.unit_instance_id == unit_id:
				return true
	return false


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
	_advance_draft_revision()
	_draft_board = null
	_draft_bench_unit_instance_ids.clear()
	_quick_toggle_unit_id = ""
	_keyboard_move_unit_id = ""
	_selected_inspector_unit_id = ""
	_pending_forge_confirmation = null
	_pending_node_choice_confirmation = null
	_selected_node_choice_id = &""
	_committed_board_preview = null
	_candidate_board_preview = null
	if snapshot == null or snapshot.roster == null:
		return
	_draft_board = snapshot.roster.board.deep_clone()
	_draft_bench_unit_instance_ids.assign(
		snapshot.roster.bench_unit_instance_ids
	)
	_draft_move_adapter.reset(_draft_board, _draft_bench_unit_instance_ids)


func _background_input_blocked() -> bool:
	var parent_screen := get_parent() as ProductionScreen
	return parent_screen != null and parent_screen.is_background_input_blocked()


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
	for logical_y: int in range(BoardPreparationValidator.PLAYER_MAX_Y + 1):
		for logical_x: int in range(BoardPreparationValidator.BOARD_WIDTH):
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
	return _unavailable_text()


func _item_display_name(
	item_instance_id: String,
	snapshot: RunPresentationSnapshot
) -> String:
	if snapshot != null and snapshot.roster != null:
		for item: ItemInstanceState in snapshot.roster.item_instances:
			if item.instance_id == item_instance_id:
				return _localized_content_text(item.def_id)
	return _unavailable_text()


func _unavailable_text() -> String:
	return _localized_ui_text(&"combat.inspection.none")


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

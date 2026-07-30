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
	return _model != null and _model.start_enabled()


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
	for path: NodePath in [
		^"CapacityValue",
		^"OverflowSelector",
		^"DeploymentIssues",
		^"BoardSelector",
		^"BenchSelector",
		^"ShopSelector",
		^"InventorySelector",
		^"BuildUnitSelector",
	]:
		var existing := get_node_or_null(path)
		if existing != null:
			remove_child(existing)
			existing.queue_free()
	var capacity := Label.new()
	capacity.name = "CapacityValue"
	capacity.position = Vector2(72.0, 112.0)
	capacity.text = str(displayed_capacity())
	capacity.set_meta(&"typed_data_kind", &"population_capacity")
	capacity.set_meta(&"accessible_text", capacity.text)
	add_child(capacity)

	_add_selector(
		&"BoardSelector",
		Vector2(72.0, 152.0),
		Vector2(260.0, 160.0),
		&"board_draft"
	)
	_add_selector(
		&"BenchSelector",
		Vector2(348.0, 152.0),
		Vector2(260.0, 160.0),
		&"bench_draft"
	)
	_add_selector(
		&"ShopSelector",
		Vector2(624.0, 152.0),
		Vector2(260.0, 160.0),
		&"shop_offer"
	)
	_add_selector(
		&"InventorySelector",
		Vector2(72.0, 328.0),
		Vector2(396.0, 160.0),
		&"item_instance",
		true
	)
	_add_selector(
		&"BuildUnitSelector",
		Vector2(488.0, 328.0),
		Vector2(396.0, 160.0),
		&"unit_instance"
	)

	var overflow := ItemList.new()
	overflow.name = "OverflowSelector"
	overflow.position = Vector2(72.0, 504.0)
	overflow.custom_minimum_size = Vector2(396.0, 120.0)
	overflow.focus_mode = Control.FOCUS_ALL
	overflow.set_meta(&"typed_data_kind", &"item_overflow")
	for item_id: String in overflow_ids():
		overflow.add_item(item_id)
		overflow.set_item_metadata(overflow.item_count - 1, item_id)
	add_child(overflow)

	var issues := ItemList.new()
	issues.name = "DeploymentIssues"
	issues.position = Vector2(488.0, 504.0)
	issues.custom_minimum_size = Vector2(396.0, 120.0)
	issues.focus_mode = Control.FOCUS_ALL
	issues.set_meta(&"typed_data_kind", &"deployment_issue")
	for issue_code: StringName in deployment_issue_codes():
		issues.add_item(String(issue_code))
		issues.set_item_metadata(issues.item_count - 1, issue_code)
	add_child(issues)
	_refresh_draft_selectors()


func _add_selector(
	control_name: StringName,
	position_value: Vector2,
	minimum_size: Vector2,
	data_kind: StringName,
	multi_select: bool = false
) -> void:
	var selector := ItemList.new()
	selector.name = String(control_name)
	selector.position = position_value
	selector.custom_minimum_size = minimum_size
	selector.focus_mode = Control.FOCUS_ALL
	selector.select_mode = (
		ItemList.SELECT_MULTI
		if multi_select
		else ItemList.SELECT_SINGLE
	)
	selector.set_meta(&"typed_data_kind", data_kind)
	selector.set_meta(&"accessible_text", String(control_name))
	add_child(selector)


func _refresh_draft_selectors() -> void:
	var snapshot := (
		_model.snapshot_clone()
		if _model != null
		else null
	)
	if snapshot == null or snapshot.roster == null:
		return
	var board := get_node_or_null(^"BoardSelector") as ItemList
	var bench := get_node_or_null(^"BenchSelector") as ItemList
	var shop := get_node_or_null(^"ShopSelector") as ItemList
	var inventory := get_node_or_null(^"InventorySelector") as ItemList
	var units := get_node_or_null(^"BuildUnitSelector") as ItemList
	if board != null:
		board.clear()
		for placement: BoardPlacementState in _draft_board.placements:
			_append_typed_item(
				board,
				"%s [%d,%d]" % [
					placement.unit_instance_id,
					placement.logical_y,
					placement.logical_x,
				],
				placement.unit_instance_id
			)
	if bench != null:
		bench.clear()
		for unit_id: String in _draft_bench_unit_instance_ids:
			_append_typed_item(bench, unit_id, unit_id)
	if shop != null:
		shop.clear()
		if snapshot.economy != null:
			for offer: ShopOffer in snapshot.economy.shop_offers:
				_append_typed_item(
					shop,
					"%s · %d" % [
						String(offer.unit_def_id),
						offer.cost,
					],
					offer.offer_id
				)
	if inventory != null:
		inventory.clear()
		for item: ItemInstanceState in snapshot.roster.item_instances:
			_append_typed_item(
				inventory,
				"%s · %s" % [
					String(item.def_id),
					item.instance_id,
				],
				item.instance_id
			)
	if units != null:
		units.clear()
		for unit: UnitInstance in snapshot.roster.unit_instances:
			_append_typed_item(
				units,
				"%s ★%d" % [String(unit.def_id), unit.star],
				unit.instance_id
			)


func _append_typed_item(
	selector: ItemList,
	label: String,
	identity: String
) -> void:
	selector.add_item(label)
	selector.set_item_metadata(selector.item_count - 1, identity)


func _reset_consumer_draft(snapshot: RunPresentationSnapshot) -> void:
	_draft_board = null
	_draft_bench_unit_instance_ids.clear()
	_pending_forge_confirmation = null
	if snapshot == null or snapshot.roster == null:
		return
	_draft_board = snapshot.roster.board.deep_clone()
	_draft_bench_unit_instance_ids.assign(
		snapshot.roster.bench_unit_instance_ids
	)


func _selected_metadata(selector_name: StringName) -> Array[String]:
	var result: Array[String] = []
	var selector := get_node_or_null(NodePath(String(selector_name))) as ItemList
	if selector == null:
		return result
	for index: int in selector.get_selected_items():
		result.append(String(selector.get_item_metadata(index)))
	return result


func _single_selected_metadata(selector_name: StringName) -> String:
	var selected := _selected_metadata(selector_name)
	return selected[0] if not selected.is_empty() else ""


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


func _selection_failure() -> RunPresentationResult:
	return RunPresentationResult.failure(_selection_error())


func _selection_error() -> DiagnosticError:
	return DiagnosticError.new(
		SELECTION_REQUIRED,
		&"error.presentation.prepare_selection_required"
	)

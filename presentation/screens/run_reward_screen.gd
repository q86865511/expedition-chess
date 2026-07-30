class_name RunRewardScreen
extends ProductionScreen

const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"

var _model := RunRewardScreenModel.new()
var _presenter: RunScreenPresenter
var _selected_reward_id: String = ""
var _offer_selector: ItemList


func compose(
	snapshot: RunPresentationSnapshot,
	intent_port: LiveScreenIntentPort
) -> StringName:
	var error_code := _model.compose(snapshot)
	if not error_code.is_empty():
		_presenter = null
		return error_code
	_presenter = RunScreenPresenter.new(&"RUN_REWARD", intent_port)
	_selected_reward_id = ""
	_build_offer_selector()
	return &""


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
	if (
		intent == null
		or _presenter == null
		or not _model.allows(intent.kind)
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
	var existing := get_node_or_null(^"OfferSelector")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	_offer_selector = ItemList.new()
	_offer_selector.name = "OfferSelector"
	_offer_selector.position = Vector2(72.0, 112.0)
	_offer_selector.custom_minimum_size = Vector2(560.0, 280.0)
	_offer_selector.focus_mode = Control.FOCUS_ALL
	_offer_selector.select_mode = ItemList.SELECT_SINGLE
	_offer_selector.set_meta(&"typed_choice_kind", &"reward_offer")
	_offer_selector.set_meta(&"semantic_kind", &"rarity")
	_offer_selector.set_meta(
		&"semantic_pattern",
		&"double-frame"
	)
	_offer_selector.set_meta(&"accessible_text", &"reward.offer_selector")
	for offer_id: String in offer_ids():
		_offer_selector.add_item(
			_localized_content_text(StringName(offer_id))
		)
		var index := _offer_selector.item_count - 1
		_offer_selector.set_item_metadata(index, offer_id)
	_offer_selector.item_selected.connect(_on_offer_selected)
	add_child(_offer_selector)
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
	_update_parent_action_state()


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

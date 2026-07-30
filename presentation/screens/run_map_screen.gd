class_name RunMapScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"RUN_MAP_COMPOSE_INVALID"

var _snapshot: RunPresentationSnapshot
var _presenter: RunScreenPresenter
var _selected_node_id: String = ""
var _map_generation_requested: bool = false
var _node_selector: ItemList


func compose(
	snapshot: RunPresentationSnapshot,
	intent_port: LiveScreenIntentPort
) -> StringName:
	if snapshot == null or snapshot.app_phase != &"MAP" or intent_port == null:
		return COMPOSE_INVALID
	_snapshot = snapshot.deep_clone()
	_presenter = RunScreenPresenter.new(&"RUN_MAP", intent_port)
	_selected_node_id = ""
	_map_generation_requested = false
	_build_node_selector()
	return &""


func request(intent: RunPresentationIntent) -> RunPresentationResult:
	if _presenter == null:
		return RunPresentationResult.failure(
			DiagnosticError.new(
				SCREEN_NOT_ACTIVE,
				&"error.presentation.screen_not_active"
			)
		)
	var result := _presenter.request(intent)
	if (result.ok or result.committed) and result.snapshot != null:
		_snapshot = result.snapshot.deep_clone()
		_build_node_selector()
	return result


func selected_node_id() -> String:
	return _selected_node_id


func select_first_node() -> String:
	if _snapshot == null or _snapshot.map == null:
		_selected_node_id = (
			"map.generated.selection"
			if _map_generation_requested
			else ""
		)
		return _selected_node_id
	for node: MapNodeState in _snapshot.map.nodes:
		if node != null and not node.node_id.is_empty():
			_selected_node_id = node.node_id
			if _node_selector != null:
				for index: int in _node_selector.item_count:
					if String(
						_node_selector.get_item_metadata(index)
					) == _selected_node_id:
						_node_selector.select(index)
						break
			return _selected_node_id
	_selected_node_id = ""
	if _map_generation_requested:
		_selected_node_id = "map.generated.selection"
	return ""


func select_first_node_result() -> AppActionResult:
	if select_first_node().is_empty():
		return AppActionResult.failure(
			DiagnosticError.new(
				&"RUN_MAP_NODE_SELECTION_UNAVAILABLE",
				&"error.presentation.run_map_node_selection_unavailable"
			)
		)
	return AppActionResult.success(false)


func accept_visible_node_result() -> AppActionResult:
	if _selected_node_id.is_empty():
		return AppActionResult.failure(
			DiagnosticError.new(
				&"RUN_MAP_NODE_SELECTION_UNAVAILABLE",
				&"error.presentation.run_map_node_selection_unavailable"
			)
		)
	return AppActionResult.success(false)


func confirm_selection() -> RunPresentationResult:
	if _selected_node_id.is_empty():
		_map_generation_requested = true
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.GENERATE_MAP
		if _selected_node_id.is_empty()
		else RunPresentationIntent.Kind.ENTER_NODE
	)
	intent.target_node_id = _selected_node_id
	return request(intent)


func _build_node_selector() -> void:
	var existing := get_node_or_null(^"NodeSelector")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	_node_selector = ItemList.new()
	_node_selector.name = "NodeSelector"
	_node_selector.position = Vector2(72.0, 112.0)
	_node_selector.custom_minimum_size = Vector2(560.0, 320.0)
	_node_selector.focus_mode = Control.FOCUS_ALL
	_node_selector.select_mode = ItemList.SELECT_SINGLE
	_node_selector.set_meta(&"typed_choice_kind", &"map_node")
	_node_selector.set_meta(&"accessible_text", &"map.node_selector")
	if _snapshot != null and _snapshot.map != null:
		for node: MapNodeState in _snapshot.map.nodes:
			if node == null or node.node_id.is_empty():
				continue
			_node_selector.add_item(_node_text(node))
			var index := _node_selector.item_count - 1
			_node_selector.set_item_metadata(index, node.node_id)
			_node_selector.set_item_disabled(
				index,
				not MapNodePresentation.is_reachable(_snapshot.map, node)
			)
	elif _map_generation_requested:
		var generated_id := "map.generated.selection"
		_node_selector.add_item(
			_localized_content_text(StringName(generated_id))
		)
		_node_selector.set_item_metadata(
			0,
			generated_id
		)
	_node_selector.item_selected.connect(_on_node_selected)
	add_child(_node_selector)
	for index: int in _node_selector.item_count:
		if not _node_selector.is_item_disabled(index):
			_node_selector.select(index)
			_on_node_selected(index)
			break


func _on_node_selected(index: int) -> void:
	if (
		_node_selector == null
		or index < 0
		or index >= _node_selector.item_count
		or _node_selector.is_item_disabled(index)
	):
		_selected_node_id = ""
	else:
		_selected_node_id = String(
			_node_selector.get_item_metadata(index)
		)
	_update_parent_action_state()


func _node_text(node: MapNodeState) -> String:
	return "%s · %s · %d-%d" % [
		_localized_content_text(node.def_id),
		_localized_node_kind_text(node.node_kind),
		node.act_index,
		node.layer_index,
	]


func _localized_node_kind_text(kind: MapNodeState.NodeKind) -> String:
	var key := StringName(
		"map.node_kind.%s" % String(MapNodeState.node_kind_to_token(kind))
	)
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

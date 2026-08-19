class_name RunMapScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"RUN_MAP_COMPOSE_INVALID"

var _snapshot: RunPresentationSnapshot
var _presenter: RunScreenPresenter
var _selected_node_id: String = ""
var _map_generation_requested: bool = false
var _node_selector: ItemList
var _map_graph: RunMapNodeGraph
var _hud_shell: InRunHudShell
var _world_board_clear_error: StringName = &""
var _world_board_clear_deferred_pending: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		# Production candidates compose while detached. The compose-time deferred
		# clear may already have been consumed; entering the tree is the event that
		# guarantees one fresh attempt without layout/process polling.
		_schedule_world_board_clear()


func compose(
	snapshot: RunPresentationSnapshot,
	intent_port: LiveScreenIntentPort,
	supply_port: LiveScreenSupplyPort = null
) -> StringName:
	if snapshot == null or snapshot.app_phase != &"MAP" or intent_port == null:
		return COMPOSE_INVALID
	_snapshot = snapshot.deep_clone()
	_presenter = RunScreenPresenter.new(&"RUN_MAP", intent_port)
	_selected_node_id = ""
	_map_generation_requested = false
	_build_hud_shell(supply_port)
	_build_map_graph()
	_build_node_selector()
	_schedule_world_board_clear()
	return &""


func _schedule_world_board_clear() -> void:
	if _snapshot == null or _world_board_clear_deferred_pending:
		return
	_world_board_clear_deferred_pending = true
	call_deferred(&"_clear_world_board")


func _clear_world_board() -> void:
	# Always release the latch: a detached deferred call must leave ENTER_TREE
	# free to schedule the same candidate's formal clear attempt.
	_world_board_clear_deferred_pending = false
	if not is_inside_tree() or _snapshot == null:
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
		_build_hud_shell()
		_build_map_graph()
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
		if (
			node != null
			and not node.node_id.is_empty()
			and MapNodePresentation.is_reachable(_snapshot.map, node)
		):
			_selected_node_id = node.node_id
			if _node_selector != null:
				for index: int in _node_selector.item_count:
					if String(
						_node_selector.get_item_metadata(index)
					) == _selected_node_id:
						_node_selector.select(index)
						break
			if _map_graph != null:
				_map_graph.set_selected_node_id(_selected_node_id)
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


func open_node_selection() -> Variant:
	if (
		_snapshot == null
		or _snapshot.map == null
		or _snapshot.map.nodes.is_empty()
	):
		_map_generation_requested = true
		return request(RunPresentationIntent.new(
			RunPresentationIntent.Kind.GENERATE_MAP
		))
	if _selected_node_id.is_empty():
		return select_first_node_result()
	return AppActionResult.success(false)


## review N1：APPLY_AND_COMPLETE 出口把 run_phase 切成 MAP（design :206），
## 未 ack 的 receipt 因此會落在本畫面重播；ack 命令帶的是該 receipt 自己的 digest。
func pending_node_choice_result() -> NodeChoiceResultSnapshot:
	return _oldest_pending_node_choice_result(_snapshot)


func acknowledge_node_choice_result() -> RunPresentationResult:
	var result := pending_node_choice_result()
	if _snapshot == null or result == null:
		return RunPresentationResult.failure(
			DiagnosticError.new(
				RunScreenPresenter.ACTION_NOT_AVAILABLE,
				&"error.presentation.action_not_available"
			)
		)
	return request(_node_choice_ack_intent(_snapshot, result))


func confirm_selection() -> RunPresentationResult:
	if _selected_node_id.is_empty():
		return RunPresentationResult.failure(
			DiagnosticError.new(
				&"RUN_MAP_NODE_SELECTION_UNAVAILABLE",
				&"error.presentation.run_map_node_selection_unavailable"
			)
		)
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.ENTER_NODE
	)
	intent.target_node_id = _selected_node_id
	return request(intent)


func _build_node_selector() -> void:
	var existing := find_child("NodeSelector", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_node_selector = ItemList.new()
	_node_selector.name = "NodeSelector"
	_node_selector.theme_type_variation = &"ExpeditionMapAccessibility"
	ExpeditionLayoutMetrics.set_min(
		_node_selector,
		0.0,
		ExpeditionLayoutMetrics.RUN_MAP_ACCESSIBILITY_MINIMUM_HEIGHT
	)
	_node_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node_selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_selector.focus_mode = Control.FOCUS_ALL
	_node_selector.select_mode = ItemList.SELECT_SINGLE
	_node_selector.set_meta(&"typed_choice_kind", &"map_node")
	_node_selector.set_meta(&"accessible_text", &"map.node_selector")
	if _snapshot != null and _snapshot.map != null:
		for node: MapNodeState in _snapshot.map.nodes:
			if node == null or node.node_id.is_empty():
				continue
			_node_selector.add_item(_node_selector_text(node))
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
	var channel := find_child("MapAccessibilityChannel", true, false) as VBoxContainer
	if channel != null:
		channel.add_child(_node_selector)
	else:
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
	if _map_graph != null:
		_map_graph.set_selected_node_id(_selected_node_id)
	_refresh_node_preview()
	_update_parent_action_state()


func _build_map_graph() -> void:
	var existing := find_child("RunMapNodeGraph", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_map_graph = RunMapNodeGraph.new()
	_map_graph.name = "RunMapNodeGraph"
	_map_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_graph.clip_contents = true
	_map_graph.mouse_filter = Control.MOUSE_FILTER_PASS
	ExpeditionLayoutMetrics.set_fixed_min(
		_map_graph,
		ExpeditionLayoutMetrics.RUN_MAP_GRAPH_MINIMUM.x,
		ExpeditionLayoutMetrics.RUN_MAP_GRAPH_MINIMUM.y
	)
	var center_host := _hud_shell.host(
		ProductionLayoutShell.REGION_CENTER
	) if _hud_shell != null else self
	center_host.add_child(_map_graph)
	_map_graph.bind(
		_snapshot.map if _snapshot != null else null,
		_selected_node_id,
		Callable(self, "_on_graph_node_selected"),
		Callable(self, "_localized_ui_text"),
		Callable(self, "_localized_content_text")
	)


func _on_graph_node_selected(node_id: String) -> void:
	if _node_selector == null:
		return
	for index: int in _node_selector.item_count:
		if (
			not _node_selector.is_item_disabled(index)
			and String(_node_selector.get_item_metadata(index)) == node_id
		):
			_node_selector.select(index)
			_on_node_selected(index)
			return


func _build_hud_shell(supply_port: LiveScreenSupplyPort = null) -> void:
	var existing := find_child("InRunHudShell", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_hud_shell = InRunHudShell.new()
	_hud_shell.name = "InRunHudShell"
	add_child(_hud_shell)
	_hud_shell.bind(
		_snapshot,
		&"RUN_MAP",
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
	preview.name = "NodePreview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview.add_child(_detail_label(
		&"map.select", _text_or_key(&"map.select")
	))
	var channel := VBoxContainer.new()
	channel.name = "MapAccessibilityChannel"
	channel.theme_type_variation = &"ExpeditionMapAccessibilityChannel"
	channel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	channel.add_child(preview)
	var selector_heading := Label.new()
	selector_heading.name = "MapAccessibilityHeading"
	selector_heading.theme_type_variation = &"ExpeditionMapActLabel"
	selector_heading.text = _text_or_key(&"map.select")
	channel.add_child(selector_heading)
	right_host.add_child(channel)


func _refresh_node_preview() -> void:
	if _hud_shell == null:
		return
	var preview := _hud_shell.find_child("NodePreview", true, false) as VBoxContainer
	if preview == null:
		return
	for child: Node in preview.get_children():
		preview.remove_child(child)
		child.free()
	var selected: MapNodeState
	if _snapshot != null and _snapshot.map != null:
		for node: MapNodeState in _snapshot.map.nodes:
			if node != null and node.node_id == _selected_node_id:
				selected = node
				break
	preview.add_child(_detail_label(
		&"map.select",
		_node_text(selected) if selected != null else _text_or_key(&"map.select")
	))


func _detail_label(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ExpeditionSection"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s\n%s" % [_text_or_key(key), value]
	return label


func _hud_region_rect(region: StringName) -> Rect2:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.layout_region_content_rect(region)
		if parent_screen != null
		else Rect2()
	)


func _localized_ui_text(key: StringName) -> String:
	return _text_or_key(key)


func _text_or_key(key: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_ui_text(key)
		if parent_screen != null
		else String(key)
	)


func _node_text(node: MapNodeState) -> String:
	return "%s · %s · %d-%d" % [
		_localized_content_text(node.def_id),
		_localized_node_kind_text(node.node_kind),
		node.act_index,
		node.layer_index,
	]


func _node_selector_text(node: MapNodeState) -> String:
	var state_signal := "×"
	if node.completed or _snapshot.map.completed_node_ids.has(node.node_id):
		state_signal = String(InRunHudShell.PROGRESS_STATE_SIGNALS[&"completed"])
	elif MapNodePresentation.is_reachable(_snapshot.map, node):
		state_signal = "‹ ›"
	var current_signal := (
		String(InRunHudShell.PROGRESS_STATE_SIGNALS[&"current"])
		if (
			_snapshot.map.current_node_id != null
			and _snapshot.map.current_node_id.value == node.node_id
		)
		else ""
	)
	var kind_signal := String(
		InRunHudShell.NODE_KIND_SIGNALS.get(
			MapNodeState.node_kind_to_token(node.node_kind),
			"?"
		)
	)
	return "%s %s %s  %s" % [
		current_signal,
		state_signal,
		kind_signal,
		_node_text(node),
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

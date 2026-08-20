class_name RunMapNodeGraph
extends Control

## C-1 的地圖是決策介面，不是世界模擬：節點座標只由 act/layer/slot
## 投影到 UI reference 空間，canonical 合法性仍由 ENTER_NODE command 裁決。

const MAP_VISUAL_ID: StringName = &"environment.run_map"
const STATE_COMPLETED: StringName = &"completed"
const STATE_REACHABLE: StringName = &"reachable"
const STATE_UNREACHABLE: StringName = &"unreachable"
const EDGE_BACKGROUND: StringName = &"background"
const EDGE_TRAVERSED: StringName = &"traversed"
const EDGE_FRONTIER: StringName = &"frontier"

var _map: MapState
var _selected_node_id: String = ""
var _on_select: Callable
var _ui_text: Callable
var _content_text: Callable
var _buttons: Dictionary = {}
var _markers: Dictionary = {}
var _focus_frames: Dictionary = {}
var _states: Dictionary = {}
var _node_centers: Dictionary = {}
var _layout_order: Array[String] = []
var _edge_segments: Array[Dictionary] = []
var _hovered_node_id: String = ""
var _environment_visuals := ProductionEnvironmentVisualCatalog.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_graph()
	elif what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func bind(
	map: MapState,
	selected_node_id: String,
	on_select: Callable,
	ui_text: Callable,
	content_text: Callable
) -> void:
	_map = map.deep_clone() if map != null else null
	_selected_node_id = selected_node_id
	_on_select = on_select
	_ui_text = ui_text
	_content_text = content_text
	_rebuild()


func set_selected_node_id(node_id: String) -> void:
	_selected_node_id = node_id
	for key: Variant in _focus_frames:
		var frame := _focus_frames[key] as Panel
		if frame != null:
			frame.visible = String(key) == node_id
	queue_redraw()


func selected_node_id() -> String:
	return _selected_node_id


func node_button(node_id: String) -> RunMapNodeTarget:
	return _buttons.get(node_id) as RunMapNodeTarget


func node_position(node_id: String) -> Vector2:
	return _node_centers.get(node_id, Vector2.ZERO) as Vector2


func node_ids_in_layout_order() -> Array[String]:
	var result: Array[String] = []
	result.assign(_layout_order)
	return result


func edge_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for segment: Dictionary in _edge_segments:
		result.append(segment.duplicate(true))
	return result


func state_for(node_id: String) -> StringName:
	return StringName(_states.get(node_id, STATE_UNREACHABLE))


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_buttons.clear()
	_markers.clear()
	_focus_frames.clear()
	_states.clear()
	_node_centers.clear()
	_layout_order.clear()
	_edge_segments.clear()
	_build_background()
	_build_act_labels()
	if _map == null:
		queue_redraw()
		return
	var nodes: Array[MapNodeState] = []
	for node: MapNodeState in _map.nodes:
		if node != null and not node.node_id.is_empty():
			nodes.append(node)
	nodes.sort_custom(_node_precedes)
	for node: MapNodeState in nodes:
		_add_node(node)
	_layout_graph()
	queue_redraw()


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "RunMapEnvironmentTexture"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = _environment_visuals.try_texture(MAP_VISUAL_ID)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.modulate.a = 0.58
	background.set_meta(&"visual_id", MAP_VISUAL_ID)
	add_child(background)


func _build_act_labels() -> void:
	for act_index: int in range(1, 4):
		var label := Label.new()
		label.name = "ActLabel%d" % act_index
		label.theme_type_variation = &"ExpeditionMapActLabel"
		label.text = _localized(StringName("map.act.%d.title" % act_index))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_meta(&"act_index", act_index)
		add_child(label)


func _add_node(node: MapNodeState) -> void:
	var state := _node_state(node)
	_states[node.node_id] = state
	_layout_order.append(node.node_id)
	var button := RunMapNodeTarget.new()
	button.name = "MapNode_%s" % node.node_id
	ExpeditionLayoutMetrics.set_fixed_min(
		button,
		ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE.x,
		ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE.y
	)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.disabled = state != STATE_REACHABLE
	button.text = _signal_text(node, state)
	button.modulate.a = (
		ExpeditionLayoutMetrics.RUN_MAP_UNREACHABLE_ALPHA
		if state == STATE_UNREACHABLE else 1.0
	)
	button.tooltip_text = _accessible_node_text(node, state)
	button.set_meta(&"typed_choice_kind", &"map_node_graph")
	button.set_meta(&"node_id", node.node_id)
	button.set_meta(&"act_index", node.act_index)
	button.set_meta(&"layer_index", node.layer_index)
	button.set_meta(&"slot_index", node.slot_index)
	button.set_meta(&"node_kind_signal", _kind_signal(node))
	button.set_meta(&"node_state", state)
	button.set_meta(&"node_state_signal", _state_signal(state))
	button.set_meta(&"current_marker", _is_current(node.node_id))
	button.set_meta(&"accessible_text", _accessible_node_text(node, state))
	button.pressed.connect(_select_node.bind(node.node_id))
	button.mouse_entered.connect(_set_hovered.bind(node.node_id))
	button.mouse_exited.connect(_clear_hovered.bind(node.node_id))
	add_child(button)
	_buttons[node.node_id] = button

	var focus_frame := Panel.new()
	focus_frame.name = "Selection_%s" % node.node_id
	focus_frame.theme_type_variation = &"ExpeditionFocus"
	focus_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_frame.visible = node.node_id == _selected_node_id
	add_child(focus_frame)
	_focus_frames[node.node_id] = focus_frame

	if _is_current(node.node_id):
		var marker := Label.new()
		marker.name = "Current_%s" % node.node_id
		marker.theme_type_variation = &"ExpeditionMapCurrentMarker"
		marker.text = InRunHudShell.PROGRESS_STATE_SIGNALS[&"current"]
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.set_meta(&"node_id", node.node_id)
		marker.set_meta(&"state_signal", &"current")
		add_child(marker)
		_markers[node.node_id] = marker


func _layout_graph() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var gap := ExpeditionLayoutMetrics.RUN_MAP_ACT_GAP
	var act_height := (size.y - gap * 2.0) / 3.0
	var usable_width := maxf(
		size.x - ExpeditionLayoutMetrics.RUN_MAP_HORIZONTAL_INSET * 2.0,
		1.0
	)
	var layer_step := usable_width / float(
		ExpeditionLayoutMetrics.RUN_MAP_LAYER_COUNT - 1
	)
	for act_index: int in range(1, 4):
		var act_label := get_node_or_null("ActLabel%d" % act_index) as Label
		if act_label != null:
			act_label.position = Vector2(
				ExpeditionLayoutMetrics.RUN_MAP_STATE_FRAME_INSET,
				float(act_index - 1) * (act_height + gap)
			)
			act_label.size = Vector2(
				ExpeditionLayoutMetrics.RUN_MAP_HORIZONTAL_INSET,
				ExpeditionLayoutMetrics.RUN_MAP_ACT_HEADER_HEIGHT
			)
	_node_centers.clear()
	for node_id: String in _layout_order:
		var button := _buttons.get(node_id) as RunMapNodeTarget
		var node := _node_by_id(node_id)
		if button == null or node == null:
			continue
		var act_zero := clampi(node.act_index, 1, 3) - 1
		var act_top := float(act_zero) * (act_height + gap)
		var slot_area_height := maxf(
			act_height - ExpeditionLayoutMetrics.RUN_MAP_ACT_HEADER_HEIGHT,
			1.0
		)
		var slot_travel := maxf(
			slot_area_height - ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE.y,
			0.0
		)
		var slot_step := slot_travel / float(
			ExpeditionLayoutMetrics.RUN_MAP_SLOT_COUNT - 1
		)
		var center := Vector2(
			ExpeditionLayoutMetrics.RUN_MAP_HORIZONTAL_INSET
				+ float(clampi(node.layer_index, 0, 6)) * layer_step,
			act_top + ExpeditionLayoutMetrics.RUN_MAP_ACT_HEADER_HEIGHT
				+ ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE.y * 0.5
				+ float(clampi(node.slot_index, 0, 2)) * slot_step
		)
		_node_centers[node_id] = center
		button.position = center - ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE * 0.5
		button.size = ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE
		var focus_frame := _focus_frames.get(node_id) as Panel
		if focus_frame != null:
			var focus_size := ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE + Vector2.ONE \
				* ExpeditionLayoutMetrics.RUN_MAP_SELECTED_FRAME_INSET * 2.0
			focus_frame.position = center - focus_size * 0.5
			focus_frame.size = focus_size
		var marker := _markers.get(node_id) as Label
		if marker != null:
			marker.position = Vector2(
				button.position.x - ExpeditionLayoutMetrics.RUN_MAP_CURRENT_MARKER_WIDTH,
				button.position.y
			)
			marker.size = Vector2(
				ExpeditionLayoutMetrics.RUN_MAP_CURRENT_MARKER_WIDTH,
				ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE.y
			)
	_rebuild_edge_segments()
	queue_redraw()


func _rebuild_edge_segments() -> void:
	_edge_segments.clear()
	if _map == null:
		return
	for edge: MapEdgeState in _map.edges:
		if (
			edge == null
			or not _node_centers.has(edge.from_node_id)
			or not _node_centers.has(edge.to_node_id)
		):
			continue
		var weight := _edge_weight(edge)
		_edge_segments.append({
			"from_node_id": edge.from_node_id,
			"to_node_id": edge.to_node_id,
			"from": _node_centers[edge.from_node_id],
			"to": _node_centers[edge.to_node_id],
			"weight": weight,
			"frontier": weight == EDGE_FRONTIER,
		})


func _edge_weight(edge: MapEdgeState) -> StringName:
	if (
		_is_current(edge.from_node_id)
		and state_for(edge.to_node_id) == STATE_REACHABLE
	):
		return EDGE_FRONTIER
	if (
		state_for(edge.from_node_id) == STATE_COMPLETED
		and (
			state_for(edge.to_node_id) == STATE_COMPLETED
			or _is_current(edge.to_node_id)
		)
	):
		return EDGE_TRAVERSED
	return EDGE_BACKGROUND


func _draw() -> void:
	var stone := get_theme_color(&"stone_500", &"ExpeditionPalette")
	var parchment := get_theme_color(&"parchment_300", &"ExpeditionPalette")
	var focus := get_theme_color(&"focus_high", &"ExpeditionPalette")
	var teal := get_theme_color(&"teal_500", &"ExpeditionPalette")
	stone.a = 0.42
	for act_index: int in range(1, 3):
		var y := float(act_index) * (size.y - ExpeditionLayoutMetrics.RUN_MAP_ACT_GAP * 2.0) / 3.0 \
			+ float(act_index - 1) * ExpeditionLayoutMetrics.RUN_MAP_ACT_GAP
		draw_dashed_line(
			Vector2(0.0, y), Vector2(size.x, y), stone,
			ExpeditionLayoutMetrics.RUN_MAP_SEPARATOR_WIDTH,
			ExpeditionLayoutMetrics.RUN_MAP_DASH_LENGTH
		)
	var background_edge := stone
	background_edge.a = ExpeditionLayoutMetrics.RUN_MAP_EDGE_BACKGROUND_ALPHA
	var traversed_edge := parchment
	traversed_edge.a = ExpeditionLayoutMetrics.RUN_MAP_EDGE_TRAVERSED_ALPHA
	var frontier_edge := teal
	frontier_edge.a = ExpeditionLayoutMetrics.RUN_MAP_EDGE_FRONTIER_ALPHA
	for weight: StringName in [EDGE_BACKGROUND, EDGE_TRAVERSED, EDGE_FRONTIER]:
		for segment: Dictionary in _edge_segments:
			if StringName(segment["weight"]) != weight:
				continue
			var color := background_edge
			var width := ExpeditionLayoutMetrics.RUN_MAP_EDGE_BACKGROUND_WIDTH
			if weight == EDGE_TRAVERSED:
				color = traversed_edge
				width = ExpeditionLayoutMetrics.RUN_MAP_EDGE_TRAVERSED_WIDTH
			elif weight == EDGE_FRONTIER:
				color = frontier_edge
				width = ExpeditionLayoutMetrics.RUN_MAP_EDGE_FRONTIER_WIDTH
			draw_line(segment["from"], segment["to"], color, width, true)
	for node_id: String in _layout_order:
		if not _node_centers.has(node_id):
			continue
		var rect := Rect2(
			_node_centers[node_id] - ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE * 0.5,
			ExpeditionLayoutMetrics.RUN_MAP_NODE_SIZE
		).grow(ExpeditionLayoutMetrics.RUN_MAP_STATE_FRAME_INSET)
		var state := state_for(node_id)
		if state == STATE_COMPLETED:
			draw_rect(rect, parchment, false, 2.0)
		elif state == STATE_REACHABLE:
			draw_rect(rect, teal, false, 2.0)
			draw_rect(rect.grow(3.0), teal, false, 1.0)
		if node_id == _hovered_node_id and state == STATE_REACHABLE:
			draw_rect(rect.grow(5.0), focus, false, 1.0)


func _select_node(node_id: String) -> void:
	if state_for(node_id) != STATE_REACHABLE:
		return
	set_selected_node_id(node_id)
	if _on_select.is_valid():
		_on_select.call(node_id)


func _set_hovered(node_id: String) -> void:
	_hovered_node_id = node_id
	queue_redraw()


func _clear_hovered(node_id: String) -> void:
	if _hovered_node_id == node_id:
		_hovered_node_id = ""
		queue_redraw()


func _node_state(node: MapNodeState) -> StringName:
	if node.completed or (_map != null and _map.completed_node_ids.has(node.node_id)):
		return STATE_COMPLETED
	if MapNodePresentation.is_reachable(_map, node):
		return STATE_REACHABLE
	return STATE_UNREACHABLE


func _signal_text(node: MapNodeState, state: StringName) -> String:
	var kind_signal := _kind_signal(node)
	if state == STATE_COMPLETED:
		return "%s %s" % [
			InRunHudShell.PROGRESS_STATE_SIGNALS[&"completed"], kind_signal
		]
	if state == STATE_REACHABLE:
		return "‹ %s ›" % kind_signal
	return kind_signal


func _state_signal(state: StringName) -> String:
	if state == STATE_COMPLETED:
		return String(InRunHudShell.PROGRESS_STATE_SIGNALS[&"completed"])
	if state == STATE_REACHABLE:
		return "‹ ›"
	return "×"


func _kind_signal(node: MapNodeState) -> String:
	return String(InRunHudShell.NODE_KIND_SIGNALS.get(
		MapNodeState.node_kind_to_token(node.node_kind),
		"?"
	))


func _accessible_node_text(node: MapNodeState, state: StringName) -> String:
	var state_key := &"map.select"
	if state == STATE_COMPLETED:
		state_key = &"map.node_state.completed"
	elif state == STATE_UNREACHABLE:
		state_key = &"map.node_state.unreached"
	var kind_key := StringName(
		"map.node_kind.%s" % String(MapNodeState.node_kind_to_token(node.node_kind))
	)
	return "%s · %s · %s %s · %d-%d" % [
		_localized_content(node.def_id),
		_localized(kind_key),
		_state_signal(state),
		_localized(state_key),
		node.act_index,
		node.layer_index,
	]


func _is_current(node_id: String) -> bool:
	return (
		_map != null
		and _map.current_node_id != null
		and _map.current_node_id.value == node_id
	)


func _node_by_id(node_id: String) -> MapNodeState:
	if _map == null:
		return null
	for node: MapNodeState in _map.nodes:
		if node != null and node.node_id == node_id:
			return node
	return null


func _node_precedes(left: MapNodeState, right: MapNodeState) -> bool:
	if left.act_index != right.act_index:
		return left.act_index < right.act_index
	if left.layer_index != right.layer_index:
		return left.layer_index < right.layer_index
	if left.slot_index != right.slot_index:
		return left.slot_index < right.slot_index
	return left.node_id < right.node_id


func _localized(key: StringName) -> String:
	return String(_ui_text.call(key)) if _ui_text.is_valid() else String(key)


func _localized_content(key: StringName) -> String:
	return String(_content_text.call(key)) if _content_text.is_valid() else String(key)

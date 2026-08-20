extends GutTest

const PROVENANCE_PATH := \
	"res://assets/production/provenance/run_map_environment.json"
const RUN_MAP_PATH := "res://assets/production/environment/run_map.png"
const RUN_MAP_SHA := \
	"70476ec7524fd444a3ff4b47feb19def7af98681d8f240f19dc86fcde8064656"

var _selected_from_graph: String = ""


class CapturingIntentPort:
	extends LiveScreenIntentPort

	var intents: Array[RunPresentationIntent] = []
	var snapshot: RunPresentationSnapshot
	var reject_next: bool = false


	func _init(value: RunPresentationSnapshot) -> void:
		snapshot = value.deep_clone()


	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		intents.append(intent.deep_clone())
		if reject_next:
			reject_next = false
			return RunPresentationResult.failure(DiagnosticError.new(
				&"C1_DOMAIN_REJECTED",
				&"error.presentation.action_not_available"
			))
		return RunPresentationResult.success(snapshot)


func test_three_acts_seven_layers_edges_and_sorting_are_deterministic() -> void:
	var graph := _graph(_map_fixture())
	await get_tree().process_frame
	var order := graph.node_ids_in_layout_order()
	assert_eq(order.front(), "a1_l0_s0")
	assert_eq(order.back(), "a3_l6_s0")
	assert_eq(order.size(), 22)
	assert_eq(graph.edge_segments().size(), 21)
	var edge_weights := {
		RunMapNodeGraph.EDGE_BACKGROUND: 0,
		RunMapNodeGraph.EDGE_TRAVERSED: 0,
		RunMapNodeGraph.EDGE_FRONTIER: 0,
	}
	for edge: Dictionary in graph.edge_segments():
		var weight := StringName(edge["weight"])
		edge_weights[weight] = int(edge_weights.get(weight, 0)) + 1
	assert_eq(edge_weights[RunMapNodeGraph.EDGE_TRAVERSED], 1)
	assert_eq(edge_weights[RunMapNodeGraph.EDGE_FRONTIER], 2)
	assert_eq(edge_weights[RunMapNodeGraph.EDGE_BACKGROUND], 18)
	for act_index: int in range(1, 4):
		var act_label := graph.get_node_or_null("ActLabel%d" % act_index) as Label
		assert_not_null(act_label)
		if act_label != null:
			assert_eq(act_label.text, "map.act.%d.title" % act_index)
		var previous_x := -INF
		for layer_index: int in range(7):
			var node_id := "a%d_l%d_s0" % [act_index, layer_index]
			var position := graph.node_position(node_id)
			assert_gt(position.x, previous_x)
			previous_x = position.x
	assert_lt(
		graph.node_position("a1_l0_s0").y,
		graph.node_position("a2_l0_s0").y
	)
	assert_lt(
		graph.node_position("a2_l0_s0").y,
		graph.node_position("a3_l0_s0").y
	)
	graph.queue_free()


func test_node_kinds_states_and_current_marker_have_non_color_signals() -> void:
	var graph := _graph(_map_fixture())
	await get_tree().process_frame
	var kind_signals: Dictionary = {}
	for layer_index: int in range(7):
		var button := graph.node_button("a1_l%d_s0" % layer_index)
		assert_not_null(button)
		if button != null:
			kind_signals[String(button.get_meta(&"node_kind_signal"))] = true
	assert_eq(kind_signals.size(), 7)
	assert_eq(graph.state_for("a1_l0_s0"), RunMapNodeGraph.STATE_COMPLETED)
	assert_string_contains(graph.node_button("a1_l0_s0").text, "✓")
	assert_eq(graph.state_for("a1_l2_s0"), RunMapNodeGraph.STATE_REACHABLE)
	assert_string_contains(graph.node_button("a1_l2_s0").text, "‹")
	assert_string_contains(graph.node_button("a1_l2_s0").text, "›")
	assert_eq(graph.state_for("a1_l3_s0"), RunMapNodeGraph.STATE_UNREACHABLE)
	assert_false(graph.node_button("a1_l3_s0").text.contains("×"))
	assert_lt(graph.node_button("a1_l3_s0").modulate.a, 1.0)
	assert_string_contains(
		String(graph.node_button("a1_l3_s0").get_meta(&"accessible_text")),
		"×"
	)
	var current_marker := graph.get_node_or_null("Current_a1_l1_s0") as Label
	assert_not_null(current_marker)
	if current_marker != null:
		assert_eq(
			current_marker.text,
			String(InRunHudShell.PROGRESS_STATE_SIGNALS[&"current"])
		)
	graph.queue_free()


func test_graph_click_is_local_preview_and_item_list_stays_in_sync() -> void:
	var snapshot := _snapshot(_map_fixture())
	var port := CapturingIntentPort.new(snapshot)
	var screen := RunMapScreen.new()
	add_child_autoqfree(screen)
	assert_eq(screen.compose(snapshot, port), &"")
	var graph := screen.find_child("RunMapNodeGraph", true, false) as RunMapNodeGraph
	var list := screen.find_child("NodeSelector", true, false) as ItemList
	assert_not_null(graph)
	assert_not_null(list)
	assert_eq(port.intents.size(), 0)
	graph.node_button("a1_l2_s1").emit_signal(&"pressed")
	assert_eq(screen.selected_node_id(), "a1_l2_s1")
	assert_eq(port.intents.size(), 0, "map.select must not dispatch canonical state")
	var selected_rows := list.get_selected_items()
	assert_eq(selected_rows.size(), 1)
	if selected_rows.size() == 1:
		assert_eq(
			String(list.get_item_metadata(selected_rows[0])),
			"a1_l2_s1"
		)
	var result := screen.confirm_selection()
	assert_true(result.ok)
	assert_eq(port.intents.size(), 1)
	assert_eq(port.intents[0].kind, RunPresentationIntent.Kind.ENTER_NODE)
	assert_eq(port.intents[0].target_node_id, "a1_l2_s1")


func test_unreachable_and_completed_nodes_cannot_submit_and_rejection_surfaces() -> void:
	var graph := _graph(_map_fixture())
	await get_tree().process_frame
	graph.node_button("a1_l0_s0").emit_signal(&"pressed")
	assert_eq(graph.selected_node_id(), "")
	graph.node_button("a1_l3_s0").emit_signal(&"pressed")
	assert_eq(graph.selected_node_id(), "")
	graph.queue_free()

	var snapshot := _snapshot(_map_fixture())
	var port := CapturingIntentPort.new(snapshot)
	port.reject_next = true
	var screen := RunMapScreen.new()
	add_child_autoqfree(screen)
	assert_eq(screen.compose(snapshot, port), &"")
	var result := screen.confirm_selection()
	assert_false(result.ok)
	assert_not_null(result.error)
	if result.error != null:
		assert_eq(result.error.code, &"C1_DOMAIN_REJECTED")
	assert_eq(port.intents.size(), 1)


func test_keyboard_channel_order_is_unchanged() -> void:
	assert_eq(
		KeyboardFocusGraph.new().focus_order(&"RUN_MAP", 150, []),
		[&"map.select", &"map.confirm", &"choice.ack"]
	)


func test_background_provenance_sha_and_dimensions_match_selected_source() -> void:
	var provenance: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PROVENANCE_PATH)
	)
	assert_true(provenance is Dictionary)
	if not provenance is Dictionary:
		return
	var document := provenance as Dictionary
	assert_eq(String(document.get("asset_id", "")), "environment.run_map")
	assert_eq(
		String((document.get("output", {}) as Dictionary).get("sha256", "")),
		RUN_MAP_SHA
	)
	assert_eq(FileAccess.get_sha256(RUN_MAP_PATH), RUN_MAP_SHA)
	var texture := load(RUN_MAP_PATH) as Texture2D
	assert_not_null(texture)
	if texture != null:
		assert_eq(texture.get_size(), Vector2(1672.0, 941.0))
	var selection := document.get("selection", {}) as Dictionary
	assert_eq(int(selection.get("candidate_count", 0)), 2)
	assert_false(bool(selection.get("pending_user_visual_approval", true)))


func _graph(map: MapState) -> RunMapNodeGraph:
	var graph := RunMapNodeGraph.new()
	graph.size = Vector2(840.0, 420.0)
	add_child(graph)
	graph.bind(
		map,
		"",
		Callable(self, "_capture_selected"),
		Callable(self, "_identity_text"),
		Callable(self, "_identity_text")
	)
	return graph


func _capture_selected(node_id: String) -> void:
	_selected_from_graph = node_id


func _identity_text(key: StringName) -> String:
	return String(key)


func _snapshot(map: MapState) -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.app_phase = &"MAP"
	snapshot.map = map.deep_clone()
	return snapshot


func _map_fixture() -> MapState:
	var nodes: Array[MapNodeState] = []
	var edges: Array[MapEdgeState] = []
	for act_index: int in range(1, 4):
		for layer_index: int in range(7):
			var node_id := "a%d_l%d_s0" % [act_index, layer_index]
			nodes.append(_node(
				node_id,
				act_index,
				layer_index,
				0,
				layer_index % 7,
				node_id in ["a1_l0_s0", "a1_l1_s0"]
			))
			if layer_index > 0:
				edges.append(MapEdgeState.new(
					"a%d_l%d_s0" % [act_index, layer_index - 1], node_id
				))
		if act_index < 3:
			edges.append(MapEdgeState.new(
				"a%d_l6_s0" % act_index,
				"a%d_l0_s0" % (act_index + 1)
			))
	var branch := _node(
		"a1_l2_s1", 1, 2, 1, MapNodeState.NodeKind.EVENT, false
	)
	nodes.append(branch)
	edges.append(MapEdgeState.new("a1_l1_s0", branch.node_id))
	var completed: Array[String] = ["a1_l0_s0", "a1_l1_s0"]
	return MapState.new(
		nodes,
		edges,
		OptionalStringValue.new("a1_l1_s0"),
		completed
	)


func _node(
	node_id: String,
	act_index: int,
	layer_index: int,
	slot_index: int,
	kind: MapNodeState.NodeKind,
	completed: bool
) -> MapNodeState:
	var token := MapNodeState.node_kind_to_token(kind)
	var key := NodeKeyState.create(
		&"run.c1", act_index, token, layer_index, slot_index,
		StringName("digest.%s" % node_id)
	)
	return MapNodeState.new(
		node_id,
		key,
		StringName("map_node.%s" % String(token)),
		act_index,
		layer_index,
		slot_index,
		kind,
		"payload.%s" % node_id,
		null,
		completed
	)

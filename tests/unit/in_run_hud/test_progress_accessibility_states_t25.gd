extends GutTest


func test_progress_accessibility_copy_localizes_all_three_node_states() -> void:
	var snapshot := _snapshot()
	var shell := InRunHudShell.new()
	add_child_autofree(shell)
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, &"_region_rect"),
		Callable(self, &"_ui_text"),
		Callable(self, &"_content_text")
	), &"")
	var sequence := shell.find_child("RunNodeSequence", true, false) as Label
	assert_not_null(sequence)
	if sequence == null:
		return
	assert_eq(
		sequence.get_meta(&"state_localization_keys"),
		[
			&"map.node_state.completed",
			&"map.node_state.current",
			&"map.node_state.unreached",
		]
	)
	assert_true(sequence.tooltip_text.contains("已完成"))
	assert_true(sequence.tooltip_text.contains("目前所在"))
	assert_true(sequence.tooltip_text.contains("未到達"))
	assert_eq(sequence.get_meta(&"accessible_text"), sequence.tooltip_text)


func _snapshot() -> RunPresentationSnapshot:
	var current_id := "node.current"
	var nodes: Array[MapNodeState] = [
		_node("node.completed", 0, MapNodeState.NodeKind.NORMAL, true),
		_node(current_id, 1, MapNodeState.NodeKind.ELITE, false),
		_node("node.upcoming", 2, MapNodeState.NodeKind.MERCHANT, false),
	]
	var run := SaveRootFixture.create_valid_root().run
	run.current_node_id = OptionalStringValue.new(current_id)
	var result := RunPresentationSnapshot.new()
	result.run_id = StringName(run.run_id)
	result.app_phase = &"PREPARE"
	result.view = RunViewState.from_run(run, U64Bits.zero())
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = ["node.completed"]
	result.map = MapState.new(
		nodes,
		edges,
		OptionalStringValue.new(current_id),
		completed
	)
	return result


func _node(
	node_id: String,
	layer_index: int,
	kind: MapNodeState.NodeKind,
	completed: bool
) -> MapNodeState:
	var key := NodeKeyState.create(
		&"run.t25.accessibility",
		1,
		MapNodeState.node_kind_to_token(kind),
		layer_index,
		0,
		"digest.%s" % node_id
	)
	return MapNodeState.new(
		node_id,
		key,
		StringName(node_id),
		1,
		layer_index,
		0,
		kind,
		"payload.%s" % node_id,
		null,
		completed
	)


func _region_rect(_region: StringName) -> Rect2:
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _ui_text(key: StringName) -> String:
	return {
		&"prepare.panel.expedition": "遠征",
		&"prepare.resource.hp": "遠征生命",
		&"combat.inspection.none": "無",
		&"map.node_state.completed": "已完成",
		&"map.node_state.current": "目前所在",
		&"map.node_state.unreached": "未到達",
		&"map.node_kind.normal": "一般戰鬥",
		&"map.node_kind.elite": "菁英戰鬥",
		&"map.node_kind.merchant": "商人",
	}.get(key, String(key))


func _content_text(key: StringName) -> String:
	return {
		&"node.completed": "完成節點",
		&"node.current": "目前節點",
		&"node.upcoming": "未到節點",
	}.get(key, String(key))

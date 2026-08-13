extends GutTest

const CURRENT_ID := "node.current"


func test_sequence_uses_explicit_coordinate_and_state_order() -> void:
	var snapshot := _three_node_snapshot()
	var shell := _bound_shell(snapshot)
	var sequence := shell.find_child("RunNodeSequence", true, false) as Label
	var tracker := shell.find_child("RunProgressTracker", true, false) as Label

	assert_not_null(sequence)
	assert_not_null(tracker)
	assert_eq(
		sequence.get_meta(&"progress_states"),
		[&"completed", &"current", &"unreached"]
	)
	assert_eq(sequence.text, "✓●  ▶▲  ○■")
	assert_true(tracker.text.contains("遠征 · 1 / 2 · 當前節點"))
	assert_true(sequence.tooltip_text.contains("一般戰鬥"))
	assert_true(sequence.tooltip_text.contains("菁英戰鬥"))
	assert_true(sequence.tooltip_text.contains("商人"))


func test_each_node_kind_has_a_distinct_non_color_signal() -> void:
	var nodes: Array[MapNodeState] = []
	for kind: MapNodeState.NodeKind in [
		MapNodeState.NodeKind.NORMAL,
		MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.MERCHANT,
		MapNodeState.NodeKind.EVENT,
		MapNodeState.NodeKind.REST,
		MapNodeState.NodeKind.TREASURE,
		MapNodeState.NodeKind.BOSS,
	]:
		var index := nodes.size()
		nodes.append(_node("node.%d" % index, index, kind, false))
	var snapshot := _snapshot(nodes, "node.0", [], 0, 37)
	var shell := _bound_shell(snapshot)
	var sequence := shell.find_child("RunNodeSequence", true, false) as Label
	var signals: Array = sequence.get_meta(&"kind_signals")
	var unique: Dictionary = {}
	for signal_value: String in signals:
		unique[signal_value] = true

	assert_eq(signals.size(), 7)
	assert_eq(unique.size(), 7, "node kinds must remain distinguishable without color")
	assert_eq(
		sequence.get_meta(&"node_kinds"),
		[&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]
	)


func test_missing_or_mismatched_typed_data_fails_closed() -> void:
	var empty_shell := _bound_shell(RunPresentationSnapshot.new())
	var empty_tracker := empty_shell.find_child(
		"RunProgressTracker", true, false
	) as Label
	var empty_sequence := empty_shell.find_child(
		"RunNodeSequence", true, false
	) as Label
	var empty_hp := empty_shell.find_child("ExpeditionHpValue", true, false) as Label
	assert_eq(empty_tracker.text, "遠征 · 無")
	assert_eq(empty_sequence.text, "無")
	assert_eq(empty_hp.text, "遠征生命  無")

	var mismatched := _three_node_snapshot()
	mismatched.map.current_node_id = OptionalStringValue.new("node.upcoming")
	var mismatch_shell := _bound_shell(mismatched)
	var mismatch_tracker := mismatch_shell.find_child(
		"RunProgressTracker", true, false
	) as Label
	var mismatch_sequence := mismatch_shell.find_child(
		"RunNodeSequence", true, false
	) as Label
	assert_eq(mismatch_tracker.text, "遠征 · 無")
	assert_false(
		(mismatch_sequence.get_meta(&"progress_states") as Array).has(&"current")
	)


func test_transition_banner_is_large_and_never_blocks_input() -> void:
	var snapshot := _three_node_snapshot()
	snapshot.progress_act_transitioned = true
	snapshot.progress_node_transitioned = true
	var shell := _bound_shell(snapshot)
	var banner := shell.find_child("RunTransitionBanner", true, false) as Label
	var overlay := shell.host(ProductionLayoutShell.REGION_OVERLAY)

	assert_not_null(banner)
	assert_eq(banner.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gte(banner.custom_minimum_size.x, 900.0)
	assert_gte(banner.custom_minimum_size.y, 144.0)
	assert_true(banner.text.contains("當前節點"))


func test_detached_bind_arms_banner_timer_after_entering_tree() -> void:
	var snapshot := _three_node_snapshot()
	snapshot.progress_node_transitioned = true
	var shell := InRunHudShell.new()
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, "_region_rect"),
		Callable(self, "_ui_text"),
		Callable(self, "_content_text")
	), &"")
	var banner := shell.find_child("RunTransitionBanner", true, false) as Label
	assert_not_null(banner)
	assert_false(bool(banner.get_meta(&"hide_timer_armed", false)))

	add_child_autofree(shell)
	await get_tree().process_frame
	assert_true(bool(banner.get_meta(&"hide_timer_armed", false)))
	assert_true(banner.visible)
	await get_tree().create_timer(0.80).timeout
	assert_false(banner.visible)


func test_bind_and_snapshot_clone_isolate_progress_source() -> void:
	var source := _three_node_snapshot()
	source.progress_node_transitioned = true
	var shell := _bound_shell(source)
	source.view.expedition_hp = 1
	source.map.nodes[1].node_kind = MapNodeState.NodeKind.BOSS
	source.progress_node_transitioned = false

	var first := shell.snapshot_clone()
	assert_eq(first.view.expedition_hp, 37)
	assert_eq(first.map.nodes[1].node_kind, MapNodeState.NodeKind.ELITE)
	assert_true(first.progress_node_transitioned)
	first.view.expedition_hp = 2
	first.map.nodes[1].node_kind = MapNodeState.NodeKind.REST
	first.progress_node_transitioned = false

	var second := shell.snapshot_clone()
	assert_eq(second.view.expedition_hp, 37)
	assert_eq(second.map.nodes[1].node_kind, MapNodeState.NodeKind.ELITE)
	assert_true(second.progress_node_transitioned)


func _three_node_snapshot() -> RunPresentationSnapshot:
	var nodes: Array[MapNodeState] = [
		_node("node.upcoming", 2, MapNodeState.NodeKind.MERCHANT, false),
		_node(CURRENT_ID, 1, MapNodeState.NodeKind.ELITE, false),
		_node("node.completed", 0, MapNodeState.NodeKind.NORMAL, true),
	]
	var completed: Array[String] = ["node.completed"]
	return _snapshot(nodes, CURRENT_ID, completed, 0, 37)


func _snapshot(
	nodes: Array[MapNodeState],
	current_node_id: String,
	completed: Array[String],
	act_index: int,
	hp: int
) -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	var run := SaveRootFixture.create_valid_root().run
	run.act_index = act_index
	run.expedition_hp = hp
	run.current_node_id = OptionalStringValue.new(current_node_id)
	result.run_id = StringName(run.run_id)
	result.app_phase = &"PREPARE"
	result.view = RunViewState.from_run(run, U64Bits.zero())
	var edges: Array[MapEdgeState] = []
	result.map = MapState.new(
		nodes,
		edges,
		OptionalStringValue.new(current_node_id),
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
		&"run.t25", 1, MapNodeState.node_kind_to_token(kind), layer_index, 0,
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


func _bound_shell(snapshot: RunPresentationSnapshot) -> InRunHudShell:
	var shell := InRunHudShell.new()
	add_child_autofree(shell)
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, "_region_rect"),
		Callable(self, "_ui_text"),
		Callable(self, "_content_text")
	), &"")
	return shell


func _region_rect(_region: StringName) -> Rect2:
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _ui_text(key: StringName) -> String:
	return {
		&"prepare.panel.expedition": "遠征",
		&"prepare.resource.hp": "遠征生命",
		&"combat.inspection.none": "無",
		&"map.node_kind.normal": "一般戰鬥",
		&"map.node_kind.elite": "菁英戰鬥",
		&"map.node_kind.merchant": "商人",
		&"map.node_kind.event": "事件",
		&"map.node_kind.rest": "休息",
		&"map.node_kind.treasure": "寶藏",
		&"map.node_kind.boss": "首領",
	}.get(key, String(key))


func _content_text(key: StringName) -> String:
	return {
		&"node.completed": "已完成節點",
		&"node.current": "當前節點",
		&"node.upcoming": "未達節點",
	}.get(key, String(key))

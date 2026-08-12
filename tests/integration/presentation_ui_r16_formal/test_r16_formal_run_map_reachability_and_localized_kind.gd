extends GutTest

## G2 wave2-B M6 regression (fix/g2-ui-review-findings): the formal RUN_MAP
## composition rendered every node flat and only disabled `completed` ones, so
## unreachable-but-not-yet-completed nodes stayed selectable even though
## RunPresentationSession already carried a reachability rule
## (node_is_reachable, formerly _node_is_reachable) that the screen never
## used. This locks the fix: unreachable nodes must be disabled too, and node
## kind text must resolve through localization instead of the raw enum token.

const REACHABLE_NODE_ID := "node.reachable"
const UNREACHABLE_NODE_ID := "node.unreachable"


func test_run_map_disables_unreachable_nodes_and_localizes_kind_text() -> void:
	var snapshot := _fixture_snapshot()
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 4301)
	var session := RunPresentationSession.new()
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_MAP")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)

	var localized_text := {
		&"loc.map_node_test_reachable": "測試據點A",
		&"loc.map_node_test_unreachable": "測試據點B",
		&"map.node_kind.normal": "一般戰鬥",
		&"map.node_kind.elite": "菁英戰鬥",
	}
	var staged := StagedScreenContext.new(
		&"RUN_MAP", snapshot, null, &"zh_TW", localized_text
	)
	assert_eq(screen.bind(staged), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_MAP",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session)
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	add_child_autofree(screen)
	screen.activate_live()

	var composition := screen.get_node_or_null(^"Composition") as RunMapScreen
	assert_not_null(composition)
	if composition == null:
		return
	var selector := composition.find_child("NodeSelector", true, false) as ItemList
	assert_not_null(selector)
	if selector == null:
		return
	assert_eq(selector.item_count, 2)

	var reachable_index := -1
	var unreachable_index := -1
	for index: int in selector.item_count:
		match String(selector.get_item_metadata(index)):
			REACHABLE_NODE_ID:
				reachable_index = index
			UNREACHABLE_NODE_ID:
				unreachable_index = index
	assert_true(reachable_index >= 0, "reachable node must still be listed")
	assert_true(unreachable_index >= 0, "unreachable node must still be listed")

	assert_false(
		selector.is_item_disabled(reachable_index),
		"the act-1/layer-0 entry node must stay selectable"
	)
	assert_true(
		selector.is_item_disabled(unreachable_index),
		"a node with no edge from a completed node must be disabled, not just completed ones"
	)

	assert_string_contains(selector.get_item_text(reachable_index), "測試據點A")
	assert_string_contains(selector.get_item_text(reachable_index), "一般戰鬥")
	assert_false(selector.get_item_text(reachable_index).contains("normal"))

	assert_string_contains(selector.get_item_text(unreachable_index), "測試據點B")
	assert_string_contains(selector.get_item_text(unreachable_index), "菁英戰鬥")
	assert_false(selector.get_item_text(unreachable_index).contains("elite"))

	composition.call(&"_on_node_selected", unreachable_index)
	assert_eq(composition.selected_node_id(), "")
	var opened: Variant = composition.open_node_selection()
	assert_true(bool(opened.get("ok")))
	assert_eq(
		composition.selected_node_id(),
		REACHABLE_NODE_ID,
		"open-node fallback must skip unreachable nodes"
	)


func _fixture_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.run_id = &"run.g2.wave2b.map"
	snapshot.app_phase = &"MAP"
	snapshot.manifest_digest = "manifest.g2.wave2b.map"

	var reachable_key := NodeKeyState.create(
		snapshot.run_id, 1, &"normal", 0, 0, "digest.reachable"
	)
	var reachable_node := MapNodeState.new(
		REACHABLE_NODE_ID,
		reachable_key,
		&"map_node.test_reachable",
		1,
		0,
		0,
		MapNodeState.NodeKind.NORMAL,
		"payload.reachable",
		null,
		false
	)
	# Not connected by any edge and not the act-1/layer-0 entry node, so it
	# must stay unreachable even though nothing is completed yet.
	var unreachable_key := NodeKeyState.create(
		snapshot.run_id, 1, &"elite", 1, 0, "digest.unreachable"
	)
	var unreachable_node := MapNodeState.new(
		UNREACHABLE_NODE_ID,
		unreachable_key,
		&"map_node.test_unreachable",
		1,
		1,
		0,
		MapNodeState.NodeKind.ELITE,
		"payload.unreachable",
		null,
		false
	)
	var nodes: Array[MapNodeState] = [unreachable_node, reachable_node]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	snapshot.map = MapState.new(nodes, edges, null, completed)
	return snapshot

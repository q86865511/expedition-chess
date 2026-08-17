extends GutTest

## C-1 / BP-SI-003：「目前 frontier 可選節點」的權威查詢。
##
## 缺陷原文：舊判準（node_entry_service._reachable、map_node_presentation.is_reachable）
## 問的是「有沒有**任一**已完成節點指向它」。地圖每層之間是完全二分連邊
## （map_service.gd:76-79），所以走過 layer0 之後，layer0 → layer1 的每一條邊都成立，
## 上一層沒選走的兄弟分支永遠可達；玩家可回頭補刷，多結算一次節點收入／商店／獎勵。
##
## 本檔鎖定 frontier 語意：只認目前所在節點（current_node_id）的出邊，尚未進節點時
## ＝ act 1 / layer 0 的起始集合，損壞輸入 fail-closed。

const RUN_ID: StringName = &"run_frontier_fixture"

## act 1 / layer 0 單節點 → layer 1 兩兄弟 → layer 2 兩節點，層間完全二分連邊，
## 與 MapService 產出的形狀一致。
const L0: String = "node_a1_l0_s0"
const L1A: String = "node_a1_l1_s0"
const L1B: String = "node_a1_l1_s1"
const L2A: String = "node_a1_l2_s0"
const L2B: String = "node_a1_l2_s1"


func test_frontier_before_any_entry_is_the_act1_layer0_start_set() -> void:
	var map := _map(null, [])
	assert_eq(
		MapFrontier.frontier_node_ids(map), [L0],
		"還沒進過任何節點時，frontier 只能是 act 1 / layer 0 的起始集合"
	)
	assert_true(MapFrontier.is_frontier_node(map, _node(map, L0)))
	assert_false(
		MapFrontier.is_frontier_node(map, _node(map, L1A)),
		"起點還沒走，第二層不得可選"
	)


func test_frontier_after_the_first_step_is_the_current_node_out_edges() -> void:
	var map := _map(L0, [L0])
	assert_eq(
		MapFrontier.frontier_node_ids(map), [L1A, L1B],
		"站在 layer0 時，frontier ＝ layer0 的兩條出邊"
	)
	assert_false(
		MapFrontier.is_frontier_node(map, _node(map, L2A)),
		"隔層節點不是一步可達，不得可選"
	)


## 本任務的回歸鎖：走 layer0 → layer1 slot0 之後，layer1 slot1 是「沒選走的歷史
## 兄弟分支」。舊判準因 L0 已完成且 L0→L1B 有邊而回 true。
func test_frontier_excludes_the_unchosen_sibling_branch_of_the_previous_layer() -> void:
	var map := _map(L1A, [L0, L1A])
	var frontier := MapFrontier.frontier_node_ids(map)
	assert_eq(frontier, [L2A, L2B], "frontier 只能是目前所在節點 layer1 slot0 的出邊")
	assert_false(
		frontier.has(L1B),
		"上一層沒選走的兄弟分支不得出現在 frontier（回頭路）"
	)
	assert_false(
		MapFrontier.is_frontier_node(map, _node(map, L1B)),
		"單點判定必須與集合判定一致地拒絕歷史分支"
	)
	assert_false(
		MapFrontier.is_frontier_node(map, _node(map, L0)),
		"已完成的所在節點本身不得再次可選"
	)


func test_frontier_excludes_completed_successors_of_the_current_node() -> void:
	var map := _map(L1A, [L0, L1A, L2A])
	assert_eq(
		MapFrontier.frontier_node_ids(map), [L2B],
		"出邊目標若已完成，必須自 frontier 剔除"
	)
	var flagged := _map(L1A, [L0, L1A])
	_node(flagged, L2B).completed = true
	assert_eq(
		MapFrontier.frontier_node_ids(flagged), [L2A],
		"節點自身的 completed 旗標同樣要剔除（不只看 completed_node_ids）"
	)


func test_frontier_fails_closed_on_missing_empty_and_self_contradictory_map() -> void:
	assert_eq(MapFrontier.frontier_node_ids(null), [] as Array[String], "map 為 null 回空集合")
	assert_eq(MapFrontier.frontier_nodes(null), [] as Array[MapNodeState])
	assert_false(MapFrontier.is_frontier_node(null, _node(_map(null, []), L0)))
	assert_false(MapFrontier.is_frontier_node(_map(null, []), null), "target 為 null 回 false")

	var empty := MapState.new(
		[] as Array[MapNodeState], [] as Array[MapEdgeState], null, [] as Array[String]
	)
	assert_eq(empty.nodes.size(), 0)
	assert_eq(MapFrontier.frontier_node_ids(empty), [] as Array[String], "空地圖回空集合")

	var dangling := _map("node_does_not_exist", [L0])
	assert_eq(
		MapFrontier.frontier_node_ids(dangling), [] as Array[String],
		"current_node_id 指向不存在的節點＝損壞狀態，必須 fail-closed 而不是退回起始集合"
	)

	var contradictory := _map(null, [L0])
	assert_eq(
		MapFrontier.frontier_node_ids(contradictory), [] as Array[String],
		"已有完成紀錄卻沒有所在節點＝自相矛盾，不得讓玩家從 act1 layer0 重走"
	)

	var foreign_key := NodeKeyState.create(RUN_ID, 1, &"normal", 0, 0, &"node_foreign")
	var foreign := MapNodeState.new(
		"node_foreign", foreign_key, &"map_node.normal", 1, 0, 0,
		MapNodeState.NodeKind.NORMAL, "digest_foreign", null, false
	)
	assert_false(
		MapFrontier.is_frontier_node(_map(null, []), foreign),
		"不屬於這張地圖的節點恆為 false"
	)


func test_frontier_nodes_keep_canonical_order_and_hand_out_clones_only() -> void:
	var map := _map(L0, [L0])
	var nodes := MapFrontier.frontier_nodes(map)
	var ids: Array[String] = []
	for node: MapNodeState in nodes:
		ids.append(node.node_id)
	assert_eq(ids, [L1A, L1B], "順序必須是 map_state.nodes 的正規順序（act/layer/slot 遞增）")
	nodes[0].completed = true
	assert_false(
		_node(map, L1A).completed,
		"回傳的必須是 deep clone，呼叫端改它不得污染 canonical map_state"
	)


## C-1 的核心：UI 亮起的集合必須恆等於 domain 會受理的集合。
func test_presentation_predicate_agrees_with_the_domain_frontier_on_every_node() -> void:
	for anchor: Variant in [null, L0, L1A]:
		var completed: Array[String] = []
		if anchor == L0:
			completed = [L0]
		elif anchor == L1A:
			completed = [L0, L1A]
		var map := _map(anchor as String if anchor != null else null, completed)
		for node: MapNodeState in map.nodes:
			assert_eq(
				MapNodePresentation.is_reachable(map, node),
				MapFrontier.is_frontier_node(map, node),
				"anchor=%s node=%s：呈現層判定與 domain frontier 必須一致" % [
					"none" if anchor == null else String(anchor), node.node_id,
				]
			)
			assert_eq(
				RunPresentationSession.node_is_reachable(map, node),
				MapFrontier.is_frontier_node(map, node),
				"session 別名同樣不得與 domain frontier 分岔"
			)


func _map(current_node_id: Variant, completed_node_ids: Array[String]) -> MapState:
	var nodes: Array[MapNodeState] = [
		_make_node(L0, 0, 0, MapNodeState.NodeKind.NORMAL, completed_node_ids),
		_make_node(L1A, 1, 0, MapNodeState.NodeKind.NORMAL, completed_node_ids),
		_make_node(L1B, 1, 1, MapNodeState.NodeKind.ELITE, completed_node_ids),
		_make_node(L2A, 2, 0, MapNodeState.NodeKind.MERCHANT, completed_node_ids),
		_make_node(L2B, 2, 1, MapNodeState.NodeKind.EVENT, completed_node_ids),
	]
	var edges: Array[MapEdgeState] = [
		MapEdgeState.new(L0, L1A),
		MapEdgeState.new(L0, L1B),
		MapEdgeState.new(L1A, L2A),
		MapEdgeState.new(L1A, L2B),
		MapEdgeState.new(L1B, L2A),
		MapEdgeState.new(L1B, L2B),
	]
	var current: OptionalStringValue = null
	if current_node_id != null:
		current = OptionalStringValue.new(String(current_node_id))
	return MapState.new(nodes, edges, current, completed_node_ids)


func _make_node(
	node_id: String,
	layer_index: int,
	slot_index: int,
	kind: MapNodeState.NodeKind,
	completed_node_ids: Array[String]
) -> MapNodeState:
	var key := NodeKeyState.create(
		RUN_ID, 1, MapNodeState.node_kind_to_token(kind), layer_index, slot_index,
		StringName(node_id)
	)
	return MapNodeState.new(
		node_id, key, StringName("map_node.%s" % String(MapNodeState.node_kind_to_token(kind))),
		1, layer_index, slot_index, kind, "digest_" + node_id, null,
		completed_node_ids.has(node_id)
	)


func _node(map: MapState, node_id: String) -> MapNodeState:
	for node: MapNodeState in map.nodes:
		if node.node_id == node_id:
			return node
	fail_test("fixture map is missing node %s" % node_id)
	return null

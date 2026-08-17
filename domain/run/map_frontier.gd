class_name MapFrontier
extends RefCounted

## 「目前可選節點」的唯一權威判準：frontier ＝ 自 map_state.current_node_id 出發、
## 一步邊可達且尚未完成的節點集合；current_node_id 為 null（本次遠征還沒進過任何
## 節點）時＝ act 1 / layer 0 的起始集合。
##
## 與「拓撲可達」的語意分家：舊判準問的是「有沒有**任一**已完成節點指向它」。地圖
## 每層之間是完全二分連邊（map_service.gd），因此上一層沒被選走的兄弟分支永遠成立
## ——玩家可以回頭補刷跳過的分支，多拿一次節點收入、商店與獎勵。frontier 只認目前
## 所在節點的出邊，回頭路一律不成立。
##
## 判準集中在這裡是為了讓 domain 受理的集合與呈現層亮起的集合恆等：
## NodeEntryService.enter() 與 MapNodePresentation.is_reachable() 都只問這個類別。
##
## 損壞／自相矛盾的輸入一律 fail-closed（回空集合／false），不猜測也不退回起始集合：
## map_state 為 null、節點表為空、current_node_id 指向不存在的節點、或
## current_node_id 為 null 卻已有完成紀錄。


## frontier 節點的 id 清單，順序同 frontier_nodes()。
static func frontier_node_ids(map_state: MapState) -> Array[String]:
	var result: Array[String] = []
	for node: MapNodeState in frontier_nodes(map_state):
		result.append(node.node_id)
	return result


## 依 map_state.nodes 的正規順序（act／layer／slot 遞增，由 RunStateValidator
## `_validate_map` 保證嚴格遞增）回傳 frontier 節點的 deep clone——呼叫端拿不到
## canonical 的可變引用。
static func frontier_nodes(map_state: MapState) -> Array[MapNodeState]:
	var result: Array[MapNodeState] = []
	if map_state == null:
		return result
	for node: MapNodeState in map_state.nodes:
		if is_frontier_node(map_state, node):
			result.append(node.deep_clone())
	return result


## 單一節點的判定。target 必須是 map_state 上的節點；不屬於這張地圖的節點恆為 false。
static func is_frontier_node(map_state: MapState, target: MapNodeState) -> bool:
	if map_state == null or target == null or map_state.nodes.is_empty():
		return false
	if target.completed or map_state.completed_node_ids.has(target.node_id):
		return false
	if _find_node(map_state, target.node_id) == null:
		return false
	if map_state.current_node_id == null:
		# 還沒進過任何節點：起始集合＝ act 1 / layer 0。已有完成紀錄卻沒有所在節點
		# 是自相矛盾的狀態（正常流程只有 NodeEntryService 會寫入所在節點，而完成
		# 紀錄只可能在那之後才追加），不得退回起始集合讓玩家從頭再走一次。
		if not map_state.completed_node_ids.is_empty():
			return false
		return target.act_index == 1 and target.layer_index == 0
	var anchor := _find_node(map_state, map_state.current_node_id.value)
	if anchor == null:
		return false
	for edge: MapEdgeState in map_state.edges:
		if edge.from_node_id == anchor.node_id and edge.to_node_id == target.node_id:
			return true
	return false


static func _find_node(map_state: MapState, node_id: String) -> MapNodeState:
	if node_id.is_empty():
		return null
	for node: MapNodeState in map_state.nodes:
		if node != null and node.node_id == node_id:
			return node
	return null

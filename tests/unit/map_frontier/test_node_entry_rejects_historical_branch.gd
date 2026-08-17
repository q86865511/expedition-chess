extends GutTest

## C-1 / BP-SI-003 的 domain 面：走過的路不得回頭。
##
## 缺陷是真實產品缺陷而非只是 UI 寬鬆——NodeEntryService 舊的 _reachable() 同樣只問
## 「任一已完成節點 → target 有邊」，因此上一層沒選走的兄弟分支真的進得去，玩家能多
## 結算一次節點收入、商店與獎勵。本檔用正式產生的地圖鎖定具名拒絕。

func test_node_entry_rejects_the_unchosen_sibling_branch_with_a_named_error() -> void:
	var fixture := _fixture()
	if fixture == null: return
	var siblings := _layer_nodes(fixture.map, 1, 1)
	assert_true(siblings.size() >= 2, "act1 layer1 至少兩個兄弟節點才驗得到回頭路")
	if siblings.size() < 2: return
	_stand_on(fixture.root.run, [fixture.entry.node_id, siblings[0].node_id], siblings[0])
	var result := NodeEntryService.new().enter(
		fixture.root.run, siblings[1].node_id, fixture.catalog, fixture.battle_catalog
	)
	assert_false(
		result.ok,
		"站在 layer1 slot0 時，同層沒選走的 slot1 是歷史分支，不得受理"
	)
	if result.ok: return
	assert_eq(result.error.code, NodeEntryError.NODE_UNREACHABLE, "拒絕必須具名")
	assert_eq(result.error.field_path, &"target_node_id")
	assert_null(result.draft, "被拒的進入不得留下 draft")


## 對照組：同一個節點、同一份 catalog，只差在「玩家站在哪裡」。證明上一則的拒絕來自
## 回頭路判定，而不是 fixture 本身就進不去。
func test_the_same_sibling_is_accepted_while_it_is_still_on_the_frontier() -> void:
	var fixture := _fixture()
	if fixture == null: return
	var siblings := _layer_nodes(fixture.map, 1, 1)
	assert_true(siblings.size() >= 2)
	if siblings.size() < 2: return
	_stand_on(fixture.root.run, [fixture.entry.node_id], fixture.entry)
	var result := NodeEntryService.new().enter(
		fixture.root.run, siblings[1].node_id, fixture.catalog, fixture.battle_catalog
	)
	assert_true(result.ok, "站在 layer0 時 layer1 的每個兄弟都還在 frontier 上：%s:%s" % [
		String(result.error.code) if result.error != null else "none",
		String(result.error.field_path) if result.error != null else "none",
	])


## C-1 的驗收面：呈現層會亮起的集合（MapFrontier）必須恰好等於 domain 會受理的集合，
## 不得有「亮著卻進不去」或「沒亮卻進得去」。掃 act1 前三層即可覆蓋起點、回頭路與
## 已完成節點三種情況。
func test_frontier_query_matches_what_node_entry_actually_accepts() -> void:
	var fixture := _fixture()
	if fixture == null: return
	var siblings := _layer_nodes(fixture.map, 1, 1)
	assert_true(siblings.size() >= 2)
	if siblings.size() < 2: return
	_stand_on(fixture.root.run, [fixture.entry.node_id, siblings[0].node_id], siblings[0])
	var map := fixture.root.run.map_state
	var checked := 0
	for layer_index: int in range(3):
		for node: MapNodeState in _layer_nodes(map, 1, layer_index):
			var expected := MapFrontier.is_frontier_node(map, node)
			var result := NodeEntryService.new().enter(
				fixture.root.run, node.node_id, fixture.catalog, fixture.battle_catalog
			)
			checked += 1
			assert_eq(
				result.ok, expected,
				"act1/layer%d/slot%d：frontier=%s 但 domain 受理=%s（%s）" % [
					layer_index, node.slot_index, str(expected), str(result.ok),
					String(result.error.code) if result.error != null else "accepted",
				]
			)
	assert_true(checked >= 5, "至少要涵蓋起點層、回頭路層與下一層")


class _Fixture:
	var root: SaveRoot
	var catalog: EconomyExpeditionCatalog
	var battle_catalog: BattleRuleCatalog
	var map: MapState
	var entry: MapNodeState


## 與 tests/unit/economy_expediton/test_node_entry_service_boss_mapping.gd 同一套
## 起手式：MAP 期、IDLE、沒有殘留 shop offers，地圖由正式 MapService 產生。
func _fixture() -> _Fixture:
	var result := _Fixture.new()
	result.root = SaveRootFixture.create_valid_root()
	var manifest: String = result.root.run.content_snapshot.manifest_digest_value()
	result.catalog = EconomyTestFixture.save_fixture_catalog(manifest)
	result.battle_catalog = EconomyTestFixture.expedition_battle_catalog(manifest)
	result.root.run.run_phase = RunState.RunPhase.MAP
	result.root.run.current_node_id = null
	result.root.run.resolution_state = IdleResolutionState.new()
	result.root.run.economy_state = EconomyState.new(47, 3, 0, 5, 0, 0, [])
	result.root.run.unit_pool_state = result.catalog.create_initial_pool()
	result.root.run.unit_pool_state.entries[0].remaining_copies -= 1
	result.root.run.unit_pool_state.entries[0].held_copies = 1
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1, no_equipment, U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [BoardPlacementState.new(3, 3, unit.instance_id)]
	var bench: Array[String] = []
	var units: Array[UnitInstance] = [unit]
	var items: Array[ItemInstanceState] = []
	var item_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5): relics.append(RelicSlotState.new(index, null))
	result.root.run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, items, item_ids, item_ids, relics
	)
	result.root.run.reservation_owners.clear()
	result.root.run.transaction_receipts.clear()
	result.root.run.income_claimed_node_ids.clear()
	result.root.run.next_transaction_serial = U64Bits.zero()
	result.root.run.next_unit_serial = U64Bits.from_u32(0, 2).value
	var generated := MapService.new().generate_map(MapGenerationRequest.new(
		StringName(result.root.run.run_id), result.root.run.run_seed, result.catalog
	))
	assert_true(generated.ok, "map generation fixture must succeed")
	if not generated.ok: return null
	result.root.run.map_state = generated.map_state
	result.map = result.root.run.map_state
	var entries := _layer_nodes(result.map, 1, 0)
	assert_eq(entries.size(), 1, "act1 layer0 恆為單一起點")
	if entries.is_empty(): return null
	result.entry = entries[0]
	return result


## 把 run 擺成「已完成 completed_node_ids、目前站在 anchor」的狀態——也就是走完
## anchor 那個節點、回到地圖後的真實樣子。
func _stand_on(run: RunState, completed_node_ids: Array[String], anchor: MapNodeState) -> void:
	var sorted := completed_node_ids.duplicate()
	sorted.sort()
	run.map_state.completed_node_ids = sorted
	for node: MapNodeState in run.map_state.nodes:
		node.completed = sorted.has(node.node_id)
	run.current_node_id = OptionalStringValue.new(anchor.node_id)
	run.map_state.current_node_id = OptionalStringValue.new(anchor.node_id)


func _layer_nodes(map: MapState, act_index: int, layer_index: int) -> Array[MapNodeState]:
	var result: Array[MapNodeState] = []
	for node: MapNodeState in map.nodes:
		if node.act_index == act_index and node.layer_index == layer_index:
			result.append(node)
	return result

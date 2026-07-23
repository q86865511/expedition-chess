extends GutTest

## T06 (specs/build-systems) — 路線型遺物在 MapService 生成決策點生效，且不新增 entropy。
## Covers：REQ-RELIC-001、S4-AC-011（路線型於 MapService/node reachability 決策點生效，
## 沿用既有 map stream、不新增 entropy 源；依 slot_index 升序）。
## 依據 design.md §6：「路線 -> MapService / node reachability -> 生成或可達性決策點依槽序
## 套用（用既有 map stream，不新增 entropy）」。
##
## 假設聲明（見 test_run_relic_table_operations.gd 的總說明）：本檔將「branch anchor」定義為
## generate_map() 既有巢狀迴圈（act_index 1..3 外層、layer_index 0..6 內層）中，
## layer_index ∈ {1,3}（既有分支層）且 slot_index == 0 的節點，依生成走訪順序列舉，
## 每個 act 各兩個 anchor：(act,1) 先於 (act,3)。共 6 個 anchor，依序為
## (1,1) (1,3) (2,1) (2,3) (3,1) (3,3)。
## 每有一件 category == &"route" 的 active 遺物（依呼叫端傳入 active_relic_ids 順序，
## run_operations 內容本身不影響此處行為，只要求非空以符合 T07 的
## CONTENT_RELIC_EFFECT_SCOPE 規則），依序強制對應 anchor 的 node_kind 為 ELITE
## （覆寫 _kind_for_layer 既有的隨機判定結果，但既有的 stream.next_bounded() 呼叫本身
## 照常發生，只是結果被覆寫——藉此保證「不新增 entropy」：無論啟用幾件路線遺物，
## next_map_rng_snapshot 必須與未啟用遺物時完全相同）。多於 6 件路線遺物時，多出的部分
## 不再有額外效果（無 anchor 可佔用）。MapGenerationRequest 新增兩個尾端可選建構參數
## relic_table/active_relic_ids（預設 null/[]），對既有呼叫端（test_map_and_income.gd）
## 完全不改變既有行為。

func test_baseline_without_relic_params_matches_existing_generation() -> void:
	var catalog := EconomyTestFixture.catalog()
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var request := MapGenerationRequest.new(&"run_fixture", seed, catalog)
	var first := MapService.new().generate_map(request)
	var second := MapService.new().generate_map(request)
	assert_true(first.ok)
	assert_true(second.ok)
	if not first.ok or not second.ok:
		return
	assert_true(first.next_map_rng_snapshot.equals(second.next_map_rng_snapshot))

func test_single_route_relic_forces_first_branch_anchor_to_elite_without_new_entropy() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_route_rule(&"relic.route_a")])
	for seed_seed: int in range(5):
		var seed := U64Bits.from_u32(seed_seed, seed_seed + 1).value
		var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
		var with_relic := MapService.new().generate_map(MapGenerationRequest.new(
			&"run_fixture", seed, catalog, table, [&"relic.route_a"]
		))
		assert_true(baseline.ok, "seed %d" % seed_seed)
		assert_true(with_relic.ok, "seed %d" % seed_seed)
		if not baseline.ok or not with_relic.ok:
			continue
		assert_true(
			baseline.next_map_rng_snapshot.equals(with_relic.next_map_rng_snapshot),
			"seed %d: an active route relic must not change RNG stream consumption" % seed_seed
		)
		assert_eq(
			_kind_at(with_relic.map_state, 1, 1, 0), MapNodeState.NodeKind.ELITE,
			"seed %d: first branch anchor (act 1, layer 1, slot 0) must be forced elite" % seed_seed
		)
		_assert_other_positions_unchanged(baseline.map_state, with_relic.map_state, [[1, 1, 0]])

func test_two_route_relics_claim_first_two_anchors_in_generation_order() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_route_rule(&"relic.route_a"),
		_route_rule(&"relic.route_b"),
	])
	var seed := U64Bits.from_hex("00000000000000ff").value
	var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_relics := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, [&"relic.route_a", &"relic.route_b"]
	))
	assert_true(baseline.ok)
	assert_true(with_relics.ok)
	if not baseline.ok or not with_relics.ok:
		return
	assert_true(baseline.next_map_rng_snapshot.equals(with_relics.next_map_rng_snapshot))
	assert_eq(_kind_at(with_relics.map_state, 1, 1, 0), MapNodeState.NodeKind.ELITE)
	assert_eq(_kind_at(with_relics.map_state, 1, 3, 0), MapNodeState.NodeKind.ELITE)
	_assert_other_positions_unchanged(baseline.map_state, with_relics.map_state, [[1, 1, 0], [1, 3, 0]])

func test_non_route_category_relic_does_not_affect_map_generation() -> void:
	var catalog := EconomyTestFixture.catalog()
	var economy_operation := RunRelicOperationRule.new()
	economy_operation.operation_index = 0
	economy_operation.kind = &"add_gold"
	economy_operation.amount = 5
	economy_operation.claim_scope = &"once_per_node"
	var economy_rule := RunRelicRule.new()
	economy_rule.relic_id = &"relic.eco_a"
	economy_rule.category = &"economy"
	economy_rule.effect_ids = [&"effect.fixture"]
	economy_rule.run_operations = [economy_operation]
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [economy_rule])
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_relic := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, [&"relic.eco_a"]
	))
	assert_true(baseline.ok)
	assert_true(with_relic.ok)
	if not baseline.ok or not with_relic.ok:
		return
	assert_true(baseline.next_map_rng_snapshot.equals(with_relic.next_map_rng_snapshot))
	_assert_other_positions_unchanged(baseline.map_state, with_relic.map_state, [])

func _route_rule(relic_id: StringName) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 0
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"route"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _kind_at(map: MapState, act_index: int, layer_index: int, slot_index: int) -> int:
	for node: MapNodeState in map.nodes:
		if node.act_index == act_index and node.layer_index == layer_index and node.slot_index == slot_index:
			return node.node_kind
	return -1

func _assert_other_positions_unchanged(
	baseline: MapState, with_relic: MapState, excluded_positions: Array
) -> void:
	assert_eq(baseline.nodes.size(), with_relic.nodes.size())
	for node: MapNodeState in baseline.nodes:
		var position := [node.act_index, node.layer_index, node.slot_index]
		if excluded_positions.has(position):
			continue
		var other_kind := _kind_at(with_relic, node.act_index, node.layer_index, node.slot_index)
		assert_eq(
			other_kind, node.node_kind,
			"node at act %d layer %d slot %d must be unaffected by relics" % [node.act_index, node.layer_index, node.slot_index]
		)

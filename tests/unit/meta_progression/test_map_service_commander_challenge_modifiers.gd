extends GutTest

## T06(specs/meta-progression) — MapService 在既有 slot-gated 路線遺物計數後,再加
## 指揮官/挑戰 always-active 路線貢獻,且不新增 RNG entropy。
## Covers：S5-AC-003；tasks.md T06 驗收：「四個 run 層作用點消費端在 slot-gated 後加
## always-active 貢獻」(map 為其一)。
## 依據 design.md §6.1:117 與既有 tests/unit/economy_expediton/test_map_service_relics.gd
## 的 branch anchor 慣例(act 1..3、layer∈{1,3}、slot 0,依生成走訪順序列舉,
## 6 個 anchor 依序為 (1,1)(1,3)(2,1)(2,3)(3,1)(3,3);每有一件 route 類作用中來源
## 依序強制對應 anchor 為 ELITE,既有 stream.next_bounded() 呼叫本身照常發生只是結果被覆寫)。
##
## 假設聲明：MapService 對「有多少件 route 來源作用中」的計數,現行只讀
## relic_table.active_count(active_relic_ids, &"route")(slot-gated)。T06 要求疊加
## always_active_count(&"route")(commander/challenge,無條件)——本檔假設兩者相加得到
## 「本次生成要強制的 anchor 總數」,疊加後續按既有生成走訪順序依序佔用 anchor(與既有
## slot-gated 路線遺物佔用邏輯完全一致,只是額度來源多了 always-active 一項)。
##
## 範圍聲明：本檔只鎖 MapService.generate_map() 的 anchor 佔用子點與 entropy 不變量;
## RunRelicTable 手動建構,不經 RunModifierTableBuilder(見 test_run_modifier_table_builder.gd)。

func test_commander_always_active_route_forces_first_anchor_without_new_entropy() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_route_rule(&"commander.fixture", &"commander"),
	])
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_commander := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, []
	))
	assert_true(baseline.ok)
	assert_true(with_commander.ok)
	if not baseline.ok or not with_commander.ok:
		return
	assert_true(
		baseline.next_map_rng_snapshot.equals(with_commander.next_map_rng_snapshot),
		"commander always-active route 貢獻不得改變 RNG stream 消耗(active_relic_ids 為空," +
		"不倚賴任何 slot 資訊)"
	)
	assert_eq(
		_kind_at(with_commander.map_state, 1, 1, 0), MapNodeState.NodeKind.ELITE,
		"first branch anchor (act 1, layer 1, slot 0) 應被 commander always-active 強制為 ELITE"
	)
	_assert_other_positions_unchanged(baseline.map_state, with_commander.map_state, [[1, 1, 0]])

func test_always_active_route_count_stacks_with_slot_gated_route_relic() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_slot_gated_route_rule(&"relic.route_a"),
		_always_active_route_rule(&"commander.fixture", &"commander"),
	])
	var seed := U64Bits.from_hex("00000000000000ff").value
	var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_both := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, [&"relic.route_a"]
	))
	assert_true(baseline.ok)
	assert_true(with_both.ok)
	if not baseline.ok or not with_both.ok:
		return
	assert_true(baseline.next_map_rng_snapshot.equals(with_both.next_map_rng_snapshot))
	assert_eq(
		_kind_at(with_both.map_state, 1, 1, 0), MapNodeState.NodeKind.ELITE,
		"第一個 anchor 應被(slot-gated 或 always-active 皆可,總額度 2)佔用"
	)
	assert_eq(
		_kind_at(with_both.map_state, 1, 3, 0), MapNodeState.NodeKind.ELITE,
		"總額度 2(1 slot-gated + 1 commander always-active) 應佔用前兩個 anchor"
	)
	_assert_other_positions_unchanged(baseline.map_state, with_both.map_state, [[1, 1, 0], [1, 3, 0]])

func test_always_active_route_contribution_ignores_which_relic_slots_are_active() -> void:
	# relic.route_a 存在於表中,但這次刻意不放進 active_relic_ids -> 其 slot-gated 額度不計;
	# commander always-active 額度(1)不受影響,只強制第一個 anchor(總額度必須是 1,不是 2)。
	# 比照既有慣例,以「與完全無 relic_table 的真正 baseline 逐位置比對」驗證,不對特定
	# anchor 的隨機結果做假設(該位置在未被強制時本來是 NORMAL 或 ELITE 純屬該 seed 的
	# 隨機捲值,不應被本測試寫死)。
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_slot_gated_route_rule(&"relic.route_a"),
		_always_active_route_rule(&"commander.fixture", &"commander"),
	])
	var seed := U64Bits.from_hex("00000000000000ff").value
	var true_baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_commander_only := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, []
	))
	assert_true(true_baseline.ok)
	assert_true(with_commander_only.ok)
	if not true_baseline.ok or not with_commander_only.ok:
		return
	assert_eq(
		_kind_at(with_commander_only.map_state, 1, 1, 0), MapNodeState.NodeKind.ELITE,
		"commander always-active 的 1 份額度應強制第一個 anchor"
	)
	_assert_other_positions_unchanged(
		true_baseline.map_state, with_commander_only.map_state, [[1, 1, 0]]
	)

func test_non_route_category_always_active_rule_does_not_affect_map_generation() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_always_active_rule_with_category(&"challenge.fixture", &"challenge", &"economy", &"add_gold", 5),
	])
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var baseline := MapService.new().generate_map(MapGenerationRequest.new(&"run_fixture", seed, catalog))
	var with_rule := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, []
	))
	assert_true(baseline.ok)
	assert_true(with_rule.ok)
	if not baseline.ok or not with_rule.ok:
		return
	assert_true(baseline.next_map_rng_snapshot.equals(with_rule.next_map_rng_snapshot))
	_assert_other_positions_unchanged(baseline.map_state, with_rule.map_state, [])

func _slot_gated_route_rule(relic_id: StringName) -> RunRelicRule:
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

func _always_active_route_rule(source_id: StringName, source: StringName) -> RunRelicRule:
	return _always_active_rule_with_category(source_id, source, &"route", &"add_gold", 0)

func _always_active_rule_with_category(
	source_id: StringName, source: StringName, category: StringName, kind: StringName, amount: int
) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
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
			"node at act %d layer %d slot %d must be unaffected" % [node.act_index, node.layer_index, node.slot_index]
		)

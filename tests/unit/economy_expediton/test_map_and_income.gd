extends GutTest

func test_map_generation_is_deterministic_and_has_three_valid_acts() -> void:
	var catalog := EconomyTestFixture.catalog()
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var request := MapGenerationRequest.new(&"run_fixture", seed, catalog)
	var first := MapService.new().generate_map(request)
	var second := MapService.new().generate_map(request)
	assert_true(first.ok)
	assert_true(second.ok)
	if not first.ok or not second.ok:
		return
	assert_eq(first.next_map_rng_snapshot.counter.to_hex(), second.next_map_rng_snapshot.counter.to_hex())
	assert_eq(first.map_state.nodes.size(), second.map_state.nodes.size())
	assert_eq(first.map_state.edges.size(), second.map_state.edges.size())
	var boss_count := 0
	for index: int in range(first.map_state.nodes.size()):
		var left := first.map_state.nodes[index]
		var right := second.map_state.nodes[index]
		assert_eq(left.node_id, right.node_id)
		assert_eq(left.node_kind, right.node_kind)
		if left.node_kind == MapNodeState.NodeKind.BOSS: boss_count += 1
	assert_eq(boss_count, 3)
	for act_index: int in range(1, 4):
		for layer_index: int in range(7):
			var layer := _nodes_at(first.map_state, act_index, layer_index)
			assert_between(layer.size(), 1, 3)
			if layer_index in [0, 5, 6]: assert_eq(layer.size(), 1)
			else: assert_between(layer.size(), 2, 3)
			if layer_index in [1, 3]:
				for node: MapNodeState in layer:
					assert_true(node.node_kind in [MapNodeState.NodeKind.NORMAL, MapNodeState.NodeKind.ELITE])

func test_income_uses_pre_gold_and_versioned_streak_rules() -> void:
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		EconomyTestFixture.catalog()
	))
	assert_true(result.ok)
	if not result.ok: return
	assert_eq(result.transaction.base_income, 5)
	assert_eq(result.transaction.interest_income, 4)
	assert_eq(result.transaction.streak_income, 2)
	assert_eq(result.transaction.economy_state.gold, 58)
	assert_eq(result.transaction.next_transaction_serial.to_hex(), "0000000000000001")

func _nodes_at(map: MapState, act_index: int, layer_index: int) -> Array[MapNodeState]:
	var result: Array[MapNodeState] = []
	for node: MapNodeState in map.nodes:
		if node.act_index == act_index and node.layer_index == layer_index:
			result.append(node)
	return result

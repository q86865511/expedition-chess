extends GutTest

## DC-REQ-007（difficulty-curve T07）觀測性殘項：
## (a) 缺 content_id 的 reward.kind.N 佔位必須計入 opaque_selected_id_count；
## (b) BalanceBotActSnapshot 新增 battle_wins/battle_losses/elimination_node_id 欄位
##     的 schema（含 is_valid() 負值防呆）與 BalanceBotReport.to_json() 的輸出；
## (c) canonical_token() 必須決定性地反映這三個新欄位。


func test_opaque_reward_placeholder_counts_toward_opaque_selected_id_stat() -> void:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 1)
	var placeholder_case := _case(&"tempo", 0)
	placeholder_case.selected_ids = [StringName("reward.kind.2")]
	report.append(placeholder_case)
	var stable_case := _case(&"economy", 1)
	stable_case.selected_ids = [StringName("unit.slice_monster_00")]
	report.append(stable_case)

	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	var observability := parsed["stable_id_observability"] as Dictionary
	assert_eq(int(observability["selected_id_count"]), 2, "兩個 case 各記一筆 selected_id")
	assert_eq(
		int(observability["opaque_selected_id_count"]), 1,
		"reward.kind.N 佔位字串必須計入 opaque 計數，不得冒充正式 content stable ID"
	)


func test_act_snapshot_schema_includes_battle_outcome_and_elimination_fields() -> void:
	var snapshot := BalanceBotActSnapshot.new(
		1, 100, 80, 1, 1, [StringName("unit.a")],
		2, 1, StringName("route.act1.layer2.normal")
	)
	assert_true(snapshot.is_valid(), "合法的勝敗數與淘汰節點 id 必須通過 is_valid()")
	assert_eq(snapshot.battle_wins, 2)
	assert_eq(snapshot.battle_losses, 1)
	assert_eq(snapshot.elimination_node_id, StringName("route.act1.layer2.normal"))

	var not_eliminated := BalanceBotActSnapshot.new(
		2, 10, 60, 1, 1, [StringName("unit.a")], 1, 0
	)
	assert_true(not_eliminated.is_valid())
	assert_eq(
		not_eliminated.elimination_node_id, &"",
		"未淘汰的幕，elimination_node_id 預設必須為空"
	)

	var invalid_wins := BalanceBotActSnapshot.new(
		1, 100, 80, 1, 1, [StringName("unit.a")], -1, 0, &""
	)
	assert_false(invalid_wins.is_valid(), "battle_wins 為負必須判定 is_valid() 為 false")
	var invalid_losses := BalanceBotActSnapshot.new(
		1, 100, 80, 1, 1, [StringName("unit.a")], 0, -1, &""
	)
	assert_false(invalid_losses.is_valid(), "battle_losses 為負必須判定 is_valid() 為 false")

	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 1)
	var value := _case(&"tempo", 0)
	value.act_snapshots = [snapshot]
	report.append(value)
	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	var proof := (parsed["case_proofs"] as Array)[0] as Dictionary
	var act_snapshots := proof["act_snapshots"] as Array
	assert_eq(act_snapshots.size(), 1)
	var act1 := act_snapshots[0] as Dictionary
	assert_eq(int(act1["battle_wins"]), 2, "report JSON 的 act_snapshots 必須帶出 battle_wins")
	assert_eq(int(act1["battle_losses"]), 1, "report JSON 的 act_snapshots 必須帶出 battle_losses")
	assert_eq(
		act1["elimination_node_id"], "route.act1.layer2.normal",
		"report JSON 的 act_snapshots 必須帶出 elimination_node_id"
	)


func test_canonical_token_is_deterministic_and_reflects_battle_and_elimination_fields() -> void:
	var base := BalanceBotActSnapshot.new(
		2, 50, 40, 2, 2, [StringName("unit.b"), StringName("unit.a")],
		3, 1, &""
	)
	var same_inputs_different_order := BalanceBotActSnapshot.new(
		2, 50, 40, 2, 2, [StringName("unit.a"), StringName("unit.b")],
		3, 1, &""
	)
	assert_eq(
		base.canonical_token(), same_inputs_different_order.canonical_token(),
		"canonical_token 必須決定性：unit id 輸入順序不同但內容相同時仍須相同"
	)

	var different_losses := BalanceBotActSnapshot.new(
		2, 50, 40, 2, 2, [StringName("unit.a"), StringName("unit.b")],
		3, 2, &""
	)
	assert_ne(
		base.canonical_token(), different_losses.canonical_token(),
		"battle_losses 改變必須反映在 canonical_token（DC-REQ-007 的 replay digest 綁定）"
	)

	var different_wins := BalanceBotActSnapshot.new(
		2, 50, 40, 2, 2, [StringName("unit.a"), StringName("unit.b")],
		4, 1, &""
	)
	assert_ne(
		base.canonical_token(), different_wins.canonical_token(),
		"battle_wins 改變必須反映在 canonical_token"
	)

	var eliminated := BalanceBotActSnapshot.new(
		2, 50, 40, 2, 2, [StringName("unit.a"), StringName("unit.b")],
		3, 1, StringName("route.act2.layer3.elite")
	)
	assert_ne(
		base.canonical_token(), eliminated.canonical_token(),
		"elimination_node_id 改變必須反映在 canonical_token"
	)


func _case(strategy_id: StringName, ending_gold: int) -> BalanceBotCaseResult:
	var value := BalanceBotCaseResult.new()
	value.strategy_id = strategy_id
	value.seed_index = 0
	value.run_id = &"shared_run"
	value.world_digest = "b".repeat(64)
	value.terminal = true
	value.act_reached = 3
	value.build_id = &"build.trait.test"
	value.ending_gold = ending_gold
	value.final_phase = &"RESULTS"
	value.settlement_receipt_digests = ["settlement"]
	value.reward_receipt_digests = ["reward"]
	value.replay_digest = "digest-%s" % String(strategy_id)
	return value

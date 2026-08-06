extends GutTest

## DC-REQ-007（difficulty-curve T09 相關）review A F6／review B #5：per-act
## battle_wins/battle_losses 差值記帳（BalanceProductionCaseDriver._capture_act_snapshot
## 的 baseline 減法）先前無任何整合測試覆蓋，只有 DTO 欄位層測試
## （test_balance_bot_act_snapshot_observability.gd）。該邏輯內嵌在 run_case 的完整
## 遠征迴圈中難以直接單測，抽出的最小純函式 _build_act_snapshot（不改行為，見
## application/balance/balance_production_case_driver.gd）在此用合成的跨三幕序列
## （含死亡當幕）驗證：(a) 各幕 battle_wins/battle_losses 只反映該幕真正發生的戰鬥，
## 不會把相鄰幕的勝敗算進來；(b) 三幕分項加總等於全局累計值，不多算不漏算。


func test_build_act_snapshot_isolates_per_act_wins_and_losses_across_three_acts() -> void:
	# 合成一次遠征：act1 打 4 場（3 勝 1 敗，Boss 收尾）、act2 打 4 場（2 勝 2 敗，Boss
	# 收尾）、act3 打 2 場（1 勝 1 敗）後死在非 Boss 節點（run 落 RESULTS，靠「run 已落
	# RESULTS」補齊點觸發快照，見 design.md「觀測性與 per-act gate」段）。
	var act_wins_baseline := 0
	var act_losses_baseline := 0

	var cumulative_wins_after_act1 := 3
	var cumulative_losses_after_act1 := 1
	var act1 := BalanceProductionCaseDriver._build_act_snapshot(
		1, 50, 20, 6, 6, [StringName("unit.a")] as Array[StringName],
		cumulative_wins_after_act1, cumulative_losses_after_act1,
		act_wins_baseline, act_losses_baseline, &""
	)
	# run_case 主迴圈只在 _capture_act_snapshot 回傳 captured=true 時才推進 baseline。
	act_wins_baseline = cumulative_wins_after_act1
	act_losses_baseline = cumulative_losses_after_act1

	var cumulative_wins_after_act2 := cumulative_wins_after_act1 + 2
	var cumulative_losses_after_act2 := cumulative_losses_after_act1 + 2
	var act2 := BalanceProductionCaseDriver._build_act_snapshot(
		2, 80, 15, 6, 6, [StringName("unit.a")] as Array[StringName],
		cumulative_wins_after_act2, cumulative_losses_after_act2,
		act_wins_baseline, act_losses_baseline, &""
	)
	act_wins_baseline = cumulative_wins_after_act2
	act_losses_baseline = cumulative_losses_after_act2

	var cumulative_wins_after_act3 := cumulative_wins_after_act2 + 1
	var cumulative_losses_after_act3 := cumulative_losses_after_act2 + 1
	var death_node_id := StringName("route.act3.layer1.normal")
	var act3 := BalanceProductionCaseDriver._build_act_snapshot(
		3, 0, 0, 4, 4, [StringName("unit.a")] as Array[StringName],
		cumulative_wins_after_act3, cumulative_losses_after_act3,
		act_wins_baseline, act_losses_baseline, death_node_id
	)

	assert_eq(act1.battle_wins, 3, "act1 的 3 勝必須完整算在 act1")
	assert_eq(act1.battle_losses, 1, "act1 的 1 敗必須完整算在 act1")
	assert_eq(act1.elimination_node_id, &"", "act1 未淘汰")

	assert_eq(act2.battle_wins, 2, "act2 的勝場不得把 act1 的 3 勝算進來")
	assert_eq(act2.battle_losses, 2, "act2 的敗場不得把 act1 的 1 敗算進來")
	assert_eq(act2.elimination_node_id, &"", "act2 未淘汰")

	assert_eq(act3.battle_wins, 1, "act3（死亡當幕）的勝場不得把 act1/act2 算進來")
	assert_eq(act3.battle_losses, 1, "act3（死亡當幕）的敗場不得把 act1/act2 算進來")
	assert_eq(
		act3.elimination_node_id, death_node_id,
		"死亡當幕必須記錄淘汰節點 id，不得被鄰幕吸收或留空"
	)

	var total_wins := act1.battle_wins + act2.battle_wins + act3.battle_wins
	var total_losses := act1.battle_losses + act2.battle_losses + act3.battle_losses
	assert_eq(
		total_wins, cumulative_wins_after_act3,
		"三幕勝場加總必須等於全局累計勝場，不多算不漏算"
	)
	assert_eq(
		total_losses, cumulative_losses_after_act3,
		"三幕敗場加總必須等於全局累計敗場，不多算不漏算"
	)


func test_build_act_snapshot_zero_battle_act_yields_zero_delta_not_negative() -> void:
	# 邊界情境：某幕（例如 act2）在 baseline 推進後緊接著又立刻觸發一次快照擷取點，
	# 中間沒有任何新戰鬥——差值必須是 0，不能因為累計值與 baseline 相等而算出負值
	# 或誤差。
	var snapshot := BalanceProductionCaseDriver._build_act_snapshot(
		2, 10, 30, 5, 5, [StringName("unit.a")] as Array[StringName],
		5, 3, 5, 3, &""
	)
	assert_eq(snapshot.battle_wins, 0)
	assert_eq(snapshot.battle_losses, 0)

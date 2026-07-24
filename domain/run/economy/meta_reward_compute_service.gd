class_name MetaRewardComputeService
extends RefCounted

## design.md §9 — 遠征結算貨幣試算純函式（S5-AC-006／REQ-META-004）。
## base     = cleared_normal·score(normal) + cleared_elite·score(elite) + defeated_boss·score(boss)
##            （score 僅 normal/elite/boss 三鍵；merchant/event/rest/treasure 等非戰鬥節點一律不計分）
## mult_bps = table.challenge_multiplier_bps 中 challenge_level 相符項的 basis_points
##            （乘數單一權威在表內 bps 欄；本函式只讀表，不硬寫「100%+10%×level」公式形態）
## scaled   = floor(base · mult_bps / 10000)
## delta    = scaled + (table.completion_reward if outcome == COMPLETED else 0)
##            （failure_reward 欄不參與計算：戰敗/放棄僅保留先前成功戰鬥計分、無額外加成）
##
## 純函式：不讀寫任何外部狀態、不修改傳入的 table，同輸入恆得同輸出。
static func compute(
	cleared_normal: int,
	cleared_elite: int,
	defeated_boss: int,
	challenge_level: int,
	outcome: SettlementReceiptState.Outcome,
	table: MetaRewardTableDef
) -> int:
	var base := (
		cleared_normal * _score(table, &"normal")
		+ cleared_elite * _score(table, &"elite")
		+ defeated_boss * _score(table, &"boss")
	)
	var mult_bps := _multiplier_bps(table, challenge_level)
	var scaled: int = (base * mult_bps) / 10000
	var completion_bonus := (
		table.completion_reward if outcome == SettlementReceiptState.Outcome.COMPLETED else 0
	)
	return scaled + completion_bonus

## 讀 node_scores 中 enum_key 相符項的分值；表內未列出的鍵一律計 0（非戰鬥節點/未知鍵防呆）。
static func _score(table: MetaRewardTableDef, key: StringName) -> int:
	for pair: EnumIntPairDef in table.node_scores:
		if pair.enum_key == key:
			return pair.value_i32
	return 0

## 讀 challenge_multiplier_bps 中 challenge_level 相符項的 basis_points；
## 表內未涵蓋的 level 防呆回退 10000（=100%，無加成無懲罰的中性值）。
static func _multiplier_bps(table: MetaRewardTableDef, challenge_level: int) -> int:
	for entry: ChallengeMultiplierDef in table.challenge_multiplier_bps:
		if entry.challenge_level == challenge_level:
			return entry.basis_points
	return 10000

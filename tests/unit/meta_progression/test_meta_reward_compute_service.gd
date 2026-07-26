extends GutTest

## T01(specs/meta-progression) — MetaRewardComputeService 純函式驗收。
## Covers：REQ-META-004、S5-AC-006（compute 公式段）；tasks.md T01 驗收：
##   「compute 純函式對表計算（floor(base·bps/10000)、completion 僅 COMPLETED、
##   failure 無加成、非戰鬥節點 0）…同輸入同輸出」。
## 對應 design.md §9（公式、乘數權威收斂）與 §12 測試案例 006
## test_meta_reward_compute_matches_table_formula。
##
## 公式（design.md §9:173-180）：
##   base   = cleared_normal·score(normal) + cleared_elite·score(elite)
##          + defeated_boss·score(boss)          （score 僅 normal/elite/boss 三鍵）
##   mult_bps = table.challenge_multiplier_bps[challenge_level]（乘數單一權威在表內 bps 欄）
##   scaled = floor(base · mult_bps / 10000)
##   delta  = scaled + (table.completion_reward if outcome == COMPLETED else 0)
##
## 假設聲明（design.md 未給精確簽名型別，本檔依既有慣例與逐字引用釘定）：
## 1. MetaRewardComputeService.compute(...) 為 **static func**，不經 .new()：design.md:95,173
##    兩處都直接寫 `MetaRewardComputeService.compute(...)`；比照既有純計算 static 慣例
##    domain/run/build/run_relic_activation.gd:7
##    （static func active_ids_in_slot_order），非 RefCounted 實例方法。
## 2. outcome 參數型別沿用既有 SettlementReceiptState.Outcome{COMPLETED,FAILED,ABANDONED}
##    （domain/run/settlement_receipt_state.gd:4），不是新型別：design.md §5.1 point1
##    正是用這三個字面值判定 outcome，§9 的 compute 直接消費同一個 outcome。
## 3. table 參數型別為既有 MetaRewardTableDef（content/definitions/meta_reward_table_def.gd，
##    唯讀不動）：node_scores: Array[EnumIntPairDef]、completion_reward/failure_reward: int、
##    challenge_multiplier_bps: Array[ChallengeMultiplierDef]。
##
## 範圍聲明：本檔只鎖 compute() 這個純函式（已知三個 cleared/defeated 計數＋challenge_level＋
## outcome＋table 為輸入）。從實際 RunState/戰鬥歷程推導 cleared_normal/cleared_elite/
## defeated_boss 計數，屬 MetaSettlementService.settle()（T02，design.md §5.1 step1-2），
## 不在 T01 範圍內，本檔不測。
## slice_default.tres 對齊 §7.3 的資料面驗收見同目錄
## test_meta_reward_table_slice_default_alignment.gd（不依賴本檔的 MetaRewardComputeService）。

func test_meta_reward_compute_matches_table_formula() -> void:
	var table := _aligned_table()

	# base=2*1+1*3+0*5=5；bps(L0)=10000；scaled=floor(50000/10000)=5；FAILED→+0
	var case_a: int = MetaRewardComputeService.compute(
		2, 1, 0, 0, SettlementReceiptState.Outcome.FAILED, table
	)
	assert_eq(case_a, 5, "L0 FAILED: floor(5*10000/10000)+0")

	# base=3*1+2*3+1*5=14；bps(L1)=11000；scaled=floor(154000/10000)=15；COMPLETED→+10
	var case_b: int = MetaRewardComputeService.compute(
		3, 2, 1, 1, SettlementReceiptState.Outcome.COMPLETED, table
	)
	assert_eq(case_b, 25, "L1 COMPLETED: floor(14*11000/10000)+10")

	# base=1*1+1*3+1*5=9；bps(L2)=12000；9*12000=108000→floor(10.8)=10
	# （刻意選非整除的一組，鎖定 floor 真的取下捨，不是四捨五入或向上取整）
	var case_c: int = MetaRewardComputeService.compute(
		1, 1, 1, 2, SettlementReceiptState.Outcome.FAILED, table
	)
	assert_eq(case_c, 10, "L2 FAILED: floor(9*12000/10000)+0，非整除驗證 floor 取下捨")

	# base=5*1+3*3+1*5=19；bps(L5，上界)=15000；19*15000=285000→floor(28.5)=28；ABANDONED→+0
	var case_d: int = MetaRewardComputeService.compute(
		5, 3, 1, 5, SettlementReceiptState.Outcome.ABANDONED, table
	)
	assert_eq(case_d, 28, "L5 ABANDONED: floor(19*15000/10000)+0")

	# 全零清空但 COMPLETED：base=0；scaled=0；仍加 completion_reward（純算式邊界，
	# outcome 判定本身不在本檔範圍，只驗證公式在 base=0 時依然正確相加）
	var case_e: int = MetaRewardComputeService.compute(
		0, 0, 0, 0, SettlementReceiptState.Outcome.COMPLETED, table
	)
	assert_eq(case_e, 10, "全零清場 + COMPLETED：delta 僅為 completion_reward")

func test_meta_reward_compute_adds_completion_only_for_completed_outcome() -> void:
	var table := _aligned_table()
	# base=2*1+1*3+1*5=10；bps(L3)=13000；scaled=floor(130000/10000)=13
	var scaled_only := 13
	var completed: int = MetaRewardComputeService.compute(
		2, 1, 1, 3, SettlementReceiptState.Outcome.COMPLETED, table
	)
	var failed: int = MetaRewardComputeService.compute(
		2, 1, 1, 3, SettlementReceiptState.Outcome.FAILED, table
	)
	var abandoned: int = MetaRewardComputeService.compute(
		2, 1, 1, 3, SettlementReceiptState.Outcome.ABANDONED, table
	)
	assert_eq(completed, scaled_only + table.completion_reward, "COMPLETED 才加 completion_reward")
	assert_eq(failed, scaled_only, "FAILED 不得加成，只剩 scaled")
	assert_eq(abandoned, scaled_only, "ABANDONED 不得加成，只剩 scaled")
	assert_eq(failed, abandoned, "FAILED 與 ABANDONED 對 delta 的效果必須相同（皆非 COMPLETED）")

func test_meta_reward_compute_ignores_failure_reward_field_regardless_of_value() -> void:
	# S5-AC-006／design.md §9:182「failure_reward 無加成」——compute() 的公式本身不讀
	# failure_reward（見 design.md:179 delta 算式），故此欄無論配置何值都不應影響 delta。
	var zero_failure := _aligned_table()
	zero_failure.failure_reward = 0
	var large_failure := _aligned_table()
	large_failure.failure_reward = 500
	for outcome: SettlementReceiptState.Outcome in [
		SettlementReceiptState.Outcome.FAILED, SettlementReceiptState.Outcome.ABANDONED,
	]:
		var with_zero: int = MetaRewardComputeService.compute(2, 1, 0, 1, outcome, zero_failure)
		var with_large: int = MetaRewardComputeService.compute(2, 1, 0, 1, outcome, large_failure)
		assert_eq(
			with_zero, with_large,
			"failure_reward 數值（0 vs 500）不得影響 delta：outcome=%d" % outcome
		)

func test_meta_reward_compute_ignores_non_combat_node_scores() -> void:
	# S5-AC-006「非戰鬥節點 0」——compute() 簽名只吃 cleared_normal/cleared_elite/
	# defeated_boss 三個計數，沒有管道餵入 merchant/event/rest/treasure 的清算次數；
	# 本測試進一步鎖定：即使 table.node_scores 裡這四類節點被配置離譜數值，
	# 也不得透過任何隱性加總管道滲入 delta。
	var baseline := _aligned_table()
	var noisy := _aligned_table()
	for pair: EnumIntPairDef in noisy.node_scores:
		if pair.enum_key in [&"merchant", &"event", &"rest", &"treasure"]:
			pair.value_i32 = 999
	for outcome: SettlementReceiptState.Outcome in [
		SettlementReceiptState.Outcome.COMPLETED, SettlementReceiptState.Outcome.FAILED,
	]:
		var expected: int = MetaRewardComputeService.compute(4, 2, 1, 2, outcome, baseline)
		var actual: int = MetaRewardComputeService.compute(4, 2, 1, 2, outcome, noisy)
		assert_eq(
			actual, expected,
			"非戰鬥節點（merchant/event/rest/treasure）score 不應影響 delta：outcome=%d" % outcome
		)

func test_meta_reward_compute_is_pure_and_deterministic() -> void:
	# S5-AC-006「同輸入同輸出」＋ design.md §9「純函式」：同一組輸入呼叫兩次必須同值，
	# 且不得側面修改傳入的 table（純函式不可有副作用）。
	var table := _aligned_table()
	var before_scores: Array[int] = []
	for pair: EnumIntPairDef in table.node_scores:
		before_scores.append(pair.value_i32)
	var before_completion := table.completion_reward
	var before_failure := table.failure_reward
	var before_bps: Array[int] = []
	for entry: ChallengeMultiplierDef in table.challenge_multiplier_bps:
		before_bps.append(entry.basis_points)

	var first: int = MetaRewardComputeService.compute(
		3, 2, 1, 4, SettlementReceiptState.Outcome.COMPLETED, table
	)
	var second: int = MetaRewardComputeService.compute(
		3, 2, 1, 4, SettlementReceiptState.Outcome.COMPLETED, table
	)
	assert_eq(first, second, "同輸入必須同輸出（純函式）")

	var after_scores: Array[int] = []
	for pair: EnumIntPairDef in table.node_scores:
		after_scores.append(pair.value_i32)
	assert_eq(after_scores, before_scores, "compute() 不得修改傳入 table 的 node_scores")
	assert_eq(
		table.completion_reward, before_completion,
		"compute() 不得修改傳入 table 的 completion_reward"
	)
	assert_eq(
		table.failure_reward, before_failure,
		"compute() 不得修改傳入 table 的 failure_reward"
	)
	var after_bps: Array[int] = []
	for entry: ChallengeMultiplierDef in table.challenge_multiplier_bps:
		after_bps.append(entry.basis_points)
	assert_eq(after_bps, before_bps, "compute() 不得修改傳入 table 的 challenge_multiplier_bps")

## 建構對齊 §7.3／S5-AC-006 後 slice_default 應有的數值（見 design.md:184）：
## normal=1、elite=3、merchant/event/rest/treasure=0、boss=5、completion_reward=10、
## failure_reward=0、bps(L0..L5)=10000..15000。獨立於磁碟上的 .tres（見同目錄
## test_meta_reward_table_slice_default_alignment.gd），只借同一組數值做公式驗證。
func _aligned_table() -> MetaRewardTableDef:
	var table := MetaRewardTableDef.new()
	var scores: Array[EnumIntPairDef] = []
	scores.append(_score(&"normal", 1))
	scores.append(_score(&"elite", 3))
	scores.append(_score(&"merchant", 0))
	scores.append(_score(&"event", 0))
	scores.append(_score(&"rest", 0))
	scores.append(_score(&"treasure", 0))
	scores.append(_score(&"boss", 5))
	table.node_scores = scores
	table.completion_reward = 10
	table.failure_reward = 0
	var bps: Array[ChallengeMultiplierDef] = []
	bps.append(_bps(0, 10000))
	bps.append(_bps(1, 11000))
	bps.append(_bps(2, 12000))
	bps.append(_bps(3, 13000))
	bps.append(_bps(4, 14000))
	bps.append(_bps(5, 15000))
	table.challenge_multiplier_bps = bps
	table.id = &"meta_reward_table.test_fixture"
	table.display_name_key = &"loc.meta_reward_table_test_fixture"
	return table

func _score(key: StringName, value: int) -> EnumIntPairDef:
	var pair := EnumIntPairDef.new()
	pair.enum_key = key
	pair.value_i32 = value
	return pair

func _bps(level: int, basis_points: int) -> ChallengeMultiplierDef:
	var entry := ChallengeMultiplierDef.new()
	entry.challenge_level = level
	entry.basis_points = basis_points
	return entry

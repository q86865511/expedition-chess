extends GutTest

## G2 Phase 2 R0（roadmap 軌 A）：3k screening 實測三策略的 reroll_count 與
## sell_unit_count 全 0，reroll_cost 與賣出退款這兩類 TUNE 值因此完全量不到效果。
## 本檔釘住補上的觸發條件：
## (a) 三組 reroll／sell 分數函式都是純函式，只吃 snapshot 可得的整數與旗標，
##     沒有 rand*／時間輸入——同一狀態必然給同一分數；
## (b) 各策略在「自己語意成立」的狀態下真的會選到 REROLL／SELL_UNIT，
##     在不成立的狀態下仍維持原本的偏好（不得把策略身分抹平）；
## (c) 板凳候選的挑選順序完全決定性（primary → secondary → instance_id 字串序）。

const BalanceProductionCaseDriverScript = preload(
	"res://application/balance/balance_production_case_driver.gd"
)

## 對應 content/packs/vertical_slice/economy_configs/slice_default.tres 的實際生效值
## （interest_step_gold=10、interest_per_step=1、max_interest=5 → 滿額利息水位 50）。
const INTEREST_STEP_GOLD: int = 10
const INTEREST_PER_STEP: int = 1
const MAX_INTEREST: int = 5
const REROLL_COST: int = 2


func test_max_reachable_cost_tier_reads_the_level_odds_table() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.max_reachable_cost_tier([10000, 0, 0, 0, 0]), 1,
		"等級 1~2 的機率表只開放 tier 1"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.max_reachable_cost_tier([7500, 2500, 0, 0, 0]), 2,
		"等級 3 起開放 tier 2"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.max_reachable_cost_tier(
			[2500, 3000, 2500, 1500, 500]
		), 5
	)
	assert_eq(
		BalanceProductionCaseDriverScript.max_reachable_cost_tier([] as Array[int]), 0,
		"查不到本級機率表時視為沒有可達費階，reroll 不得因此拿到加成"
	)


func test_interest_preserved_after_spend_matches_the_max_interest_water_line() -> void:
	assert_true(BalanceProductionCaseDriverScript.interest_preserved_after_spend(
		53, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
	), "53 金滾一次剩 51，仍在滿額利息水位（50）之上")
	assert_false(BalanceProductionCaseDriverScript.interest_preserved_after_spend(
		51, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
	), "51 金滾一次剩 49，會掉出滿額利息")
	assert_false(BalanceProductionCaseDriverScript.interest_preserved_after_spend(
		1, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
	), "買不起就不算保得住利息")
	assert_true(BalanceProductionCaseDriverScript.economy_xp_allowed(
		54, 4, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST, 3, 3
	), "重構後 economy_xp_allowed 的判準必須與原本逐條等價")
	assert_false(BalanceProductionCaseDriverScript.economy_xp_allowed(
		53, 4, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST, 3, 3
	))


func test_tempo_reroll_bonus_needs_full_board_gold_reserve_and_a_better_reachable_tier() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(3, 3, 10, REROLL_COST, 1, 2),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE
			+ BalanceProductionCaseDriverScript.REROLL_TEMPO_UPGRADE_BONUS,
		"板滿、金幣有餘裕、商店只買得起 tier 1 但本級能出到 tier 2 → 滾"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(3, 3, 10, REROLL_COST, 2, 2),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE,
		"已經買得起本級最高費階時沒有升級空間，不得加成"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(3, 3, 10, REROLL_COST, 1, 1),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE,
		"本級只出 tier 1 時滾再多次也不會變好"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(2, 3, 10, REROLL_COST, 1, 2),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE,
		"板面還沒鋪滿時先補人，不得改去滾商店"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(3, 3, 5, REROLL_COST, 1, 2),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE,
		"金幣低於保留水位（reroll_cost x 3）時不得把最後一塊錢滾掉"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_tempo_score(3, 3, 10, 0, 1, 2),
		BalanceProductionCaseDriverScript.REROLL_TEMPO_BASE,
		"reroll_cost 非正值是無效設定，不得據以加成"
	)


func test_synergy_reroll_bonus_needs_a_shop_with_no_trait_overlap() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_synergy_score(3, 3, 10, REROLL_COST, 0),
		BalanceProductionCaseDriverScript.REROLL_SYNERGY_BASE
			+ BalanceProductionCaseDriverScript.REROLL_SYNERGY_OFF_TRAIT_BONUS,
		"買得起的牌沒有一張接得上現有羈絆 → 滾"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_synergy_score(3, 3, 10, REROLL_COST, 1),
		BalanceProductionCaseDriverScript.REROLL_SYNERGY_BASE,
		"只要有一張接得上就留著買，不得加成"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_synergy_score(2, 3, 10, REROLL_COST, 0),
		BalanceProductionCaseDriverScript.REROLL_SYNERGY_BASE,
		"板面還沒鋪滿時先補人"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_synergy_score(3, 3, 5, REROLL_COST, 0),
		BalanceProductionCaseDriverScript.REROLL_SYNERGY_BASE,
		"金幣低於保留水位時不得滾"
	)


func test_economy_reroll_only_spends_gold_that_still_keeps_max_interest() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_economy_score(
			3, 3, true, 53, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.REROLL_ECONOMY_INTEREST_SURPLUS,
		"板滿且滾完仍保得住滿額利息 → reroll 對 economy 是免費的資訊價值"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_economy_score(
			2, 3, false, 53, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.REROLL_ECONOMY_INTEREST_SURPLUS,
		"缺人又買不到東西時，利息水位以上一樣可以滾"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_economy_score(
			2, 3, true, 53, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.economy_reroll_score(2, 3, true),
		"還缺人又買得起時必須先鋪場，維持既有分數"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.reroll_economy_score(
			3, 3, true, 20, REROLL_COST, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.economy_reroll_score(3, 3, true),
		"金幣未達利息水位時退回既有分數，不得為了滾而破壞利息"
	)


func test_sell_triggers_follow_each_strategy_semantics() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.sell_tempo_score(2, 1, 2),
		BalanceProductionCaseDriverScript.SELL_TRIGGER_SCORE,
		"板凳溢出且商店站著更高費的候選 → tempo 換戰力"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_tempo_score(2, 1, 1), 0,
		"商店沒有更高費的候選時賣了也換不到更好的"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_tempo_score(1, 1, 5), 0,
		"只有 1 隻溢出是正常換血雜訊，不算冗員"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_economy_score(
			2, 10, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.SELL_TRIGGER_SCORE,
		"金幣還沒到滿額利息水位時，冗員換成利息本金"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_economy_score(
			2, 60, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		), 0,
		"已在利息水位以上，多賣的金幣生不出更多利息"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_synergy_score(2, 0),
		BalanceProductionCaseDriverScript.SELL_TRIGGER_SCORE,
		"與隊伍毫無共通羈絆的冗員該賣"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.sell_synergy_score(2, 1), 0,
		"還有一條共通羈絆就留著（可能是下一階的第 N 隻）"
	)


func test_trait_overlap_count_discounts_the_units_own_share() -> void:
	var counts: Dictionary = {&"trait.faction_ember": 2, &"trait.role_guard": 1}
	var traits: Array[StringName] = [&"trait.faction_ember", &"trait.role_guard"]
	assert_eq(
		BalanceProductionCaseDriverScript.trait_overlap_count(traits, counts, 1), 1,
		"扣掉自己後只有 ember 還有其他持有者"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.trait_overlap_count(traits, counts, 0), 2,
		"還沒買下的商店候選不必扣自己"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.trait_overlap_count(
			[&"trait.faction_shadow"] as Array[StringName], counts, 0
		), 0
	)


func test_worst_bench_index_is_deterministic_on_ties() -> void:
	var ids: Array[String] = ["unit_b", "unit_a"]
	assert_eq(
		BalanceProductionCaseDriverScript.worst_bench_index(
			ids, [1, 1] as Array[int], [0, 0] as Array[int]
		), 1,
		"primary/secondary 全平手時比 instance_id 字串序"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.worst_bench_index(
			ids, [2, 1] as Array[int], [0, 0] as Array[int]
		), 1,
		"primary 最低者優先"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.worst_bench_index(
			ids, [1, 1] as Array[int], [1, 0] as Array[int]
		), 1,
		"primary 平手時比 secondary"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.worst_bench_index(
			[] as Array[String], [] as Array[int], [] as Array[int]
		), -1,
		"沒有候選時回 -1，不得回 0 讓呼叫端誤取"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.worst_bench_index(
			ids, [1] as Array[int], [0, 0] as Array[int]
		), -1,
		"長度不一致是呼叫端錯誤，必須明確回 -1"
	)


## 性質：tempo 在「板滿＋只買得起最低費牌＋本級能出更高費」時真的會選 REROLL，
## 而不是繼續買最低費的牌。
func test_tempo_rerolls_instead_of_buying_the_cheapest_junk() -> void:
	var chosen := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO).try_choose_action(
		BalanceBotObservation.new(10, 3, 100, 1, _actions_with_reroll(3, 3, 10, 1, 2, 1))
	)
	assert_eq(
		chosen.stable_id, &"action.refresh_shop",
		"商店只有最低費牌時 tempo 必須滾，否則 reroll_cost 永遠量不到效果"
	)


## 性質：同一個狀態，只要商店裡有買得起的高費牌，tempo 就回到買人——
## 本次改動不得讓 tempo 變成無腦滾商店。
func test_tempo_still_buys_when_a_higher_tier_offer_is_affordable() -> void:
	var actions := _actions_with_reroll(3, 3, 10, 2, 2, 1)
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_UNIT, &"action.tier2", 2, 140, 10, 30
	))
	var chosen := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO).try_choose_action(
		BalanceBotObservation.new(10, 3, 100, 1, actions)
	)
	assert_eq(
		chosen.stable_id, &"action.tier2",
		"買得起本級最高費階時必須買人，不得改去滾商店"
	)


## 性質：synergy 在「買得起的牌全都接不上現有羈絆」時滾，接得上時買。
func test_synergy_rerolls_only_when_the_shop_has_no_trait_overlap() -> void:
	var off_trait := _actions_with_reroll(3, 3, 10, 1, 1, 0)
	var rolled := BalanceBotStrategy.new(BalanceBotStrategy.SYNERGY).try_choose_action(
		BalanceBotObservation.new(10, 3, 100, 1, off_trait)
	)
	assert_eq(
		rolled.stable_id, &"action.refresh_shop",
		"商店沒有一張接得上羈絆時 synergy 必須滾"
	)
	var on_trait := _actions_with_reroll(3, 3, 10, 1, 1, 1)
	on_trait.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_UNIT, &"action.trait_unit", 1, 120, 15, 60
	))
	var bought := BalanceBotStrategy.new(BalanceBotStrategy.SYNERGY).try_choose_action(
		BalanceBotObservation.new(10, 3, 100, 1, on_trait)
	)
	assert_eq(
		bought.stable_id, &"action.trait_unit",
		"有接得上羈絆的牌時 synergy 必須買，不得改去滾商店"
	)


## 性質：economy 只在「滾完仍保得住滿額利息、且買不起經驗」的窄帶滾；
## 一旦經驗買得起，economy 的身分（先升級）不變。
func test_economy_rerolls_in_the_gap_where_xp_is_unaffordable_but_interest_is_safe() -> void:
	var rolled := BalanceBotStrategy.new(BalanceBotStrategy.ECONOMY).try_choose_action(
		BalanceBotObservation.new(53, 3, 100, 1, _actions_with_reroll(3, 3, 53, 1, 2, 1))
	)
	assert_eq(
		rolled.stable_id, &"action.refresh_shop",
		"金幣在利息水位以上、經驗又買不起時，economy 必須滾而不是乾等"
	)
	var with_xp := _actions_with_reroll(3, 3, 60, 1, 2, 1)
	with_xp.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4, 40, 150, 20,
		BalanceProductionCaseDriverScript.economy_xp_allowed(
			60, 4, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST, 3, 3
		)
	))
	var leveled := BalanceBotStrategy.new(BalanceBotStrategy.ECONOMY).try_choose_action(
		BalanceBotObservation.new(60, 3, 100, 1, with_xp)
	)
	assert_eq(
		leveled.stable_id, &"action.buy_xp",
		"經驗買得起時 economy 仍必須先升級，reroll 不得蓋過既有身分"
	)


## 性質：板凳有冗員且商店站著更高費的候選時，tempo 真的會選 SELL_UNIT。
func test_tempo_sells_the_worst_bench_unit_when_the_shop_has_an_upgrade() -> void:
	var actions := _actions_with_reroll(5, 3, 3, 2, 2, 1)
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_UNIT, &"action.tier2", 2, 140, 10, 30
	))
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.SELL_UNIT, &"bench.weak", 0,
		BalanceProductionCaseDriverScript.sell_tempo_score(2, 1, 2),
		BalanceProductionCaseDriverScript.sell_economy_score(
			2, 3, INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
		),
		BalanceProductionCaseDriverScript.sell_synergy_score(2, 1)
	))
	var chosen := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO).try_choose_action(
		BalanceBotObservation.new(3, 3, 100, 1, actions)
	)
	assert_eq(
		chosen.stable_id, &"bench.weak",
		"板凳卡著低費冗員、商店又有更高費候選時必須賣，否則 sell 永遠是 0"
	)


## `_shop_actions` 對 BUY_UNIT/HOLD/REROLL 的建構方式在此複刻一份最小版本：
## 只有 REROLL 三軸走新的觸發函式，其餘沿用既有公式，讓斷言比較的是觸發條件本身。
func _actions_with_reroll(
	unit_count: int,
	level: int,
	gold: int,
	best_affordable_cost_tier: int,
	reachable_cost_tier: int,
	best_affordable_trait_overlap: int
) -> Array[BalanceBotAction]:
	var actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"action.tier1", 1, 120, 15, 30
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.REROLL, &"action.refresh_shop", REROLL_COST,
			BalanceProductionCaseDriverScript.reroll_tempo_score(
				unit_count, level, gold, REROLL_COST,
				best_affordable_cost_tier, reachable_cost_tier
			),
			BalanceProductionCaseDriverScript.reroll_economy_score(
				unit_count, level, true, gold, REROLL_COST,
				INTEREST_STEP_GOLD, INTEREST_PER_STEP, MAX_INTEREST
			),
			BalanceProductionCaseDriverScript.reroll_synergy_score(
				unit_count, level, gold, REROLL_COST, best_affordable_trait_overlap
			)
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.HOLD, &"action.hold", 0, 0,
			BalanceProductionCaseDriverScript.economy_hold_score(unit_count, level), 30
		),
	]
	return actions

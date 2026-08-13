class_name ShopEconomySnapshot
extends RefCounted

## 經濟資訊列的唯讀投影（IRH-REQ-011）：金幣、等級／經驗進度、連勝連敗、
## 目前等級的費用機率列。全部欄位是 EconomyState 與 pinned EconomyConfigRule 的原值
## 轉呈，沒有任何本地換算（利息、收入、機率權重都不在此重算）。
##
## xp_required_for_next_level：EconomyConfigRule.xp_thresholds 中 key＝目前等級的原值；
## 門檻用盡（最高等級）時為 -1，此時 at_max_level 為 true。

var gold: int = 0
var gold_cap: int = 0
var level: int = 0
var xp: int = 0
var xp_required_for_next_level: int = -1
var at_max_level: bool = false
var win_streak: int = 0
var loss_streak: int = 0
var shop_refresh_index: int = 0
## 目前等級在 shop_odds_by_level 的 authored 機率列；查無該等級時為 -1 與空陣列。
var odds_level: int = -1
## 各費用階（tier 1 起）的萬分比權重，原序原值（ShopOddsRule.tier_basis_points）。
var odds_tier_basis_points: Array[int] = []


func deep_clone() -> ShopEconomySnapshot:
	var copied := ShopEconomySnapshot.new()
	copied.gold = gold
	copied.gold_cap = gold_cap
	copied.level = level
	copied.xp = xp
	copied.xp_required_for_next_level = xp_required_for_next_level
	copied.at_max_level = at_max_level
	copied.win_streak = win_streak
	copied.loss_streak = loss_streak
	copied.shop_refresh_index = shop_refresh_index
	copied.odds_level = odds_level
	copied.odds_tier_basis_points = odds_tier_basis_points.duplicate()
	return copied

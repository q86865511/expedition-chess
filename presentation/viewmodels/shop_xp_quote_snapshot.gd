class_name ShopXpQuoteSnapshot
extends RefCounted

## 購買經驗的報價投影（IRH-REQ-011）。除了 ShopQuoteSnapshot 的可行性欄位，另投影
## ShopService.quote_buy_xp() 折算後的等級／經驗結果——升級折算（xp_thresholds 逐級扣抵）
## 是 domain 的規則，面板只顯示 level_after／xp_after，不得自行推算。
##
## at_max_level：quote 被 domain 以 SHOP_LEVEL_MAX 拒絕時為 true，即面板該顯示「MAX」
## 而非價格。

var available: bool = false
var affordable: bool = false
var quotable: bool = false
var at_max_level: bool = false
var gold_cost: int = 0
var gold_before: int = 0
## 單次購買獲得的經驗（EconomyConfigRule.xp_buy_amount 原值）。
var xp_gain: int = 0
var level_before: int = 0
var xp_before: int = 0
## 報價成立時折算後的等級／經驗；quotable 為 false 時等同 before 值。
var level_after: int = 0
var xp_after: int = 0
var rejection_code: StringName = &""


func deep_clone() -> ShopXpQuoteSnapshot:
	var copied := ShopXpQuoteSnapshot.new()
	copied.available = available
	copied.affordable = affordable
	copied.quotable = quotable
	copied.at_max_level = at_max_level
	copied.gold_cost = gold_cost
	copied.gold_before = gold_before
	copied.xp_gain = xp_gain
	copied.level_before = level_before
	copied.xp_before = xp_before
	copied.level_after = level_after
	copied.xp_after = xp_after
	copied.rejection_code = rejection_code
	return copied

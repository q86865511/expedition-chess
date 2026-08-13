class_name ShopQuoteSnapshot
extends RefCounted

## 單一商店動作（刷新／出售）的報價投影（IRH-REQ-011、IRH-REQ-014）。
##
## 全部數字來自 ShopService.quote_* 的實際結果：gold_cost／gold_gain 是「報價後的
## economy_state.gold 與現有 gold 的差額」，不是本地重算的價格公式——reroll 的挑戰加價
## （shop_service.gd quote_refresh 的 surcharge）與出售的星級價、gold_cap 夾擠因此都被
## 如實反映（spec §10.3 禁止呈現層複製 domain 公式）。
##
## rejection_code 直接是 domain 的 ShopError 具名碼（SHOP_GOLD_INSUFFICIENT、
## SHOP_LEVEL_MAX…），不另發明代碼；可行時為空字串名。

var action: StringName = &""
## quote 是否可執行；false 時 rejection_code 說明原因。
var available: bool = false
## 金幣是否足夠（quotable 為 false 時無意義，一律 false）。
var affordable: bool = false
## gold_cost／gold_gain 是否為已知值。金幣不足以外的拒絕（例如商店狀態不一致）
## 會讓價格無法報出，此時為 false 且兩個金額欄位皆為 0。
var quotable: bool = false
var gold_cost: int = 0
var gold_gain: int = 0
## 報價當下的金幣（讓面板能一致地畫「花費後剩餘」而不必另外讀一次）。
var gold_before: int = 0
var rejection_code: StringName = &""


func deep_clone() -> ShopQuoteSnapshot:
	var copied := ShopQuoteSnapshot.new()
	copied.action = action
	copied.available = available
	copied.affordable = affordable
	copied.quotable = quotable
	copied.gold_cost = gold_cost
	copied.gold_gain = gold_gain
	copied.gold_before = gold_before
	copied.rejection_code = rejection_code
	return copied

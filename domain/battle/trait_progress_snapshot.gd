class_name TraitProgressSnapshot
extends RefCounted

## 單一羈絆的進度投影（IRH-REQ-013）——由 BattleSetupSourceCompiler.compile_trait_progress()
## 產出，是「未達門檻的羈絆也要顯示進度」的唯一上游權威。
##
## 與 TraitBattleSnapshot 的關係：後者只承載「已達門檻、要進戰鬥」的羈絆；本型別覆蓋
## pinned catalog 的全部 trait rule，包含場上 0 隻的 inactive 列，因此多了
## distinct_count／next_required_count／thresholds 三個進度欄位。已達門檻的列，其
## trait_id／active_tier／member_instance_ids 與 compile() 的 player_active_traits 同源
## （共用同一份計數與階序判定，不是第二套實作）。
##
## active_tier：0 表示未達任何門檻（沿用 _compile_traits 對 tier 的既有語意，1 起算）。
## next_required_count：下一階所需的不同 def_id 數；已達最高階時為 -1。

var trait_id: StringName = &""
## 上場（board.placements）單位中，帶有此羈絆的**不同 def_id** 數量——tier 判定的計數來源。
var distinct_count: int = 0
var active_tier: int = 0
var next_required_count: int = -1
var member_instance_ids: Array[StringName] = []
var thresholds: Array[TraitProgressThresholdSnapshot] = []


func deep_clone() -> TraitProgressSnapshot:
	var copied := TraitProgressSnapshot.new()
	copied.trait_id = trait_id
	copied.distinct_count = distinct_count
	copied.active_tier = active_tier
	copied.next_required_count = next_required_count
	copied.member_instance_ids = member_instance_ids.duplicate()
	for threshold: TraitProgressThresholdSnapshot in thresholds:
		copied.thresholds.append(
			threshold.deep_clone() if threshold != null else null
		)
	return copied

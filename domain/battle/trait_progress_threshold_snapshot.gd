class_name TraitProgressThresholdSnapshot
extends RefCounted

## pinned BattleRuleCatalog 中單一羈絆門檻階的原樣投影（IRH-REQ-013）。
## 只承載 authored 資料：tier 是階序（1 起算，與 TraitBattleSnapshot.tier 同語意），
## required_count 是該階要求的「不同 def_id 數」。此型別不含任何啟用判定，
## 判定一律由 BattleSetupSourceCompiler 產出（呈現層不得複製門檻公式，spec §10.3）。

var tier: int = 0
var required_count: int = 0
var effect_ids: Array[StringName] = []


func deep_clone() -> TraitProgressThresholdSnapshot:
	var copied := TraitProgressThresholdSnapshot.new()
	copied.tier = tier
	copied.required_count = required_count
	copied.effect_ids = effect_ids.duplicate()
	return copied

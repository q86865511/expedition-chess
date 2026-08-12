class_name TraitThresholdPresentationSnapshot
extends RefCounted

## Clone-only projection of one threshold from the pinned BattleRuleCatalog.
## It carries authored data only; no activation or progress formula lives here.

var tier: int = 0
var required_count: int = 0
var effect_ids: Array[StringName] = []


func deep_clone() -> TraitThresholdPresentationSnapshot:
	var clone := TraitThresholdPresentationSnapshot.new()
	clone.tier = tier
	clone.required_count = required_count
	clone.effect_ids.assign(effect_ids)
	return clone

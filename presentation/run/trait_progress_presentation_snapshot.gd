class_name TraitProgressPresentationSnapshot
extends RefCounted

## Active-trait presentation DTO. Current tier and member count are copied from
## TraitBattleSnapshot; thresholds are copied from the same pinned catalog.

var trait_id: StringName = &""
var current_tier: int = 0
var member_count: int = 0
var thresholds: Array[TraitThresholdPresentationSnapshot] = []


func deep_clone() -> TraitProgressPresentationSnapshot:
	var clone := TraitProgressPresentationSnapshot.new()
	clone.trait_id = trait_id
	clone.current_tier = current_tier
	clone.member_count = member_count
	for threshold: TraitThresholdPresentationSnapshot in thresholds:
		clone.thresholds.append(
			threshold.deep_clone() if threshold != null else null
		)
	return clone

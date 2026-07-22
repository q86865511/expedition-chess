class_name RewardTableRule
extends RefCounted

var table_id: StringName
var candidates: Array[RewardCandidateRule] = []
var draw_count: int

func _init(
	p_table_id: StringName,
	p_candidates: Array[RewardCandidateRule],
	p_draw_count: int
) -> void:
	table_id = p_table_id
	for candidate: RewardCandidateRule in p_candidates:
		candidates.append(candidate.deep_clone())
	draw_count = p_draw_count

func supports_stage(stage: PendingRewardState.StageId) -> bool:
	var has_relic := false
	var has_non_relic := false
	var has_non_unit := false
	for candidate: RewardCandidateRule in candidates:
		if candidate.kind == &"relic":
			has_relic = true
		else:
			has_non_relic = true
			if candidate.kind != &"unit":
				has_non_unit = true
	match stage:
		PendingRewardState.StageId.RELIC:
			return has_relic and not has_non_relic
		PendingRewardState.StageId.STANDARD:
			return has_non_relic and not has_relic and has_non_unit
		PendingRewardState.StageId.EVENT_GRANT:
			return has_non_relic and not has_relic
	return false

func deep_clone() -> RewardTableRule:
	return RewardTableRule.new(table_id, candidates, draw_count)

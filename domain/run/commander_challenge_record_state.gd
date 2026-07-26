class_name CommanderChallengeRecordState
extends RefCounted

## S5 meta-progression (specs/meta-progression/design.md SS10): 挑戰碑 "highest
## challenge level cleared" record, tracked per commander_id. Updated by meta
## settlement (T02) on a COMPLETED run; carried on
## ProfileState.commander_challenge_records (sorted ascending by commander_id,
## unique per commander_id -- see RunStateValidator).

var commander_id: StringName
var highest_cleared_level: int

func _init(p_commander_id: StringName, p_highest_cleared_level: int) -> void:
	commander_id = p_commander_id
	highest_cleared_level = p_highest_cleared_level

func deep_clone() -> CommanderChallengeRecordState:
	return CommanderChallengeRecordState.new(commander_id, highest_cleared_level)

class_name ProfileLastSelectionState
extends RefCounted

## S5 meta-progression (specs/meta-progression/design.md SS10): the 遠征門
## "most recent selection" -- which commander and challenge level the player
## last used to start an expedition. Written by StartExpeditionCommand (T05);
## carried on ProfileState.last_selection, which may be null (no expedition
## started yet for this profile).

var commander_id: StringName
var challenge_level: int

func _init(p_commander_id: StringName, p_challenge_level: int) -> void:
	commander_id = p_commander_id
	challenge_level = p_challenge_level

func deep_clone() -> ProfileLastSelectionState:
	return ProfileLastSelectionState.new(commander_id, challenge_level)

class_name StartExpeditionRequest
extends RefCounted

var commander_id: StringName
var challenge_level: int


func _init(
	p_commander_id: StringName = &"",
	p_challenge_level: int = 0
) -> void:
	commander_id = p_commander_id
	challenge_level = p_challenge_level


func deep_clone() -> StartExpeditionRequest:
	return StartExpeditionRequest.new(commander_id, challenge_level)

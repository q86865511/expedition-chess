class_name BattleMoveProposal
extends RefCounted

var instance_id: StringName
var start_y: int
var start_x: int
var to_y: int
var to_x: int
var effective_speed: int

func deep_clone() -> BattleMoveProposal:
	var copied := BattleMoveProposal.new()
	copied.instance_id = instance_id
	copied.start_y = start_y
	copied.start_x = start_x
	copied.to_y = to_y
	copied.to_x = to_x
	copied.effective_speed = effective_speed
	return copied

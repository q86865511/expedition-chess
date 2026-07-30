class_name PresentationSubrouteToken
extends RefCounted

var _coordinator_id: StringName
var _token_id: StringName
var _expected_parent: int
var _expected_generation: int
var _target_route: StringName
var _snapshot_identity: StringName
var _consumed: bool


func _init(
	p_coordinator_id: StringName = &"",
	p_token_id: StringName = &"",
	p_expected_parent: int = 0,
	p_expected_generation: int = 0,
	p_target_route: StringName = &"",
	p_snapshot_identity: StringName = &""
) -> void:
	_coordinator_id = p_coordinator_id
	_token_id = p_token_id
	_expected_parent = p_expected_parent
	_expected_generation = p_expected_generation
	_target_route = p_target_route
	_snapshot_identity = p_snapshot_identity
	_consumed = false

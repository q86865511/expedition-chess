class_name PresentationRouteState
extends RefCounted

var parent_state: int
var route_kind: StringName
var route_generation: int
var screen_identity: StringName
var snapshot_identity: StringName


func _init(
	p_parent_state: int = 0,
	p_route_kind: StringName = &"",
	p_route_generation: int = 0,
	p_screen_identity: StringName = &"",
	p_snapshot_identity: StringName = &""
) -> void:
	parent_state = p_parent_state
	route_kind = p_route_kind
	route_generation = p_route_generation
	screen_identity = p_screen_identity
	snapshot_identity = p_snapshot_identity


func deep_clone() -> PresentationRouteState:
	return PresentationRouteState.new(
		parent_state,
		route_kind,
		route_generation,
		screen_identity,
		snapshot_identity
	)

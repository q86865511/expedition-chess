class_name LiveScreenLease
extends RefCounted

var lease_id: StringName
var parent_state: int
var route_generation: int
var _issuer: RefCounted
var _identity: RefCounted


func _init(
	p_lease_id: StringName = &"",
	p_parent_state: int = 0,
	p_route_generation: int = 0,
	p_issuer: RefCounted = null,
	p_identity: RefCounted = null
) -> void:
	lease_id = p_lease_id
	parent_state = p_parent_state
	route_generation = p_route_generation
	_issuer = p_issuer
	_identity = p_identity


func deep_clone() -> LiveScreenLease:
	return LiveScreenLease.new(
		lease_id,
		parent_state,
		route_generation,
		_issuer,
		_identity
	)

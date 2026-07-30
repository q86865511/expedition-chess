class_name ScreenActivationCapability
extends RefCounted

var _registry_identity: StringName
var _lease_id: StringName
var _parent_state: int
var _route_generation: int
var _use_nonce: StringName
var _lease_identity: RefCounted
var _consumed: bool = false


func _init(
	registry_identity: StringName = &"",
	lease_id: StringName = &"",
	parent_state: int = 0,
	route_generation: int = 0,
	use_nonce: StringName = &"",
	lease_identity: RefCounted = null
) -> void:
	_registry_identity = registry_identity
	_lease_id = lease_id
	_parent_state = parent_state
	_route_generation = route_generation
	_use_nonce = use_nonce
	_lease_identity = lease_identity

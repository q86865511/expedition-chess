class_name LiveScreenLeaseRegistry
extends RefCounted

var _active: LiveScreenLease
var _next_lease_sequence: int = 1
var _registry_identity: StringName = StringName(
	"screen.registry.%d" % _next_registry_sequence()
)
var _registry_issuer := RefCounted.new()
var _pending: Dictionary[StringName, ScreenActivationCapability] = {}


func activate(parent_state: int, route_generation: int) -> LiveScreenLease:
	var capability := prepare_activation(parent_state, route_generation)
	return activate_prepared(capability)


func prepare_activation(
	parent_state: int,
	route_generation: int
) -> ScreenActivationCapability:
	if route_generation < 1:
		return null
	var lease_id := StringName("screen.lease.%d" % _next_lease_sequence)
	_next_lease_sequence += 1
	var nonce := StringName(
		"screen.activation.%s.%d"
		% [String(_registry_identity), _next_lease_sequence]
	)
	var capability := ScreenActivationCapability.new(
		_registry_identity,
		lease_id,
		parent_state,
		route_generation,
		nonce,
		RefCounted.new()
	)
	_pending[nonce] = capability
	return capability


func prepared_lease(
	capability: ScreenActivationCapability
) -> LiveScreenLease:
	if not _is_pending(capability):
		return null
	return LiveScreenLease.new(
		capability._lease_id,
		capability._parent_state,
		capability._route_generation,
		_registry_issuer,
		capability._lease_identity
	)


func activate_prepared(
	capability: ScreenActivationCapability
) -> LiveScreenLease:
	var lease := prepared_lease(capability)
	if lease == null:
		return null
	capability._consumed = true
	_pending.erase(capability._use_nonce)
	_active = lease.deep_clone()
	return lease


func cancel_activation(capability: ScreenActivationCapability) -> void:
	if _is_pending(capability):
		capability._consumed = true
		_pending.erase(capability._use_nonce)


func revoke(lease: LiveScreenLease) -> void:
	if is_active(lease):
		_active = null


func revoke_active() -> void:
	_active = null


func is_active(lease: LiveScreenLease) -> bool:
	return (
		lease != null
		and _active != null
		and lease._issuer == _registry_issuer
		and lease._identity != null
		and lease._identity == _active._identity
		and not lease.lease_id.is_empty()
		and lease.lease_id == _active.lease_id
		and lease.parent_state == _active.parent_state
		and lease.route_generation == _active.route_generation
	)


func active_lease() -> LiveScreenLease:
	return _active.deep_clone() if _active != null else null


func _is_pending(capability: ScreenActivationCapability) -> bool:
	return (
		capability != null
		and not capability._consumed
		and capability._registry_identity == _registry_identity
		and _pending.get(capability._use_nonce) == capability
	)


static var _registry_sequence: int = 1


static func _next_registry_sequence() -> int:
	var result := _registry_sequence
	_registry_sequence += 1
	return result

class_name InstalledResultsPresentationCapability
extends RefCounted

var _snapshot_digest: String
var _parent_state: int
var _route_generation: int
var _use_nonce: RefCounted
var _consumed: bool = false


func _init(
	p_snapshot_digest: String = "",
	p_parent_state: int = -1,
	p_route_generation: int = -1
) -> void:
	_snapshot_digest = p_snapshot_digest
	_parent_state = p_parent_state
	_route_generation = p_route_generation
	_use_nonce = RefCounted.new()


func _matches(
	snapshot: ResultsPresentationSnapshot,
	parent_state: int,
	route_generation: int
) -> bool:
	return (
		not _consumed
		and snapshot != null
		and not _snapshot_digest.is_empty()
		and snapshot.presentation_digest() == _snapshot_digest
		and parent_state == _parent_state
		and route_generation == _route_generation
	)


func _consume(
	snapshot: ResultsPresentationSnapshot,
	parent_state: int,
	route_generation: int
) -> bool:
	if not _matches(snapshot, parent_state, route_generation):
		return false
	_consumed = true
	return true


func _is_consumed() -> bool:
	return _consumed

class_name ConfirmationDraft
extends RefCounted

var operation_kind: RunPresentationIntent.Kind
var snapshot_identity: StringName
var lifecycle: StringName
var payload_digest: String
var lease_id: StringName
var route_generation: int
var _use_nonce: StringName
var _intent: RunPresentationIntent
var _issuer: RefCounted
var _resolved: bool = false


func deep_clone() -> ConfirmationDraft:
	var clone := ConfirmationDraft.new()
	clone.operation_kind = operation_kind
	clone.snapshot_identity = snapshot_identity
	clone.lifecycle = lifecycle
	clone.payload_digest = payload_digest
	clone.lease_id = lease_id
	clone.route_generation = route_generation
	clone._use_nonce = _use_nonce
	clone._intent = _intent.deep_clone() if _intent != null else null
	clone._issuer = _issuer
	clone._resolved = _resolved
	return clone

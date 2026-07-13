class_name RunMutationProposal
extends RefCounted

var operation_index: int = 0
var operation_kind: StringName = &""
var amount: int = 0
var claim_key: EffectClaimKeyState = null
var payload_digest: StringName = &""

func deep_clone() -> RunMutationProposal:
	var copied := RunMutationProposal.new()
	copied.operation_index = operation_index
	copied.operation_kind = operation_kind
	copied.amount = amount
	copied.claim_key = claim_key.deep_clone() as EffectClaimKeyState if claim_key != null else null
	copied.payload_digest = payload_digest
	return copied

class_name EffectClaimKeyState
extends RuntimeKeyState

var run_id: StringName = &""
var node_id: StringName = &""
var claim_scope: StringName = &""
var source_instance_or_slot: StringName = &""
var effect_id: StringName = &""
var operation_index: int = 0

static func create(run: StringName, node: StringName, scope: StringName, source: StringName, effect: StringName, operation: int, key_digest: StringName) -> EffectClaimKeyState:
	var value := EffectClaimKeyState.new()
	value.kind = &"effect_claim"
	value.run_id = run
	value.node_id = node
	value.claim_scope = scope
	value.source_instance_or_slot = source
	value.effect_id = effect
	value.operation_index = operation
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(run_id, node_id, claim_scope, source_instance_or_slot, effect_id, operation_index, digest)

class_name RuntimeKeyLedgerEntry
extends RefCounted

var key_state: RuntimeKeyState = null
var payload_digest: StringName = &""

static func create(state: RuntimeKeyState, payload: StringName) -> RuntimeKeyLedgerEntry:
	var value := RuntimeKeyLedgerEntry.new()
	value.key_state = state.deep_clone()
	value.payload_digest = payload
	return value

func deep_clone() -> RuntimeKeyLedgerEntry:
	return create(key_state, payload_digest)

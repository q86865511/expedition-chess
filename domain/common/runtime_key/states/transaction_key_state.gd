class_name TransactionKeyState
extends RuntimeKeyState

var run_id: StringName = &""
var node_id_or_camp: StringName = &""
var command_kind: StringName = &""
var next_transaction_serial: U64Bits = null

static func create(run: StringName, node_or_camp: StringName, command: StringName, serial: U64Bits, key_digest: StringName) -> TransactionKeyState:
	var value := TransactionKeyState.new()
	value.kind = &"transaction"
	value.run_id = run
	value.node_id_or_camp = node_or_camp
	value.command_kind = command
	value.next_transaction_serial = serial.deep_clone()
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(run_id, node_id_or_camp, command_kind, next_transaction_serial, digest)

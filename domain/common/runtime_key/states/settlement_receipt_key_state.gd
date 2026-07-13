class_name SettlementReceiptKeyState
extends RuntimeKeyState

var run_id: StringName = &""

static func create(run: StringName, key_digest: StringName) -> SettlementReceiptKeyState:
	var value := SettlementReceiptKeyState.new()
	value.kind = &"settlement_receipt"
	value.run_id = run
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(run_id, digest)

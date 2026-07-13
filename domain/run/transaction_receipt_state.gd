class_name TransactionReceiptState
extends RefCounted

var key: TransactionKeyState
var payload_digest: String

func _init(p_key: TransactionKeyState, p_payload_digest: String) -> void:
	key = p_key.deep_clone()
	payload_digest = p_payload_digest

func deep_clone() -> TransactionReceiptState:
	return TransactionReceiptState.new(key, payload_digest)

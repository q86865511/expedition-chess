class_name NodeChoiceCommitReceiptState
extends RefCounted

var run_id: StringName
var node_id: StringName
var choice_set_id: StringName
var choice_id: StringName
var pending_digest: String
var lifecycle_nonce: String
var transaction_serial: String
var transaction_digest: String
var result_key: StringName
var outcome_kind: int
var receipt_digest: String

func deep_clone() -> NodeChoiceCommitReceiptState:
	var clone := NodeChoiceCommitReceiptState.new()
	clone.run_id = run_id
	clone.node_id = node_id
	clone.choice_set_id = choice_set_id
	clone.choice_id = choice_id
	clone.pending_digest = pending_digest
	clone.lifecycle_nonce = lifecycle_nonce
	clone.transaction_serial = transaction_serial
	clone.transaction_digest = transaction_digest
	clone.result_key = result_key
	clone.outcome_kind = outcome_kind
	clone.receipt_digest = receipt_digest
	return clone


func refresh_digest() -> void:
	receipt_digest = _compute_digest()


func is_valid() -> bool:
	var validator := StableIdValidator.new()
	if (
		not _is_key_digest(String(run_id), "run_")
		or not _is_key_digest(String(node_id), "node_")
		or not validator.is_valid(choice_set_id)
		or not validator.is_valid(choice_id)
		or not validator.is_valid(result_key)
		or outcome_kind not in [1, 2, 3]
	):
		return false
	if (
		not _lower_hex(pending_digest, 64)
		or not _lower_hex(lifecycle_nonce, 16)
		or not _lower_hex(transaction_serial, 16)
		or not _is_key_digest(transaction_digest, "transaction_")
		or not _lower_hex(receipt_digest, 64)
	):
		return false
	return receipt_digest == _compute_digest()


func _compute_digest() -> String:
	if (
		not _lower_hex(pending_digest, 64)
		or not _lower_hex(lifecycle_nonce, 16)
		or not _lower_hex(transaction_serial, 16)
		or not _is_key_digest(transaction_digest, "transaction_")
	):
		return ""
	var bytes := "NCR1".to_ascii_buffer()
	for value: String in [
		String(run_id),
		String(node_id),
		String(choice_set_id),
		String(choice_id),
	]:
		_append_text(bytes, value)
	bytes.append_array(pending_digest.hex_decode())
	bytes.append_array(lifecycle_nonce.hex_decode())
	bytes.append_array(transaction_serial.hex_decode())
	bytes.append_array(
		transaction_digest.trim_prefix("transaction_").hex_decode()
	)
	_append_text(bytes, String(result_key))
	_append_u32(bytes, outcome_kind)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
		or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _append_text(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_utf8_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)


func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)


func _lower_hex(value: String, length: int) -> bool:
	return value.length() == length \
		and value == value.to_lower() \
		and value.hex_decode().size() == length / 2


# RuntimeKeyCodecV1 的 key digest 格式為 "<kind>_" + 64 lower-hex
func _is_key_digest(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) \
		and _lower_hex(value.trim_prefix(prefix), 64)

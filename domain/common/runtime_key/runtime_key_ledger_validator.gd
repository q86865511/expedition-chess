class_name RuntimeKeyLedgerValidator
extends RefCounted

const DIGEST_MISMATCH: StringName = &"KEY_DIGEST_MISMATCH"
const DUPLICATE_TUPLE: StringName = &"KEY_DUPLICATE_TUPLE"
const DUPLICATE_DIGEST: StringName = &"KEY_DUPLICATE_DIGEST"
const PAYLOAD_CONFLICT: StringName = &"KEY_PAYLOAD_CONFLICT"
const SERIAL_ROLLBACK: StringName = &"KEY_SERIAL_ROLLBACK"
const SERIAL_EXHAUSTED: StringName = &"KEY_SERIAL_EXHAUSTED"

func validate(entries: Array[RuntimeKeyLedgerEntry]) -> RuntimeKeyLedgerResult:
	var canonical_tuples: Array[String] = []
	var digests: Array[StringName] = []
	var payloads: Array[StringName] = []
	var schema := RuntimeKeySchemaRegistry.new()
	for index: int in range(entries.size()):
		var entry := entries[index]
		if entry == null or entry.key_state == null or not _is_digest(String(entry.payload_digest)):
			return RuntimeKeyLedgerResult.failure(DIGEST_MISMATCH, StringName("entries.%d" % index))
		var encoded := schema.reencode_state(entry.key_state)
		if not encoded.ok:
			return RuntimeKeyLedgerResult.failure(encoded.error.code, StringName("entries.%d.%s" % [index, encoded.error.field_path]))
		var tuple_hex := encoded.canonical_bytes.hex_encode()
		var digest_index := digests.find(entry.key_state.digest)
		if digest_index >= 0:
			if payloads[digest_index] != entry.payload_digest:
				return RuntimeKeyLedgerResult.failure(PAYLOAD_CONFLICT, StringName("entries.%d.payload_digest" % index))
			if canonical_tuples[digest_index] == tuple_hex:
				return RuntimeKeyLedgerResult.failure(DUPLICATE_TUPLE, StringName("entries.%d" % index))
			return RuntimeKeyLedgerResult.failure(DUPLICATE_DIGEST, StringName("entries.%d" % index))
		if canonical_tuples.has(tuple_hex):
			return RuntimeKeyLedgerResult.failure(DUPLICATE_TUPLE, StringName("entries.%d" % index))
		canonical_tuples.append(tuple_hex)
		digests.append(entry.key_state.digest)
		payloads.append(entry.payload_digest)
	return RuntimeKeyLedgerResult.success()

func validate_serial_transition(previous: U64Bits, current: U64Bits, allocated_count: int, is_retry: bool) -> RuntimeKeyLedgerResult:
	if previous == null or current == null or allocated_count < 0:
		return RuntimeKeyLedgerResult.failure(SERIAL_ROLLBACK, &"serial")
	if is_retry:
		if not previous.equals(current):
			return RuntimeKeyLedgerResult.failure(SERIAL_ROLLBACK, &"serial")
		return RuntimeKeyLedgerResult.success()
	if allocated_count > 0 and previous.equals(U64Bits.max_value()):
		return RuntimeKeyLedgerResult.failure(SERIAL_EXHAUSTED, &"serial")
	var expected := previous.deep_clone()
	for _index: int in range(allocated_count):
		if expected.equals(U64Bits.max_value()):
			return RuntimeKeyLedgerResult.failure(SERIAL_EXHAUSTED, &"serial")
		expected = expected.add(U64Bits.one())
	if not expected.equals(current):
		return RuntimeKeyLedgerResult.failure(SERIAL_ROLLBACK, &"serial")
	return RuntimeKeyLedgerResult.success()

func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

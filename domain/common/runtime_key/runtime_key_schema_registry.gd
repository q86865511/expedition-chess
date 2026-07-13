class_name RuntimeKeySchemaRegistry
extends RefCounted

const KIND_UNKNOWN: StringName = &"KEY_KIND_UNKNOWN"
const FIELD_COUNT: StringName = &"KEY_FIELD_COUNT"
const FIELD_TAG: StringName = &"KEY_FIELD_TAG"
const FIELD_ORDER: StringName = &"KEY_FIELD_ORDER"
const TOKEN_INVALID: StringName = &"KEY_TOKEN_INVALID"
const DIGEST_MISMATCH: StringName = &"KEY_DIGEST_MISMATCH"

const MAX_U32: int = 0xffffffff

func build_run(profile_id: String, next_run_serial: U64Bits) -> RuntimeKeyEncodeResult:
	if not _is_lower_hex(profile_id, 32):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"profile_id")
	if next_run_serial == null:
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"next_run_serial")
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("run"),
		FixedHexToken._from_value(profile_id),
		U64Token._from_value(next_run_serial),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"run", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		RunKeyState.create(profile_id, next_run_serial, encoded.key_state.digest),
		encoded.canonical_bytes
	)

func build_node(run_id: StringName, act_index: int, node_kind: StringName, layer_index: int, slot_index: int) -> RuntimeKeyEncodeResult:
	var invalid_path := _first_invalid_node_field(run_id, act_index, node_kind, layer_index, slot_index)
	if not invalid_path.is_empty():
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, invalid_path)
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("node"),
		StableAsciiToken._from_value(String(run_id)),
		NonNegativeIntToken._from_value(act_index),
		EnumToken._from_value(String(node_kind)),
		NonNegativeIntToken._from_value(layer_index),
		NonNegativeIntToken._from_value(slot_index),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"node", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		NodeKeyState.create(
			run_id, act_index, node_kind, layer_index, slot_index,
			encoded.key_state.digest
		),
		encoded.canonical_bytes
	)

func build_reservation_owner(run_id: StringName, node_id: StringName, source_kind: StringName, stage_or_refresh_id: StringName, slot_index: int) -> RuntimeKeyEncodeResult:
	var fields: Array[StringName] = [run_id, node_id, stage_or_refresh_id]
	var names: Array[StringName] = [&"run_id", &"node_id", &"stage_or_refresh_id"]
	for index: int in range(fields.size()):
		if not _is_stable_ascii(String(fields[index])):
			return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, names[index])
	if not _is_enum(String(source_kind)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"source_kind")
	if not _is_u32(slot_index):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"slot_index")
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("reservation_owner"),
		StableAsciiToken._from_value(String(run_id)),
		StableAsciiToken._from_value(String(node_id)),
		EnumToken._from_value(String(source_kind)),
		StableAsciiToken._from_value(String(stage_or_refresh_id)),
		NonNegativeIntToken._from_value(slot_index),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"reservation_owner", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		ReservationOwnerKeyState.create(
			run_id, node_id, source_kind, stage_or_refresh_id, slot_index,
			encoded.key_state.digest
		),
		encoded.canonical_bytes
	)

func build_transaction(run_id: StringName, node_id_or_camp: StringName, command_kind: StringName, next_transaction_serial: U64Bits) -> RuntimeKeyEncodeResult:
	if not _is_stable_ascii(String(run_id)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"run_id")
	if not _is_stable_ascii(String(node_id_or_camp)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"node_id_or_camp")
	if not _is_enum(String(command_kind)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"command_kind")
	if next_transaction_serial == null:
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"next_transaction_serial")
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("transaction"),
		StableAsciiToken._from_value(String(run_id)),
		StableAsciiToken._from_value(String(node_id_or_camp)),
		EnumToken._from_value(String(command_kind)),
		U64Token._from_value(next_transaction_serial),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"transaction", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		TransactionKeyState.create(
			run_id, node_id_or_camp, command_kind, next_transaction_serial,
			encoded.key_state.digest
		),
		encoded.canonical_bytes
	)

func build_effect_claim(run_id: StringName, node_id: StringName, claim_scope: StringName, source_instance_or_slot: StringName, effect_id: StringName, operation_index: int) -> RuntimeKeyEncodeResult:
	var stable_fields: Array[StringName] = [run_id, node_id, source_instance_or_slot, effect_id]
	var paths: Array[StringName] = [&"run_id", &"node_id", &"source_instance_or_slot", &"effect_id"]
	for index: int in range(stable_fields.size()):
		if not _is_stable_ascii(String(stable_fields[index])):
			return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, paths[index])
	if not StableIdValidator.new().is_valid(effect_id):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"effect_id")
	if not _is_enum(String(claim_scope)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"claim_scope")
	if not _is_u32(operation_index):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"operation_index")
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("effect_claim"),
		StableAsciiToken._from_value(String(run_id)),
		StableAsciiToken._from_value(String(node_id)),
		EnumToken._from_value(String(claim_scope)),
		StableAsciiToken._from_value(String(source_instance_or_slot)),
		StableAsciiToken._from_value(String(effect_id)),
		NonNegativeIntToken._from_value(operation_index),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"effect_claim", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		EffectClaimKeyState.create(
			run_id, node_id, claim_scope, source_instance_or_slot, effect_id,
			operation_index, encoded.key_state.digest
		),
		encoded.canonical_bytes
	)

func build_settlement_receipt(run_id: StringName) -> RuntimeKeyEncodeResult:
	if not _is_stable_ascii(String(run_id)):
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"run_id")
	var tokens: Array[RuntimeKeyToken] = [
		KeyKindToken._from_value("settlement_receipt"),
		StableAsciiToken._from_value(String(run_id)),
	]
	var encoded := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"settlement_receipt", tokens))
	if not encoded.ok:
		return encoded
	return RuntimeKeyEncodeResult.success(
		SettlementReceiptKeyState.create(run_id, encoded.key_state.digest),
		encoded.canonical_bytes
	)

func reencode_state(state: RuntimeKeyState) -> RuntimeKeyEncodeResult:
	if state == null:
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"state")
	var encoded: RuntimeKeyEncodeResult
	if state is RunKeyState:
		var typed := state as RunKeyState
		encoded = build_run(typed.profile_id, typed.next_run_serial)
	elif state is NodeKeyState:
		var typed := state as NodeKeyState
		encoded = build_node(typed.run_id, typed.act_index, typed.node_kind, typed.layer_index, typed.slot_index)
	elif state is ReservationOwnerKeyState:
		var typed := state as ReservationOwnerKeyState
		encoded = build_reservation_owner(typed.run_id, typed.node_id, typed.source_kind, typed.stage_or_refresh_id, typed.slot_index)
	elif state is TransactionKeyState:
		var typed := state as TransactionKeyState
		encoded = build_transaction(typed.run_id, typed.node_id_or_camp, typed.command_kind, typed.next_transaction_serial)
	elif state is EffectClaimKeyState:
		var typed := state as EffectClaimKeyState
		encoded = build_effect_claim(typed.run_id, typed.node_id, typed.claim_scope, typed.source_instance_or_slot, typed.effect_id, typed.operation_index)
	elif state is SettlementReceiptKeyState:
		var typed := state as SettlementReceiptKeyState
		encoded = build_settlement_receipt(typed.run_id)
	else:
		return RuntimeKeyEncodeResult.failure(KIND_UNKNOWN, &"kind")
	if not encoded.ok:
		return encoded
	if state.kind != encoded.key_state.kind or state.digest != encoded.key_state.digest:
		return RuntimeKeyEncodeResult.failure(DIGEST_MISMATCH, &"digest")
	return encoded

func validate_tuple(tuple: RuntimeKeyTuple) -> RuntimeKeyValidationResult:
	if tuple == null:
		return RuntimeKeyValidationResult.failure(
			RuntimeKeyError.create(TOKEN_INVALID, &"tuple")
		)
	var expected := _expected_tags(tuple.kind())
	if expected.is_empty():
		return RuntimeKeyValidationResult.failure(
			RuntimeKeyError.create(KIND_UNKNOWN, &"kind")
		)
	if tuple.token_count() != expected.size():
		return RuntimeKeyValidationResult.failure(
			RuntimeKeyError.create(FIELD_COUNT, &"tokens")
		)
	for index: int in range(expected.size()):
		var token := tuple.token_at(index)
		if String(token.tag) != expected[index]:
			var code := FIELD_ORDER if expected.has(String(token.tag)) else FIELD_TAG
			return RuntimeKeyValidationResult.failure(
				RuntimeKeyError.create(code, StringName("tokens.%d" % index))
			)
		if not _valid_token(token, index == 0):
			return RuntimeKeyValidationResult.failure(
				RuntimeKeyError.create(
					TOKEN_INVALID, StringName("tokens.%d" % index)
				)
			)
	if tuple.token_at(0).value != String(tuple.kind()):
		return RuntimeKeyValidationResult.failure(
			RuntimeKeyError.create(KIND_UNKNOWN, &"tokens.0")
		)
	return RuntimeKeyValidationResult.success()

func _expected_tags(kind: StringName) -> Array[String]:
	match kind:
		&"run": return ["k", "h", "u"]
		&"node": return ["k", "s", "i", "e", "i", "i"]
		&"reservation_owner": return ["k", "s", "s", "e", "s", "i"]
		&"transaction": return ["k", "s", "s", "e", "u"]
		&"effect_claim": return ["k", "s", "s", "e", "s", "s", "i"]
		&"settlement_receipt": return ["k", "s"]
	return []

func _valid_token(token: RuntimeKeyToken, is_kind: bool) -> bool:
	match token.tag:
		&"k": return is_kind and _is_enum(token.value)
		&"e": return _is_enum(token.value)
		&"s": return _is_stable_ascii(token.value)
		&"h": return _is_lower_hex(token.value, 32)
		&"u": return U64Bits.from_hex(token.value).ok
		&"i": return _is_canonical_u32(token.value)
	return false

func _first_invalid_node_field(run_id: StringName, act_index: int, node_kind: StringName, layer_index: int, slot_index: int) -> StringName:
	if not _is_stable_ascii(String(run_id)): return &"run_id"
	if not _is_u32(act_index): return &"act_index"
	if not _is_enum(String(node_kind)): return &"node_kind"
	if not _is_u32(layer_index): return &"layer_index"
	if not _is_u32(slot_index): return &"slot_index"
	return &""

func _is_u32(value: int) -> bool:
	return value >= 0 and value <= MAX_U32

func _is_canonical_u32(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	if value.length() > 10:
		return false
	var parsed := value.to_int()
	return parsed >= 0 and parsed <= MAX_U32 and str(parsed) == value

func _is_enum(value: String) -> bool:
	if value.is_empty(): return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if index == 0:
			if code < 97 or code > 122: return false
		elif not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true

func _is_stable_ascii(value: String) -> bool:
	if value.is_empty(): return false
	var bytes := value.to_utf8_buffer()
	for byte: int in bytes:
		if byte < 33 or byte > 126:
			return false
	return true

func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length: return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

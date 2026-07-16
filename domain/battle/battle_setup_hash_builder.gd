class_name BattleSetupHashBuilder
extends RefCounted

const RECEIPT_INVALID: StringName = &"BATTLE_VALIDATION_RECEIPT_INVALID"
const INPUT_INVALID: StringName = &"BATTLE_INPUT_INVALID"

var _run_seed: U64Bits
var _rng_service: RngService

func _init(
	run_seed: U64Bits,
	rng_service: RngService = null
) -> void:
	_run_seed = run_seed.deep_clone() if run_seed != null else null
	_rng_service = rng_service if rng_service != null else RngService.new()

func build_from_validated(inputs: BattleSetupInputs, validation_receipt: BattleSetupValidationReceipt) -> BattleSetupBuildResult:
	if _run_seed == null:
		return BattleSetupBuildResult.failure(INPUT_INVALID, &"run_seed")
	var encoded := BattleSetupInputsValidator._codec_for_schema(inputs.setup_schema_version).encode(inputs)
	if not encoded.ok:
		return BattleSetupBuildResult.failure(encoded.error.code, encoded.error.field_path)
	var digest := sha256_hex(encoded.canonical_bytes)
	if digest.is_empty():
		return BattleSetupBuildResult.failure(INPUT_INVALID, &"sha256")
	if not BattleSetupInputsValidator._verifies_receipt(
		validation_receipt,
		StringName(digest)
	):
		return BattleSetupBuildResult.failure(RECEIPT_INVALID, &"validation_receipt")
	var context := StringName("%s:%s" % [String(inputs.encounter_snapshot.encounter_id), digest])
	var derived := _rng_service.derive_stream(_run_seed, &"combat", context)
	if not derived.ok:
		return BattleSetupBuildResult.failure(INPUT_INVALID, StringName("rng.%s" % derived.error.field_path))
	var setup := BattleSetup.new()
	setup.inputs = inputs.deep_clone()
	setup.hash_version = 1
	setup.battle_setup_hash = StringName(digest)
	setup.rng_version = 1
	setup.combat_rng_snapshot = derived.snapshot.deep_clone()
	if inputs.setup_schema_version == 2:
		var envelope := envelope_digest(
			setup.hash_version,
			digest,
			setup.rng_version,
			setup.combat_rng_snapshot
		)
		if envelope.is_empty():
			return BattleSetupBuildResult.failure(INPUT_INVALID, &"battle_setup_envelope_digest")
		setup.battle_setup_envelope_digest = StringName(envelope)
	return BattleSetupBuildResult.success(setup)

static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

static func envelope_digest(
	hash_version: int,
	setup_hash: String,
	rng_version: int,
	snapshot: RngSnapshot
) -> String:
	if hash_version != 1 or rng_version != 1 or snapshot == null \
		or snapshot.rng_version != rng_version or setup_hash.length() != 64:
		return ""
	var setup_bytes := setup_hash.hex_decode()
	if setup_bytes.size() != 32 or setup_bytes.hex_encode() != setup_hash:
		return ""
	var bytes := PackedByteArray()
	bytes.append_array("BSE1".to_ascii_buffer())
	_append_u32(bytes, hash_version)
	bytes.append_array(setup_bytes)
	_append_u32(bytes, rng_version)
	_append_u64(bytes, snapshot.state)
	_append_u64(bytes, snapshot.inc)
	_append_u64(bytes, snapshot.counter)
	return sha256_hex(bytes)

static func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)

static func _append_u64(bytes: PackedByteArray, value: U64Bits) -> void:
	_append_u32(bytes, value.high_u32())
	_append_u32(bytes, value.low_u32())

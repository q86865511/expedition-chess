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
	var encoded := CanonicalBattleCodecV1.new().encode(inputs)
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
	return BattleSetupBuildResult.success(setup)

static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

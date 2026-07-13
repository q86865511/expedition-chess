class_name BattleCodecResult
extends RefCounted

var ok: bool = false
var canonical_bytes: PackedByteArray = PackedByteArray()
var inputs: BattleSetupInputs = null
var error: BattleCodecError = null

static func encoded(bytes: PackedByteArray) -> BattleCodecResult:
	return BattleCodecResult.new(true, bytes, null, null)

static func decoded(value: BattleSetupInputs) -> BattleCodecResult:
	return BattleCodecResult.new(true, PackedByteArray(), value, null)

static func failure(code: StringName = &"BATTLE_CODEC_INVALID", path: StringName = &"") -> BattleCodecResult:
	return BattleCodecResult.new(
		false, PackedByteArray(), null, BattleCodecError.create(code, path)
	)

func _init(
	p_ok: bool,
	p_canonical_bytes: PackedByteArray,
	p_inputs: BattleSetupInputs,
	p_error: BattleCodecError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		(not p_canonical_bytes.is_empty()) != (p_inputs != null),
		p_canonical_bytes.is_empty() and p_inputs == null
	)
	ok = p_ok
	canonical_bytes = p_canonical_bytes.duplicate()
	inputs = p_inputs.deep_clone() if p_inputs != null else null
	error = p_error

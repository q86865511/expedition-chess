class_name BattleResultCodecResult
extends RefCounted

var ok: bool
var canonical_bytes: PackedByteArray
var record: BattleResultRecord
var error: BattleResultCodecError

static func encoded(bytes: PackedByteArray) -> BattleResultCodecResult:
	return BattleResultCodecResult.new(true, bytes, null, null)

static func decoded(value: BattleResultRecord) -> BattleResultCodecResult:
	return BattleResultCodecResult.new(true, PackedByteArray(), value, null)

static func failure(code: StringName, path: StringName = &"") -> BattleResultCodecResult:
	return BattleResultCodecResult.new(
		false, PackedByteArray(), null, BattleResultCodecError.new(code, path)
	)

func _init(
	p_ok: bool,
	p_bytes: PackedByteArray,
	p_record: BattleResultRecord,
	p_error: BattleResultCodecError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		(not p_bytes.is_empty()) != (p_record != null),
		p_bytes.is_empty() and p_record == null
	)
	ok = p_ok
	canonical_bytes = p_bytes.duplicate()
	record = p_record.deep_clone() if p_record != null else null
	error = p_error.deep_clone() if p_error != null else null

class_name BattleEventCodecResult
extends RefCounted

var ok: bool
var canonical_bytes: PackedByteArray
var event: BattleEvent
var error: BattleEventCodecError

static func encoded(bytes: PackedByteArray) -> BattleEventCodecResult:
	return BattleEventCodecResult.new(true, bytes, null, null)

static func decoded(value: BattleEvent) -> BattleEventCodecResult:
	return BattleEventCodecResult.new(true, PackedByteArray(), value, null)

static func failure(code: StringName, path: StringName = &"") -> BattleEventCodecResult:
	return BattleEventCodecResult.new(
		false, PackedByteArray(), null, BattleEventCodecError.new(code, path)
	)

func _init(
	p_ok: bool,
	p_bytes: PackedByteArray,
	p_event: BattleEvent,
	p_error: BattleEventCodecError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		(not p_bytes.is_empty()) != (p_event != null),
		p_bytes.is_empty() and p_event == null
	)
	ok = p_ok
	canonical_bytes = p_bytes.duplicate()
	event = p_event.deep_clone() if p_event != null else null
	error = p_error.deep_clone() if p_error != null else null

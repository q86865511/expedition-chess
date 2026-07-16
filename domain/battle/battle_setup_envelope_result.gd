class_name BattleSetupEnvelopeResult
extends RefCounted

var ok: bool
var verified_snapshot: RngSnapshot
var error: BattleSetupEnvelopeError

static func success(snapshot: RngSnapshot) -> BattleSetupEnvelopeResult:
	return BattleSetupEnvelopeResult.new(true, snapshot, null)

static func failure(code: StringName, path: StringName = &"") -> BattleSetupEnvelopeResult:
	return BattleSetupEnvelopeResult.new(
		false, null, BattleSetupEnvelopeError.new(code, path)
	)

func _init(
	p_ok: bool,
	p_snapshot: RngSnapshot,
	p_error: BattleSetupEnvelopeError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_snapshot != null, p_snapshot == null)
	ok = p_ok
	verified_snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null

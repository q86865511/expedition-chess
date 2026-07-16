class_name BattleResultFinalizeResult
extends RefCounted

var ok: bool
var record: BattleResultRecord
var receipt: BattleResultValidationReceipt
var error: BattleResultCodecError

static func success(
	value: BattleResultRecord,
	validation_receipt: BattleResultValidationReceipt
) -> BattleResultFinalizeResult:
	return BattleResultFinalizeResult.new(true, value, validation_receipt, null)

static func failure(code: StringName, path: StringName = &"") -> BattleResultFinalizeResult:
	return BattleResultFinalizeResult.new(
		false, null, null, BattleResultCodecError.new(code, path)
	)

func _init(
	p_ok: bool,
	p_record: BattleResultRecord,
	p_receipt: BattleResultValidationReceipt,
	p_error: BattleResultCodecError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_record != null and p_receipt != null,
		p_record == null and p_receipt == null
	)
	ok = p_ok
	record = p_record.deep_clone() if p_record != null else null
	receipt = p_receipt.deep_clone() if p_receipt != null else null
	error = p_error.deep_clone() if p_error != null else null

class_name BattleInputValidationResult
extends RefCounted

var ok: bool = false
var error: BattleCodecError = null
var receipt: BattleSetupValidationReceipt = null

static func success(
	p_receipt: BattleSetupValidationReceipt = null
) -> BattleInputValidationResult:
	return BattleInputValidationResult.new(true, null, p_receipt)

static func failure(code: StringName, path: StringName) -> BattleInputValidationResult:
	return BattleInputValidationResult.new(
		false,
		BattleCodecError.create(code, path),
		null
	)

func _init(
	p_ok: bool,
	p_error: BattleCodecError,
	p_receipt: BattleSetupValidationReceipt
) -> void:
	ResultInvariant.require(p_ok, p_error, true, p_receipt == null)
	ok = p_ok
	error = p_error
	receipt = p_receipt.deep_clone() if p_receipt != null else null

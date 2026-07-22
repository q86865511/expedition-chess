class_name IncomeQuoteResult
extends RefCounted

var ok: bool
var transaction: IncomeTransaction
var error: ShopError

static func success(value: IncomeTransaction) -> IncomeQuoteResult:
	return IncomeQuoteResult.new(true, value, null)

static func failure(code: StringName, path: StringName) -> IncomeQuoteResult:
	return IncomeQuoteResult.new(false, null, ShopError.new(code, path))

func _init(p_ok: bool, p_transaction: IncomeTransaction, p_error: ShopError) -> void:
	ResultInvariant.require(p_ok, p_error, p_transaction != null, p_transaction == null)
	ok = p_ok
	transaction = p_transaction.deep_clone() if p_transaction != null else null
	error = p_error.deep_clone() if p_error != null else null

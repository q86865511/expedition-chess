class_name ShopTransactionResult
extends RefCounted

var ok: bool
var transaction: ShopTransaction
var error: ShopError

static func success(value: ShopTransaction) -> ShopTransactionResult:
	return ShopTransactionResult.new(true, value, null)

static func failure(code: StringName, path: StringName) -> ShopTransactionResult:
	return ShopTransactionResult.new(false, null, ShopError.new(code, path))

func _init(p_ok: bool, p_transaction: ShopTransaction, p_error: ShopError) -> void:
	ResultInvariant.require(p_ok, p_error, p_transaction != null, p_transaction == null)
	ok = p_ok
	transaction = p_transaction.deep_clone() if p_transaction != null else null
	error = p_error.deep_clone() if p_error != null else null
